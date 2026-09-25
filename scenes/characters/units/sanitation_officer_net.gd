extends CharacterBase
class_name SanitationOfficerNet

## ============================================================================
## THE SANITATION OFFICER (net)  —  the disabler  (fight 7)
## ============================================================================
## HIS SIGNATURE IS NOT A STAT. It is `ai_priority = 3.0` on net.tres — because a
## stat cannot name an ability, and "prefer the net" is a statement about one
## ability (AI_PRIMER §9.3). That is the archetype proving its own design.
##
## NETTING THE SLOWEST PARTY MEMBER IS NEARLY FREE AND NETTING THE FASTEST IS THE
## WHOLE FIGHT — and the AI gets that for nothing IF the Netted entry's `magnitude`
## reflects it. It is set at 5.0, the hard-control anchor.
##
## The net has no duration: it is ESCAPED, rolled at the start of each of the
## bearer's turns against the Disdain he threw it with (§1.10).
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
	char_name = "Sanitation Officer"
	char_type = Stats.CharType.ENEMY
	organic = true
	incorporeal = false
	figure = Stats.Figure.MALE
	ai = "disabler"
	color_override = Color(0.26, 0.34, 0.44)
	size_scale = 1.05

	base_stats["vitality"] = 5.0      # p1 — BEFORE set_max_hp; kept <= hp/10 so hp_base stays >= 0
	set_max_hp(56)                     # p1
	base_stats["vigor"] = 13.0      # p1
	base_stats["instinct"] = 10.0    # p1
	base_stats["alacrity"] = 12.0    # TUNE
	base_stats["spirit"] = 100.0      # TUNE
	base_stats["magnificence"] = 14.0  # TUNE
	base_stats["disdain"] = 14.0       # TUNE

	# --- MIND: disabler — the signature lives on net.tres as ai_priority, not here
	base_stats["magnetism"] = 110.0
	base_stats["ai_grudge"] = 3.0
	base_stats["ai_pressure"] = 2.5
	base_stats["ai_prudence"] = 2.5
	base_stats["ai_efficiency"] = 1.5

	# What killing this one is worth (§1.19). TUNE — but the RATIO between
	# these across the ladder is the part that matters, not the absolutes.
	bounty_money = 11      # p1
	bounty_xp = 16        # p1

	abilities = ["net", "spear", "low_stab", "strip"]
	ability_ranks = {}
	init_vitals()
