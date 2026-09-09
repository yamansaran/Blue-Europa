extends RefCounted
class_name CombatResist

## ============================================================================
## COMBAT RESIST  —  MAGNIFICENCE vs DISDAIN: the debuff-landing system
## ============================================================================
## Two majors that until now existed in Stats and were read by nothing:
##   MAGNIFICENCE — resistance to being debuffed.
##   DISDAIN      — the ability to apply debuffs, and their potency.
##
## They drive TWO separate things, and the split is the whole design:
##
##   1. THE RESIST ROLL (does the debuff land at all?)
##      d       = target.magnificence - caster.disdain
##      resist% = clampf(BASE + SPREAD * squash(STIFFNESS * d) + entry.resist_bias,
##                       MIN_PCT, MAX_PCT)
##      The curve is deliberately SHALLOW. At parity it is 10%, and an enemy that
##      never scales magnificence past its base never resists more than that — so
##      the player's debuffs land ~90% of the time and are always worth casting.
##      The player is the one who can OPT IN to real resistance by investing.
##      Worked: d = 0 -> 10.0% ; +25 -> 19.2% ; +50 -> 25.7% ; +100 -> 34.4% ;
##              +200 -> 43.8% ; +400 -> 51.9% ; asymptote 65%.
##      Downward it hits the 5% floor at only d = -13, i.e. ~13 more Disdain than
##      the target's Magnificence already buys you everything the roll has to give.
##      THAT IS INTENTIONAL — see (2), which is where surplus Disdain actually pays.
##
##   2. THE OVERPOWER TERM (how HARD does the debuff land?)
##      O = maxf(0, squash(OP_STIFFNESS * (caster.disdain - target.magnificence)))
##      A 0..1 gauge of how far the caster out-disdains the target, floored at 0 so
##      a losing caster never gets a WEAKER-than-base debuff. Worked:
##        d = 0 -> 0.00 ; +25 -> 0.23 ; +50 -> 0.38 ; +100 -> 0.55 ; +200 -> 0.71.
##      Each debuff then converts O into effect through TWO per-entry floats
##      (authored in BuffLibrary, see Buff.make), so every debuff scales at its own
##      rate — a damage-over-time gaining a turn is far less powerful than a stun
##      gaining a turn, and the numbers say so:
##        potency_scale  -> potency_mult = 1 + potency_scale * O, multiplied through
##                          the entry's whole numeric per_stack payload by
##                          Buff.scale_potency (mods, mult, dot, spirit_per_turn, ...).
##        duration_scale -> expected extra turns = duration_scale * O, rolled once,
##                          capped by the entry's max_extra_duration. Never applied
##                          to a permanent (duration -1) entry.
##
## So: Disdain up to the target's Magnificence buys RELIABILITY; Disdain past it
## buys POWER. A high-Disdain build does not get a marginally better hit rate on an
## already-90% roll — it gets visibly bigger, longer debuffs.
##
## WHAT IS RESISTIBLE. Buff.make now defaults `resistible` to (kind == debuff), so
## every debuff rolls unless its BuffLibrary entry sets `resistible: false`. Buffs
## never roll. Neither does a self-application (applies_buff_self, permanent_buffs,
## a passive's passive_buff) — CombatBuffs.apply() stays the raw, unconditional
## applier and only CombatBuffs.try_apply() rolls.
##
## class_name global — RESTART Godot once after adding this script.
## ----------------------------------------------------------------------------

# --- resist-roll tuning -----------------------------------------------------
const BASE      := 10.0    # resist % when magnificence == disdain
const SPREAD    := 55.0    # travel from BASE before the clamps
const STIFFNESS := 0.03   # gentler than dodge — the gap must be LARGE to matter
const MIN_PCT   := 5.0     # a debuff is never a certainty
const MAX_PCT   := 70.0    # ...and never a wall, even for a dedicated build

# --- overpower (disdain scaling) tuning -------------------------------------
const OP_STIFFNESS := 0.0535   # scales (disdain - magnificence) before the squash

# --- per-entry field defaults (mirrored in Buff.make) -----------------------
const DEFAULT_MAX_EXTRA_DURATION := 2

# ----------------------------------------------------------------------------
## squash(y) = y / (1 + |y|), mapping any real into (-1, +1).
static func _squash(y: float) -> float:
	return y / (1.0 + absf(y))

## True when this entry should be offered a resist roll at all. Buffs never are;
## a debuff is unless its entry opts out with `resistible: false` (Shatter's
## `stunned`, which is already paid for by consuming an ice debuff, and the
## `hoarfrost` marker, which other abilities read as a combo piece).
static func is_resistible(entry: Dictionary) -> bool:
	if entry.is_empty():
		return false
	return bool(entry.get("resistible", Buff.is_debuff(entry)))

# ----------------------------------------------------------------------------
## The chance in 0..100 that `target` shrugs off `entry` cast by `caster`.
## A null caster is treated as having 0 disdain advantage (environmental effects),
## and a null target cannot resist.
static func resist_chance(caster: CharacterBase, target: CharacterBase, entry: Dictionary) -> float:
	if target == null or not is_resistible(entry):
		return 0.0
	var d := target.get_effective("magnificence")
	if caster != null:
		d -= caster.get_effective("disdain")
	var raw := BASE + SPREAD * _squash(STIFFNESS * d) + float(entry.get("resist_bias", 0.0))
	return clampf(raw, MIN_PCT, MAX_PCT)

## Roll against a resist chance. Pass floor >= 0 to inject a specific 0..99 roll
## (tests). Mirrors CombatCrit.rolls_crit / CombatDodge.rolls_dodge.
static func rolls_resist(chance_pct: float, floor: int = -1) -> bool:
	if chance_pct <= 0.0:
		return false
	var roll := floor if floor >= 0 else (randi() % 100)
	return float(roll) < chance_pct

# ----------------------------------------------------------------------------
## The 0..1 overpower gauge: how far `caster` out-disdains `target`. Floored at 0,
## so a caster who is being out-magnificenced still applies the debuff at its
## authored base strength — never weaker.
static func overpower(caster: CharacterBase, target: CharacterBase) -> float:
	if caster == null or target == null:
		return 0.0
	var d := caster.get_effective("disdain") - target.get_effective("magnificence")
	return maxf(0.0, _squash(OP_STIFFNESS * d))

## The potency multiplier this entry earns at overpower `op`. 1.0 = unscaled.
static func potency_multiplier(entry: Dictionary, op: float) -> float:
	return 1.0 + maxf(0.0, float(entry.get("potency_scale", 0.0))) * maxf(0.0, op)

## Roll the extra-duration bonus this entry earns at overpower `op`, in turns.
## `expected` = duration_scale * op; the whole part is granted outright and the
## fractional part is the chance of one more, so a duration_scale of 2.0 can grant
## up to 2 turns at full overpower. Capped by the entry's max_extra_duration, and
## always 0 for a permanent (duration -1) or already-expired entry.
static func roll_extra_duration(entry: Dictionary, op: float, forced: float = -1.0) -> int:
	if int(entry.get("duration", -1)) <= 0:
		return 0
	var scale := maxf(0.0, float(entry.get("duration_scale", 0.0)))
	var expected := scale * maxf(0.0, op)
	if expected <= 0.0:
		return 0
	var whole := int(floor(expected))
	var frac := expected - float(whole)
	var roll := forced if forced >= 0.0 else randf()
	var extra := whole + (1 if roll < frac else 0)
	var cap := int(entry.get("max_extra_duration", DEFAULT_MAX_EXTRA_DURATION))
	return clampi(extra, 0, maxi(0, cap))

# ----------------------------------------------------------------------------
## Apply the full disdain scaling to `entry` IN PLACE, before it is handed to
## CombatBuffs.apply. Multiplies the numeric per-stack payload by the potency
## multiplier (via Buff.scale_potency, which also refreshes the live mirrors) and
## extends `duration` by the rolled bonus. Records the applied potency multiplier
## on the entry as "potency_applied" so a later re-application of a STACKING debuff
## at a higher overpower can rescale the existing entry rather than being locked to
## the first cast's numbers (CombatBuffs.apply handles that).
## Returns { "potency": float, "extra_turns": int }.
static func apply_scaling(entry: Dictionary, op: float) -> Dictionary:
	var mult := potency_multiplier(entry, op)
	if mult != 1.0:
		Buff.scale_potency(entry, mult)
	entry["potency_applied"] = mult

	var extra := roll_extra_duration(entry, op)
	if extra > 0:
		entry["duration"] = int(entry.get("duration", 0)) + extra
	# Recorded on the entry so the BuffBar chip can mark itself as empowered and its
	# hover card can state exactly what the caster's Disdain bought.
	entry["duration_bonus"] = extra
	return { "potency": mult, "extra_turns": extra }

## True when this entry actually gained something from its caster's Disdain — used by
## the UI to flag it. Tolerant of entries that predate the system.
static func is_empowered(entry: Dictionary) -> bool:
	return float(entry.get("potency_applied", 1.0)) > 1.0 \
		or int(entry.get("duration_bonus", 0)) > 0
