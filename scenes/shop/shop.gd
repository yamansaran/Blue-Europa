extends Control

## ============================================================================
## SHOP SCREEN  (shell-content panel — toolbar stays)
## ============================================================================
## Built entirely in code. Three width sections (each 30% wide, 10% total in
## buffers):
##
##   LEFT 30%   ── shopkeep panel (80% tall, 10% buffers): a blank shopkeep image
##                 (10%-50% length) over the shopkeep's dialogue (60%-100%).
##   MIDDLE 30% ── two stacked panels (35% tall each, 10% buffers): the shared
##                 LoadoutSlots (model + equipped gear, synced with inventory) on
##                 top, the "for sale" item grid below.
##   RIGHT 30%  ── the player's inventory grid (10%-70% length), a 10% buffer,
##                 then a money + Sell bar (80%-90% length).
##
## Buying: click a "for sale" box. Selling: select a bag box, press Sell.
## Equipping: drag a bag box onto a fitting slot in the middle loadout (right-
## click a slot to unequip) — the same LoadoutSlots the inventory screen shows,
## so changes appear in both places.
## ----------------------------------------------------------------------------

const SCREEN_BG := Color(0.06, 0.16, 0.10)   # muted shop green
const PANEL_BG  := Color(0.16, 0.20, 0.17)
const SUBPANEL_BG := Color(0.12, 0.15, 0.13)
const TITLE_COL := Color(0.92, 0.94, 0.90)
const MONEY_COL := Color(1.0, 0.86, 0.35)
const DIALOGUE_COL := Color(0.86, 0.90, 0.84)
const SLOT_TEXT := Color(0.62, 0.66, 0.62)

const SHOP_COLS := 5
const BAG_MIN_ROWS := 6

var _tooltip: ItemTooltip
var _loadout: LoadoutSlots
var _sale_grid: GridContainer
var _bag_grid: GridContainer
var _money_label: Label
var _sell_button: Button
var _dialogue: Label

var _stock_ids: Array = []
var _bag_boxes: Array = []
var _selected_index: int = -1


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = SCREEN_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# one tooltip shared by both item grids
	_tooltip = ItemTooltip.new()
	add_child(_tooltip)

	_build_shopkeep()
	_build_middle()
	_build_right()
	_build_close_button()

	var ch := _char()
	if ch and not ch.changed.is_connected(_on_character_changed):
		ch.changed.connect(_on_character_changed)

	_refresh_all()
	if _stock_ids.is_empty():
		_say("Sorry, traveller — I've nothing to sell here. Try another town.")
	else:
		_say("Welcome, traveller. See anything you like?")


func _char() -> Node:
	return get_node_or_null("/root/Character")


# ---------------------------------------------------------------------------
# Shared builders
# ---------------------------------------------------------------------------
func _make_panel(l: float, t: float, r: float, b: float, col := PANEL_BG) -> Panel:
	var p := Panel.new()
	_anchor(p, l, t, r, b)
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(4)
	p.add_theme_stylebox_override("panel", sb)
	return p


func _anchor(c: Control, l: float, t: float, r: float, b: float) -> void:
	c.anchor_left = l
	c.anchor_top = t
	c.anchor_right = r
	c.anchor_bottom = b
	c.offset_left = 0.0
	c.offset_top = 0.0
	c.offset_right = 0.0
	c.offset_bottom = 0.0


func _title(text: String, size := 15) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", TITLE_COL)
	return l


## A scrollable, centred grid inside `panel`, below an optional title band.
func _grid_in(panel: Panel, cols: int, title_text := "") -> GridContainer:
	var top := 0.02
	if title_text != "":
		var title := _title(title_text)
		_anchor(title, 0.0, 0.02, 1.0, 0.16)
		panel.add_child(title)
		top = 0.18
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_anchor(scroll, 0.04, top, 0.96, 0.97)
	panel.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = cols
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(grid)
	return grid


# ---------------------------------------------------------------------------
# LEFT: shopkeep (image + dialogue)
# ---------------------------------------------------------------------------
func _build_shopkeep() -> void:
	var panel := _make_panel(0.02, 0.10, 0.32, 0.90)
	add_child(panel)

	# blank shopkeep image (10%-50% length)
	var portrait := Panel.new()
	_anchor(portrait, 0.10, 0.10, 0.90, 0.50)
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0.08, 0.10, 0.09)
	psb.set_corner_radius_all(4)
	psb.set_border_width_all(1)
	psb.border_color = Color(0.24, 0.28, 0.24)
	portrait.add_theme_stylebox_override("panel", psb)
	panel.add_child(portrait)

	var ph := _title("Shopkeep", 13)
	ph.add_theme_color_override("font_color", SLOT_TEXT)
	ph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.add_child(ph)

	# dialogue (60%-100% length)
	var dbox := Panel.new()
	_anchor(dbox, 0.08, 0.60, 0.92, 0.96)
	var dsb := StyleBoxFlat.new()
	dsb.bg_color = SUBPANEL_BG
	dsb.set_corner_radius_all(4)
	dbox.add_theme_stylebox_override("panel", dsb)
	panel.add_child(dbox)

	_dialogue = Label.new()
	_anchor(_dialogue, 0.06, 0.06, 0.94, 0.94)
	_dialogue.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dialogue.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_dialogue.add_theme_font_size_override("font_size", 13)
	_dialogue.add_theme_color_override("font_color", DIALOGUE_COL)
	dbox.add_child(_dialogue)


func _say(text: String) -> void:
	if _dialogue:
		_dialogue.text = text


# ---------------------------------------------------------------------------
# MIDDLE: loadout (top) + for-sale grid (bottom)
# ---------------------------------------------------------------------------
func _build_middle() -> void:
	var top := _make_panel(0.35, 0.10, 0.65, 0.45)
	add_child(top)
	var t := _title("Equipped")
	_anchor(t, 0.0, 0.02, 1.0, 0.14)
	top.add_child(t)
	_loadout = LoadoutSlots.new()
	_anchor(_loadout, 0.04, 0.15, 0.96, 0.97)
	top.add_child(_loadout)

	var bottom := _make_panel(0.35, 0.55, 0.65, 0.90)
	add_child(bottom)
	_sale_grid = _grid_in(bottom, SHOP_COLS, "For Sale")


## The stock this shop shows comes from the CURRENT campaign module
## (Campaign.shop_stock, set in scenes/campaigns/modules/<id>/<id>.gd) — NOT
## hard-coded here. Empty campaign stock -> an empty shop.
func _current_shop_stock() -> Array:
	var cdb := get_node_or_null("/root/CampaignDB")
	if cdb == null or not cdb.has_method("get_current"):
		return []
	var camp = cdb.get_current()
	if camp == null:
		return []
	if camp.has_method("shop_stock_ids"):
		return camp.shop_stock_ids()
	# fallback: read the field directly if the helper isn't present
	var s = camp.get("shop_stock")
	return s if typeof(s) == TYPE_ARRAY else []


func _refresh_sale() -> void:
	if _sale_grid == null:
		return
	for c in _sale_grid.get_children():
		c.queue_free()
	_stock_ids.clear()

	var db := get_node_or_null("/root/ItemDB")
	if db == null:
		return
	_stock_ids = _current_shop_stock()
	for i in _stock_ids.size():
		var iid := str(_stock_ids[i])
		var item = db.get_item(iid)
		var entry := {"id": iid, "name": (item.display_name if item else iid)}
		var box := ItemBox.new()
		_sale_grid.add_child(box)
		box.setup(i, entry, _tooltip, false, "shop")   # not draggable: click to buy
		box.pressed.connect(_on_buy_pressed)
		box.mouse_entered.connect(_on_stock_hover.bind(i))


func _on_stock_hover(index: int) -> void:
	if index < 0 or index >= _stock_ids.size():
		return
	var db := get_node_or_null("/root/ItemDB")
	if db == null:
		return
	var item = db.get_item(str(_stock_ids[index]))
	if item:
		_say("%s — %d gold.%s" % [item.display_name, item.value, ("" if _can_afford(item.value) else "  (You can't afford that.)")])


func _on_buy_pressed(index: int) -> void:
	if index < 0 or index >= _stock_ids.size():
		return
	var ch := _char()
	var db := get_node_or_null("/root/ItemDB")
	if ch == null or db == null:
		return
	var iid := str(_stock_ids[index])
	var item = db.get_item(iid)
	if item == null:
		return
	if not _can_afford(item.value):
		_say("That's %d gold — more than you've got, I'm afraid." % item.value)
		return
	if ch.has_method("buy_item") and ch.buy_item(iid):
		_say("The %s is yours. Pleasure doing business." % item.display_name)


func _can_afford(amount: int) -> bool:
	var ch := _char()
	if ch and ch.has_method("can_afford"):
		return ch.can_afford(amount)
	return false


# ---------------------------------------------------------------------------
# RIGHT: player inventory grid + money/sell bar
# ---------------------------------------------------------------------------
func _build_right() -> void:
	var inv := _make_panel(0.68, 0.10, 0.98, 0.70)
	add_child(inv)
	_bag_grid = _grid_in(inv, SHOP_COLS, "Inventory")

	var money := _make_panel(0.68, 0.80, 0.98, 0.90)
	add_child(money)
	_money_label = Label.new()
	_anchor(_money_label, 0.06, 0.0, 0.60, 1.0)
	_money_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_money_label.add_theme_color_override("font_color", MONEY_COL)
	_money_label.add_theme_font_size_override("font_size", 16)
	money.add_child(_money_label)

	_sell_button = Button.new()
	_anchor(_sell_button, 0.64, 0.22, 0.94, 0.78)
	_sell_button.text = "Sell"
	_sell_button.pressed.connect(_on_sell_pressed)
	money.add_child(_sell_button)


func _refresh_bag() -> void:
	if _bag_grid == null:
		return
	for c in _bag_grid.get_children():
		c.queue_free()
	_bag_boxes.clear()
	_selected_index = -1

	var ch := _char()
	var items: Array = []
	if ch and typeof(ch.get("items")) == TYPE_ARRAY:
		items = ch.items

	var rows: int = maxi(BAG_MIN_ROWS, int(ceil(float(items.size()) / float(SHOP_COLS))))
	var cells: int = rows * SHOP_COLS
	for i in cells:
		var box := ItemBox.new()
		_bag_grid.add_child(box)
		if i < items.size():
			box.setup(i, items[i], _tooltip, true, "bag")
			box.pressed.connect(_on_bag_pressed)
		else:
			box.setup(i, null, _tooltip, false, "bag")
		_bag_boxes.append(box)

	_update_sell_enabled()


func _on_bag_pressed(index: int) -> void:
	if _selected_index == index:
		_set_selected(-1)
	else:
		_set_selected(index)


func _set_selected(index: int) -> void:
	for b in _bag_boxes:
		if is_instance_valid(b):
			b.set_selected(b.index == index)
	_selected_index = index
	_update_sell_enabled()


func _update_sell_enabled() -> void:
	if _sell_button:
		_sell_button.disabled = _selected_index < 0


func _on_sell_pressed() -> void:
	var ch := _char()
	if ch == null or _selected_index < 0:
		return
	var name_txt := ""
	if _selected_index < ch.items.size():
		var it = ch.items[_selected_index]
		if typeof(it) == TYPE_DICTIONARY:
			name_txt = str(it.get("name", it.get("id", "item")))
	if ch.has_method("sell_item"):
		var got: int = ch.sell_item(_selected_index)   # emits changed -> refresh
		if got >= 0:
			_say("Sold%s for %d gold." % [(" the %s" % name_txt) if name_txt != "" else "", got])


# ---------------------------------------------------------------------------
# Refresh + close
# ---------------------------------------------------------------------------
func _on_character_changed() -> void:
	_refresh_all()


func _refresh_all() -> void:
	if _loadout:
		_loadout.refresh()
	_refresh_sale()
	_refresh_bag()
	_refresh_money()


func _refresh_money() -> void:
	var ch := _char()
	if _money_label and ch:
		_money_label.text = "Money: %d" % int(ch.money)


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
