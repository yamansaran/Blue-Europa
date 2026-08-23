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
	ai = "none"              # passes its turn for now (no enemy AI yet)
	color_override = Color(0.55, 0.75, 0.95)
	_define_stats()
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
