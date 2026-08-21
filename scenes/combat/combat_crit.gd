extends RefCounted
class_name CombatCrit

## ============================================================================
## COMBAT CRIT  —  critical-strike chance, the roll, and crit damage
## ============================================================================
## Its own script (alongside CombatMitigation) so the crit model can be tuned in
## one place. CombatMath.resolve() asks it for the chance, whether the hit crits,
## and the crit damage multiplier.
##
## CRIT CHANCE (dev-specified):
##   crit% = ( ( luck + (X + Y + Z) * (user_level / target_level) )
##             * ability.crit_chance_mult ) + ability.crit_chance_add
##   X = alacrity / 5            (attacker's alacrity)
##   Y = pierce   / 3            (attacker's pierce for the attack's element)
##   Z = crit-chance bonus summed from the attacker's buffs + debuffs (0 for now)
##   luck = attacker's hidden luck stat
## The result is clamped to 0..100.
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
const PIERCE_DIVISOR   := 3.0     # Y = pierce   / 3
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
static func chance(attacker: CharacterBase, defender: CharacterBase, ability: Ability) -> float:
	if attacker == null or ability == null:
		return 0.0

	var element := ability.element_key()
	var luck := attacker.get_effective("luck")
	var x := attacker.get_effective("alacrity") / ALACRITY_DIVISOR
	var y := attacker.get_effective(Stats.pierce_key(element)) / PIERCE_DIVISOR
	var z := _buff_debuff_bonus(attacker, CRIT_CHANCE_BONUS_KEY)

	var user_level := maxi(1, attacker.level)
	var target_level := maxi(1, defender.level) if defender != null else 1
	var level_ratio := float(user_level) / float(target_level)

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
