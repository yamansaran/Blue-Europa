extends CharacterBase
class_name BurningCorpse

## ============================================================================
## THE BURNING CORPSE  —  slight alone, a squeeze as a set  (the Burning Ground)
## ============================================================================
## The `old_ice` profile: individually slight, dangerous as a set.
##
## THE TRIO IS A THREE-WAY SQUEEZE ON THREE DIFFERENT LINES OF THE PIPELINE. The Hulk
## raises damage TAKEN, one corpse cuts healing RECEIVED (Cauterized), the other cuts
## ACCURACY (Smokescreen). NONE OF THEM IS RAW DAMAGE — the fight is lost to the
## arithmetic rather than to a big number, which is the point of putting it here.
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
	char_name = "Burning Corpse"
	char_type = Stats.CharType.ENEMY
	organic = true
	incorporeal = false
	figure = Stats.Figure.MALE
	ai = "hexer"
	color_override = Color(0.66, 0.42, 0.30)
	size_scale = 1.0

	base_stats["vitality"] = 4.0      # TUNE — BEFORE set_max_hp
	set_max_hp(40)                     # p1
	base_stats["vigor"] = 15.0      # p1
	base_stats["instinct"] = 12.0    # p1
	base_stats["alacrity"] = 12.0    # TUNE
	base_stats["spirit"] = 100.0      # TUNE
	base_stats["magnificence"] = 14.0  # TUNE
	base_stats["disdain"] = 14.0       # TUNE

	# --- MIND: hexer — the debuffs matter more than the damage
	base_stats["magnetism"] = 90.0
	base_stats["ai_tidiness"] = 0.15         # SIGNATURE: spread the squeeze
	base_stats["ai_prudence"] = 2.0
	base_stats["ai_efficiency"] = 1.8

	# What killing this one is worth (§1.19). TUNE — but the RATIO between
	# these across the ladder is the part that matters, not the absolutes.
	bounty_money = 15      # p1
	bounty_xp = 30        # p1

	abilities = ["burning_strike", "cauterizing_strike", "exhale_smoke"]
	ability_ranks = {}
	init_vitals()
