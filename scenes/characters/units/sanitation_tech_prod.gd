extends CharacterBase
class_name SanitationTechProd

## ============================================================================
## SANITATION TECHNICIAN (prod)  —  the first enemy that DEFENDS  (fights 6, 7)
## ============================================================================
## Higher alacrity, lower health than the hook technician. SHARES A DISPLAY NAME
## with it deliberately — the ids do the distinguishing, the player sees two men in
## the same uniform.
##
## BRACE IS THE JOB. A 65% cut for one turn means the player's biggest hit can simply
## be WASTED, and WHEN you attack starts to matter. It is the first time the zone
## asks the player to think about ordering rather than targeting.
##
## A coward beats up whoever cannot hurt it and turtles the moment it is threatened,
## so it also punishes leaving a squishy party member exposed.
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
	char_name = "Sanitation Technician"
	char_type = Stats.CharType.ENEMY
	organic = true
	incorporeal = false
	figure = Stats.Figure.MALE
	ai = "coward"
	color_override = Color(0.40, 0.52, 0.46)
	size_scale = 1.0

	base_stats["vitality"] = 4.0      # p1 — BEFORE set_max_hp; kept <= hp/10 so hp_base stays >= 0
	set_max_hp(46)                     # p1
	base_stats["vigor"] = 16.0      # p1
	base_stats["instinct"] = 12.0    # p1
	base_stats["alacrity"] = 12.0    # TUNE
	base_stats["spirit"] = 100.0      # TUNE
	base_stats["magnificence"] = 14.0  # TUNE
	base_stats["disdain"] = 14.0       # TUNE

	# --- MIND: coward — hits the soft one, hides the moment it is threatened
	base_stats["magnetism"] = 80.0
	base_stats["ai_caution"] = 0.12          # SIGNATURE: avoid whatever can hurt it
	base_stats["ai_efficiency"] = 2.5
	base_stats["ai_pressure"] = 2.0
	base_stats["ai_panic"] = 12.0

	# What killing this one is worth (§1.19). TUNE — but the RATIO between
	# these across the ladder is the part that matters, not the absolutes.
	bounty_money = 10      # p1
	bounty_xp = 16        # p1

	abilities = ["cattle_prod", "taze", "arc_discharge", "brace"]
	ability_ranks = {}
	init_vitals()
