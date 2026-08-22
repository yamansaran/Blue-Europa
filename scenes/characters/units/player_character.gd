extends CharacterBase
class_name PlayerCharacter

## ============================================================================
## PLAYER CHARACTER  —  the player's body type (extends CharacterBase)
## ============================================================================
## The player is the deliberate EXCEPTION in the module system: unlike a plain
## enemy, its stats are driven by the Character autoload (levels, attributes,
## equipped items, passive abilities — all rebuilt into the body's baskets), so
## this class stays intentionally thin. It exists so the player is a real module
## like every other character AND inherits from CharacterBase, and so there is a
## single home for PLAYER-WIDE permanent buffs (auto-applied at the start of every
## combat). Character owns one of these as its `body`.
##
## Keep this minimal: do NOT hard-code the player's stat block here — that lives in
## Character (character.gd), which manages progression. Only set things that are
## always true of "the player" and give player-wide innate buffs a home.
##
## class_name global — RESTART Godot once after adding this file.
## ----------------------------------------------------------------------------

func _init() -> void:
	char_type = Stats.CharType.CHARACTER
	# Player-wide permanent buffs, auto-applied at the start of every combat.
	# Empty by default — add BuffLibrary ids here to give the player innate buffs
	# (e.g. a starter aura). Per-run buffs still come from combat as usual.
	permanent_buffs = []
