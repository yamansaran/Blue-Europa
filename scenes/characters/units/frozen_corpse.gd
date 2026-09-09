extends CharacterBase
class_name FrozenCorpse

## ============================================================================
## FROZEN CORPSE  —  frozen so hard it stopped being soft  (zone 1, fight 3)
## ============================================================================
## SEVENTY-FIVE PHYSICAL DEFENCE AND ZERO OF EVERYTHING ELSE. The single most
## legible resistance profile in the game, and the fight where the player learns
## that an element is a question rather than a colour.
##
## The zeroes are not a hole to be patched later. A player carrying one damage type
## only finds out they have one damage type by meeting something that answers it —
## and this is paired in fight 3 with the Unknown Entity, whose profile is the
## inverse, so the lesson is a comparison rather than an assertion.
##
## class_name global — RESTART Godot once after adding this file.
## ----------------------------------------------------------------------------

func _init() -> void:
	char_name = "Frozen Corpse"
	char_type = Stats.CharType.ENEMY
	organic = true
	incorporeal = false
	ai = "stalwart"                     # barely reacts to its own danger
	color_override = Color(0.66, 0.74, 0.80)
	size_scale = 1.05

	base_stats["vitality"] = 5.0        # BEFORE set_max_hp
	set_max_hp(58)                      # => hp_base 8
	base_stats["vigor"] = 12.0
	base_stats["instinct"] = 12.0
	base_stats["alacrity"] = 5.0        # very slow — half the player's turn rate

	# THE PROFILE. Written out element by element rather than looped, because the
	# zeroes ARE the content and a loop would hide which ones were chosen.
	base_stats["physical_defense"] = 75.0
	base_stats["ice_defense"] = 0.0
	base_stats["fire_defense"] = 0.0
	base_stats["lightning_defense"] = 0.0
	base_stats["blood_defense"] = 0.0
	base_stats["toxic_defense"] = 0.0
	base_stats["mental_defense"] = 0.0
	base_stats["spiritual_defense"] = 0.0

	base_stats["vulnerability"] = 0.7   # frozen things bleed slowly: -30% DoT taken
	base_stats["magnetism"] = 110.0

	abilities = ["cudgel", "frostnip"]
	ability_ranks = {}
	init_vitals()
