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
## STACKING — INDEPENDENT INSTANCES. Stacking is the DEFAULT (`stackable` is true
## unless an entry opts out), and each application is appended by CombatBuffs.apply as
## its OWN separate entry rather than merged into one with a bumped count. Every
## instance freezes the numbers it was built with — the caster's Instinct snapshot, the
## Disdain potency multiplier, the rolled duration — and ticks and expires on its own
## clock. NOTHING later reaches back into an instance that has already landed, so a
## second, stronger cast lands as a second, stronger instance and leaves the first
## alone. Once applied, a debuff is fully disconnected from its caster; only the
## BEARER's own layer (vulnerability, resistance, damage_taken_mult) still modulates
## it, because those are read live off the bearer at tick time.
##
## The per-entry `stacks` count and the per_stack -> live mirroring (recompute_scaled)
## remain for an entry AUTHORED with stacks > 1, but re-application no longer uses
## them; `max_stacks` is now a cap on the NUMBER OF INSTANCES.
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

## Instance cap applied to a stacking entry that names no `max_stacks` of its own.
## Effectively unlimited by design — a cap is a deliberate authoring decision, never
## something the engine imposes behind your back. 216 rather than 0 (0 = truly
## unlimited) only so a runaway loop has a ceiling.
const DEFAULT_MAX_STACKS := 216

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

	# STACKING IS THE DEFAULT, AND EACH STACK IS AN INDEPENDENT INSTANCE.
	# `stackable` defaults TRUE; an effect that must stay single-instance opts out with
	# `stackable: false`. Re-applying a stacking effect does NOT merge into one entry —
	# CombatBuffs.apply appends a SEPARATE entry with its own frozen numbers and its own
	# duration. That is what makes an applied debuff independent of the caster: a later,
	# stronger cast never reaches back and empowers an earlier one, and each instance
	# expires on its own schedule.
	# `max_stacks` is therefore a cap on the NUMBER OF INSTANCES, defaulting to the
	# effectively-unlimited DEFAULT_MAX_STACKS. Capping is an authoring decision — set
	# it only when an effect genuinely needs one.
	var stackable := bool(config.get("stackable", true))
	# Kind is read first because `resistible` now DEFAULTS from it (see below).
	var kind := str(config.get("kind", KIND_BUFF))
	var entry := {
		"id": str(config.get("id", "buff")),
		"source": str(config.get("source", "Buff")),
		"desc": str(config.get("desc", "")),
		# Optional token template re-rendered from the entry's LIVE numbers every time
		# the text is displayed (see describe). Set this on anything whose description
		# quotes a value, so an instance empowered by Disdain shows what it ACTUALLY
		# does rather than the base figure it was authored with. Blank = use `desc`.
		"desc_template": str(config.get("desc_template", "")),
		"kind": kind,
		"visible": bool(config.get("visible", true)),
		"duration": int(config.get("duration", -1)),   # -1 = permanent
		"element": str(config.get("element", "")),
		"stackable": stackable,
		"max_stacks": int(config.get("max_stacks", DEFAULT_MAX_STACKS)),
		"stacks": maxi(1, int(config.get("stacks", 1))),
		"weight": float(config.get("weight", 1.0)),
		# HIDDEN severity gauge — how "big" this stack of buff/debuff is. Reserved
		# for future targeting + character UI; default 1.0, tune per buff.
		"magnitude": float(config.get("magnitude", 1.0)),
		# MAGNIFICENCE / DISDAIN — the resist roll (CombatResist). This now DEFAULTS
		# to "every debuff can be resisted, no buff can": a debuff rolls the target's
		# magnificence against the caster's disdain before it lands. Set it to false
		# explicitly on a debuff that must ALWAYS land — Shatter's `stunned` (already
		# paid for by consuming an ice debuff) and the `hoarfrost` combo marker.
		"resistible": bool(config.get("resistible", kind == KIND_DEBUFF)),
		# Flat percentage points added to the target's resist chance for THIS entry
		# (negative = harder to shrug off). The per-debuff "slippery / sticky" knob.
		"resist_bias": float(config.get("resist_bias", 0.0)),
		# --- DISDAIN SCALING (CombatResist.apply_scaling) ------------------------
		# How much surplus Disdain amplifies this debuff. O is the 0..1 overpower
		# gauge = squash(0.012 * (caster.disdain - target.magnificence)).
		#   potency_scale  : the entry's whole numeric per_stack payload is multiplied
		#                    by (1 + potency_scale * O). 0 = never amplified (a stun
		#                    has no magnitude to grow). 1.0 = up to +100% at extreme
		#                    overpower, ~+55% at a 100-point Disdain lead.
		#   duration_scale : expected EXTRA turns = duration_scale * O, rolled once.
		#                    Tune this DOWN for control (an extra stun turn is worth
		#                    far more than an extra tick of a damage-over-time).
		#   max_extra_duration : hard cap on the rolled bonus, in turns.
		"potency_scale": float(config.get("potency_scale", 0.0)),
		"duration_scale": float(config.get("duration_scale", 0.0)),
		"max_extra_duration": int(config.get("max_extra_duration", 2)),
		# The potency multiplier actually baked into per_stack when this entry was
		# applied (1.0 = unscaled). CombatBuffs.apply reads it so a re-applied
		# STACKING debuff cast at a HIGHER overpower rescales the existing entry up
		# instead of being locked to the first cast's numbers.
		"potency_applied": 1.0,
		# Extra turns this entry's duration actually gained from the caster's Disdain
		# (CombatResist.roll_extra_duration). Display-only — the bonus is already baked
		# into `duration`; this is what lets the BuffBar say WHY the number is high.
		"duration_bonus": 0,
		"transient": bool(config.get("transient", false)),
		"silence": bool(config.get("silence", false)),
		"stun": bool(config.get("stun", false)),
		# --- CHARGES: a lifetime measured in ATTACKS rather than in turns --------
		# "for the next N attacks". 0 (the default) = UNLIMITED, so every existing
		# entry is unchanged. When positive, CombatBuffs.spend_attack_charges
		# decrements it each time the BEARER lands an attack and removes the entry
		# the moment it reaches 0. `duration` still runs in parallel and is the
		# OUTER bound — whichever runs out first ends the buff. NOT stack-scaled:
		# stacking a charged buff refreshes its charges rather than multiplying them
		# (see CombatBuffs.apply), because "three more attacks" is the intent.
		"charges": maxi(0, int(config.get("charges", 0))),
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

## Every numeric per_stack key that represents a MAGNITUDE, and is therefore scaled
## by the caster's Disdain overpower. Deliberately excludes `dot_mult` (itself a
## multiplier, not a magnitude) and `dot_element` (a string).
const POTENCY_SCALAR_KEYS := [
	"dot", "dot_pct_per_turn", "spirit_per_turn",
	"heal_per_turn", "heal_pct_per_turn", "resist_mult",
]
## Per_stack keys holding a {stat_key: value} map whose VALUES are magnitudes.
const POTENCY_MAP_KEYS := ["mods", "mult", "resist_mult_by_element"]

## Multiply this entry's whole numeric payload by `mult`, IN PLACE, then refresh the
## live mirrors. This is how DISDAIN amplifies a debuff (CombatResist.apply_scaling):
## every magnitude the entry carries — flat stat mods, multiplier mods, damage- and
## heal-over-time, spirit drain, multiplicative resist, and the top-level hoarfrost
## ice amp — grows by the same factor, so ANY debuff in the catalogue scales with
## zero per-buff code. Negative mods (Hypothermia's alacrity cut) get MORE negative,
## which is correct: a bigger cut.
## A `mult` of 1.0 is a no-op; values below 0 are ignored.
static func scale_potency(entry: Dictionary, mult: float) -> void:
	if entry.is_empty() or mult < 0.0 or is_equal_approx(mult, 1.0):
		return
	var per_stack: Dictionary = entry.get("per_stack", _default_per_stack())

	for k in POTENCY_SCALAR_KEYS:
		if per_stack.has(k):
			per_stack[k] = float(per_stack[k]) * mult

	for k in POTENCY_MAP_KEYS:
		if not per_stack.has(k) or typeof(per_stack[k]) != TYPE_DICTIONARY:
			continue
		var m: Dictionary = per_stack[k]
		for stat_key in m:
			m[stat_key] = float(m[stat_key]) * mult

	# Hoarfrost's ice amplification is top-level metadata, not part of per_stack, so
	# it has to be scaled explicitly — otherwise a high-Disdain Hoarfrost would be
	# the one debuff that ignored the system.
	if entry.has("ice_amp_per_stack"):
		entry["ice_amp_per_stack"] = float(entry["ice_amp_per_stack"]) * mult

	entry["per_stack"] = per_stack
	recompute_scaled(entry)

# ---------------------------------------------------------------------------
# LIVE DESCRIPTION
# ---------------------------------------------------------------------------
## An entry's description with its ACTUAL current numbers substituted in.
##
## WHY THIS EXISTS. `desc` is baked by BuffLibrary at build time from the base values,
## so the moment a cast is empowered by the caster's Disdain (potency multiplier and/or
## extra turns) the stored text is a lie — it promises 40 damage while the entry ticks
## for 62. An entry that sets `desc_template` gets re-rendered from its LIVE fields
## every time the text is shown, so the card always states what this instance will
## really do. An entry with no template falls back to the static `desc`, so nothing
## that predates this is affected.
##
## TOKENS (all read off the live, stack-scaled and potency-scaled fields):
##   {dot}        flat damage-over-time per turn, incl. dot_mult   e.g. "62"
##   {dot_pct}    dot_pct_per_turn as whole percent                e.g. "5"
##   {heal}       heal_per_turn                                    e.g. "30"
##   {heal_pct}   heal_pct_per_turn as whole percent
##   {spirit}     spirit_per_turn, signed                          e.g. "-20"
##   {spiritabs}  spirit_per_turn, magnitude only                  e.g. "20"
##   {duration}   turns remaining as an integer ("inf" if permanent)
##   {turns}      turns remaining, pluralised                      e.g. "3 turns"
##   {mod:<stat>}     that flat mod, signed        e.g. {mod:ice_defense}  -> "-15"
##   {modabs:<stat>}  that flat mod, magnitude     e.g.                    -> "15"
##   {modpct:<stat>}     a flat mod that IS a fraction, as whole percent — for the
##   {modpctabs:<stat>}  keys stored in `mods` around 0 (healing_received_mult,
##                       damage_taken_mult, ...): -0.5 -> "-50" / "50"
##   {mult:<stat>}    that multiplier as whole percent, signed  e.g. "-30"
##   {multabs:<stat>} same, magnitude only
static func describe(entry: Dictionary) -> String:
	var tmpl := str(entry.get("desc_template", ""))
	if tmpl == "":
		return str(entry.get("desc", ""))

	var dur := int(entry.get("duration", -1))
	var spirit := float(entry.get("spirit_per_turn", 0.0))
	var out := tmpl
	out = out.replace("{dot}", str(dot_damage(entry)))
	out = out.replace("{dot_pct}", str(int(round(float(entry.get("dot_pct_per_turn", 0.0)) * 100.0))))
	out = out.replace("{heal}", str(heal_amount(entry)))
	out = out.replace("{heal_pct}", str(int(round(float(entry.get("heal_pct_per_turn", 0.0)) * 100.0))))
	out = out.replace("{spirit}", "%d" % int(round(spirit)))
	out = out.replace("{spiritabs}", "%d" % int(round(absf(spirit))))
	out = out.replace("{duration}", "inf" if dur < 0 else str(dur))
	out = out.replace("{turns}", "permanent" if dur < 0 else "%d turn%s" % [dur, "" if dur == 1 else "s"])

	# {mod:<stat>} / {modabs:<stat>} / {mult:<stat>} / {multabs:<stat>}
	var re := RegEx.new()
	# Longest alternatives first so "modpctabs" is not eaten by "mod".
	if re.compile("\\{(modpctabs|modpct|modabs|mod|multabs|mult):([A-Za-z0-9_]+)\\}") != OK:
		return out
	# Replace back-to-front so earlier match offsets stay valid.
	var matches := re.search_all(out)
	for i in range(matches.size() - 1, -1, -1):
		var m: RegExMatch = matches[i]
		var kind := m.get_string(1)
		var stat := m.get_string(2)
		var src: Dictionary = entry.get("mult" if kind.begins_with("mult") else "mods", {})
		var v := float(src.get(stat, 0.0))
		if kind.begins_with("mult") or kind.begins_with("modpct"):
			v *= 100.0
		if kind.ends_with("abs"):
			v = absf(v)
		out = out.substr(0, m.get_start()) + ("%d" % int(round(v))) + out.substr(m.get_end())
	return out

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

## Attack-charges left on this entry. 0 = UNLIMITED (the default), which is why
## every caller has to test `has_charges` rather than `charges > 0`.
static func charges(entry: Dictionary) -> int:
	return maxi(0, int(entry.get("charges", 0)))

## True when this entry's lifetime is measured in attacks as well as in turns.
static func has_charges(entry: Dictionary) -> bool:
	return charges(entry) > 0

## Spend ONE attack charge. Returns true when that was the last one, i.e. the
## caller should now REMOVE the entry. A charge-less entry is never spent and
## always returns false.
static func spend_charge(entry: Dictionary) -> bool:
	if not has_charges(entry):
		return false
	entry["charges"] = charges(entry) - 1
	return int(entry["charges"]) <= 0

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
