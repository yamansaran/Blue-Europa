extends CharacterBase
class_name SanitationOfficerShield

## ============================================================================
## THE SANITATION OFFICER (shield)  —  the most engine per unit in either zone  (fight 7)
## ============================================================================
## FOUR MECHANICS MEET IN ONE MAN (§1.13-§1.17):
##   - Riot Shield grants him an absorbing shield and COMMITS him to Shield Bash next
##     (ai_follow_up on the .tres) — a two-beat pattern the player can learn to read.
##   - Shield Bash hits harder the more of that shield is still standing.
##   - Covering puts Protected on an ally; it breaks the moment HE takes ACTUAL
##     HEALTH damage, not shield. Hit the shield man to free his friend.
##   - He is a bulwark: very magnetic, and the archetype that MANIPULATES the
##     targeting layer rather than merely reading it.
##
## THE CHEAP VERSION SHIPPED, ON PURPOSE (§1.14). There is no Covering self-buff and
## no two-way link — Protected simply points at its caster. 90% of the feel for a
## fraction of the machinery; build the real link only when a later zone needs one.
##
## >> §2.7 TUNING PASS 1. Health, Vigor, Instinct and the bounty are DERIVED:
##    solved against two reference builds for a target margin per fight (the
##    table is in claude/GODTHAAB_TUNING.md). Lines marked `p1` came out of
##    that pass; lines still marked `# TUNE` (vitality, alacrity, spirit,
##    Magnificence/Disdain) were NOT part of it. What is AUTHORED and load-bearing
##    is the identity: the archetype, the signature and texture gains, the
##    magnetism RELATIVE to the rest of the zone, and the kit.
##
## class_name global — RESTART Godot once after adding this file.
## ----------------------------------------------------------------------------

func _init() -> void:
	char_name = "Sanitation Officer"
	char_type = Stats.CharType.ENEMY
	organic = true
	incorporeal = false
	figure = Stats.Figure.MALE
	ai = "bulwark"
	color_override = Color(0.24, 0.30, 0.40)
	size_scale = 1.1

	base_stats["vitality"] = 9.0      # TUNE — BEFORE set_max_hp. DELIBERATELY above hp/10
	                                  # (hp_base -20): Riot Shield scales 2.0 x vitality, so
	                                  # this line is the shield's size, not his health.
	set_max_hp(70)                     # p1
	base_stats["vigor"] = 13.0      # p1
	base_stats["instinct"] = 10.0    # p1
	base_stats["alacrity"] = 12.0    # TUNE
	base_stats["spirit"] = 100.0      # TUNE
	base_stats["magnificence"] = 14.0  # TUNE
	base_stats["disdain"] = 14.0       # TUNE

	# --- MIND: bulwark — the one archetype that manipulates targeting instead of reading it
	base_stats["magnetism"] = 180.0            # SIGNATURE: a bulwark eats attention
	base_stats["ai_vigilance"] = 4.0
	base_stats["ai_efficiency"] = 1.8
	base_stats["ai_grudge"] = 1.8

	# What killing this one is worth (§1.19). TUNE — but the RATIO between
	# these across the ladder is the part that matters, not the absolutes.
	bounty_money = 12      # p1
	bounty_xp = 16        # p1

	abilities = ["riot_shield", "shield_bash", "shield_strike", "covering"]
	ability_ranks = {}
	init_vitals()
