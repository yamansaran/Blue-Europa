extends CharacterBase
class_name ChiefOfTheDetail

## ============================================================================
## THE CHIEF OF THE DETAIL  —  BOSS   ** KIT OPEN: THE DEV WRITES THIS ONE **
## ============================================================================
## >> THIS MODULE IS A STUB. GODTHAAB_BUILD §2.5 reserves the Chief's kit for the
##    dev, so `abilities` below is a PLACEHOLDER borrowed from the harbour guards and
##    is not a design proposal. Replace it.
##
## WHAT THE LADDER ALREADY FIXES, whatever kit he gets: he arrives with two harbour
## guards, so Amphetamines is on the field and the fight has a six-turn shape whether
## or not he has one of his own.
##
## WHAT THE ZONE LEAVES UNUSED, if any of it is useful:
##   - NOTHING IN GODTHAAB HEALS. A boss who repairs his own escort would reuse a
##     mechanic the player last met in c1 fight 6.
##   - NOTHING SUMMONS, and no summon mechanic exists (AI_PRIMER §19.14).
##   - NOTHING IS SMART. `ai_smart 1.0` plus the awareness cluster is the catalogue's
##     own boss treatment, and this is the first zone that gives the player a
##     Magnificence worth reading — so a boss who stops feeding it is a real
##     escalation rather than a stat check.
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
	char_name = "The Chief of the Detail"
	char_type = Stats.CharType.ENEMY
	organic = true
	incorporeal = false
	figure = Stats.Figure.MALE
	unit_rank = Stats.UnitRank.BOSS
	ai = "stalwart"
	color_override = Color(0.20, 0.26, 0.36)
	size_scale = 1.5

	base_stats["vitality"] = 14.0      # p1 — BEFORE set_max_hp; kept <= hp/10 so hp_base stays >= 0
	set_max_hp(140)                     # p1
	base_stats["vigor"] = 12.0      # p1
	base_stats["instinct"] = 9.0    # p1
	base_stats["alacrity"] = 12.0    # TUNE
	base_stats["spirit"] = 100.0      # TUNE
	base_stats["magnificence"] = 14.0  # TUNE
	base_stats["disdain"] = 14.0       # TUNE

	# --- MIND: stalwart PLACEHOLDER — the dev picks the real archetype
	base_stats["magnetism"] = 160.0
	base_stats["ai_smart"] = 0.0             # TODO: 1.0 + the awareness cluster is the boss treatment
	base_stats["ai_efficiency"] = 2.0
	base_stats["ai_pressure"] = 1.8
	base_stats["ai_grudge"] = 2.0

	# What killing this one is worth (§1.19). TUNE — but the RATIO between
	# these across the ladder is the part that matters, not the absolutes.
	bounty_money = 144      # p1
	bounty_xp = 428        # p1

	abilities = ["risen_strike", "rifle", "amphetamines"]   # PLACEHOLDER — see the note above
	ability_ranks = {}
	init_vitals()
