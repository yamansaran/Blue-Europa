extends RefCounted
class_name CombatMath

## ============================================================================
## COMBAT MATH  —  the single place damage is turned into a number
## ============================================================================
## Everything routes through resolve_damage(). Right now it returns the raw
## pre-mitigation value (element scaling only); the pierce / defence /
## amplification formula is left as a clearly-marked HOOK so the full (complex)
## damage model can drop in here without touching combat.gd or ability.gd.
##
## The stats it will need are already summed (base + every basket) on the two
## CharacterBase bodies, keyed per element:
##   attacker.get_effective( Stats.pierce_key(element) )   # e.g. "fire_pierce"
##   defender.get_effective( Stats.defense_key(element) )  # e.g. "fire_defense"
##   attacker.get_effective( Stats.amp_key(element) )      # e.g. "fire_amp"
## The hidden TRUE element bypasses all of it (pierce/def/amp are 0 there).
## ----------------------------------------------------------------------------

static func resolve_damage(attacker: CharacterBase, defender: CharacterBase, ability: Ability, points: int = 1) -> int:
	if attacker == null or ability == null:
		return 0

	var element := ability.element_key()
	var raw := ability.compute_damage(attacker.effective_stats(), points)

	# TRUE damage ignores every defensive stat.
	if element == "true":
		return int(round(maxf(0.0, raw)))

	# --- HOOK: replace this pass-through with the real damage formula --------
	# var pierce  := attacker.get_effective(Stats.pierce_key(element))
	# var defense := 0.0
	# if defender != null:
	#     defense = defender.get_effective(Stats.defense_key(element))
	# var amp     := attacker.get_effective(Stats.amp_key(element))
	# ... combine raw, pierce, defense, amp into the final number ...
	var final_dmg := raw
	# ------------------------------------------------------------------------

	return int(round(maxf(0.0, final_dmg)))
