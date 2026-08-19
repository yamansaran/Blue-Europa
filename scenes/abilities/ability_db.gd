extends Node
## AbilityDB — indexes every Ability (.tres) in ability_data/ by its `id`.
## Both the abilities screen (pool) and combat (execution) resolve ids through here.

const ABILITY_DIR := "res://scenes/abilities/ability_data/"

var _by_id: Dictionary = {}

func _ready() -> void:
	reload()

func reload() -> void:
	_by_id.clear()
	var seen := {}
	var dir := DirAccess.open(ABILITY_DIR)
	if dir == null:
		push_warning("AbilityDB: cannot open %s" % ABILITY_DIR)
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir():
			var clean := fname
			if clean.ends_with(".remap"):
				clean = clean.trim_suffix(".remap")
			elif clean.ends_with(".import"):
				clean = clean.trim_suffix(".import")
			if clean.ends_with(".tres") and not seen.has(clean):
				seen[clean] = true
				var res = load(ABILITY_DIR + clean)
				if res is Ability:
					_by_id[String(res.id)] = res
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