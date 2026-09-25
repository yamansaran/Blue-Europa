extends RefCounted
class_name DialogueDB

## ============================================================================
## DIALOGUE DB  —  finds a fight's dialogue in its ZONE's dialogue file
## ============================================================================
## ONE FILE PER ZONE, found by naming convention — no registration:
##
##     res://scenes/dialogue/zones/<zone_id>_dialogue.gd      e.g. c1_dialogue.gd
##
## Each file is a plain script holding one constant, FIGHTS, keyed by FIGHT ID (the
## "id" in the campaign module's fight spec — "c1_f1", "c1_boss", "c1_train_old_ice").
## The zone prefix may be dropped ("f1", "boss"). The value is exactly what
## CombatDialogue accepts: a list of lines, or a list of {"when", "lines"} triggers.
##
## GameManager._stage_fight asks here first; a fight with no entry falls back to an
## inline "dialogue" key on its spec (still supported), else plays none.
## Add a zone = add a file. Add a fight's lines = add a key.
##
## class_name global — RESTART Godot once after adding this script.
## ----------------------------------------------------------------------------

const ZONE_DIR := "res://scenes/dialogue/zones/"

static var _cache: Dictionary = {}   # zone_id -> FIGHTS dict ({} when the zone has no file)

static func path_for(zone_id: String) -> String:
	return ZONE_DIR + zone_id + "_dialogue.gd"

## The dialogue config for `fight_id` in `zone_id`, or [] if none is authored.
static func for_fight(zone_id: String, fight_id: String) -> Array:
	var fights := _fights(zone_id)
	var v = fights.get(fight_id, null)
	if v == null and fight_id.begins_with(zone_id + "_"):
		v = fights.get(fight_id.substr(zone_id.length() + 1), null)
	return (v as Array).duplicate(true) if typeof(v) == TYPE_ARRAY else []

static func _fights(zone_id: String) -> Dictionary:
	if _cache.has(zone_id):
		return _cache[zone_id]
	var out := {}
	var p := path_for(zone_id)
	if zone_id != "" and ResourceLoader.exists(p):
		var s = load(p)
		if s is Script:
			var consts: Dictionary = (s as Script).get_script_constant_map()
			if typeof(consts.get("FIGHTS", null)) == TYPE_DICTIONARY:
				out = consts["FIGHTS"]
			else:
				push_warning("[dialogue] %s has no FIGHTS dictionary." % p)
	_cache[zone_id] = out
	return out
