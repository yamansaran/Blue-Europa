extends CharacterBase
class_name HarbourGuard

## ============================================================================
## THE HARBOUR GUARD  —  a buff that becomes its own debuff  (fight 8, boss)
## ============================================================================
## UNREMARKABLE ON PURPOSE. The whole creature is its third ability.
##
## AMPHETAMINES IS A BUFF THAT BECOMES ITS OWN DEBUFF: six turns of rising numbers
## that visibly FADE on the chip badge every turn, then expire into Crash, which
## grows worse every turn it holds. THE FIRST FIGHT THE PLAYER CAN WIN BY SURVIVING
## — and three of them ticking down at once is what makes that legible rather than
## merely true.
##
## amphetamines.tres carries `ai_not_before_turn = 3`, so they take it when it is
## needed rather than on turn one. Without that gate the fight has no shape.
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
	char_name = "Harbour Guard"
	char_type = Stats.CharType.ENEMY
	organic = true
	incorporeal = false
	figure = Stats.Figure.MALE
	ai = "stalwart"
	color_override = Color(0.32, 0.40, 0.50)
	size_scale = 1.0

	base_stats["vitality"] = 6.0      # TUNE — BEFORE set_max_hp
	set_max_hp(82)                     # p1
	base_stats["vigor"] = 13.0      # p1
	base_stats["instinct"] = 10.0    # p1
	base_stats["alacrity"] = 12.0    # TUNE
	base_stats["spirit"] = 100.0      # TUNE
	base_stats["magnificence"] = 14.0  # TUNE
	base_stats["disdain"] = 14.0       # TUNE

	# --- MIND: stalwart — steady, and holding out is the point
	base_stats["magnetism"] = 105.0
	base_stats["ai_panic"] = 1.5             # SIGNATURE, by its lowness
	base_stats["ai_efficiency"] = 2.0
	base_stats["ai_pressure"] = 1.8
	base_stats["ai_grudge"] = 1.5

	# What killing this one is worth (§1.19). TUNE — but the RATIO between
	# these across the ladder is the part that matters, not the absolutes.
	bounty_money = 18      # p1
	bounty_xp = 26        # p1

	abilities = ["risen_strike", "rifle", "amphetamines"]
	ability_ranks = {}
	init_vitals()
