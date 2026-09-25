extends CharacterBase
class_name SecurityGuard

## ============================================================================
## THE SECURITY GUARD  —  the line  (fights 2, 3)
## ============================================================================
## Sturdier and slower than a stevedore, and MORE MAGNETIC — he is meant to be hit.
##
## THE BASE SPEC is a stalwart, whose signature is its LOWNESS: ai_panic 1.5 means he
## barely reacts to his own danger. Steady, relentless, boring on purpose — he is the
## baseline against which the zone's panicky archetypes read as panicky.
##
## THE TANKY SPEC (fight 3) is a fight-spec override to `warden` with the
## Electrified Baton and Oversight: a tank whose job is making somebody ELSE
## unkillable, and whose ai_vigilance 8.0 puts Oversight on whoever is ABOUT to be
## hit rather than whoever already has been.
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
	char_name = "Security Guard"
	char_type = Stats.CharType.ENEMY
	organic = true
	incorporeal = false
	figure = Stats.Figure.MALE
	ai = "stalwart"
	color_override = Color(0.34, 0.38, 0.46)
	size_scale = 1.0

	base_stats["vitality"] = 6.0      # p1 — BEFORE set_max_hp; kept <= hp/10 so hp_base stays >= 0
	set_max_hp(60)                     # p1
	base_stats["vigor"] = 18.0      # p1
	base_stats["instinct"] = 13.0    # p1
	base_stats["alacrity"] = 12.0    # TUNE
	base_stats["spirit"] = 100.0      # TUNE
	base_stats["magnificence"] = 14.0  # TUNE
	base_stats["disdain"] = 14.0       # TUNE

	# --- MIND: stalwart — barely reacts to its own danger
	base_stats["magnetism"] = 135.0            # AUTHORED: he is meant to be hit
	base_stats["ai_panic"] = 1.5              # SIGNATURE, by its lowness
	base_stats["ai_efficiency"] = 2.0
	base_stats["ai_pressure"] = 1.8
	base_stats["ai_grudge"] = 1.5

	# What killing this one is worth (§1.19). TUNE — but the RATIO between
	# these across the ladder is the part that matters, not the absolutes.
	bounty_money = 9      # p1
	bounty_xp = 15        # p1

	abilities = ["on_guard", "baton_bash"]
	ability_ranks = {}
	init_vitals()
