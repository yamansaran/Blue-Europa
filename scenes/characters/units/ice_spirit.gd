extends CharacterBase
class_name IceSpirit

## ============================================================================
## ICE SPIRIT  —  a self-contained character module (extends CharacterBase)
## ============================================================================
## Everything that makes an ice spirit "an ice spirit" lives HERE, in one file:
## its identity, its stat block, its colour/size, its AI routine, and the
## PERMANENT BUFFS it grants itself at the start of combat. That makes the
## character a module you can slot into any fight — a campaign fight just names
## it ("ice_spirit") and CharacterRegistry instantiates this class.
##
## HOW A MODULE IS BUILT: base_stats/baskets are filled with defaults by
## CharacterBase's member initialisers BEFORE _init() runs, so _init() only has to
## OVERRIDE the handful of things that differ from a default character. Finish by
## calling init_vitals() so current HP/Spirit start full.
##
## class_name global — RESTART Godot once after adding this file.
## ----------------------------------------------------------------------------

func _init() -> void:
	char_name = "Ice Spirit"
	char_type = Stats.CharType.ENEMY
	organic = false          # a spirit, not flesh
	incorporeal = true
	# THE AI ROUTINE. "standard" is the plain soldier: it attacks whoever is most
	# magnetic, lunges at a kill it can actually land, and defends when it is badly
	# hurt. Anything other than "none" hands the turn to AITurn (AI_PRIMER).
	ai = "standard"
	color_override = Color(0.55, 0.75, 0.95)
	_define_stats()
	_define_loadout()
	# Permanent buff(s) auto-applied when combat begins. An ice spirit is wreathed
	# in frost, so it resists ice damage innately (see BuffLibrary "frost_ward").
	permanent_buffs = ["frost_ward"]
	init_vitals()

## The ice spirit's stat block. Split out from _init() so LargeIceSpirit can reuse
## it (via super._init()) and then tweak only what a boss needs.
func _define_stats() -> void:
	set_max_hp(150)                        # HP is derived — this back-solves hp_base
	base_stats["ice_defense"] = 50.0       # flavour: tough against ice
	base_stats["fire_defense"] = 25.0      # and a little soft to fire

## WHAT IT CAN CAST, in SLOT ORDER — the index into this array is the unit's slot
## index, which is what its per-slot cooldowns are keyed by. Also split out so the
## boss can replace it wholesale after super._init().
##
## The four are chosen to give the AI a real decision rather than one move:
##   frost_bolt   free, no cooldown — the fallback that is always available
##   rime_touch   action_cost 0.5, so it can be used TWICE in a turn, and it is a
##                delivery=ATTACK strike, which means it fires the player's
##                on-struck reactions (thorns, Rime Skin, High Voltage) — the first
##                thing in the game that ever has
##   chillbind    a DEBUFF, on a cooldown and a spirit cost, so DEBUFF is viable
##                some turns and not others
##   rime_guard   a SELF shield, which is the only thing that makes DEFENSE viable
## An ice spirit has 100 Spirit and regenerates 5 a turn, so it cannot afford the
## two paid abilities back to back — running dry and falling back on Frost Bolt is
## intended, and needs no AI code: `_use_blocked` simply stops offering them.
func _define_loadout() -> void:
	abilities = ["frost_bolt", "rime_touch", "chillbind", "rime_guard"]
	ability_ranks = {}                     # everything at rank 1; a fight spec can raise it
