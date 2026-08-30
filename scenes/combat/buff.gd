extends RefCounted
class_name Buff

## ============================================================================
## BUFF  —  the data model for one buff / debuff (class_name global)
## ============================================================================
## A buff or debuff is a persistent combat effect. It is stored as a plain
## Dictionary ENTRY inside a CharacterBase basket ("buffs" or "debuffs"), so it
## rides the SAME "everything is a basket of stat mods" model everything else
## uses — CharacterBase.get_bonus() sums an entry's "mods" (flat) and
## get_mult_bonus() sums its "mult" (multiplier) with no knowledge that it is a
## buff. That is deliberate: any stat augment a buff carries (a +5 vigor buff, a
## +20% vigor buff, Malkuth's -15 resists, a temporary max-HP via hp_base) is just
## a key in "mods" / "mult" and works for free — AND now shows in the effective
## stat readouts, then clears when the fight ends (buffs live on the battle clone).
##
## On TOP of "mods" / "mult", a buff entry carries extra fields for the mechanics
## that are NOT a plain stat:
##   - a per-turn DoT (bleed / poison), with its own element and flat multiplier
##   - a per-turn spirit change (regen buff / drain debuff)
##   - a MULTIPLICATIVE resist multiplier (read by CombatMath as a real layer)
##   - silence / stun gameplay flags
##   - an on-expire event hook id
## and the metadata the systems around it read: visible vs hidden, duration,
## element tag, stackable + max_stacks + current stacks, weight, magnitude,
## resistible, transient, and a list of ON-STRUCK reactions.
##
## STACKING. A stackable buff is stored as ONE entry with a `stacks` count. The
## PER-STACK values live in entry["per_stack"]; the live top-level fields
## ("mods", "mult", "dot", "spirit_per_turn", "resist_mult", ...) are the per-stack
## values times `stacks`, recomputed by recompute_scaled(). That way the stat reads
## (which see the top-level "mods"/"mult") automatically reflect the stack count.
##
## NOTE — TWO different "mult"s: entry["mult"] here is the BASE-STAT multiplier
## layer (scales vigor, defenses, ... and shows in readouts). The separate
## per-stack "resist_mult" is the combat-only damage-pipeline resist layer read by
## CombatMath. They are unrelated; keep them straight.
##
## class_name global — RESTART Godot once after adding this script.
## ----------------------------------------------------------------------------

const KIND_BUFF := "buff"
const KIND_DEBUFF := "debuff"

## A fresh per-stack payload with every field at its neutral default.
static func _default_per_stack() -> Dictionary:
	return {
		"mods": {},                 # FLAT additive stat mods (per stack)
		"mult": {},                 # MULTIPLIER stat mods, 0.2 = +20% (per stack)
		"dot": 0.0,                 # damage-over-time per turn (per stack)
		"dot_element": "physical",  # element the DoT is dealt as
		"dot_mult": 1.0,            # flat DoT multiplier (future buffs tune this)
		"dot_pct_per_turn": 0.0,    # DoT per turn as a FRACTION of the bearer's current
									#   max HP (0.05 = 5%); read LIVE each turn against
									#   max_hp() and ADDED to the flat `dot`. The exact
									#   mirror of heal_pct_per_turn. Dealt as dot_element,
									#   so a "true" DoT ignores mitigation AND shields.
									#   Used by Sclerosis in Binah.
		"spirit_per_turn": 0.0,     # + regen / - drain per turn (per stack)
		"heal_per_turn": 0.0,       # HP restored per turn (per stack); snapshotted at apply
		"heal_pct_per_turn": 0.0,   # HP restored per turn as a FRACTION of the bearer's current
									#   max HP (0.10 = 10%); read LIVE each turn against max_hp()
		"resist_mult": 0.0,         # GLOBAL multiplicative resist bonus (per stack)
		"resist_mult_by_element": {}, # per-element multiplicative resist bonus
	}

## Build a full buff/debuff entry from a partial `config`. Everything not given
## falls back to a sane default. `config` may set any metadata field directly and
## supplies the per-stack payload under whatever of these keys it wants:
##   mods, mult, dot, dot_element, dot_mult, spirit_per_turn, resist_mult,
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
	per_stack["mult"] = (per_stack["mult"] as Dictionary).duplicate(true)
	per_stack["resist_mult_by_element"] = (per_stack["resist_mult_by_element"] as Dictionary).duplicate(true)

	# ON-STRUCK reactions: a list of "when this bearer is struck, do X" effect
	# dicts (see CombatBuffs.fire_on_struck for the dispatch). Deep-copied so two
	# entries never share the list. Empty = no reaction.
	var on_struck: Array = []
	var raw_on_struck = config.get("on_struck", [])
	if typeof(raw_on_struck) == TYPE_ARRAY:
		on_struck = (raw_on_struck as Array).duplicate(true)

	# ON-HIT-APPLY: a list of "when the BEARER lands an attack, apply a buff to the
	# target it hit" specs (see CombatBuffs.fire_on_hit). Each spec is a dict
	# { "buff": "<id>", (opt) "duration": int } — the named buff is built and applied
	# to the struck target, with duration overridden when given. Deep-copied; empty =
	# no on-hit effect. Used by Wraith Form to coat every struck target in Rime Skin.
	var on_hit_apply: Array = []
	var raw_on_hit = config.get("on_hit_apply", [])
	if typeof(raw_on_hit) == TYPE_ARRAY:
		on_hit_apply = (raw_on_hit as Array).duplicate(true)

	# ON-HIT-DAMAGE: a list of "when the BEARER lands an attack, deal EXTRA damage to
	# the target it hit" specs (see CombatBuffs.fire_on_hit). Each spec is a dict
	# { "element": "lightning", (opt) "amount": float, (opt) "scale_stat": "vigor",
	#   (opt) "pct": float } — the bonus hit is `amount + pct * attacker[scale_stat]`,
	# resolved through the normal damage pipeline and dealt with NO source (so it can
	# trigger no on-struck reaction and cannot recurse). Deep-copied; empty = none.
	# Used by Energized Form (+45% of Vigor as Lightning damage on every hit).
	var on_hit_damage: Array = []
	var raw_on_hit_dmg = config.get("on_hit_damage", [])
	if typeof(raw_on_hit_dmg) == TYPE_ARRAY:
		on_hit_damage = (raw_on_hit_dmg as Array).duplicate(true)

	# OVERFLOW-SHIELD: "spirit that refills past my maximum becomes an absorbing shield".
	# A spec dict { "per_spirit": int, "scale": { stat_key: fraction }, (opt) "decay": {} }:
	# for every `per_spirit` points of spirit the bearer WOULD have gained above its cap,
	# it gains a shield of sum(fraction * bearer[stat]) — read LIVE off the bearer, not
	# snapshotted, so it tracks Vitality/Instinct as they move. Read by
	# BattleCharacter.change_spirit via CombatBuffs.overflow_shield_specs. Deep-copied;
	# empty = overfilled spirit is wasted as usual. Used by Lightning Shell (Geburah).
	var overflow_shield := {}
	var raw_overflow = config.get("overflow_shield", {})
	if typeof(raw_overflow) == TYPE_DICTIONARY:
		overflow_shield = (raw_overflow as Dictionary).duplicate(true)

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
		# Per-stack ice-damage amplifier (Hoarfrost). While present, the NEXT sourced
		# ice hit on the bearer is multiplied by (1 + ice_amp_per_stack * stacks) and
		# then this entry is consumed. Plain metadata (not stack-scaled here — the ×stacks
		# is applied by CombatBuffs.apply_incoming_ice_amp at read time). 0.0 = inert.
		"ice_amp_per_stack": float(config.get("ice_amp_per_stack", 0.0)),
		"expire_effect": str(config.get("expire_effect", "")),
		"on_struck": on_struck,
		"on_hit_apply": on_hit_apply,
		"on_hit_damage": on_hit_damage,
		"overflow_shield": overflow_shield,
		"per_stack": per_stack,
		# scaled live fields (filled by recompute_scaled below):
		"mods": {},
		"mult": {},
		"dot": 0.0,
		"dot_element": str(per_stack["dot_element"]),
		"dot_mult": float(per_stack["dot_mult"]),
		"dot_pct_per_turn": 0.0,
		"spirit_per_turn": 0.0,
		"heal_per_turn": 0.0,
		"heal_pct_per_turn": 0.0,
		"resist_mult": 0.0,
		"resist_mult_by_element": {},
	}
	recompute_scaled(entry)
	return entry

## Recompute the live (scaled) fields from per_stack * stacks. Call after `stacks`
## changes. The stat system reads entry["mods"] (flat) and entry["mult"]
## (multiplier), so this is what makes a stack actually change the effective stats.
static func recompute_scaled(entry: Dictionary) -> void:
	var per_stack: Dictionary = entry.get("per_stack", _default_per_stack())
	var s := float(maxi(1, int(entry.get("stacks", 1))))

	var scaled_mods := {}
	var base_mods: Dictionary = per_stack.get("mods", {})
	for k in base_mods:
		scaled_mods[k] = float(base_mods[k]) * s
	entry["mods"] = scaled_mods

	var scaled_mult := {}
	var base_mult: Dictionary = per_stack.get("mult", {})
	for k in base_mult:
		scaled_mult[k] = float(base_mult[k]) * s
	entry["mult"] = scaled_mult

	entry["dot"] = float(per_stack.get("dot", 0.0)) * s
	entry["dot_element"] = str(per_stack.get("dot_element", "physical"))
	entry["dot_mult"] = float(per_stack.get("dot_mult", 1.0))
	entry["dot_pct_per_turn"] = float(per_stack.get("dot_pct_per_turn", 0.0)) * s
	entry["spirit_per_turn"] = float(per_stack.get("spirit_per_turn", 0.0)) * s
	entry["heal_per_turn"] = float(per_stack.get("heal_per_turn", 0.0)) * s
	entry["heal_pct_per_turn"] = float(per_stack.get("heal_pct_per_turn", 0.0)) * s
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

## The list of on-hit-apply spec dicts on this entry ([] when none). Each is
## { "buff": "<id>", (opt) "duration": int } — applied to the target the bearer hits.
static func on_hit_apply(entry: Dictionary) -> Array:
	var r = entry.get("on_hit_apply", [])
	return r if typeof(r) == TYPE_ARRAY else []

## The list of on-hit-damage spec dicts on this entry ([] when none). Each is
## { "element": s, "amount"?: f, "scale_stat"?: s, "pct"?: f } — bonus damage the
## bearer deals to whatever it hits. NOT stack-scaled here; fire_on_hit scales by stacks.
static func on_hit_damage(entry: Dictionary) -> Array:
	var r = entry.get("on_hit_damage", [])
	return r if typeof(r) == TYPE_ARRAY else []

## This entry's overflow-shield spec ({} when it has none) —
## { "per_spirit": int, "scale": { stat_key: fraction }, (opt) "decay": {} }. See the
## comment in make(). Plain metadata, NOT stack-scaled.
static func overflow_shield(entry: Dictionary) -> Dictionary:
	var r = entry.get("overflow_shield", {})
	return r if typeof(r) == TYPE_DICTIONARY else {}

## The RAW DoT damage this entry deals THIS turn (already stack-scaled), as an int.
## NOTE: this is BEFORE the bearer's `vulnerability` multiplier — CombatBuffs
## applies vulnerability when it collects the turn's DoT (see collect_turn_start).
static func dot_damage(entry: Dictionary) -> int:
	var raw := float(entry.get("dot", 0.0)) * float(entry.get("dot_mult", 1.0))
	return int(round(maxf(0.0, raw)))

## The HP this entry restores THIS turn (already stack-scaled), as an int. Mirrors
## dot_damage but for the heal-over-turn field. The amount is snapshotted into
## heal_per_turn when the buff is built (e.g. Scaled Skin bakes 30/40/50% of the
## target's Instinct at cast), so this is a plain readout of that stored value.
static func heal_amount(entry: Dictionary) -> int:
	return int(round(maxf(0.0, float(entry.get("heal_per_turn", 0.0)))))

## The basket name an entry belongs in, from its kind.
static func basket_for(entry: Dictionary) -> String:
	return "debuffs" if is_debuff(entry) else "buffs"
