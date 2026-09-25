extends CharacterBase
class_name SanitationTechHook

## ============================================================================
## SANITATION TECHNICIAN (hook)  —  the titan slayer  (fight 6)
## ============================================================================
## Higher health, standard alacrity. SHARES A DISPLAY NAME with the prod technician.
##
## THE CATALOGUE WROTE `titan_slayer` FOR A %-MAX-HP SCALER THAT DID NOT EXIST YET,
## and Disembowel is it (§1.8). He is drawn to HEALTHY targets and repelled by
## wounded ones, which is the exact inverse of every other attacker in the zone.
##
## ai_efficiency BELOW 1.0 IS CORRECT AND IS NOT A TYPO: efficiency reads "whose pool
## does my damage cut through fastest", and a %-max-HP scaler wants the opposite —
## it seeks the target its ordinary damage does NOT easily cut.
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
	char_name = "Sanitation Technician"
	char_type = Stats.CharType.ENEMY
	organic = true
	incorporeal = false
	figure = Stats.Figure.MALE
	ai = "titan_slayer"
	color_override = Color(0.36, 0.48, 0.44)
	size_scale = 1.05

	base_stats["vitality"] = 7.0      # p1 — BEFORE set_max_hp; kept <= hp/10 so hp_base stays >= 0
	set_max_hp(72)                     # p1
	base_stats["vigor"] = 16.0      # p1
	base_stats["instinct"] = 12.0    # p1
	base_stats["alacrity"] = 12.0    # TUNE
	base_stats["spirit"] = 100.0      # TUNE
	base_stats["magnificence"] = 14.0  # TUNE
	base_stats["disdain"] = 14.0       # TUNE

	# --- MIND: titan_slayer — the bigger you are, the more he wants you
	base_stats["magnetism"] = 100.0
	base_stats["ai_gluttony"] = 6.0          # SIGNATURE: hunt the HEALTHY
	base_stats["ai_efficiency"] = 0.7        # BELOW 1.0 on purpose — see above
	base_stats["ai_grudge"] = 2.0
	base_stats["ai_bloodlust"] = 0.5

	# What killing this one is worth (§1.19). TUNE — but the RATIO between
	# these across the ladder is the part that matters, not the absolutes.
	bounty_money = 15      # p1
	bounty_xp = 22        # p1

	abilities = ["hook_slice", "impale", "disembowel", "brace"]
	ability_ranks = {}
	init_vitals()
