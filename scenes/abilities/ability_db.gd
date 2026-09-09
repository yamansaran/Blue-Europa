extends Node
## AbilityDB — indexes every Ability (.tres) under ability_data/ by its `id`.
## Both the abilities screen (pool) and combat (execution) resolve ids through here.
##
## The scan is RECURSIVE (rev2): ability_data/ is organised into subfolders
## (player/<class>, player/general, player/debug, ally/<ally>, enemy/<family>,
## special/) purely for authoring convenience. The INDEX IS FLAT — `id` is the
## only key anything resolves by, so an id must be unique across the WHOLE tree,
## not just within its folder. Moving a .tres between folders changes nothing at
## runtime; it is a filing operation, not a gameplay one.

const ABILITY_DIR := "res://scenes/abilities/ability_data/"

var _by_id: Dictionary = {}
var _path_by_id: Dictionary = {}   ## id -> the .tres it was loaded from (collision reporting)

func _ready() -> void:
	reload()

func reload() -> void:
	_by_id.clear()
	_path_by_id.clear()
	_scan_dir(ABILITY_DIR)

## Recursive worker. `path` always ends in "/".
func _scan_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		push_warning("AbilityDB: cannot open %s" % path)
		return
	var seen := {}
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if dir.current_is_dir():
			# skip "." / ".." and any hidden folder (.godot, .import, ...)
			if not fname.begins_with("."):
				_scan_dir(path.path_join(fname) + "/")
		else:
			var clean := fname
			if clean.ends_with(".remap"):
				clean = clean.trim_suffix(".remap")
			elif clean.ends_with(".import"):
				clean = clean.trim_suffix(".import")
			if clean.ends_with(".tres") and not seen.has(clean):
				seen[clean] = true
				var full := path.path_join(clean)
				var res = load(full)
				if res is Ability:
					var key := String(res.id)
					if _by_id.has(key):
						push_warning("AbilityDB: duplicate ability id '%s' — %s overrides %s" % [key, full, _path_by_id[key]])
					_by_id[key] = res
					_path_by_id[key] = full
		fname = dir.get_next()
	dir.list_dir_end()

func get_ability(id) -> Ability:
	return _by_id.get(String(id), null)

func has(id) -> bool:
	return _by_id.has(String(id))

func all_ids() -> Array:
	var ids := _by_id.keys()
	ids.sort()
	return ids

func all_abilities() -> Array:
	return _by_id.values()

## Where an id's .tres actually lives — handy in the creation studio / debug.
func source_path(id) -> String:
	return _path_by_id.get(String(id), "")
