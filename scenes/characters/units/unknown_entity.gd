extends CharacterBase
class_name UnknownEntity

## ============================================================================
## UNKNOWN ENTITY  —  a frost wraith nobody has a word for  (fights 3 and 4)
## ============================================================================
## Thin, evasive, and it does not decide anything you could predict. It KEEPS this
## name because in zone one nobody out here has a category for anything — and the
## hunters in fight 5 having an ordinary word for the Old Ice, when the game itself
## files this under "Unknown Entity", is the whole point of the pairing.
##
## THE ONE CREATURE WHOSE ARCHETYPE IS CORRECT TODAY. `erratic` is uniform random
## across the legal set, which is exactly and only what the AI's Phase 0 does — so
## fight 4 is finished and correct right now while every fight around it is waiting
## on the scoring layers. The zone's most atmospheric encounter is also its smoke test.
##
## ALACRITY 18 against the player's 10 is why three of them is unnerving rather than
## lethal: on the timeline they act nearly twice as often, but each one only puts out
## about 7 a turn. Fight 4 is the zone's slowest fight and close to its safest.
##
## class_name global — RESTART Godot once after adding this file.
## ----------------------------------------------------------------------------

func _init() -> void:
	char_name = "Unknown Entity"
	char_type = Stats.CharType.ENEMY
	organic = false                     # not flesh
	incorporeal = true
	ai = "erratic"
	color_override = Color(0.70, 0.82, 0.92)
	size_scale = 0.9

	base_stats["vitality"] = 6.0        # BEFORE set_max_hp
	set_max_hp(65)                      # => hp_base 5
	base_stats["vigor"] = 9.0
	base_stats["instinct"] = 15.0
	base_stats["alacrity"] = 11.0
	base_stats["spirit"] = 100.0

	# The INVERSE of the Frozen Corpse: soft-ish everywhere, and only actually
	# defended against the element it is made of.
	base_stats["ice_defense"] = 45.0
	base_stats["physical_defense"] = 30.0
	base_stats["fire_defense"] = 30.0
	base_stats["lightning_defense"] = 30.0
	base_stats["blood_defense"] = 30.0
	base_stats["toxic_defense"] = 30.0
	base_stats["mental_defense"] = 30.0
	base_stats["spiritual_defense"] = 30.0

	base_stats["magnetism"] = 70.0      # hard to hold onto

	# Rend is the zone's TWO-ELEMENT attack: physical off Vigor, plus a second ice
	# hit off Instinct through bonus_damage_element. That split is what makes fight
	# 3's resistance lesson land — against the Frozen Corpse's 75 physical / 0 ice,
	# the two halves of one attack visibly do different things.
	abilities = ["rend", "terrify"]
	ability_ranks = {}
	init_vitals()
