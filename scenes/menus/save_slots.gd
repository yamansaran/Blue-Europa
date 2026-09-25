extends Node

## ============================================================================
## SAVE SLOTS  —  up to five named save files (autoload singleton "SaveSlots")
## ============================================================================
## Before this, the game had ONE save: user://character.save + user://campaign.save.
## Now every save file lives in its own folder:
##
##     user://saves/slot_1/character.save     the Character autoload's JSON (unchanged format)
##     user://saves/slot_1/campaign.save      CampaignDB's JSON (unchanged format)
##     user://saves/slot_1/meta.json          what the menu shows: name, class, level, zone, dates
##
## and ONE slot is ACTIVE at a time. Character and CampaignDB ask this autoload for
## their file paths (character_path() / campaign_path()), so neither knows slots exist.
## With NO active slot (the intro and main menu) they don't read or write anything.
##
## ACCOUNT-WIDE data lives beside the slots in user://profile.save — today only which
## CLASSES are unlocked (ClassRegistry reads it), since unlocking a class is a
## player-level achievement, not one save file's.
##
## AUTOLOAD ORDER MATTERS: SaveSlots must load BEFORE Character and CampaignDB
## (project.godot lists it right after GameManager).
##
## LEGACY SAVES: on first boot with no slots, an existing user://character.save (and
## campaign.save) is COPIED into slot 1 as "Imported save", so dev progress survives.
## ----------------------------------------------------------------------------

signal slots_changed

const MAX_SLOTS := 5
const ROOT := "user://saves"
const PROFILE_PATH := "user://profile.save"
const LEGACY_CHARACTER := "user://character.save"
const LEGACY_CAMPAIGN := "user://campaign.save"

## 1..MAX_SLOTS, or -1 when no save is loaded (intro / main menu).
var active_slot: int = -1

## Account-wide unlocks: class_id -> true.
var unlocked_classes: Dictionary = {}

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT)
	_load_profile()
	_import_legacy_save()

# ----------------------------------------------------------------------------
# Paths
# ----------------------------------------------------------------------------
func slot_dir(slot: int) -> String:
	return "%s/slot_%d" % [ROOT, slot]

func has_active() -> bool:
	return active_slot >= 1 and active_slot <= MAX_SLOTS

## "" while no slot is active — callers must then skip reading / writing.
func character_path() -> String:
	return slot_dir(active_slot) + "/character.save" if has_active() else ""

func campaign_path() -> String:
	return slot_dir(active_slot) + "/campaign.save" if has_active() else ""

func _meta_path(slot: int) -> String:
	return slot_dir(slot) + "/meta.json"

# ----------------------------------------------------------------------------
# Queries (the menus)
# ----------------------------------------------------------------------------
## The slot's meta dictionary, or {} for an empty slot.
func slot_info(slot: int) -> Dictionary:
	var p := _meta_path(slot)
	if not FileAccess.file_exists(p):
		return {}
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}

func is_empty(slot: int) -> bool:
	return slot_info(slot).is_empty()

func any_saves() -> bool:
	for i in range(1, MAX_SLOTS + 1):
		if not is_empty(i):
			return true
	return false

# ----------------------------------------------------------------------------
# Actions
# ----------------------------------------------------------------------------
## Start a NEW save in `slot` (overwriting whatever was there), named `save_name`,
## for class `class_id`. Makes it active, resets Character + CampaignDB to a fresh
## game and writes all three files.
func create_slot(slot: int, save_name: String, class_id: String) -> void:
	if slot < 1 or slot > MAX_SLOTS:
		push_error("[saves] slot %d out of range" % slot)
		return
	_wipe_dir(slot)
	DirAccess.make_dir_recursive_absolute(slot_dir(slot))
	active_slot = slot
	var now := Time.get_datetime_string_from_system()
	_write_meta(slot, {"name": save_name.strip_edges() if save_name.strip_edges() != "" else "Save %d" % slot,
		"class_id": class_id, "created": now, "last_played": now, "level": 1, "zone": ""})
	if typeof(Character) != TYPE_NIL and Character.has_method("new_game"):
		Character.new_game(class_id)
	if typeof(CampaignDB) != TYPE_NIL and CampaignDB.has_method("reset"):
		CampaignDB.reset()
	touch()
	slots_changed.emit()

## Make `slot` active and load its files into Character + CampaignDB.
func load_slot(slot: int) -> bool:
	if is_empty(slot):
		return false
	active_slot = slot
	if typeof(Character) != TYPE_NIL and Character.has_method("load_game"):
		Character.load_game()
	if typeof(CampaignDB) != TYPE_NIL and CampaignDB.has_method("load_game"):
		if not CampaignDB.load_game():
			CampaignDB.reset()
	touch()
	return true

func delete_slot(slot: int) -> void:
	if slot == active_slot:
		active_slot = -1
	_wipe_dir(slot)
	slots_changed.emit()

## Close the active save (back to the main menu). Nothing is written.
func close_active() -> void:
	active_slot = -1

## Refresh the active slot's meta (level, zone, last played). Character.save_game
## calls this, so the menu is always current.
func touch() -> void:
	if not has_active():
		return
	var meta := slot_info(active_slot)
	if meta.is_empty():
		meta = {"name": "Save %d" % active_slot, "created": Time.get_datetime_string_from_system()}
	meta["last_played"] = Time.get_datetime_string_from_system()
	if typeof(Character) != TYPE_NIL:
		meta["level"] = int(Character.level)
		if "class_id" in Character:
			meta["class_id"] = str(Character.class_id)
	if typeof(CampaignDB) != TYPE_NIL and CampaignDB.has_method("get_current"):
		var c = CampaignDB.get_current()
		if c != null:
			meta["zone"] = str(c.display_name)
	_write_meta(active_slot, meta)

# ----------------------------------------------------------------------------
# Account profile (class unlocks)
# ----------------------------------------------------------------------------
func unlock_class(class_id: String) -> void:
	unlocked_classes[class_id] = true
	_save_profile()

func is_class_unlocked_in_profile(class_id: String) -> bool:
	return bool(unlocked_classes.get(class_id, false))

func _load_profile() -> void:
	if not FileAccess.file_exists(PROFILE_PATH):
		return
	var f := FileAccess.open(PROFILE_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) == TYPE_DICTIONARY and typeof(parsed.get("unlocked_classes", {})) == TYPE_DICTIONARY:
		unlocked_classes = parsed["unlocked_classes"]

func _save_profile() -> void:
	var f := FileAccess.open(PROFILE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"unlocked_classes": unlocked_classes}))
		f.close()

# ----------------------------------------------------------------------------
# Internals
# ----------------------------------------------------------------------------
func _write_meta(slot: int, meta: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(slot_dir(slot))
	var f := FileAccess.open(_meta_path(slot), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(meta, "\t"))
		f.close()

func _wipe_dir(slot: int) -> void:
	var dir := slot_dir(slot)
	if not DirAccess.dir_exists_absolute(dir):
		return
	var d := DirAccess.open(dir)
	if d == null:
		return
	d.list_dir_begin()
	var n := d.get_next()
	while n != "":
		if not d.current_is_dir():
			d.remove(n)
		n = d.get_next()
	DirAccess.remove_absolute(dir)

func _import_legacy_save() -> void:
	if any_saves() or not FileAccess.file_exists(LEGACY_CHARACTER):
		return
	var dir := slot_dir(1)
	DirAccess.make_dir_recursive_absolute(dir)
	DirAccess.copy_absolute(LEGACY_CHARACTER, dir + "/character.save")
	if FileAccess.file_exists(LEGACY_CAMPAIGN):
		DirAccess.copy_absolute(LEGACY_CAMPAIGN, dir + "/campaign.save")
	var now := Time.get_datetime_string_from_system()
	_write_meta(1, {"name": "Imported save", "class_id": "blue_blood", "created": now,
		"last_played": now, "level": 1, "zone": ""})
	print("[saves] imported the old single save into slot 1.")
