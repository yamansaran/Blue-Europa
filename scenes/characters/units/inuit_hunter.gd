extends CharacterBase
class_name InuitHunter

## ============================================================================
## HUNTER  —  a temporary ally  (zone 1, fight 5 — two of them)
## ============================================================================
## Two of them, fighting alongside Sonny for exactly one fight. `char_type ALLY`, so
## they sit on the player's side of `_is_hostile` and everything targets around them
## correctly with no new code — combat's targeting is relative to the caster, so an
## enemy's attack legally reaches them and their heal legally reaches the player.
##
## MAGNETISM 110, ABOVE THE PLAYER'S 100, ON PURPOSE. It is the number fight 5 is
## balanced on: see the arithmetic in old_ice.gd. They are meant to eat attention.
##
## A DEFENSIVE INTENT OF EXACTLY ZERO is the characterisation, and it is a stat rather
## than a line of dialogue: they will heal each other and they will not take cover,
## because they are not afraid of the thing the player is currently learning to be
## afraid of. That weight lives on the archetype (`ally_neutral`) and lands when the
## AI's intent layer does; today the name is a label on a random picker.
##
## ONE MALE AND ONE FEMALE is authored in c1's fight spec rather than here — the
## `figure` field does not exist yet, so the pair currently differ only in name.
##
## class_name global — RESTART Godot once after adding this file.
## ----------------------------------------------------------------------------

func _init() -> void:
	char_name = "Hunter"
	char_type = Stats.CharType.ALLY
	organic = true
	incorporeal = false
	ai = "ally_neutral"
	color_override = Color(0.55, 0.42, 0.30)
	size_scale = 1.0

	base_stats["vitality"] = 6.0        # BEFORE set_max_hp
	set_max_hp(130)                     # => hp_base 70
	base_stats["vigor"] = 15.0
	base_stats["instinct"] = 18.0
	base_stats["alacrity"] = 14.0
	base_stats["spirit"] = 100.0
	base_stats["ice_defense"] = 65.0    # they dress for it
	base_stats["magnetism"] = 110.0

	# Harpoon Shot is a 500%-Vigor cooldown-99 shot that one-shots anything in the
	# zone — once per fight, and it should be held for a kill. The finisher tag that
	# would make the AI hold it does not exist yet, so it carries ai_priority 3.0 as
	# a placeholder nudge and is otherwise picked whenever the random picker lands
	# on it. Worth revisiting when the ability layer ships.
	abilities = ["cut", "rejuvenating_salve", "harpoon_shot"]
	ability_ranks = {}
	init_vitals()
