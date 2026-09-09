extends CharacterBase
class_name TheScavenger

## ============================================================================
## THE SCAVENGER  —  zone 1's boss
## ============================================================================
## A polar bear gorged on the wreck, holding the one place Sonny needs to reach. It is
## the LEAST intelligent thing in the zone and the most dangerous, which is the
## argument the whole game will make about categories: nothing here has decided
## anything about him, and it is still trying to eat him.
##
## THE ONE CREATURE IN THE ZONE THAT WAS ALREADY INTERESTING BEFORE THE AI EXISTED.
## Its `thorns` fires on the PLAYER's attacks, and on-struck has only ever needed a
## sourced hit — which the player's melee provides. Everything else in the roster was
## waiting on the deciding; this was not.
##
## THE CLOCK. Gorge heals about 3.2 a turn averaged, taking the player's net output
## from 18.8 down to 15.6 and stretching the fight from 9 turns to 11. That is the
## whole boss. IF IT NEEDS TO BE HARDER, RAISE action_points TO 2.0 before touching
## any other number — a one-line change with no code behind it, which doubles the
## pressure without making any single hit unfair.
##
## class_name global — RESTART Godot once after adding this file.
## ----------------------------------------------------------------------------

func _init() -> void:
	char_name = "The Scavenger"
	char_type = Stats.CharType.ENEMY
	organic = true
	incorporeal = false
	ai = "berserker"                    # angrier as it dies, not more careful
	color_override = Color(0.90, 0.88, 0.82)
	size_scale = 2.60

	base_stats["vitality"] = 9.0        # BEFORE set_max_hp
	set_max_hp(170)                     # => hp_base 80
	base_stats["vigor"] = 17.0
	base_stats["instinct"] = 12.0
	base_stats["alacrity"] = 12.0
	base_stats["action_points"] = 1.0   # THE difficulty dial — see the header
	base_stats["physical_defense"] = 60.0
	base_stats["ice_defense"] = 70.0    # it lives here
	base_stats["blood_defense"] = 30.0  # and it is still meat
	# The only creature in the zone that pierces above the default 15. It is what
	# takes Maul from a scratch to 12.4 a hit through the player's 45 physical.
	base_stats["physical_pierce"] = 30.0
	base_stats["crit_damage_mult"] = 3.5
	base_stats["magnetism"] = 200.0

	# A PERMANENT thorns (duration -1 — the `thorns_permanent` clone, not the 5-turn
	# player buff, which would quietly lapse partway through the fight).
	permanent_buffs = ["thorns_permanent"]

	abilities = ["maul", "charge", "gorge"]
	ability_ranks = {}
	init_vitals()
