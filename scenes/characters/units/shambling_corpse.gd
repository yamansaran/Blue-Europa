extends CharacterBase
class_name ShamblingCorpse

## ============================================================================
## SHAMBLING CORPSE  —  the zeppelin's own crew, risen  (zone 1, fights 1 and 2)
## ============================================================================
## The first thing the player kills, and the thing everyone in the next twenty-two
## zones will tell him he is. One attack, one self-buff, and a rule about when it
## may use it.
##
## IT IS THE CONTROL CASE. Every defence is the default 45, magnetism is the default
## 100, and it carries no gain, no aura and no resistance profile — deliberately, so
## that every creature after it in the zone reads as a DEPARTURE from something. A
## roster whose first entry already has an opinion has nothing to measure against.
##
## THE VITALITY TRAP (and why every creature in this zone sets it explicitly):
## max_hp = hp_base + vitality * 10, and hp_base defaults to 100 — so a body with
## DEFAULT vitality has a FLOOR of 200 health, which is the player's whole health
## bar. A 52-HP corpse is vitality 3 and hp_base 22. Set vitality BEFORE set_max_hp:
## set_max_hp back-solves against the CURRENT vitality, so the order matters.
##
## class_name global — RESTART Godot once after adding this file.
## ----------------------------------------------------------------------------

func _init() -> void:
	char_name = "Shambling Corpse"
	char_type = Stats.CharType.ENEMY
	organic = true
	incorporeal = false
	# "standard" — the plain soldier. Today every non-"none" value runs the AI's
	# Phase-0 uniform-random picker; the archetype name is what the scoring layers
	# will read when they land (AI_PRIMER §13).
	ai = "standard"
	color_override = Color(0.42, 0.46, 0.52)
	size_scale = 1.0
	_define_stats()
	_define_loadout()
	init_vitals()

## The corpse's stat block. Split out so ShamblingGuard can reuse it via
## super._init() and then override only what an armoured one differs by.
func _define_stats() -> void:
	base_stats["vitality"] = 5.0        # BEFORE set_max_hp — it back-solves off this
	set_max_hp(52)                      # => hp_base 2
	base_stats["vigor"] = 10.0
	base_stats["instinct"] = 10.0
	# Everything else stays default on purpose: alacrity / magnificence / disdain 10,
	# spirit 100, every defence 45, magnetism 100. See the header.

## Strike is free and always available; Frenzy is the decision. The corpse has 100
## spirit and the base 5 a turn, so it can afford Frenzy roughly once every four
## turns whatever its cooldown says — running dry and falling back on Strike is
## intended and needs no AI code (`_use_blocked` simply stops offering it).
##
## FRENZY CANNOT BE USED ON TURN ONE. That rule is not here — it is
## `ai_not_before_turn = 2` on frenzy.tres, which keeps the ability out of the AI's
## usable set entirely until the corpse's second turn. A tutorial enemy that opens
## by tripling its own damage teaches the wrong lesson in the wrong order.
func _define_loadout() -> void:
	abilities = ["risen_strike", "frenzy"]
	ability_ranks = {}                  # rank 1; a fight spec can raise it
