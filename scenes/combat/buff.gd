extends RefCounted
class_name Buff

## ============================================================================
## BUFF  —  the data model for one buff / debuff (class_name global)
## ============================================================================
## A buff or debuff is a persistent combat effect. It is stored as a plain
## Dictionary ENTRY inside a CharacterBase basket ("buffs" or "debuffs"), so it
## rides the SAME "everything is a basket of stat mods" model everything else
## uses — CharacterBase.get_bonus() / get_basket_bonus() sum an entry's "mods"
## dict with no knowledge that it is a buff. That is deliberate: any stat
## augment a buff carries (a +5 vigor buff, Dalet's -15 resists, a
## damage_dealt_mult, a healing_received_mult, a hp_base / spirit change for
## temporary max-HP / max-Spirit) is just a key in "mods" and works for free.
##
## On TOP of "mods", a buff entry carries extra fields for the mechanics that are
## NOT a plain additive stat:
##   - a per-turn DoT (bleed / poison), with its own element and flat multiplier
##   - a per-turn spirit change (regen buff / drain debuff)
##   - a MULTIPLICATIVE resist multiplier (read by CombatMath as a real layer)
##   - silence / stun gameplay flags
##   - an on-expire event hook id
## and the metadata the systems around it read: visible vs hidden, duration,
## element tag, stackable + max_stacks + current stacks, buff/debuff weight (for
## future AI targeting), resistible, transient, a hidden MAGNITUDE (severity
## gauge, default 1.0), and a list of ON-STRUCK reactions ("when struck do X",
## e.g. thorns) fired by CombatBuffs when the bearer takes a hit.
##
## STACKING. A stackable buff is stored as ONE entry with a `stacks` count. The
## PER-STACK values live in entry["per_stack"]; the live top-level fields
## ("mods", "dot", "spirit_per_turn", "resist_mult", ...) are the per-stack
## values times `stacks`, recomputed by recompute_scaled(). That way the additive
## stat reads (which see the top-level "mods") automatically reflect the stack
## count, and CombatBuffs only has to bump `stacks` and re-scale.
##
## Storage is a Dictionary (not an Object) ON PURPOSE: CharacterBase.get_bonus()
## does entry.get("mods", {}), which only works on a Dictionary. Buff is a bag of
## STATIC helpers over that dict, mirroring CombatMath / CombatCrit.
##
## class_name global — RESTART Godot once after adding this script.
## ----------------------------------------------------------------------------

const KIND_BUFF := "buff"
const KIND_DEBUFF := "debuff"

## A fresh per-stack payload with every field at its neutral default.
static func _default_per_stack() -> Dictionary:
	return {
		"mods": {},                 # additive stat mods (per stack)
		"dot": 0.0,                 # damage-over-time per turn (per stack)
		"dot_element": "physical",  # element the DoT is dealt as
		"dot_mult": 1.0,            # flat DoT multiplier (future buffs tune this)
		"spirit_per_turn": 0.0,     # + regen / - drain per turn (per stack)
		"resist_mult": 0.0,         # GLOBAL multiplicative resist bonus (per stack)
		"resist_mult_by_element": {}, # per-element multiplicative resist bonus
	}

## Build a full buff/debuff entry from a partial `config`. Everything not given
## falls back to a sane default. `config` may set any metadata field directly and
## supplies the per-stack payload under whatever of these keys it wants:
##   mods, dot, dot_element, dot_mult, spirit_per_turn, resist_mult,
##   resist_mult_by_element
## (they are copied into per_stack), OR pass a ready "per_stack" dict.
static func make(config: Dictionary) -> Dictionary:
	var per_stack := _default_per_stack()
	# accept a whole per_stack, else pull the individual per-stack keys out of config
	if config.has("per_stack") and typeof(config["per_stack"]) == TYPE_DICTIONARY:
		for k in config["per_stack"]:
			per_stack[k] = config["per_stack"][k]
	else:
		for k in _default_per_stack().keys():
			if config.has(k):
				per_stack[k] = config[k]
	# deep-copy the nested dicts so two entries never share a reference
	per_stack["mods"] = (per_stack["mods"] as Dictionary).duplicate(true)
	per_stack["resist_mult_by_element"] = (per_stack["resist_mult_by_element"] as Dictionary).duplicate(true)

	# ON-STRUCK reactions: a list of "when this bearer is struck, do X" effect
	# dicts (see CombatBuffs.fire_on_struck for the dispatch). Deep-copied so two
	# entries never share the list. Empty = no reaction.
	var on_struck: Array = []
	var raw_on_struck = config.get("on_struck", [])
	if typeof(raw_on_struck) == TYPE_ARRAY:
		on_struck = (raw_on_struck as Array).duplicate(true)

	var stackable := bool(config.get("stackable", false))
	var entry := {
		"id": str(config.get("id", "buff")),
		"source": str(config.get("source", "Buff")),
		"desc": str(config.get("desc", "")),
		"kind": str(config.get("kind", KIND_BUFF)),
		"visible": bool(config.get("visible", true)),
		"duration": int(config.get("duration", -1)),   # -1 = permanent
		"element": str(config.get("element", "")),
		"stackable": stackable,
		"max_stacks": int(config.get("max_stacks", 1)),
		"stacks": maxi(1, int(config.get("stacks", 1))),
		"weight": float(config.get("weight", 1.0)),
		# HIDDEN severity gauge — how "big" this stack of buff/debuff is. Reserved
		# for future targeting + character UI; default 1.0, tune per buff.
		"magnitude": float(config.get("magnitude", 1.0)),
		"resistible": bool(config.get("resistible", false)),
		"transient": bool(config.get("transient", false)),
		"silence": bool(config.get("silence", false)),
		"stun": bool(config.get("stun", false)),
		"expire_effect": str(config.get("expire_effect", "")),
		"on_struck": on_struck,
		"per_stack": per_stack,
		# scaled live fields (filled by recompute_scaled below):
		"mods": {},
		"dot": 0.0,
		"dot_element": str(per_stack["dot_element"]),
		"dot_mult": float(per_stack["dot_mult"]),
		"spirit_per_turn": 0.0,
		"resist_mult": 0.0,
		"resist_mult_by_element": {},
	}
	recompute_scaled(entry)
	return entry

## Recompute the live (scaled) fields from per_stack * stacks. Call after `stacks`
## changes. The additive stat system reads entry["mods"], so this is what makes a
## stack actually change the effective stats.
static func recompute_scaled(entry: Dictionary) -> void:
	var per_stack: Dictionary = entry.get("per_stack", _default_per_stack())
	var s := float(maxi(1, int(entry.get("stacks", 1))))

	var scaled_mods := {}
	var base_mods: Dictionary = per_stack.get("mods", {})
	for k in base_mods:
		scaled_mods[k] = float(base_mods[k]) * s
	entry["mods"] = scaled_mods

	entry["dot"] = float(per_stack.get("dot", 0.0)) * s
	entry["dot_element"] = str(per_stack.get("dot_element", "physical"))
	entry["dot_mult"] = float(per_stack.get("dot_mult", 1.0))
	entry["spirit_per_turn"] = float(per_stack.get("spirit_per_turn", 0.0)) * s
	entry["resist_mult"] = float(per_stack.get("resist_mult", 0.0)) * s

	var scaled_rme := {}
	var base_rme: Dictionary = per_stack.get("resist_mult_by_element", {})
	for k in base_rme:
		scaled_rme[k] = float(base_rme[k]) * s
	entry["resist_mult_by_element"] = scaled_rme

# ---------------------------------------------------------------------------
# Small accessors (tolerant of missing keys, so hand-authored entries are safe).
# ---------------------------------------------------------------------------
static func is_buff(entry: Dictionary) -> bool:
	return str(entry.get("kind", KIND_BUFF)) == KIND_BUFF

static func is_debuff(entry: Dictionary) -> bool:
	return str(entry.get("kind", KIND_BUFF)) == KIND_DEBUFF

static func is_visible(entry: Dictionary) -> bool:
	return bool(entry.get("visible", true))

static func is_permanent(entry: Dictionary) -> bool:
	return int(entry.get("duration", -1)) < 0

static func remaining(entry: Dictionary) -> int:
	return int(entry.get("duration", -1))

static func stacks(entry: Dictionary) -> int:
	return maxi(1, int(entry.get("stacks", 1)))

## The hidden severity gauge for this entry (default 1.0). Reserved for future
## targeting + character UI.
static func magnitude(entry: Dictionary) -> float:
	return float(entry.get("magnitude", 1.0))

## The list of on-struck reaction dicts on this entry ([] when none).
static func on_struck(entry: Dictionary) -> Array:
	var r = entry.get("on_struck", [])
	return r if typeof(r) == TYPE_ARRAY else []

## True when this entry reacts to its bearer being struck.
static func has_on_struck(entry: Dictionary) -> bool:
	return not on_struck(entry).is_empty()

## The DoT damage this entry deals THIS turn (already stack-scaled), as an int.
static func dot_damage(entry: Dictionary) -> int:
	var raw := float(entry.get("dot", 0.0)) * float(entry.get("dot_mult", 1.0))
	return int(round(maxf(0.0, raw)))

## The basket name an entry belongs in, from its kind.
static func basket_for(entry: Dictionary) -> String:
	return "debuffs" if is_debuff(entry) else "buffs"
