extends CharacterBase
class_name Stevedore

## ============================================================================
## THE STEVEDORE  —  the zone's baseline body  (fight 1, x2)
## ============================================================================
## THE MEASURING STICK. Everything else in Godthaab is described relative to this
## body, so tune it first and tune it carefully — moving it moves the whole zone.
##
## TWO SPECS, ONE MODULE (rule one: a creature is a module, a VARIANT is a fight
## spec). This file is SPEC A, the brute with Flurry. Spec B overrides `ai` and
## `abilities` in c2b's fight list to become the chain-carrying plaguebearer.
##
## SPEC A EXISTS TO TEACH ONE THING: that a multi-hit and a single hit of identical
## total damage are NOT the same thing. Flurry deals one Dock Swing's worth across
## three rolls, so it dodges differently, crits differently, and is eaten by a shield
## three separate times.
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
	char_name = "Stevedore"
	char_type = Stats.CharType.ENEMY
	organic = true
	incorporeal = false
	figure = Stats.Figure.MALE
	ai = "brute"
	color_override = Color(0.50, 0.44, 0.40)
	size_scale = 1.0

	base_stats["vitality"] = 5.0      # TUNE — BEFORE set_max_hp
	set_max_hp(52)                     # p1
	base_stats["vigor"] = 12.0      # p1
	base_stats["instinct"] = 9.0    # p1
	base_stats["alacrity"] = 12.0    # TUNE
	base_stats["spirit"] = 100.0      # TUNE
	base_stats["magnificence"] = 14.0  # TUNE
	base_stats["disdain"] = 14.0       # TUNE

	# --- MIND: brute — pure magnetism targeting, deliberately almost bare
	base_stats["magnetism"] = 100.0            # the zone's baseline draw
	base_stats["ai_efficiency"] = 2.0        # TEXTURE: a brute's only opinion

	# What killing this one is worth (§1.19). TUNE — but the RATIO between
	# these across the ladder is the part that matters, not the absolutes.
	bounty_money = 7      # p1
	bounty_xp = 12        # p1

	abilities = ["dock_swing", "flurry"]
	ability_ranks = {}
	init_vitals()
