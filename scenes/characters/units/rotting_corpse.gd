extends CharacterBase
class_name RottingCorpse

## ============================================================================
## THE ROTTING CORPSE  —  a big soft target  (fight 4)
## ============================================================================
## High health, LOW resistances relative to it. It is large and it does not hold up.
##
## THE DELIBERATE ECHO: c1's Old Ice was a HEXER that SPREAD Infected across the
## party. This one is a PLAGUEBEARER that STACKS it on one victim. Same debuff,
## opposite archetype — and a player who fought both will feel the difference before
## they can name it. That contrast is the reason it is worth a module at all.
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
	char_name = "Rotting Corpse"
	char_type = Stats.CharType.ENEMY
	organic = true
	incorporeal = false
	figure = Stats.Figure.MALE
	ai = "plaguebearer"
	color_override = Color(0.46, 0.52, 0.38)
	size_scale = 1.15

	# VITALITY 12 WITH A NEGATIVE hp_base (dev call 2026-09-25): poison scales on the
	# applier's Vitality, so this is what keeps infectious_strike / toxic_breath at their
	# old tick (was 53% of Instinct 11 = 5.8 raw; now 50% of 12 = 6.0). HP unchanged.
	base_stats["vitality"] = 12.0     # BEFORE set_max_hp
	set_max_hp(54)                     # p1 => hp_base -66 (negative on purpose)
	base_stats["vigor"] = 14.0      # p1
	base_stats["instinct"] = 11.0    # p1
	base_stats["alacrity"] = 12.0    # TUNE
	base_stats["spirit"] = 100.0      # TUNE
	base_stats["magnificence"] = 14.0  # TUNE
	base_stats["disdain"] = 14.0       # TUNE

	# --- MIND: plaguebearer — stacks everything on ONE target until it falls over
	base_stats["magnetism"] = 110.0
	base_stats["ai_spite"] = 4.0             # SIGNATURE: pile onto one victim
	base_stats["ai_pressure"] = 2.5
	base_stats["ai_efficiency"] = 2.0
	base_stats["ai_prudence"] = 1.8

	# What killing this one is worth (§1.19). TUNE — but the RATIO between
	# these across the ladder is the part that matters, not the absolutes.
	bounty_money = 12      # p1
	bounty_xp = 18        # p1

	abilities = ["frenzy", "infectious_strike", "toxic_breath"]
	ability_ranks = {}
	init_vitals()
