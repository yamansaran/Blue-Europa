extends Control

## ============================================================================
## INVENTORY SCREEN  (shell-content panel — toolbar stays)
## ============================================================================
## Built entirely in code. Three width regions:
##
##   LEFT 35%  ── LoadoutSlots widget (model + 9 gear slots) + XP bar
##   MID  20%  ── major & minor attributes (read-only)
##   RIGHT 35% ── a 6-wide x 8-tall GRID of item boxes (vertical scroll) + a
##                money / sell bar
##
## Rev9: the item list is now a grid of square boxes (each shows the item's image
## asset, or a pink square when none is found; hover pops the shared ItemTooltip
## with no fade delay). Gear equipping is real — drag a box onto a fitting slot to
## equip, right-click a slot to unequip. The loadout is the shared LoadoutSlots
## widget, so the shop's copy stays in sync.
## ----------------------------------------------------------------------------

const SCREEN_BG := Color(0.12, 0.12, 0.14)
const PANEL_BG  := Color(0.20, 0.20, 0.20)
const TITLE_COL := Color(0.92, 0.92, 0.92)
const MONEY_COL := Color(1.0, 0.86, 0.35)
const SLOT_TEXT := Color(0.62, 0.62, 0.66)

const GRID_COLS := 6
const GRID_MIN_ROWS := 8

# --- horizontal region anchors (fractions of the panel width) ---
const COL_L_LEFT  := 0.025
const COL_L_RIGHT := 0.375
const COL_M_LEFT  := 0.40
const COL_M_RIGHT := 0.60
const COL_R_LEFT  := 0.625
const COL_R_RIGHT := 0.975

# --- vertical anchors (fractions of the panel length) ---
const BAND_TOP    := 0.10
const BAND_BOTTOM := 0.95
const SPLIT_TOP   := 0.80
const SPLIT_GAP   := 0.82

# runtime refs
var _loadout: LoadoutSlots
var _xp_bar: XPProgressBar
var _attr_list: VBoxContainer
var _grid: GridContainer
var _tooltip: ItemTooltip
var _money_label: Label
var _sell_button: Button
var _name_label: Label
var _selected_index: int = -1
var _boxes: Array = []
## Remembered minor-attribute view (Pierce/Defense/Amp) so it survives refreshes.
var _minor_metric: int = 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = SCREEN_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# one tooltip shared by every grid box
	_tooltip = ItemTooltip.new()
	add_child(_tooltip)

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


func _anchor(c: Control, l: float, t: float, r: float, b: float) -> void:
	c.anchor_left = l
	c.anchor_top = t
	c.anchor_right = r
	c.anchor_bottom = b
	c.offset_left = 0.0
	c.offset_top = 0.0
	c.offset_right = 0.0
	c.offset_bottom = 0.0


# ---------------------------------------------------------------------------
# LEFT top: loadout (shared LoadoutSlots widget + xp bar)
# ---------------------------------------------------------------------------
func _build_loadout(panel: Panel) -> void:
	_name_label = _title("Loadout")
	_anchor(_name_label, 0.0, 0.02, 1.0, 0.09)
	panel.add_child(_name_label)

	_loadout = LoadoutSlots.new()
	_anchor(_loadout, 0.02, 0.10, 0.98, 0.86)
	panel.add_child(_loadout)

	_xp_bar = XPProgressBar.new()
	_anchor(_xp_bar, 0.06, 0.885, 0.94, 0.975)
	panel.add_child(_xp_bar)


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
	var title := _title("Attributes")
	_anchor(title, 0.0, 0.02, 1.0, 0.10)
	panel.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_anchor(scroll, 0.04, 0.12, 0.96, 0.97)
	panel.add_child(scroll)

	_attr_list = VBoxContainer.new()
	_attr_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_attr_list.add_theme_constant_override("separation", 3)
	scroll.add_child(_attr_list)


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

	_attr_header("MINOR ATTRIBUTES", Color(1.0, 0.8, 0.75))
	var bars := MinorAttrBars.new()
	bars.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_attr_list.add_child(bars)
	bars.set_metric(_minor_metric)
	bars.set_body(body)
	bars.metric_changed.connect(func(m): _minor_metric = m)


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
# RIGHT top: item GRID (6 wide, >=8 tall, vertical scroll)
# ---------------------------------------------------------------------------
func _build_items(panel: Panel) -> void:
	var title := _title("Inventory")
	_anchor(title, 0.0, 0.02, 1.0, 0.10)
	panel.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_anchor(scroll, 0.04, 0.12, 0.96, 0.97)
	panel.add_child(scroll)

	_grid = GridContainer.new()
	_grid.columns = GRID_COLS
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 6)
	_grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(_grid)


func _refresh_items() -> void:
	if _grid == null:
		return
	for c in _grid.get_children():
		c.queue_free()
	_boxes.clear()
	_selected_index = -1

	var ch := _char()
	var items: Array = []
	if ch and typeof(ch.get("items")) == TYPE_ARRAY:
		items = ch.items

	var rows: int = maxi(GRID_MIN_ROWS, int(ceil(float(items.size()) / float(GRID_COLS))))
	var cells: int = rows * GRID_COLS
	for i in cells:
		var box := ItemBox.new()
		_grid.add_child(box)
		if i < items.size():
			box.setup(i, items[i], _tooltip, true, "bag")
			box.pressed.connect(_on_box_pressed)
		else:
			box.setup(i, null, _tooltip, false, "bag")
		_boxes.append(box)

	_update_sell_enabled()


func _on_box_pressed(index: int) -> void:
	# toggle selection
	if _selected_index == index:
		_set_selected(-1)
	else:
		_set_selected(index)


func _set_selected(index: int) -> void:
	for b in _boxes:
		if is_instance_valid(b):
			b.set_selected(b.index == index)
	_selected_index = index
	_update_sell_enabled()


# ---------------------------------------------------------------------------
# RIGHT bottom: money + sell
# ---------------------------------------------------------------------------
func _build_money(panel: Panel) -> void:
	_money_label = Label.new()
	_anchor(_money_label, 0.06, 0.0, 0.60, 1.0)
	_money_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_money_label.add_theme_color_override("font_color", MONEY_COL)
	_money_label.add_theme_font_size_override("font_size", 16)
	panel.add_child(_money_label)

	_sell_button = Button.new()
	_sell_button.text = "Sell"
	_anchor(_sell_button, 0.64, 0.22, 0.94, 0.78)
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
	if _loadout:
		_loadout.refresh()
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
