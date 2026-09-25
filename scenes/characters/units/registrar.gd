extends CharacterBase
class_name Registrar

## ============================================================================
## THE REGISTRAR  —  he is not armoured, he is FILED  (fight 3, BACK COLUMN)
## ============================================================================
## THE SOFTEST BODY IN THE ZONE. Once reached he must die in one or two hits — the
## fight is not about his health, it is about reaching him at all.
##
## LOW MAGNETISM, AND THAT IS THE DESIGN: the AI should not want him and the PLAYER
## should want him badly. He sits at col 0 row 2 with three men in front across rows
## 1-3, so all three cover him and killing the centre one is not enough. That is the
## lesson, and it is stated by the seating rather than by any ability.
##
## EVERY ABILITY IS delivery = 0 (a spell). He never touches anyone.
##
## THE ARCHETYPE IS THE JOKE. His On Guard variant EXCLUDES SELF in the data, so
## `martyr` — whose entire identity is ai_self_buff 0.0, never targeting itself with
## a buff — is the honest match rather than a gag.
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
	char_name = "The Registrar"
	char_type = Stats.CharType.ENEMY
	organic = true
	incorporeal = false
	figure = Stats.Figure.MALE
	ai = "martyr"
	color_override = Color(0.42, 0.40, 0.50)
	size_scale = 0.95

	base_stats["vitality"] = 2.0      # p1 — BEFORE set_max_hp; kept <= hp/10 so hp_base stays >= 0
	set_max_hp(26)                     # p1
	base_stats["vigor"] = 16.0      # p1
	base_stats["instinct"] = 12.0    # p1
	base_stats["alacrity"] = 12.0    # TUNE
	base_stats["spirit"] = 100.0      # TUNE
	base_stats["magnificence"] = 14.0  # TUNE
	base_stats["disdain"] = 14.0       # TUNE

	# --- MIND: martyr — will die holding the line, and never helps himself
	base_stats["magnetism"] = 55.0             # AUTHORED: the AI should not want him
	base_stats["ai_self_buff"] = 0.0          # SIGNATURE: never buffs himself
	base_stats["ai_triage"] = 5.0
	base_stats["ai_vigilance"] = 3.0
	base_stats["ai_favoritism"] = 2.0

	# What killing this one is worth (§1.19). TUNE — but the RATIO between
	# these across the ladder is the part that matters, not the absolutes.
	bounty_money = 10      # p1
	bounty_xp = 12        # p1

	abilities = ["pistol_shot", "kneecap", "spray", "on_guard_detail", "commend"]
	ability_ranks = {}
	init_vitals()
