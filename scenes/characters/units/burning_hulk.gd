extends CharacterBase
class_name BurningHulk

## ============================================================================
## THE BURNING HULK  —  MINIBOSS  (the Burning Ground)
## ============================================================================
## The zone's largest pool outside the boss, and slow with it.
##
## ON FIRE IS NOT A DAMAGE DEBUFF. It is a VULNERABILITY debuff with a burn attached
## — the first time an enemy uses the player's own damage_taken lever offensively,
## and the reason the Hulk is dangerous in company rather than alone.
##
## FLAIL is three hits at FULL damage each, every one carrying its own 50% chance of
## On Fire. One use is zero to three stacks, and THAT VARIANCE IS THE THREAT.
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
	char_name = "Burning Hulk"
	char_type = Stats.CharType.ENEMY
	organic = true
	incorporeal = false
	figure = Stats.Figure.MALE
	unit_rank = Stats.UnitRank.MINIBOSS
	ai = "plaguebearer"
	color_override = Color(0.70, 0.36, 0.22)
	size_scale = 1.45

	base_stats["vitality"] = 14.0      # TUNE — BEFORE set_max_hp
	set_max_hp(158)                     # p1
	base_stats["vigor"] = 15.0      # p1
	base_stats["instinct"] = 12.0    # p1
	base_stats["alacrity"] = 12.0    # TUNE
	base_stats["spirit"] = 100.0      # TUNE
	base_stats["magnificence"] = 14.0  # TUNE
	base_stats["disdain"] = 14.0       # TUNE

	# --- MIND: plaguebearer with a high focus — it picks a victim and does not wander
	base_stats["magnetism"] = 150.0
	base_stats["ai_spite"] = 6.0             # SIGNATURE: one victim, relentlessly
	base_stats["ai_efficiency"] = 2.0
	base_stats["ai_pressure"] = 2.0
	base_stats["ai_focus"] = 3.0

	# What killing this one is worth (§1.19). TUNE — but the RATIO between
	# these across the ladder is the part that matters, not the absolutes.
	bounty_money = 60      # p1
	bounty_xp = 140        # p1

	abilities = ["burning_strike", "bash", "flail"]
	ability_ranks = {}
	init_vitals()
