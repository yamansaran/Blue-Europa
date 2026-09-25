extends CharacterBase
class_name Enforcer

## ============================================================================
## THE ENFORCER  —  he goes after whoever is actually hurting them  (fight 3)
## ============================================================================
## A non-tanky guard with better stats across the board and THE SAME KIT AS THE BASE
## GUARD, unchanged. His identity is entirely his targeting — which is the cleanest
## possible demonstration that in this AI an archetype IS a creature.
##
## THE ZONE'S ANSWER TO HIDING BEHIND AN ALLY. ai_grudge 15 reads `reputation`: who
## has actually been carrying the party. Today that is in-fight damage dealt (the
## persisted cross-battle history is not built), so he warms up over a few turns and
## then commits. Failing that, ai_gluttony sends him at the healthiest.
##
## His whole stat block lives in AIRules' `enforcer` preset, which is why this module
## sets almost nothing: naming the archetype is the character.
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
	char_name = "Enforcer"
	char_type = Stats.CharType.ENEMY
	organic = true
	incorporeal = false
	figure = Stats.Figure.MALE
	ai = "enforcer"
	color_override = Color(0.30, 0.32, 0.40)
	size_scale = 1.0

	base_stats["vitality"] = 4.0      # p1 — BEFORE set_max_hp; kept <= hp/10 so hp_base stays >= 0
	set_max_hp(46)                     # p1
	base_stats["vigor"] = 16.0      # p1
	base_stats["instinct"] = 12.0    # p1
	base_stats["alacrity"] = 12.0    # TUNE
	base_stats["spirit"] = 100.0      # TUNE
	base_stats["magnificence"] = 14.0  # TUNE
	base_stats["disdain"] = 14.0       # TUNE

	# --- MIND: enforcer — the archetype supplies the whole gain block (AIRules)
	base_stats["magnetism"] = 105.0

	# What killing this one is worth (§1.19). TUNE — but the RATIO between
	# these across the ladder is the part that matters, not the absolutes.
	bounty_money = 6      # p1
	bounty_xp = 10        # p1

	abilities = ["on_guard", "baton_bash"]
	ability_ranks = {}
	init_vitals()
