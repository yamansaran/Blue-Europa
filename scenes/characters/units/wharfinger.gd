extends CharacterBase
class_name Wharfinger

## ============================================================================
## THE WHARFINGER  —  he gives the orders  (fight 1)
## ============================================================================
## The first enemy in the game that makes ANOTHER enemy better. Everything else on
## the wharf swings; he points, and the swing lands harder.
##
## HIS MAGNETISM SITS ABOVE THE STEVEDORES' ON PURPOSE. A support enemy the player
## can ignore is a support enemy that never teaches anything — he has to be worth
## reaching for before the men he is buffing are.
##
## FIRST CREATURE WITH A NON-DEFAULT MAGNIFICENCE. Zone one held both sides of the
## resist roll at 10, so nothing there ever resisted; Godthaab is where the roll
## stops being a formality and the player sees a RESIST float for the first time.
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
	char_name = "Wharfinger"
	char_type = Stats.CharType.ENEMY
	organic = true
	incorporeal = false
	figure = Stats.Figure.MALE
	ai = "zealot"
	color_override = Color(0.58, 0.46, 0.34)
	size_scale = 1.0

	base_stats["vitality"] = 5.0      # TUNE — BEFORE set_max_hp
	set_max_hp(56)                     # p1
	base_stats["vigor"] = 12.0      # p1
	base_stats["instinct"] = 9.0    # p1
	base_stats["alacrity"] = 12.0    # TUNE
	base_stats["spirit"] = 100.0      # TUNE
	base_stats["magnificence"] = 14.0  # TUNE
	base_stats["disdain"] = 14.0       # TUNE

	# --- MIND: zealot — buffs the STRONGEST ally, which changes who the player kills first
	base_stats["magnetism"] = 125.0            # AUTHORED: above the stevedores'
	base_stats["ai_favoritism"] = 6.0        # SIGNATURE: buff the strongest, not the neediest
	base_stats["ai_vigilance"] = 3.0
	base_stats["ai_triage"] = 2.0
	base_stats["ai_efficiency"] = 2.0

	# What killing this one is worth (§1.19). TUNE — but the RATIO between
	# these across the ladder is the part that matters, not the absolutes.
	bounty_money = 10      # p1
	bounty_xp = 16        # p1

	abilities = ["dock_swing", "heavy_swing", "work_order"]
	ability_ranks = {}
	init_vitals()
