extends CharacterBase
class_name ScreamingCorpse

## ============================================================================
## THE SCREAMING CORPSE  —  the answer to an armour build  (fight 4)
## ============================================================================
## THE FIRST ENEMY THAT ANSWERS ARMOUR. Every ability it owns carries 15 PHYSICAL
## PIERCE — and the pierce is on the ABILITIES, not on the body, so it belongs to the
## scream rather than to the creature. Tinnitus carries its own pierce too, which is
## what §1.7 was built for: a damage-over-time that goes through resistance.
##
## Less health than a shambler and standard resistances. It is not durable; it is
## simply not answerable by the one defence the player has been rewarded for so far.
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
	char_name = "Screaming Corpse"
	char_type = Stats.CharType.ENEMY
	organic = true
	incorporeal = false
	figure = Stats.Figure.MALE
	ai = "hexer"
	color_override = Color(0.58, 0.54, 0.52)
	size_scale = 1.0

	base_stats["vitality"] = 2.0      # p1 — BEFORE set_max_hp; kept <= hp/10 so hp_base stays >= 0
	set_max_hp(28)                     # p1
	base_stats["vigor"] = 14.0      # p1
	base_stats["instinct"] = 11.0    # p1
	base_stats["alacrity"] = 12.0    # TUNE
	base_stats["spirit"] = 100.0      # TUNE
	base_stats["magnificence"] = 14.0  # TUNE
	base_stats["disdain"] = 14.0       # TUNE

	# --- MIND: hexer — spreads its debuffs evenly, favouring whoever will live to suffer them
	base_stats["magnetism"] = 95.0
	base_stats["ai_tidiness"] = 0.15         # SIGNATURE: SPREAD, never stack
	base_stats["ai_prudence"] = 2.2
	base_stats["ai_efficiency"] = 1.8
	base_stats["ai_grudge"] = 2.0

	# What killing this one is worth (§1.19). TUNE — but the RATIO between
	# these across the ladder is the part that matters, not the absolutes.
	bounty_money = 10      # p1
	bounty_xp = 16        # p1

	abilities = ["risen_strike", "scream", "deafen", "wail"]
	ability_ranks = {}
	init_vitals()
