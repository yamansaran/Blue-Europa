extends Control

## ============================================================================
## MAIN MENU  —  New Game / Load Game, over five save slots
## ============================================================================
## NEW GAME: pick a slot (an occupied one asks to overwrite) -> name the save ->
##           class select (GameManager.go_to_class_select).
## LOAD GAME: pick an occupied slot -> SaveSlots.load_slot -> the shell / overworld.
##           Occupied slots also carry a small Delete button (with a confirm).
## Everything is built in code on Godot's stock Controls + ConfirmationDialog.
## ----------------------------------------------------------------------------

enum Mode { NONE, NEW, LOAD }

const ACCENT := Color(0.40, 0.55, 0.95)
const PANEL_BG := Color(0.07, 0.08, 0.12, 0.96)
const NAME_MAX := 24

var _mode: int = Mode.NONE
var _load_btn: Button
var _slot_panel: PanelContainer
var _slot_title: Label
var _slot_list: VBoxContainer
var _name_panel: PanelContainer
var _name_edit: LineEdit
var _confirm: ConfirmationDialog
var _pending_slot := -1
var _pending_action := ""

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	SaveSlots.close_active()
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.04, 0.07)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# --- left column: title + buttons ---
	var left := VBoxContainer.new()
	left.anchor_left = 0.07
	left.anchor_right = 0.40
	left.anchor_top = 0.18
	left.anchor_bottom = 0.90
	left.add_theme_constant_override("separation", 16)
	add_child(left)
	var title := Label.new()
	title.text = "BLUE EUROPA"
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", Color(0.74, 0.82, 1.0))
	left.add_child(title)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 40)
	left.add_child(spacer)
	left.add_child(_menu_button("New Game", _on_new_game))
	_load_btn = _menu_button("Load Game", _on_load_game)
	left.add_child(_load_btn)
	left.add_child(_menu_button("Quit", func(): get_tree().quit()))

	# --- right: the slot list ---
	_slot_panel = _panel(0.46, 0.93, 0.16, 0.86)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	_slot_panel.add_child(col)
	_slot_title = Label.new()
	_slot_title.add_theme_font_size_override("font_size", 26)
	col.add_child(_slot_title)
	_slot_list = VBoxContainer.new()
	_slot_list.add_theme_constant_override("separation", 10)
	_slot_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_slot_list)
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(120, 38)
	back.size_flags_horizontal = Control.SIZE_SHRINK_END
	back.pressed.connect(_close_slots)
	col.add_child(back)
	_slot_panel.visible = false

	# --- name-the-save dialog ---
	_name_panel = _panel(0.30, 0.70, 0.36, 0.64)
	var nv := VBoxContainer.new()
	nv.add_theme_constant_override("separation", 14)
	_name_panel.add_child(nv)
	var nl := Label.new()
	nl.text = "Name this save"
	nl.add_theme_font_size_override("font_size", 24)
	nv.add_child(nl)
	_name_edit = LineEdit.new()
	_name_edit.max_length = NAME_MAX
	_name_edit.placeholder_text = "Save name"
	_name_edit.custom_minimum_size = Vector2(0, 44)
	_name_edit.add_theme_font_size_override("font_size", 20)
	_name_edit.text_submitted.connect(func(_t): _on_name_confirmed())
	nv.add_child(_name_edit)
	var nb := HBoxContainer.new()
	nb.alignment = BoxContainer.ALIGNMENT_END
	nb.add_theme_constant_override("separation", 10)
	nv.add_child(nb)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.custom_minimum_size = Vector2(110, 40)
	cancel.pressed.connect(func(): _name_panel.visible = false)
	nb.add_child(cancel)
	var ok := Button.new()
	ok.text = "Choose Class  ›"
	ok.custom_minimum_size = Vector2(170, 40)
	ok.pressed.connect(_on_name_confirmed)
	nb.add_child(ok)
	_name_panel.visible = false

	_confirm = ConfirmationDialog.new()
	_confirm.confirmed.connect(_on_confirmed)
	add_child(_confirm)

	_refresh_load_button()

func _menu_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(300, 58)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.add_theme_font_size_override("font_size", 24)
	b.pressed.connect(cb)
	return b

func _panel(l: float, r: float, t: float, b: float) -> PanelContainer:
	var p := PanelContainer.new()
	p.anchor_left = l
	p.anchor_right = r
	p.anchor_top = t
	p.anchor_bottom = b
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.border_color = ACCENT.darkened(0.3)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(20)
	p.add_theme_stylebox_override("panel", sb)
	add_child(p)
	return p

func _refresh_load_button() -> void:
	_load_btn.disabled = not SaveSlots.any_saves()

# ----------------------------------------------------------------------------
func _on_new_game() -> void:
	_open_slots(Mode.NEW)

func _on_load_game() -> void:
	_open_slots(Mode.LOAD)

func _open_slots(mode: int) -> void:
	_mode = mode
	_slot_title.text = "New Game — choose a slot" if mode == Mode.NEW else "Load Game"
	_rebuild_slots()
	_slot_panel.visible = true

func _close_slots() -> void:
	_slot_panel.visible = false
	_mode = Mode.NONE

func _rebuild_slots() -> void:
	for c in _slot_list.get_children():
		c.queue_free()
	for i in range(1, SaveSlots.MAX_SLOTS + 1):
		var info := SaveSlots.slot_info(i)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var b := Button.new()
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 64)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 17)
		b.text = _slot_text(i, info)
		b.pressed.connect(_on_slot_pressed.bind(i))
		if _mode == Mode.LOAD and info.is_empty():
			b.disabled = true
		row.add_child(b)
		if _mode == Mode.LOAD and not info.is_empty():
			var del := Button.new()
			del.text = "Delete"
			del.custom_minimum_size = Vector2(84, 64)
			del.pressed.connect(_ask.bind("delete", i, "Delete \"%s\"? This cannot be undone." % str(info.get("name", "Save"))))
			row.add_child(del)
		_slot_list.add_child(row)

func _slot_text(i: int, info: Dictionary) -> String:
	if info.is_empty():
		return "  Slot %d   —   Empty" % i
	var parts := [ClassRegistry.display_name(str(info.get("class_id", "blue_blood"))), "Lv %d" % int(info.get("level", 1))]
	if str(info.get("zone", "")) != "":
		parts.append(str(info["zone"]))
	return "  Slot %d   —   %s\n  %s   ·   last played %s" % [i, str(info.get("name", "Save")),
		"  ·  ".join(parts), str(info.get("last_played", "")).replace("T", " ")]

func _on_slot_pressed(slot: int) -> void:
	if _mode == Mode.LOAD:
		if SaveSlots.load_slot(slot):
			GameManager.go_to_shell()
		return
	if _mode == Mode.NEW:
		if not SaveSlots.is_empty(slot):
			_ask("overwrite", slot, "Slot %d already holds \"%s\". Overwrite it with a new game?" % [slot, str(SaveSlots.slot_info(slot).get("name", "Save"))])
		else:
			_ask_name(slot)

func _ask(action: String, slot: int, text: String) -> void:
	_pending_action = action
	_pending_slot = slot
	_confirm.dialog_text = text
	_confirm.popup_centered(Vector2i(460, 150))

func _on_confirmed() -> void:
	match _pending_action:
		"overwrite":
			_ask_name(_pending_slot)
		"delete":
			SaveSlots.delete_slot(_pending_slot)
			_rebuild_slots()
			_refresh_load_button()

func _ask_name(slot: int) -> void:
	_pending_slot = slot
	_name_edit.text = "Save %d" % slot
	_name_panel.visible = true
	_name_edit.grab_focus()
	_name_edit.select_all()

func _on_name_confirmed() -> void:
	if _pending_slot < 1:
		return
	var nm := _name_edit.text.strip_edges()
	if nm == "":
		nm = "Save %d" % _pending_slot
	_name_panel.visible = false
	GameManager.go_to_class_select(_pending_slot, nm)
