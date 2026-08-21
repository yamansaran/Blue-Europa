extends Node
## ItemDB — indexes every Item (.tres) in items/item_data/ by its `id`.
## Autoload singleton "ItemDB". The inventory, shop, tooltips and Character all
## resolve item ids to full Item resources through here (same role AbilityDB
## plays for abilities). Registered BEFORE Character in project.godot so the
## player's equipped-item stats can be resolved while the save is loading.

const ITEM_DIR := "res://scenes/items/item_data/"

var _by_id: Dictionary = {}

func _ready() -> void:
	reload()

func reload() -> void:
	_by_id.clear()
	var seen := {}
	var dir := DirAccess.open(ITEM_DIR)
	if dir == null:
		push_warning("ItemDB: cannot open %s (no items yet?)" % ITEM_DIR)
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
				var res = load(ITEM_DIR + clean)
				if res is Item:
					_by_id[String(res.id)] = res
		fname = dir.get_next()
	dir.list_dir_end()

func get_item(id) -> Item:
	return _by_id.get(String(id), null)

func has(id) -> bool:
	return _by_id.has(String(id))

func all_ids() -> Array:
	var ids := _by_id.keys()
	ids.sort()
	return ids

func all_items() -> Array:
	return _by_id.values()

## Item ids offered in the shop, in a stable order. For now this is simply every
## item in the database sorted by (rarity, value); later a shop can carry its own
## stock list. Returns an Array of String ids.
func shop_stock() -> Array:
	var arr := _by_id.values()
	arr.sort_custom(func(a, b):
		if a.rarity != b.rarity:
			return a.rarity < b.rarity
		return a.value < b.value)
	var ids := []
	for it in arr:
		ids.append(String(it.id))
	return ids
