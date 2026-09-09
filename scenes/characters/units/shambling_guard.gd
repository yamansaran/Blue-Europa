extends ShamblingCorpse
class_name ShamblingGuard

## ============================================================================
## SHAMBLING GUARD  —  armoured in life  (zone 1, fight 6)
## ============================================================================
## Heavier, and it was wearing something when it died. ITS JOB IS NOT DAMAGE — it is
## to be slow to remove while the Chaplain behind it undoes the player's work. It
## draws attention on purpose and it is bad at everything else.
##
## MAGNETISM 160 AGAINST THE CHAPLAIN'S 70 IS THE WHOLE FIGHT. Once the AI's
## targeting layer lands that will pull the guards' own attention; today it does the
## more important half of the job already, because the PLAYER's instinct is to hit
## what is in front of them, and what is in front of them is the wrong target.
##
## Extends ShamblingCorpse, so it inherits the identity, the control-case defaults
## and Strike, and overrides only the deltas. NB it drops Frenzy: a wall that also
## triples its own damage is a different creature.
##
## class_name global — RESTART Godot once after adding this file.
## ----------------------------------------------------------------------------

func _init() -> void:
	super._init()                       # the whole Shambling Corpse setup first
	char_name = "Shambling Guard"
	ai = "bulwark"
	color_override = Color(0.30, 0.33, 0.40)
	size_scale = 1.1
	base_stats["vitality"] = 4.0        # BEFORE set_max_hp
	set_max_hp(64)                      # => hp_base 24
	base_stats["alacrity"] = 6.0        # slow; it acts less often on the timeline
	base_stats["physical_defense"] = 60.0
	# The signature, and the one archetype whose signature is a STAT rather than a
	# gain: it is 60% more magnetic than anything else on its side of the field.
	base_stats["magnetism"] = 160.0
	abilities = ["risen_strike", "cudgel"]
	init_vitals()                       # re-snap after the max-HP change
