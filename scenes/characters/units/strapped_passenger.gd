extends CharacterBase
class_name StrappedPassenger

## ============================================================================
## STRAPPED PASSENGER  —  the Chaplain  (zone 1, fight 6)
## ============================================================================
## He never got out of the seat. He is dressed as a priest, and he IS the priest from
## the expedition — the man the hand-copied prayer card in Sonny's own coat came from,
## which Sonny has no way to know and the player will only understand in retrospect,
## three zones east. He is named for what the player can see, not for what he is.
##
## MECHANICALLY he is the zone's only SUPPORT enemy and its only TRUE damage. He
## cannot be out-damaged while he is alive: Never Rest restores more to a Guard than
## the player removes from one in a turn. The fight is a target-priority lesson with a
## body — leave him up and the margin is 1.07, which is a loss once a roll goes badly;
## kill him on turn three and it is 1.37.
##
## EVERY ABILITY HE HAS IS A SPELL — he never strikes anything. Consequence worth
## knowing before it reads as a bug: a player who has invested in Rime Skin or
## Lightning Shell's capstone will watch those reactions sit completely silent through
## fight 6, because on-struck is attacks-only and he has no attacks.
##
## GRASP is the first enemy use of TRUE damage in the game. Eleven a turn from a dead
## priest is trivia rather than a threat, which keeps the Diary's reveal at Vienna's
## alienist intact — but it is a deliberate seed, not an accident.
##
## class_name global — RESTART Godot once after adding this file.
## ----------------------------------------------------------------------------

func _init() -> void:
	char_name = "Strapped Passenger"
	char_type = Stats.CharType.ENEMY
	organic = true
	incorporeal = false
	ai = "medic"
	color_override = Color(0.24, 0.22, 0.28)
	size_scale = 1.0

	base_stats["vitality"] = 3.0        # BEFORE set_max_hp
	set_max_hp(56)                      # => hp_base 26
	base_stats["vigor"] = 8.0           # he does not fight
	base_stats["instinct"] = 22.0       # the highest in the zone; everything scales off it
	base_stats["alacrity"] = 8.0
	base_stats["spirit"] = 100.0
	# Like the Old Ice: an explicit override against the rev30 base of 5. Never Rest
	# (25) and Dark Blessing (15) are the fight, and at 5 a turn he would cast one and
	# then stand there. Haunted Choir exists to top this up when it still runs dry.
	base_stats["spirit_regen"] = 15.0
	# Every defence stays default 45 — he is not protected by anything but the Guards,
	# which is the fight's argument stated in his stat block.
	base_stats["magnetism"] = 70.0      # he does not want to be looked at

	abilities = ["never_rest", "dark_blessing", "grasp", "haunted_choir"]
	ability_ranks = {}
	init_vitals()
