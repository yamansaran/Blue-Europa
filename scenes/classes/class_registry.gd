extends RefCounted
class_name ClassRegistry

## ============================================================================
## CLASS REGISTRY  —  the player classes (the Diary's "Four Houses")
## ============================================================================
## One entry per class the player can start a save as. The class-select screen draws
## a card for every entry IN ORDER; everything a class needs at the start of a game
## (its starting kit, its skill tree, its opening cutscene, its portrait) is read from
## here, so ADDING / FINISHING A CLASS IS AN EDIT TO THIS FILE (plus its content).
##
## FIELDS
##   name              display name on the card
##   tagline           one short line under the name
##   color             the card's accent (and the placeholder portrait's tint)
##   portrait          res:// path to the card art — "" draws a placeholder until art lands
##   unlocked          available from a fresh profile? (else SaveSlots.unlock_class(id))
##   tree_scene        the class's skill tree (the abilities screen still loads Blue
##                     Blood's directly — this is the hook for when a second tree exists)
##   opening_cutscene  CutsceneDB id played after the class is picked; "" or an id with
##                     no registered cutscene skips straight into zone 1
##   starting_kit      Character fields for a new game (unlocked_abilities / equipped_abilities)
##
## class_name global — RESTART Godot once after adding this script.
## ----------------------------------------------------------------------------

const ORDER := ["blue_blood", "nephilic", "psychological", "fleshcrafter"]

const CLASSES := {
	"blue_blood": {
		"name": "Blue Blooded",
		"tagline": "Ice, lightning and the spirit between them.",
		"color": Color(0.30, 0.42, 0.86),
		"portrait": "",
		"unlocked": true,
		"tree_scene": "res://scenes/abilities/blue_blood_tree.tscn",
		"opening_cutscene": "opening_blue_blood",
		"starting_kit": {
			"unlocked_abilities": ["claw", "scour"],
			"equipped_abilities": ["claw", "scour", "", "", "", "", "", "", "", ""],
		},
	},
	"nephilic": {
		"name": "The Nephilic",
		"tagline": "Vigor, vitality, and the helix of wings.",
		"color": Color(0.80, 0.55, 0.20),
		"portrait": "",
		"unlocked": false,
		"tree_scene": "res://scenes/abilities/nephilic_tree.tscn",
		"opening_cutscene": "opening_nephilic",
		# Lead (free builder, +50 spirit) + Crash (100-spirit spender) — NEPHILIC_PLAN.
		"starting_kit": {
			"unlocked_abilities": ["lead", "crash_blow"],
			"equipped_abilities": ["lead", "crash_blow", "", "", "", "", "", "", "", ""],
		},
	},
	"psychological": {
		"name": "The Psychological",
		"tagline": "Disdain, magnificence, and the party as a battery.",
		"color": Color(0.62, 0.34, 0.82),
		"portrait": "",
		"unlocked": false,
		"tree_scene": "res://scenes/abilities/psychological_tree.tscn",   # phase 2 builds it
		"opening_cutscene": "opening_psychological",
		"starting_kit": {
			"unlocked_abilities": ["claw", "scour"],
			"equipped_abilities": ["claw", "scour", "", "", "", "", "", "", "", ""],
		},
	},
	"fleshcrafter": {
		"name": "The Fleshcrafter",
		"tagline": "Blood at the core, a little of everything at the edges.",
		"color": Color(0.62, 0.10, 0.16),
		"portrait": "",
		"unlocked": false,
		"tree_scene": "",
		"opening_cutscene": "opening_fleshcrafter",
		"starting_kit": {},
	},
}

static func ids() -> Array:
	return ORDER.duplicate()

static func has(id: String) -> bool:
	return CLASSES.has(id)

static func info(id: String) -> Dictionary:
	return CLASSES.get(id, {})

static func display_name(id: String) -> String:
	return str(info(id).get("name", id))

## Unlocked by default, or unlocked on this player's profile.
static func is_unlocked(id: String) -> bool:
	if not has(id):
		return false
	if bool(info(id).get("unlocked", false)):
		return true
	return typeof(SaveSlots) != TYPE_NIL and SaveSlots.is_class_unlocked_in_profile(id)

static func starting_kit(id: String) -> Dictionary:
	return info(id).get("starting_kit", {})

static func opening_cutscene(id: String) -> String:
	return str(info(id).get("opening_cutscene", ""))
