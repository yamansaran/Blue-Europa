extends Control

## ============================================================================
## INVENTORY SCREEN  (shell-content panel — toolbar stays)
## ============================================================================
## Built entirely in code (anchors are finicky in the editor; the .tscn is just a
## Control root + this script + a background). Three width regions, each 85% of
## the panel length, with 10% length buffer above and 5% below:
##
##   LEFT 35%  ── loadout panel (70% length)  + portrait panel (blank, ~13%)
##   MID  20%  ── major & minor attributes (85% length)
##   RIGHT 35% ── item list (70% length)      + money/sell bar (~13%)
##
## The loadout panel shows the viewed character's gear slots around a central
## skeleton rig, with the shared XPProgressBar pinned to its bottom.
## ----------------------------------------------------------------------------

# Optional: assign a skeleton-rig PackedScene in the Inspector to show the real
# rig in the centre of the loadout panel. Left null -> a labelled placeholder.
@export var rig_scene: PackedScene = null

const SCREEN_BG := Color(0.12, 0.12, 0.14)
const PANEL_BG  := Color(0.20, 0.20, 0.20)
const SLOT_BG   := Color(0.15, 0.15, 0.17)
const SLOT_TEXT := Color(0.62, 0.62, 0.66)
const TITLE_COL := Color(0.92, 0.92, 0.92)
const MONEY_COL := Color(1.0, 0.86, 0.35)

# --- horizontal region anchors (fractions of the panel width) ---
const COL_L_LEFT  := 0.025
const COL_L_RIGHT := 0.375
const COL_M_LEFT  := 0.40
const COL_M_RIGHT := 0.60
const COL_R_LEFT  := 0.625
const COL_R_RIGHT := 0.975

# --- vertical anchors (fractions of the panel length) ---
const BAND_TOP    := 0.10   # 10% buffer above
const BAND_BOTTOM := 0.95   # 5% buffer below
const SPLIT_TOP   := 0.80   # bottom of the tall (70%) panels
const SPLIT_GAP   := 0.82   # top of the short (~13%) panels

# runtime refs
var _xp_bar: XPProgressBar
var _attr_list: VBoxContainer
var _item_list: VBoxContainer
var _money_label: Label
var _sell_button: Button
var _name_label: Label
var _item_group: ButtonGroup
var _selected_index: int = -1


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = SCREEN_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# --- the five panels ---
	var loadout   := _make_panel(COL_L_LEFT, BAND_TOP, COL_L_RIGHT, SPLIT_TOP)
	var portraits := _make_panel(COL_L_LEFT, SPLIT_GAP, COL_L_RIGHT, BAND_BOTTOM)
	var attributes := _make_panel(COL_M_LEFT, BAND_TOP, COL_M_RIGHT, BAND_BOTTOM)
	var items     := _make_panel(COL_R_LEFT, BAND_TOP, COL_R_RIGHT, SPLIT_TOP)
	var money     := _make_panel(COL_R_LEFT, SPLIT_GAP, COL_R_RIGHT, BAND_BOTTOM)
	add_child(loadout)
	add_child(portraits)
	add_child(attributes)
	add_child(items)
	add_child(money)

	_build_loadout(loadout)
	_build_portraits(portraits)
	_build_attributes(attributes)
	_build_items(items)
	_build_money(money)
	_build_close_button()

	var ch := _char()
	if ch and not ch.changed.is_connected(_on_character_changed):
		ch.changed.connect(_on_character_changed)

	_refresh_all()


func _char() -> Node:
	return get_node_or_null("/root/Character")


# ---------------------------------------------------------------------------
# Panel + helper builders
# ---------------------------------------------------------------------------
func _make_panel(l: float, t: float, r: float, b: float) -> Panel:
	var p := Panel.new()
	p.anchor_left = l
	p.anchor_top = t
	p.anchor_right = r
	p.anchor_bottom = b
	p.offset_left = 0.0
	p.offset_top = 0.0
	p.offset_right = 0.0
	p.offset_bottom = 0.0
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.set_corner_radius_all(4)
	p.add_theme_stylebox_override("panel", sb)
	return p


func _title(text: String, size := 18) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", TITLE_COL)
	return l


## A titled ScrollContainer + VBox filling most of a panel. Returns the VBox.
func _scroll_list_in(panel: Panel, title_text: String) -> VBoxContainer:
	var title := _title(title_text)
	title.anchor_left = 0.0
	title.anchor_right = 1.0
	title.anchor_top = 0.02
	title.anchor_bottom = 0.10
	title.offset_left = 0.0
	title.offset_right = 0.0
	title.offset_top = 0.0
	title.offset_bottom = 0.0
	panel.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.anchor_left = 0.04
	scroll.anchor_right = 0.96
	scroll.anchor_top = 0.12
	scroll.anchor_bottom = 0.97
	scroll.offset_left = 0.0
	scroll.offset_right = 0.0
	scroll.offset_top = 0.0
	scroll.offset_bottom = 0.0
	panel.add_child(scroll)

	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 3)
	scroll.add_child(vb)
	return vb


func _item_name(it) -> String:
	if typeof(it) == TYPE_DICTIONARY:
		return str(it.get("name", it.get("id", "item")))
	return str(it)


# ---------------------------------------------------------------------------
# LEFT top: loadout (gear slots + rig + xp bar)
# ---------------------------------------------------------------------------
func _build_loadout(panel: Panel) -> void:
	_name_label = _title("Loadout")
	_name_label.anchor_left = 0.0
	_name_label.anchor_right = 1.0
	_name_label.anchor_top = 0.02
	_name_label.anchor_bottom = 0.09
	_name_label.offset_left = 0.0
	_name_label.offset_right = 0.0
	_name_label.offset_top = 0.0
	_name_label.offset_bottom = 0.0
	panel.add_child(_name_label)

	# central skeleton rig (real scene if assigned, else placeholder)
	var rig_area := Control.new()
	rig_area.anchor_left = 0.31
	rig_area.anchor_right = 0.69
	rig_area.anchor_top = 0.14
	rig_area.anchor_bottom = 0.66
	rig_area.offset_left = 0.0
	rig_area.offset_right = 0.0
	rig_area.offset_top = 0.0
	rig_area.offset_bottom = 0.0
	rig_area.clip_contents = true
	rig_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(rig_area)
	if rig_scene != null:
		var rig := rig_scene.instantiate()
		rig_area.add_child(rig)
		if rig is Control:
			(rig as Control).set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	else:
		var ph := ColorRect.new()
		ph.color = Color(0.10, 0.10, 0.12)
		ph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rig_area.add_child(ph)
		var pl := Label.new()
		pl.text = "Skeleton\nRig"
		pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		pl.add_theme_color_override("font_color", SLOT_TEXT)
		pl.add_theme_font_size_override("font_size", 12)
		pl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		pl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rig_area.add_child(pl)

	# gear slots: two columns of four + one accessory below the rig
	var lx0 := 0.05
	var lx1 := 0.28
	var rx0 := 0.72
	var rx1 := 0.95
	var rows := [[0.12, 0.27], [0.30, 0.45], [0.48, 0.63], [0.66, 0.81]]
	# left column
	_make_slot(panel, "Headwear",         lx0, rows[0][0], lx1, rows[0][1])
	_make_slot(panel, "Bodywear",         lx0, rows[1][0], lx1, rows[1][1])
	_make_slot(panel, "Leggings",         lx0, rows[2][0], lx1, rows[2][1])
	_make_slot(panel, "Gloves",           lx0, rows[3][0], lx1, rows[3][1])
	# right column
	_make_slot(panel, "Footwear",         rx0, rows[0][0], rx1, rows[0][1])
	_make_slot(panel, "Primary Weapon",   rx0, rows[1][0], rx1, rows[1][1])
	_make_slot(panel, "Secondary Weapon", rx0, rows[2][0], rx1, rows[2][1])
	_make_slot(panel, "Accessory I",      rx0, rows[3][0], rx1, rows[3][1])
	# ninth slot, centred below the rig
	_make_slot(panel, "Accessory II",     0.35, 0.68, 0.65, 0.83)

	# level-up progress bar pinned to the bottom of the loadout panel
	_xp_bar = XPProgressBar.new()
	_xp_bar.anchor_left = 0.06
	_xp_bar.anchor_right = 0.94
	_xp_bar.anchor_top = 0.885
	_xp_bar.anchor_bottom = 0.975
	_xp_bar.offset_left = 0.0
	_xp_bar.offset_right = 0.0
	_xp_bar.offset_top = 0.0
	_xp_bar.offset_bottom = 0.0
	panel.add_child(_xp_bar)


## A labelled empty gear box at the given anchor rect (fractions of the panel).
func _make_slot(panel: Panel, label: String, l: float, t: float, r: float, b: float) -> void:
	var slot := Panel.new()
	slot.anchor_left = l
	slot.anchor_top = t
	slot.anchor_right = r
	slot.anchor_bottom = b
	slot.offset_left = 0.0
	slot.offset_top = 0.0
	slot.offset_right = 0.0
	slot.offset_bottom = 0.0
	var sb := StyleBoxFlat.new()
	sb.bg_color = SLOT_BG
	sb.set_corner_radius_all(3)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.30, 0.30, 0.34)
	slot.add_theme_stylebox_override("panel", sb)
	panel.add_child(slot)

	var lbl := Label.new()
	lbl.text = label
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_color_override("font_color", SLOT_TEXT)
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(lbl)


# ---------------------------------------------------------------------------
# LEFT bottom: portraits (blank for now)
# ---------------------------------------------------------------------------
func _build_portraits(panel: Panel) -> void:
	var l := Label.new()
	l.text = "Party"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", SLOT_TEXT)
	l.add_theme_font_size_override("font_size", 12)
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(l)


# ---------------------------------------------------------------------------
# MIDDLE: attributes (major + minor, read-only)
# ---------------------------------------------------------------------------
func _build_attributes(panel: Panel) -> void:
	_attr_list = _scroll_list_in(panel, "Attributes")


func _refresh_attributes() -> void:
	if _attr_list == null:
		return
	for c in _attr_list.get_children():
		c.queue_free()
	var ch := _char()
	if ch == null or not ch.has_method("get_body"):
		return
	var body: CharacterBase = ch.get_body()
	if body == null:
		return

	_attr_header("Level %d" % int(ch.level), MONEY_COL)
	_attr_line("Max HP", str(body.max_hp()))
	_attr_line("Spirit (max)", str(body.max_spirit()))

	_attr_header("MAJOR", Color(0.75, 0.85, 1.0))
	for major in Stats.visible_major_keys():
		var base_v := int(round(body.get_base(major)))
		var bonus_v := int(round(body.get_bonus(major)))
		var eff_v := body.get_effective_int(major)
		var txt := str(eff_v)
		if bonus_v != 0:
			var sgn := "+" if bonus_v > 0 else ""
			txt = "%d (%s%d) %d" % [base_v, sgn, bonus_v, eff_v]
		_attr_line(major.capitalize(), txt)

	_attr_header("MINOR  (Pierce / Def / Amp)", Color(1.0, 0.8, 0.75))
	for element in Stats.REAL_ELEMENTS:
		var p := body.get_effective_int(Stats.pierce_key(element))
		var d := body.get_effective_int(Stats.defense_key(element))
		var a := body.get_effective_int(Stats.amp_key(element))
		_attr_line(element.capitalize(), "%d / %d / %d" % [p, d, a])


func _attr_header(text: String, col: Color) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", col)
	_attr_list.add_child(l)


func _attr_line(name_text: String, value_text: String) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var n := Label.new()
	n.text = name_text
	n.add_theme_font_size_override("font_size", 12)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := Label.new()
	v.text = value_text
	v.add_theme_font_size_override("font_size", 12)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(n)
	row.add_child(v)
	_attr_list.add_child(row)


# ---------------------------------------------------------------------------
# RIGHT top: item list (selectable)
# ---------------------------------------------------------------------------
func _build_items(panel: Panel) -> void:
	_item_list = _scroll_list_in(panel, "Inventory")


func _refresh_items() -> void:
	if _item_list == null:
		return
	for c in _item_list.get_children():
		c.queue_free()
	_item_group = ButtonGroup.new()
	_selected_index = -1

	var ch := _char()
	var items: Array = []
	if ch and typeof(ch.get("items")) == TYPE_ARRAY:
		items = ch.items

	if items.is_empty():
		var none := Label.new()
		none.text = "(empty)"
		none.add_theme_color_override("font_color", SLOT_TEXT)
		_item_list.add_child(none)
	else:
		for i in items.size():
			var it = items[i]
			var b := Button.new()
			b.toggle_mode = true
			b.button_group = _item_group
			b.text = _item_name(it)
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.add_theme_font_size_override("font_size", 12)
			var idx := i
			b.toggled.connect(func(pressed: bool): _on_item_toggled(pressed, idx))
			_item_list.add_child(b)

	_update_sell_enabled()


func _on_item_toggled(pressed: bool, index: int) -> void:
	# In a ButtonGroup the old button's toggled(false) can arrive after the new
	# button's toggled(true); only clear if the deselected item was the selected one.
	if pressed:
		_selected_index = index
	elif _selected_index == index:
		_selected_index = -1
	_update_sell_enabled()


# ---------------------------------------------------------------------------
# RIGHT bottom: money + sell
# ---------------------------------------------------------------------------
func _build_money(panel: Panel) -> void:
	_money_label = Label.new()
	_money_label.anchor_left = 0.06
	_money_label.anchor_right = 0.60
	_money_label.anchor_top = 0.0
	_money_label.anchor_bottom = 1.0
	_money_label.offset_left = 0.0
	_money_label.offset_right = 0.0
	_money_label.offset_top = 0.0
	_money_label.offset_bottom = 0.0
	_money_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_money_label.add_theme_color_override("font_color", MONEY_COL)
	_money_label.add_theme_font_size_override("font_size", 16)
	panel.add_child(_money_label)

	_sell_button = Button.new()
	_sell_button.text = "Sell"
	_sell_button.anchor_left = 0.64
	_sell_button.anchor_right = 0.94
	_sell_button.anchor_top = 0.22
	_sell_button.anchor_bottom = 0.78
	_sell_button.offset_left = 0.0
	_sell_button.offset_right = 0.0
	_sell_button.offset_top = 0.0
	_sell_button.offset_bottom = 0.0
	_sell_button.pressed.connect(_on_sell_pressed)
	panel.add_child(_sell_button)


func _refresh_money() -> void:
	var ch := _char()
	if _money_label and ch:
		_money_label.text = "Money: %d" % int(ch.money)


func _update_sell_enabled() -> void:
	if _sell_button:
		_sell_button.disabled = _selected_index < 0


func _on_sell_pressed() -> void:
	var ch := _char()
	if ch == null or _selected_index < 0:
		return
	if ch.has_method("sell_item"):
		ch.sell_item(_selected_index)   # emits `changed` -> _refresh_all rebuilds


# ---------------------------------------------------------------------------
# Refresh + close
# ---------------------------------------------------------------------------
func _on_character_changed() -> void:
	_refresh_all()


func _refresh_all() -> void:
	var ch := _char()
	if ch and _name_label:
		_name_label.text = "%s  ·  Lv %d" % [str(ch.char_name), int(ch.level)]
	if ch and _xp_bar:
		_xp_bar.set_xp_level(int(ch.xp), int(ch.level))
	_refresh_attributes()
	_refresh_items()
	_refresh_money()


func _build_close_button() -> void:
	var x := Button.new()
	x.text = "X"
	x.tooltip_text = "Return to overworld"
	x.add_theme_font_size_override("font_size", 16)
	x.anchor_left = 1.0
	x.anchor_right = 1.0
	x.anchor_top = 0.0
	x.anchor_bottom = 0.0
	x.offset_left = -40.0
	x.offset_top = 8.0
	x.offset_right = -8.0
	x.offset_bottom = 40.0
	x.pressed.connect(_on_close_pressed)
	add_child(x)


func _on_close_pressed() -> void:
	if GameManager and GameManager.has_method("go_to_overworld"):
		GameManager.go_to_overworld()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_close_pressed()
