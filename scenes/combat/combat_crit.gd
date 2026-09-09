extends RefCounted
class_name CombatCrit

## ============================================================================
## COMBAT CRIT  —  critical-strike chance, the roll, and crit damage
## ============================================================================
## Its own script (alongside CombatMitigation) so the crit model can be tuned in
## one place. CombatMath.resolve() asks it for the chance, whether the hit crits,
## and the crit damage multiplier.
##
## CRIT CHANCE:
##   crit% = ( ( luck + (X + Y + Z) * L ) * ability.crit_chance_mult )
##           + ability.crit_chance_add
##   X = alacrity / 5            (attacker's alacrity)
##   Y = (pierce + DEFENSE_DEFAULT - resistance) / 3
##   Z = crit-chance bonus summed from the attacker's buffs + debuffs
##   L = clampf(user_level / target_level, LEVEL_RATIO_MIN, LEVEL_RATIO_MAX)
##   luck = attacker's hidden luck stat
## The result is clamped to 0..100.
##
## THE Y TERM IS A DIFFERENCE, ANCHORED. It used to be a bare `pierce / 3`, which
## meant a target's elemental defence did nothing to its odds of being critically
## struck. It is now the GAP between the attacker's pierce and the defender's
## resistance for the attack's element — offset by Stats.DEFENSE_DEFAULT (45) so
## the scale stays anchored to a STANDARD defender:
##   - against a target at the default 45 defence, Y collapses to exactly pierce/3,
##     i.e. IDENTICAL to the old formula. Nothing rebalances at baseline.
##   - against a 90-defence boss:  Y = (15 + 45 - 90)/3 = -10  -> crit collapses
##     unless you actually build pierce for that element.
##   - against a 0-defence target: Y = (15 + 45 - 0)/3  = +20  -> crit rewards you.
## `resistance` includes the defender's MULTIPLICATIVE resist layer (the same
## CombatBuffs.resist_mult_bonus the mitigation stage uses), so a Netzach-buffed
## target is harder to crit as well as harder to hurt.
##
## THE LEVEL TERM IS CLAMPED. `user_level / target_level` was unbounded, so a
## level-100 attacker against a level-1 enemy multiplied its (X+Y+Z) group by 100
## and was GUARANTEED to crit every hit. It is now clamped to [0.5, 1.5]: out-
## levelling a target is worth up to +50% of the group and no more, and being
## out-levelled never costs more than half of it.
##
## THE ROLL:
##   crit_floor = a random int in 0..99. If crit_floor < crit% -> critical strike.
##   (So crit% = 100 always crits, crit% = 0 never does.)
##
## CRIT DAMAGE (dev-specified): three numbers multiplied together —
##   1) the CHARACTER's base crit-damage multiplier (base 3.0, read from the body;
##      per-character overridable via base_stats["crit_damage_mult"]).
##   2) the ABILITY's crit-damage multiplier (base 1.0, ability.crit_damage_mult).
##   3) the BUFF/DEBUFF number: 1.0 + (crit-damage bonus summed from buffs+debuffs).
##   final_crit_mult = 1 * 2 * 3.
## ----------------------------------------------------------------------------

# --- tuning knobs -----------------------------------------------------------
const ALACRITY_DIVISOR := 5.0     # X = alacrity / 5
const PIERCE_DIVISOR   := 3.0     # Y = (pierce + anchor - resistance) / 3
## The defence level the pierce-vs-resistance gap is measured against. Set to the
## standard defender (Stats.DEFENSE_DEFAULT, 45) so a fight against a stock-defence
## target produces exactly the old `pierce / 3` — the rework is a pure generalisation
## at baseline, and only bites for targets that are unusually armoured or unusually
## soft in the attack's element.
const CRIT_GAP_ANCHOR := Stats.DEFENSE_DEFAULT
## Bounds on the user/target level ratio, so a huge level lead can't guarantee crits.
const LEVEL_RATIO_MIN := 0.5
const LEVEL_RATIO_MAX := 1.5
const DEFAULT_CHAR_CRIT_DAMAGE := 3.0   # fallback if the body has no crit_damage_mult

# --- basket stat keys (read from buffs + debuffs) ---------------------------
## Additive contributions to the (X + Y + Z) crit-chance group (percentage points).
const CRIT_CHANCE_BONUS_KEY := "crit_chance_bonus"
## Additive contributions to the buff/debuff crit-damage number (around 1.0).
const CRIT_DAMAGE_BONUS_KEY := "crit_damage_bonus"

## Sum a stat across ONLY the buffs and debuffs baskets (skills/combat effects).
static func _buff_debuff_bonus(body: CharacterBase, key: String) -> float:
	if body == null:
		return 0.0
	return body.get_basket_bonus("buffs", key) + body.get_basket_bonus("debuffs", key)

# ----------------------------------------------------------------------------
## Crit chance as a number in 0..100.
## `extra_pierce` is the same per-hit pierce rider the mitigation stage receives
## (Cryonecrosis' pierce-per-ice-debuff); it counts toward the crit gap too, so a
## setup that shreds resistance also improves the odds of a crit.
static func chance(attacker: CharacterBase, defender: CharacterBase, ability: Ability, extra_pierce: float = 0.0) -> float:
	if attacker == null or ability == null:
		return 0.0

	var element := ability.element_key()
	var luck := attacker.get_effective("luck")
	var x := attacker.get_effective("alacrity") / ALACRITY_DIVISOR
	# Y is the pierce-vs-resistance GAP, anchored to a standard-defence target. The
	# defender's multiplicative resist layer counts here exactly as it does in the
	# mitigation stage, so a resist buff also protects against crits.
	var resistance := 0.0
	if defender != null:
		resistance = defender.get_effective(Stats.defense_key(element))
		resistance = maxf(0.0, resistance * (1.0 + CombatBuffs.resist_mult_bonus(defender, element)))
	var pierce := attacker.get_effective(Stats.pierce_key(element)) + maxf(0.0, extra_pierce)
	var y := (pierce + CRIT_GAP_ANCHOR - resistance) / PIERCE_DIVISOR
	var z := _buff_debuff_bonus(attacker, CRIT_CHANCE_BONUS_KEY)

	var user_level := maxi(1, attacker.level)
	var target_level := maxi(1, defender.level) if defender != null else 1
	var level_ratio := clampf(float(user_level) / float(target_level), LEVEL_RATIO_MIN, LEVEL_RATIO_MAX)

	var ability_mult := _ability_crit_chance_mult(ability)
	var ability_add := _ability_crit_chance_add(ability)

	var raw := (luck + (x + y + z) * level_ratio) * ability_mult + ability_add
	return clampf(raw, 0.0, 100.0)

## Roll against a chance. Pass floor >= 0 to inject a specific 0..99 roll (tests);
## otherwise a fresh random 0..99 is drawn.
static func rolls_crit(chance_pct: float, floor: int = -1) -> bool:
	var crit_floor := floor if floor >= 0 else (randi() % 100)
	return float(crit_floor) < chance_pct

## The final crit damage multiplier = char_base * ability * (1 + buff/debuff sum).
static func damage_multiplier(attacker: CharacterBase, ability: Ability) -> float:
	var char_base := DEFAULT_CHAR_CRIT_DAMAGE
	if attacker != null:
		# base_stats value if present (per-character override), else the 3.0 default.
		if attacker.base_stats.has("crit_damage_mult"):
			char_base = attacker.get_base("crit_damage_mult")
	var ability_mult := _ability_crit_damage_mult(ability)
	var buff_number := 1.0 + _buff_debuff_bonus(attacker, CRIT_DAMAGE_BONUS_KEY)
	return char_base * ability_mult * buff_number

# ----------------------------------------------------------------------------
# Ability field access — tolerant of abilities authored before the crit fields
# existed (missing property -> the documented default).
# ----------------------------------------------------------------------------
static func _ability_crit_chance_mult(ability: Ability) -> float:
	if ability != null and "crit_chance_mult" in ability:
		return float(ability.crit_chance_mult)
	return 1.0

static func _ability_crit_chance_add(ability: Ability) -> float:
	if ability != null and "crit_chance_add" in ability:
		return float(ability.crit_chance_add)
	return 0.0

static func _ability_crit_damage_mult(ability: Ability) -> float:
	if ability != null and "crit_damage_mult" in ability:
		return float(ability.crit_damage_mult)
	return 1.0
