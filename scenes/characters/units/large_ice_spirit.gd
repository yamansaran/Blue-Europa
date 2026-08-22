extends IceSpirit
class_name LargeIceSpirit

## ============================================================================
## LARGE ICE SPIRIT  —  the boss variant (extends IceSpirit)
## ============================================================================
## The same creature as an Ice Spirit, just bigger and tougher. This is the point
## of the module system: a character can inherit from ANOTHER character, not only
## from CharacterBase — so the boss starts from the ice spirit's whole setup and
## overrides only what actually differs (name, size, HP, and one extra aura).
##
## super._init() runs the IceSpirit setup first (identity, stats, frost_ward),
## then we layer the boss changes on top and re-init vitals.
##
## class_name global — RESTART Godot once after adding this file.
## ----------------------------------------------------------------------------

func _init() -> void:
	super._init()                           # inherit the full Ice Spirit setup
	char_name = "Large Ice Spirit"
	color_override = Color(0.40, 0.66, 0.95)
	size_scale = 2.2                        # drawn ~2.2x bigger by the combat engine
	set_max_hp(600)                         # a lot more health than the base spirit
	# A greater frost aura: on top of the inherited frost_ward, the boss also wears
	# a permanent Frost Mantle that reflects a little ice damage when struck.
	if not permanent_buffs.has("frost_mantle"):
		permanent_buffs.append("frost_mantle")
	init_vitals()
