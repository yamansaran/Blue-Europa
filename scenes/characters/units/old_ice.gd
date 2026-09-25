extends CharacterBase
class_name OldIce

## ============================================================================
## THE OLD ICE  —  much older than anything wearing a uniform  (fight 5, five of them)
## ============================================================================
## Individually slight — 58 health and about nine damage a turn — but there are FIVE,
## and they SPREAD what they carry rather than concentrating it. The zone's only toxic
## damage, and the first evidence that this plague predates the people naming it.
##
## A HEXER IS INVISIBLE IN A DUEL. Spreading a debuff evenly only looks like a
## decision when there is more than one person to spread it across, which is why the
## swarm and the ally tutorial are correctly the SAME fight and could not have been
## either one alone.
##
## THE ARITHMETIC, because it is the one fight in the zone not balanced against the
## player: five of these put out about 57 damage a turn between them, which is a
## four-turn loss against a lone player. With two hunters at magnetism 110 the player
## draws roughly 100/(100+220) — about 31% — and takes 18 instead. FIGHT 5 IS BALANCED
## AGAINST THE PARTY. If the hunters are ever cut, rebuild it from three Old Ice, not
## five.
##
## class_name global — RESTART Godot once after adding this file.
## ----------------------------------------------------------------------------

func _init() -> void:
	char_name = "The Old Ice"
	char_type = Stats.CharType.ENEMY
	organic = true
	incorporeal = false
	ai = "hexer"
	color_override = Color(0.62, 0.66, 0.58)
	size_scale = 1.15

	# VITALITY 15 WITH A NEGATIVE hp_base (dev call 2026-09-25). Poison scales on the
	# applier's Vitality (50%), and `infected` folded into poison — so Vitality is what
	# keeps this creature's poison at its old bite (was 53% of Instinct 14 = 7.4 raw a
	# tick; now 50% of 15 = 7.5). HP is unchanged: set_max_hp back-solves hp_base.
	base_stats["vitality"] = 15.0       # BEFORE set_max_hp
	set_max_hp(58)                      # => hp_base -92 (negative on purpose)
	base_stats["vigor"] = 14.0
	base_stats["instinct"] = 14.0
	base_stats["alacrity"] = 8.0
	base_stats["spirit"] = 100.0
	# AN EXPLICIT OVERRIDE, not a leftover: the base regen came down to 5 in rev30,
	# and at 5 a turn one of these could not afford Contaminating Strike (15) and
	# Miasmic (25) in any sustainable pattern. 15 is what pays for the hex rotation
	# that makes it a hexer rather than a creature that Strikes and apologises.
	base_stats["spirit_regen"] = 15.0
	base_stats["vulnerability"] = 0.7   # old and cold: -30% DoT taken
	base_stats["magnetism"] = 100.0

	# Strike is SHARED with the Shambling Corpse — one .tres, two creatures, filed in
	# enemy/_shared for exactly that reason. A shared basic attack is the cheapest
	# possible way to make a zone feel like one place.
	abilities = ["risen_strike", "contaminating_strike", "miasmic"]
	ability_ranks = {}
	init_vitals()
