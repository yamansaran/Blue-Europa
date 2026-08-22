extends Window

## ============================================================================
## CREATION STUDIO  —  a debug tool for authoring Ability / Item .tres files
## ============================================================================
## A standalone Window that builds one form per data type by REFLECTING the
## @export fields off ability.gd / item.gd (get_property_list). Add a new @export
## to either script and its row appears here automatically — nothing to update.
##
## HOW TO OPEN
##   • From its file: open creation_studio.tscn and press F6 (Run Current Scene).
##   • From the game (debug):
##         var s = preload("res://scenes/tools/creation_studio.tscn").instantiate()
##         add_child(s)
##         s.popup_centered(Vector2i(780, 860))
##
## WHERE IT SAVES
##   Abilities -> res://scenes/abilities/ability_data/<file>.tres
##   Items     -> res://scenes/items/item_data/<file>.tres
##   ResourceSaver writes the same text .tres format Godot itself produces
##   (script_class + ext_resource + a fresh uid). Writing into res:// works in
##   any editor-launched run; it is only read-only in an EXPORTED build.
##
## After a save it reloads AbilityDB / ItemDB (if present at /root) so the new
## object is live immediately in a running game. In the editor's FileSystem dock
## the new file appears when you refocus the Godot window.
## ----------------------------------------------------------------------------

const ABILITY_SCRIPT_PATH := "res://scenes/abilities/ability.gd"
const ABILITY_DIR := "res://scenes/abilities/ability_data/"
const ITEM_SCRIPT_PATH := "res://scenes/items/item.gd"
const ITEM_DIR := "res://scenes/items/item_data/"

# One "tab context" per data type. Holds the widgets + a field list so save/clone
# can walk them generically.
class TabCtx:
	var type_name: String              # "Ability" / "Item"
	var type_script: Script                 # the .gd whose @exports we reflect
	var dir: String                    # where the .tres go
	var db_autoload: String            # "AbilityDB" / "ItemDB" to reload after save
	var fields: Array = []             # [{ name, get: Callable, set: Callable }]
	var clone_pick: OptionButton
	var filename_edit: LineEdit
	var overwrite: CheckBox
	var status: RichTextLabel


func _ready() -> void:
	title = "Blue Europa — Creation Studio"
	min_size = Vector2i(640, 560)
	if size.x < 780:
		size = Vector2i(780, 860)
	close_requested.connect(func(): _on_close())

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	panel.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)

	var header := Label.new()
	header.text = "Creation Studio  ·  author new game objects"
	header.add_theme_font_size_override("font_size", 20)
	root.add_child(header)

	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(tabs)

	var ability_tab := _build_tab("Ability", ABILITY_SCRIPT_PATH, ABILITY_DIR, "AbilityDB")
	ability_tab.name = "Abilities"
	tabs.add_child(ability_tab)

	var item_tab := _build_tab("Item", ITEM_SCRIPT_PATH, ITEM_DIR, "ItemDB")
	item_tab.name = "Items"
	tabs.add_child(item_tab)


func _on_close() -> void:
	# If we were popped up from the game, just hide/free; if we're the run scene, quit.
	if get_parent() == get_tree().root:
		get_tree().quit()
	else:
		queue_free()


# ----------------------------------------------------------------------------
# TAB CONSTRUCTION
# ----------------------------------------------------------------------------
func _build_tab(type_name: String, script_path: String, dir: String, db_autoload: String) -> Control:
	var ctx := TabCtx.new()
	ctx.type_name = type_name
	ctx.type_script = load(script_path)
	ctx.dir = dir
	ctx.db_autoload = db_autoload

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)

	# --- clone-from row ------------------------------------------------------
	var clone_row := HBoxContainer.new()
	var clone_lbl := Label.new()
	clone_lbl.text = "Start from:"
	clone_lbl.custom_minimum_size.x = 160
	clone_row.add_child(clone_lbl)
	ctx.clone_pick = OptionButton.new()
	ctx.clone_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clone_row.add_child(ctx.clone_pick)
	var reload_btn := Button.new()
	reload_btn.text = "↻"
	reload_btn.tooltip_text = "Rescan the folder for existing objects"
	clone_row.add_child(reload_btn)
	col.add_child(clone_row)

	col.add_child(HSeparator.new())

	# --- reflected fields (scrollable) --------------------------------------
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)

	var form := VBoxContainer.new()
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_theme_constant_override("separation", 6)
	scroll.add_child(form)

	var sample = ctx.type_script.new()   # fresh instance -> its @export defaults + property list
	for prop in sample.get_property_list():
		if not _is_editable_export(prop):
			continue
		_add_field(ctx, form, prop, sample)

	col.add_child(HSeparator.new())

	# --- footer: filename + overwrite + save + status -----------------------
	var fn_row := HBoxContainer.new()
	var fn_lbl := Label.new()
	fn_lbl.text = "File name:"
	fn_lbl.custom_minimum_size.x = 160
	fn_row.add_child(fn_lbl)
	ctx.filename_edit = LineEdit.new()
	ctx.filename_edit.placeholder_text = "leave blank to use the id"
	ctx.filename_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fn_row.add_child(ctx.filename_edit)
	var ext_lbl := Label.new()
	ext_lbl.text = ".tres"
	fn_row.add_child(ext_lbl)
	col.add_child(fn_row)

	var save_row := HBoxContainer.new()
	ctx.overwrite = CheckBox.new()
	ctx.overwrite.text = "Overwrite if it already exists"
	save_row.add_child(ctx.overwrite)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_row.add_child(spacer)
	var dup_btn := Button.new()
	dup_btn.text = "Duplicate"
	dup_btn.tooltip_text = "Save as a NEW %s with a fresh UID (id + file name get a _copy suffix)" % type_name
	dup_btn.custom_minimum_size.x = 110
	save_row.add_child(dup_btn)
	var save_btn := Button.new()
	save_btn.text = "Save %s" % type_name
	save_btn.tooltip_text = "Save. Overwriting an existing file keeps its UID, so scene references stay intact."
	save_btn.custom_minimum_size.x = 140
	save_row.add_child(save_btn)
	col.add_child(save_row)

	ctx.status = RichTextLabel.new()
	ctx.status.bbcode_enabled = true
	ctx.status.fit_content = true
	ctx.status.custom_minimum_size.y = 48
	ctx.status.scroll_active = false
	col.add_child(ctx.status)

	# --- wiring --------------------------------------------------------------
	save_btn.pressed.connect(func(): _save(ctx))
	dup_btn.pressed.connect(func(): _duplicate(ctx))
	reload_btn.pressed.connect(func(): _refresh_clone_list(ctx))
	ctx.clone_pick.item_selected.connect(func(idx): _apply_clone(ctx, idx))

	_refresh_clone_list(ctx)
	return col


## Only user-declared @export vars (skips built-in Resource props, groups, categories).
func _is_editable_export(prop: Dictionary) -> bool:
	var usage: int = prop.usage
	if not (usage & PROPERTY_USAGE_SCRIPT_VARIABLE):
		return false
	if not (usage & PROPERTY_USAGE_EDITOR):
		return false
	return true


# ----------------------------------------------------------------------------
# FIELD WIDGETS  (one row per reflected property; registers get/set closures)
# ----------------------------------------------------------------------------
func _add_field(ctx: TabCtx, form: VBoxContainer, prop: Dictionary, sample) -> void:
	var pname: String = prop.name
	var ptype: int = prop.type
	var hint: int = prop.hint
	var hint_string: String = prop.hint_string

	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lbl := Label.new()
	lbl.text = pname.capitalize()
	lbl.custom_minimum_size.x = 160
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	row.add_child(lbl)

	var default_val = sample.get(pname)
	var getter: Callable
	var setter: Callable

	# --- special-cased fields (guardrails > raw text) -----------------------
	if pname == "stats" and ptype == TYPE_DICTIONARY:
		var pair := _make_stat_dict_editor()
		row.add_child(pair.control)
		getter = pair.getter
		setter = pair.setter
	elif pname == "scaling_stat":
		var ob := OptionButton.new()
		ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ob.add_item("(none)", 0)
		var majors: Array = Stats.major_keys()
		for i in majors.size():
			ob.add_item(str(majors[i]), i + 1)
		row.add_child(ob)
		getter = func():
			var t := ob.get_item_text(ob.get_selected())
			return StringName("" if t == "(none)" else t)
		setter = func(v):
			var s := str(v)
			for i in ob.item_count:
				if ob.get_item_text(i) == s or (s == "" and ob.get_item_text(i) == "(none)"):
					ob.select(i)
					return
			ob.select(0)
	elif pname == "requires" and ptype == TYPE_ARRAY:
		var le := LineEdit.new()
		le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		le.placeholder_text = "comma-separated ids, e.g. strike, guard"
		row.add_child(le)
		getter = func():
			var arr: Array[StringName] = []
			for part in le.text.split(",", false):
				var p := part.strip_edges()
				if p != "":
					arr.append(StringName(p))
			return arr
		setter = func(v):
			var parts := []
			for x in v:
				parts.append(str(x))
			le.text = ", ".join(parts)

	# --- generic widgets by type -------------------------------------------
	elif ptype == TYPE_BOOL:
		var cb := CheckBox.new()
		row.add_child(cb)
		getter = func(): return cb.button_pressed
		setter = func(v): cb.button_pressed = bool(v)
	elif ptype == TYPE_INT and hint == PROPERTY_HINT_ENUM:
		var opts := _parse_enum(hint_string)
		var ob := OptionButton.new()
		ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for o in opts:
			ob.add_item(o.text, o.value)
		row.add_child(ob)
		getter = func(): return ob.get_selected_id()
		setter = func(v):
			var target := int(v)
			for i in ob.item_count:
				if ob.get_item_id(i) == target:
					ob.select(i)
					return
			if ob.item_count > 0:
				ob.select(0)
	elif ptype == TYPE_INT or ptype == TYPE_FLOAT:
		var sb := SpinBox.new()
		sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sb.allow_greater = true
		sb.allow_lesser = true
		_apply_range(sb, hint, hint_string, ptype == TYPE_INT)
		row.add_child(sb)
		var is_int := ptype == TYPE_INT
		getter = func(): return int(sb.value) if is_int else sb.value
		setter = func(v): sb.value = float(v)
	elif ptype == TYPE_STRING or ptype == TYPE_STRING_NAME:
		var is_name := ptype == TYPE_STRING_NAME
		if hint == PROPERTY_HINT_MULTILINE_TEXT:
			var te := TextEdit.new()
			te.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			te.custom_minimum_size.y = 60
			te.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
			row.add_child(te)
			getter = func(): return StringName(te.text) if is_name else te.text
			setter = func(v): te.text = str(v)
		else:
			var le := LineEdit.new()
			le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(le)
			getter = func(): return StringName(le.text) if is_name else le.text
			setter = func(v): le.text = str(v)
	elif ptype == TYPE_OBJECT:
		# icon (Texture2D) / model (PackedScene): optional res:// path, loaded on save.
		var le := LineEdit.new()
		le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		le.placeholder_text = "res:// path to a %s (optional)" % hint_string
		row.add_child(le)
		getter = func():
			var p := le.text.strip_edges()
			if p == "":
				return null
			if not ResourceLoader.exists(p):
				return "__BAD_PATH__:" + p   # flagged in _save so we can warn
			return load(p)
		setter = func(v):
			le.text = v.resource_path if (v != null and v is Resource) else ""
	else:
		var le := LineEdit.new()
		le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		le.editable = false
		le.text = "(unsupported type %d — edit in Inspector)" % ptype
		row.add_child(le)
		getter = func(): return default_val
		setter = func(_v): pass

	form.add_child(row)

	# prime the widget with the script's default, then register.
	setter.call(default_val)
	ctx.fields.append({ "name": pname, "getter": getter, "setter": setter })


## Build the { control, get, set } trio for the Item.stats dictionary editor.
func _make_stat_dict_editor() -> Dictionary:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(rows)
	var add_btn := Button.new()
	add_btn.text = "+ Add stat mod"
	box.add_child(add_btn)

	var keys := _all_stat_keys()
	var add_row := func(key: String, val: float):
		var r := HBoxContainer.new()
		var ob := OptionButton.new()
		ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for k in keys:
			ob.add_item(k)
		if key != "":
			for i in ob.item_count:
				if ob.get_item_text(i) == key:
					ob.select(i)
					break
		r.add_child(ob)
		var sb := SpinBox.new()
		sb.allow_greater = true
		sb.allow_lesser = true
		sb.min_value = -99999
		sb.max_value = 99999
		sb.step = 0.5
		sb.value = val
		sb.custom_minimum_size.x = 120
		r.add_child(sb)
		var del := Button.new()
		del.text = "✕"
		del.pressed.connect(func(): r.queue_free())
		r.add_child(del)
		rows.add_child(r)
	add_btn.pressed.connect(func(): add_row.call("", 0.0))

	var getter := func():
		var d := {}
		for r in rows.get_children():
			var ob: OptionButton = r.get_child(0)
			var sb: SpinBox = r.get_child(1)
			var k := ob.get_item_text(ob.get_selected())
			if k != "" and sb.value != 0.0:
				d[k] = sb.value
		return d
	var setter := func(v):
		for c in rows.get_children():
			c.queue_free()
		if v is Dictionary:
			for k in v.keys():
				add_row.call(str(k), float(v[k]))

	return { "control": box, "getter": getter, "setter": setter }


# ----------------------------------------------------------------------------
# CLONE-FROM  (prefill the form from an existing .tres)
# ----------------------------------------------------------------------------
func _refresh_clone_list(ctx: TabCtx) -> void:
	ctx.clone_pick.clear()
	ctx.clone_pick.add_item("— New (blank) —", 0)
	var files := _list_tres(ctx.dir)
	files.sort()
	for i in files.size():
		ctx.clone_pick.add_item(files[i], i + 1)
	ctx.clone_pick.select(0)


func _apply_clone(ctx: TabCtx, idx: int) -> void:
	if idx <= 0:
		var blank = ctx.type_script.new()
		for f in ctx.fields:
			f.setter.call(blank.get(f.name))
		ctx.filename_edit.text = ""
		_set_status(ctx, "Reset to a blank %s." % ctx.type_name, Color.GRAY)
		return
	var fname := ctx.clone_pick.get_item_text(idx)
	var res = load(ctx.dir + fname)
	if res == null:
		_set_status(ctx, "Could not load %s." % fname, Color("e06c6c"))
		return
	for f in ctx.fields:
		f.setter.call(res.get(f.name))
	ctx.filename_edit.text = fname.trim_suffix(".tres")
	_set_status(ctx, "Loaded [b]%s[/b] — edit and Save (tick Overwrite to replace it)." % fname, Color.GRAY)


# ----------------------------------------------------------------------------
# SAVE
# ----------------------------------------------------------------------------
func _save(ctx: TabCtx) -> void:
	var collected := _collect_values(ctx)
	var values: Array = collected["vals"]
	var bad_paths: Array = collected["bad"]

	# --- validation ----------------------------------------------------------
	var id_str := str(_value_of(values, "id")).strip_edges()
	if id_str == "":
		_set_status(ctx, "[b]Can't save:[/b] id is empty.", Color("e06c6c"))
		return

	var fname := ctx.filename_edit.text.strip_edges()
	if fname == "":
		fname = id_str
	fname = fname.trim_suffix(".tres")
	if not _is_valid_basename(fname):
		_set_status(ctx, "[b]Can't save:[/b] file name has illegal characters.", Color("e06c6c"))
		return

	var path := ctx.dir + fname + ".tres"
	var existed := FileAccess.file_exists(path)
	if existed and not ctx.overwrite.button_pressed:
		_set_status(ctx, "[b]%s.tres already exists.[/b] Tick “Overwrite” to replace it (keeps its UID), or use Duplicate for a fresh copy." % fname, Color("e0b062"))
		return

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ctx.dir))

	# Overwriting: mutate the LOADED resource so ResourceSaver keeps its UID (scene
	# references by uid stay valid). A brand-new file gets a fresh instance + new UID.
	var reused := existed and ctx.overwrite.button_pressed
	var res = _resource_for_save(ctx, path, reused)
	_apply_values(res, values)

	var err := ResourceSaver.save(res, path)
	if err != OK:
		_set_status(ctx, "[b]Save failed[/b] (error %d) writing %s" % [err, path], Color("e06c6c"))
		return

	_reload_db(ctx.db_autoload)
	_refresh_clone_list(ctx)

	var uid_note := "kept its UID" if reused else "new file, fresh UID"
	var msg := "[b]Saved[/b] %s  →  %s  (%s)" % [ctx.type_name, path, uid_note]
	msg += _warn_suffix(_soft_warnings(ctx, res), bad_paths)
	msg += "\n[color=#8a8a8a](appears in the FileSystem dock when you refocus Godot)[/color]"
	_set_status(ctx, msg, Color("7bd88f"))


## Duplicate: always write a NEW file with a FRESH UID and the same field values, giving
## the id + file name a matching _copy suffix. Both must stay unique — AbilityDB/ItemDB
## key on id, so two objects sharing an id would clash in the DB. Then point the form at
## the new copy so the next Save targets it.
func _duplicate(ctx: TabCtx) -> void:
	var collected := _collect_values(ctx)
	var values: Array = collected["vals"]
	var bad_paths: Array = collected["bad"]

	var base_id := str(_value_of(values, "id")).strip_edges()
	if base_id == "":
		base_id = "new"
	var base_name := ctx.filename_edit.text.strip_edges().trim_suffix(".tres")
	if base_name == "":
		base_name = base_id

	var uniq := _unique_copy(ctx, base_name, base_id)
	var new_name: String = uniq["name"]
	var new_id: String = uniq["id"]

	# override the id in the collected values so the copy is independent
	for pair in values:
		if pair["name"] == "id":
			pair["value"] = StringName(new_id)

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ctx.dir))
	var res = ctx.type_script.new()          # fresh instance -> a brand-new UID on save
	_apply_values(res, values)

	var path := ctx.dir + new_name + ".tres"
	var err := ResourceSaver.save(res, path)
	if err != OK:
		_set_status(ctx, "[b]Duplicate failed[/b] (error %d) writing %s" % [err, path], Color("e06c6c"))
		return

	_reload_db(ctx.db_autoload)
	_refresh_clone_list(ctx)

	# move the form onto the new copy (id widget + file name)
	for f in ctx.fields:
		if f["name"] == "id":
			f["setter"].call(StringName(new_id))
	ctx.filename_edit.text = new_name
	ctx.overwrite.button_pressed = false

	var msg := "[b]Duplicated[/b] → %s  (new id [b]%s[/b], fresh UID)\nNow editing the copy — rename its id / file if you like, then Save." % [path, new_id]
	msg += _warn_suffix([], bad_paths)
	_set_status(ctx, msg, Color("7bd88f"))


# ----------------------------------------------------------------------------
# SAVE HELPERS
# ----------------------------------------------------------------------------
## Read every field into [{name, value}] (+ a list of bad res:// paths to warn about).
func _collect_values(ctx: TabCtx) -> Dictionary:
	var values := []
	var bad_paths := []
	for f in ctx.fields:
		var v = f["getter"].call()
		if typeof(v) == TYPE_STRING and str(v).begins_with("__BAD_PATH__:"):
			bad_paths.append(str(f["name"]) + " -> " + str(v).trim_prefix("__BAD_PATH__:"))
			continue   # leave the property at its default (null)
		values.append({"name": f["name"], "value": v})
	return {"vals": values, "bad": bad_paths}


func _apply_values(res, values: Array) -> void:
	for pair in values:
		res.set(pair["name"], pair["value"])


func _value_of(values: Array, key: String, default_val = ""):
	for pair in values:
		if pair["name"] == key:
			return pair["value"]
	return default_val


## The resource to save into `path`. When reusing, load the existing one so its UID is
## preserved on re-save; fall back to a fresh instance if it's missing / the wrong type.
func _resource_for_save(ctx: TabCtx, path: String, reuse: bool):
	if reuse:
		var existing = load(path)
		if existing != null and is_instance_of(existing, ctx.type_script):
			return existing
	return ctx.type_script.new()


## A _copy[/N] suffix that avoids BOTH an existing file AND an existing id in this dir, so
## the file name and id stay in sync. Returns {name, id}.
func _unique_copy(ctx: TabCtx, base_name: String, base_id: String) -> Dictionary:
	var ids := _existing_ids(ctx)
	var is_free := func(suffix: String) -> bool:
		return not FileAccess.file_exists(ctx.dir + base_name + suffix + ".tres") \
			and not ids.has(base_id + suffix)
	if is_free.call("_copy"):
		return {"name": base_name + "_copy", "id": base_id + "_copy"}
	var n := 2
	while not is_free.call("_copy" + str(n)):
		n += 1
	return {"name": base_name + "_copy" + str(n), "id": base_id + "_copy" + str(n)}


## Every id currently used by a .tres in this tab's folder, as a set {id: true}.
func _existing_ids(ctx: TabCtx) -> Dictionary:
	var ids := {}
	for fname in _list_tres(ctx.dir):
		var r = load(ctx.dir + fname)
		if r != null:
			ids[str(r.get("id"))] = true
	return ids


## Fold soft warnings + bad-path notes into a status suffix ("" when none).
func _warn_suffix(warns: Array, bad_paths: Array) -> String:
	var all := warns.duplicate()
	for b in bad_paths:
		all.append("path not found, saved as null: " + b)
	if all.is_empty():
		return ""
	return "\n[color=#e0b062]Heads-up:[/color] " + "  •  ".join(all)


## Non-blocking sanity nudges — the kind of thing the Inspector won't tell you.
func _soft_warnings(ctx: TabCtx, res) -> Array:
	var w := []
	if ctx.type_name == "Ability":
		var kind := int(res.get("kind"))   # 0 ATTACK 1 BUFF 2 DEBUFF 3 HEAL 4 PASSIVE
		var has_power := float(res.get("base_power")) != 0.0 or float(res.get("power_per_point")) != 0.0
		var has_scaling := str(res.get("scaling_stat")) != "" and float(res.get("scaling_mult")) != 0.0
		if (kind == 0 or kind == 3) and not has_power and not has_scaling:
			w.append("this %s has no power and no scaling — it'll do 0." % ("HEAL" if kind == 3 else "ATTACK"))
		if str(res.get("applies_buff")) != "" and kind != 1 and kind != 2:
			w.append("applies_buff is set but kind isn't BUFF/DEBUFF.")
	else:
		var equippable := bool(res.get("equippable"))
		var slot := int(res.get("slot"))
		if equippable and slot == 0:
			w.append("equippable is on but slot is NONE — it won't fit anywhere.")
		if not equippable and slot != 0:
			w.append("slot is set but equippable is off.")
	return w


# ----------------------------------------------------------------------------
# HELPERS
# ----------------------------------------------------------------------------
func _parse_enum(hint_string: String) -> Array:
	var out := []
	var next_val := 0
	for part in hint_string.split(",", false):
		var text := part
		var val := next_val
		if ":" in part:
			var kv := part.split(":")
			text = kv[0]
			val = int(kv[1])
		out.append({ "text": text, "value": val })
		next_val = val + 1
	return out


func _apply_range(sb: SpinBox, hint: int, hint_string: String, is_int: bool) -> void:
	sb.step = 1.0 if is_int else 0.01
	sb.min_value = -99999
	sb.max_value = 99999
	if hint == PROPERTY_HINT_RANGE:
		var parts := hint_string.split(",", false)
		if parts.size() >= 2:
			sb.min_value = float(parts[0])
			sb.max_value = float(parts[1])
			sb.allow_greater = false
			sb.allow_lesser = false
		if parts.size() >= 3 and not parts[2].contains("_"):
			sb.step = float(parts[2])


func _all_stat_keys() -> Array:
	var keys := []
	for k in Stats.major_keys():
		keys.append(str(k))
	keys.append("hp_base")
	for e in Stats.REAL_ELEMENTS:
		keys.append(e + "_pierce")
		keys.append(e + "_defense")
		keys.append(e + "_amp")
	return keys


func _list_tres(dir_path: String) -> Array:
	var out := []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".tres"):
			out.append(fname)
		fname = dir.get_next()
	dir.list_dir_end()
	return out


func _is_valid_basename(s: String) -> bool:
	if s == "":
		return false
	for c in "/\\:*?\"<>|":
		if s.contains(c):
			return false
	return true


func _reload_db(autoload_name: String) -> void:
	var n := get_node_or_null("/root/" + autoload_name)
	if n and n.has_method("reload"):
		n.reload()


func _set_status(ctx: TabCtx, bbcode: String, color: Color) -> void:
	ctx.status.clear()
	ctx.status.push_color(color)
	ctx.status.append_text(bbcode)
	ctx.status.pop()
