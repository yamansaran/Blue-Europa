extends RefCounted
class_name CombatMath

## ============================================================================
## COMBAT MATH  —  the single place damage is turned into a number
## ============================================================================
## Everything routes through resolve() / resolve_damage(). The pipeline is:
##
##   1. PRE-MITIGATION  — the ability's damage output * pre-mitigation multipliers
##                        (stored as buffs/debuffs on the attacker, visible or
##                        hidden), via the PRE_DAMAGE_MULT_KEY basket stat.
##   2. MITIGATION      — CombatMitigation.apply(pre, R, P, A) with the attack's
##                        element resistance/pierce/amplification. (TRUE bypasses.)
##   3. CRIT            — CombatCrit rolls the chance; on a crit the post-mitigation
##                        damage is multiplied by CombatCrit.damage_multiplier(...).
##
## The element stats are already summed (base + every basket) on the two bodies:
##   attacker.get_effective( Stats.pierce_key(element) )   # e.g. "fire_pierce"
##   defender.get_effective( Stats.defense_key(element) )  # e.g. "fire_defense"
##   attacker.get_effective( Stats.amp_key(element) )      # e.g. "fire_amp"
## The hidden TRUE element has 0 for all three, so mitigation is a no-op there.
##
## MULTIPLICATIVE RESIST LAYER (buffs). On top of the additive defense stat, the
## defender's buffs/debuffs can carry a MULTIPLICATIVE resist bonus (e.g. Bet:
## +100% all resists, stacking). The mitigation stage multiplies the defender's
## effective defense by (1 + CombatBuffs.resist_mult_bonus(defender, element))
## BEFORE handing R to CombatMitigation, so flat resist mods (Dalet's -15) and the
## percentage layer compose: R = (base_defense + flat_mods) * (1 + resist_mult).
## ----------------------------------------------------------------------------

## Basket stat key holding pre-mitigation damage multipliers. Stored on buffs /
## debuffs as an ADDITIVE bonus around 1.0: a +20% buff stores 0.20, a -10%
## debuff stores -0.10; total multiplier = 1.0 + sum. Any basket entry using this
## key counts, but by design it is written by buffs/debuffs.
const PRE_DAMAGE_MULT_KEY := "damage_dealt_mult"

## Basket stat key holding the DEFENDER's incoming-damage multiplier. Symmetric to
## PRE_DAMAGE_MULT_KEY but read off the DEFENDER: stored on buffs/debuffs as an
## ADDITIVE bonus around 0 (an 80%-damage-reduction buff stores -0.80), so the
## applied multiplier is 1.0 + sum, clamped to >= 0. Written by buffs (e.g. Guard),
## read in the mitigation stage below. Independent of element, so it also scales TRUE.
const DAMAGE_TAKEN_MULT_KEY := "damage_taken_mult"

# ----------------------------------------------------------------------------
## Full resolution. Returns a result dictionary:
##   { pre, post, damage, is_crit, crit_chance, crit_mult, element }
## - pre         : pre-mitigation damage (ability output * pre-mult)
## - post        : after mitigation, before crit
## - is_crit     : did this hit critically strike
## - crit_chance : the 0..100 chance that was rolled against
## - crit_mult   : the crit damage multiplier applied (1.0 when not a crit)
## - damage      : the final integer damage dealt
## - element     : the attack's element string
## Pass crit_floor >= 0 to force the crit roll (for tests); -1 rolls randomly.
## `scaling_bonus` (stat_key -> extra multiplier) carries per-stat scaling granted
## by invested UPGRADE nodes (e.g. Sinewed buffing Claw/Scour); combat fills it from
## Character.ability_scaling_bonus(ability.id). Empty for enemies and un-upgraded casts.
static func resolve(attacker: CharacterBase, defender: CharacterBase, ability: Ability, points: int = 1, crit_floor: int = -1, scaling_bonus: Dictionary = {}) -> Dictionary:
	var result := {
		"pre": 0.0, "post": 0.0, "damage": 0,
		"is_crit": false, "crit_chance": 0.0, "crit_mult": 1.0,
		"element": "physical",
	}
	if attacker == null or ability == null:
		return result

	var element := ability.element_key()
	result["element"] = element

	# --- 1. PRE-MITIGATION ---------------------------------------------------
	var base_dmg := ability.compute_damage(attacker.effective_stats(), points, scaling_bonus)
	var pre_mult := 1.0 + _pre_mitigation_bonus(attacker)
	var pre := maxf(0.0, base_dmg * pre_mult)
	result["pre"] = pre

	# --- 2. MITIGATION -------------------------------------------------------
	var post := pre
	if element != "true":
		var resistance := 0.0
		if defender != null:
			resistance = defender.get_effective(Stats.defense_key(element))
			# Multiplicative resist layer from the defender's buffs/debuffs (Bet, ...).
			resistance = maxf(0.0, resistance * (1.0 + CombatBuffs.resist_mult_bonus(defender, element)))
		var pierce := attacker.get_effective(Stats.pierce_key(element))
		var amp := attacker.get_effective(Stats.amp_key(element))
		# Mitigation stiffness (m) is the DEFENDER's own curve stat; fall back if a
		# body predates the stat (0 / missing).
		var stiffness := CombatMitigation.STIFFNESS_FALLBACK
		if defender != null:
			var s := defender.get_effective("mitigation_stiffness")
			if s > 0.0:
				stiffness = s
		post = CombatMitigation.apply(pre, resistance, pierce, amp, stiffness)

	# --- 2b. INCOMING-DAMAGE MULTIPLIER (the DEFENDER's Guard, etc.) ----------
	# A flat multiplier on the damage this defender takes, applied AFTER mitigation
	# and OUTSIDE the element check (so it scales TRUE damage too). It is 1.0 + the
	# sum of the defender's damage_taken_mult buffs (additive around 0; negative
	# reduces — a Guard granting 80% reduction stores -0.80), clamped to >= 0.
	if defender != null:
		post = maxf(0.0, post * maxf(0.0, 1.0 + _damage_taken_bonus(defender)))
	result["post"] = post

	# --- 3. CRIT -------------------------------------------------------------
	var chance := CombatCrit.chance(attacker, defender, ability)
	result["crit_chance"] = chance
	var final_dmg := post
	if CombatCrit.rolls_crit(chance, crit_floor):
		var cmult := CombatCrit.damage_multiplier(attacker, ability)
		final_dmg = post * cmult
		result["is_crit"] = true
		result["crit_mult"] = cmult

	result["damage"] = int(round(maxf(0.0, final_dmg)))
	return result

## Convenience wrapper: just the final integer damage (backward compatible with
## the old signature used by combat.gd).
static func resolve_damage(attacker: CharacterBase, defender: CharacterBase, ability: Ability, points: int = 1) -> int:
	return int(resolve(attacker, defender, ability, points)["damage"])

# ----------------------------------------------------------------------------
## Sum of pre-mitigation damage multipliers from the attacker's buffs + debuffs.
static func _pre_mitigation_bonus(attacker: CharacterBase) -> float:
	if attacker == null:
		return 0.0
	return attacker.get_basket_bonus("buffs", PRE_DAMAGE_MULT_KEY) \
		+ attacker.get_basket_bonus("debuffs", PRE_DAMAGE_MULT_KEY)

## Sum of the DEFENDER's incoming-damage multipliers across its buffs + debuffs
## (e.g. Guard's damage reduction). Additive around 0; negative reduces damage.
static func _damage_taken_bonus(defender: CharacterBase) -> float:
	if defender == null:
		return 0.0
	return defender.get_basket_bonus("buffs", DAMAGE_TAKEN_MULT_KEY) \
		+ defender.get_basket_bonus("debuffs", DAMAGE_TAKEN_MULT_KEY)
