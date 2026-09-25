extends CharacterBase
class_name SanitationEngineer

## ============================================================================
## THE SANITATION ENGINEER  —  the same organisation, better trained  (fights 6, 7)
## ============================================================================
## Below-base alacrity; otherwise sturdy. A natural BACK-column occupant now that
## §1.3 exists — giving him a seat changes the corps fights for one line of spec.
##
## SAME ARCHETYPE AS THE WHARFINGER, SIX FIGHTS LATER. That is the zone's whole
## structure in one line: the same organisation, better trained. The player met this
## shape on the wharf and has to answer it again with more on the board.
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
	char_name = "Sanitation Engineer"
	char_type = Stats.CharType.ENEMY
	organic = true
	incorporeal = false
	figure = Stats.Figure.MALE
	ai = "zealot"
	color_override = Color(0.30, 0.44, 0.42)
	size_scale = 1.05

	base_stats["vitality"] = 7.0      # p1 — BEFORE set_max_hp; kept <= hp/10 so hp_base stays >= 0
	set_max_hp(76)                     # p1
	base_stats["vigor"] = 16.0      # p1
	base_stats["instinct"] = 12.0    # p1
	base_stats["alacrity"] = 12.0    # TUNE
	base_stats["spirit"] = 100.0      # TUNE
	base_stats["magnificence"] = 14.0  # TUNE
	base_stats["disdain"] = 14.0       # TUNE

	# --- MIND: zealot — the wharfinger's mind with a better kit
	base_stats["magnetism"] = 115.0
	base_stats["ai_favoritism"] = 6.0        # SIGNATURE: empower the strongest
	base_stats["ai_vigilance"] = 3.0
	base_stats["ai_triage"] = 2.0
	base_stats["ai_thirst"] = 5.0

	# What killing this one is worth (§1.19). TUNE — but the RATIO between
	# these across the ladder is the part that matters, not the absolutes.
	bounty_money = 15      # p1
	bounty_xp = 22        # p1

	abilities = ["stun_gun", "thud", "order", "flamethrower", "brace"]
	ability_ranks = {}
	init_vitals()
