extends Control
## END-OF-COMBAT (victory) screen — a shell-content panel (toolbar stays).
## Left 25%: party (portrait / level / XP bar). Center 25%: the SPOILS menu — the
## money/xp readout plus a GRID of the items rolled for this fight. Right 40%: the
## player's real INVENTORY grid (same ItemBox grid used on the inventory screen).
##
## SPOILS -> INVENTORY: items rolled for the fight sit in the spoils grid. The
## player DRAGS an item from the spoils grid onto the inventory grid to KEEP it;
## anything still sitting in the spoils grid when Proceed is pressed is LEFT
## BEHIND (never granted). A kept item can be dragged back to the spoils grid to
## drop it again before proceeding.

const SCREEN_BG := Color(0.24, 0.03, 0.03)   # dark red
const PANEL_BG  := Color(0.20, 0.20, 0.20)   # dark gray

const INV_COLS := 6           # inventory grid width (matches the inventory screen)
const INV_MIN_ROWS := 6
const SPOILS_COLS := 4        # narrower centre panel
const SPOILS_MIN_ROWS := 3

var _money := 0
var _xp := 0
var _items: Array = []
var _party: Array = []

## Live spoils/keep state. `_left` = items still in the spoils grid (left behind on
## Proceed); `_kept` = items dragged into the inventory (granted on Proceed).
var _left: Array = []
var _kept: Array = []
## The character's PRE-existing items, shown (read-only) in the inventory grid so
## the screen looks like the real inventory.
var _char_items: Array = []

var _tooltip: ItemTooltip
var _spoils_grid: GridContainer
var _inv_grid: GridContainer

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_money = int(BattleState.result_money)
	_xp = int(BattleState.result_xp)
	_items = BattleState.result_items.duplicate(true)
	_party = BattleState.result_party.duplicate()
	_left = _items.duplicate(true)
	_kept = []

	var ch := get_node_or_null("/root/Character")
	if ch and typeof(ch.get("items")) == TYPE_ARRAY:
		_char_items = (ch.items as Array).duplicate()

	var bg := ColorRect.new()
	bg.color = SCREEN_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# one tooltip shared by every grid box on this screen
	_tooltip = ItemTooltip.new()
	add_child(_tooltip)

	var left := _make_panel(0.025, 0.275)
	var center := _make_panel(0.30, 0.55)
	var right := _make_panel(0.575, 0.975)
	add_child(left)
	add_child(center)
	add_child(right)

	_build_party(left)
	_build_loot(center)
	_build_inventory(right)

func _make_panel(left_frac: float, right_frac: float) -> Panel:
	var p := Panel.new()
	p.anchor_left = left_frac
	p.anchor_right = right_frac
	p.anchor_top = 0.0
	p.anchor_bottom = 1.0
	p.offset_left = 0.0
	p.offset_right = 0.0
	p.offset_top = 0.0
	p.offset_bottom = 0.0
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.set_corner_radius_all(4)
	p.add_theme_stylebox_override("panel", sb)
	return p

func _title(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_color_override("font_color", Color(0.92, 0.92, 0.92))
	return l

func _vbox_in(panel: Panel, top_frac := 0.02, bottom_frac := 0.98) -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.anchor_left = 0.0
	margin.anchor_right = 1.0
	margin.anchor_top = top_frac
	margin.anchor_bottom = bottom_frac
	margin.offset_left = 0.0
	margin.offset_right = 0.0
	margin.offset_top = 0.0
	margin.offset_bottom = 0.0
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	margin.add_child(vb)
	return vb

# ---- left: party -------------------------------------------------------
func _build_party(panel: Panel) -> void:
	var vb := _vbox_in(panel)
	vb.add_child(_title("PARTY"))
	if _party.is_empty():
		var none := Label.new()
		none.text = "—"
		vb.add_child(none)
	for member in _party:
		vb.add_child(_party_card(member))

func _party_card(member: Dictionary) -> Control:
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.26, 0.26, 0.26)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	card.add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)
	var portrait := ColorRect.new()      # blank for now
	portrait.color = Color(0.12, 0.12, 0.12)
	portrait.custom_minimum_size = Vector2(48, 48)
	row.add_child(portrait)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 3)
	row.add_child(col)
	var nm := Label.new()
	nm.text = str(member.get("name", "?"))
	col.add_child(nm)
	var lv := Label.new()
	lv.text = "Level %d" % int(member.get("level", 1))
	lv.add_theme_font_size_override("font_size", 12)
	lv.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	col.add_child(lv)
	var xpbar := XPProgressBar.new()     # shared level-progress widget
	xpbar.custom_minimum_size = Vector2(0, 14)
	xpbar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(xpbar)
	# The player's continuous XP drives a real bar; other party members (no xp
	# data in the snapshot) show their current level at 0% for now.
	if bool(member.get("is_player", false)):
		var ch := get_node_or_null("/root/Character")
		if ch:
			# Rewards aren't applied until Proceed, so ch.xp is still the PRE-battle
			# total. Paint that pre-fight progress in solid WHITE and animate the xp
			# gained this fight as a rising FADED-GRAY overlay on top, so the size of
			# the gain reads at a glance (crossing a level if it earned enough).
			var cur_xp := int(ch.xp)
			xpbar.animate_gain(cur_xp, cur_xp + _xp, 2.0)
	else:
		xpbar.set_xp_level(0, int(member.get("level", 1)))
	return card

# ---- center: spoils (money/xp + item grid) + proceed -------------------
func _build_loot(panel: Panel) -> void:
	var vb := _vbox_in(panel, 0.02, 0.86)
	vb.add_child(_title("SPOILS"))
	var money_lbl := Label.new()
	money_lbl.text = "Money:  +%d" % _money
	money_lbl.add_theme_color_override("font_color", Color(1.0, 0.86, 0.35))
	vb.add_child(money_lbl)
	var xp_lbl := Label.new()
	xp_lbl.text = "Experience:  +%d" % _xp
	xp_lbl.add_theme_color_override("font_color", Color(0.6, 0.85, 1.0))
	vb.add_child(xp_lbl)

	vb.add_child(_title_small("Items — drag into your inventory to keep"))

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(scroll)
	_spoils_grid = GridContainer.new()
	_spoils_grid.columns = SPOILS_COLS
	_spoils_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_spoils_grid.add_theme_constant_override("h_separation", 6)
	_spoils_grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(_spoils_grid)
	_populate_spoils_grid()

	var proceed := Button.new()
	proceed.text = "Proceed"
	proceed.anchor_left = 0.1
	proceed.anchor_right = 0.9
	proceed.anchor_top = 0.9
	proceed.anchor_bottom = 0.98
	proceed.offset_left = 0.0
	proceed.offset_right = 0.0
	proceed.offset_top = 0.0
	proceed.offset_bottom = 0.0
	panel.add_child(proceed)
	proceed.pressed.connect(_on_proceed)

func _title_small(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	return l

# ---- right: inventory --------------------------------------------------
func _build_inventory(panel: Panel) -> void:
	var vb := _vbox_in(panel)
	vb.add_child(_title("INVENTORY"))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(scroll)
	_inv_grid = GridContainer.new()
	_inv_grid.columns = INV_COLS
	_inv_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inv_grid.add_theme_constant_override("h_separation", 6)
	_inv_grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(_inv_grid)
	_populate_inventory_grid()

# ---- grid population ---------------------------------------------------
## Spoils grid: the loot still up for grabs. Each filled box is draggable with
## source "spoils"; every box accepts a "kept" box dragged back out of inventory.
func _populate_spoils_grid() -> void:
	if _spoils_grid == null:
		return
	for c in _spoils_grid.get_children():
		c.queue_free()
	var rows: int = maxi(SPOILS_MIN_ROWS, int(ceil(float(_left.size()) / float(SPOILS_COLS))))
	var cells: int = rows * SPOILS_COLS
	for i in cells:
		var box := ItemBox.new()
		_spoils_grid.add_child(box)
		if i < _left.size():
			box.setup(i, _left[i], _tooltip, true, "spoils")
		else:
			box.setup(i, null, _tooltip, false, "spoils")
		box.enable_drop(["kept"])
		box.dropped.connect(_on_spoils_drop)

## Inventory grid: the character's existing items (read-only) followed by items
## kept from the spoils this fight (draggable back out). Every box accepts a
## "spoils" box dragged in.
func _populate_inventory_grid() -> void:
	if _inv_grid == null:
		return
	for c in _inv_grid.get_children():
		c.queue_free()
	var existing := _char_items.size()
	var total := existing + _kept.size()
	var rows: int = maxi(INV_MIN_ROWS, int(ceil(float(total) / float(INV_COLS))))
	var cells: int = rows * INV_COLS
	for i in cells:
		var box := ItemBox.new()
		_inv_grid.add_child(box)
		if i < existing:
			box.setup(i, _char_items[i], _tooltip, false, "inv")
		elif i < total:
			var j := i - existing
			box.setup(j, _kept[j], _tooltip, true, "kept")
		else:
			box.setup(i, null, _tooltip, false, "inv")
		box.enable_drop(["spoils"])
		box.dropped.connect(_on_inventory_drop)

func _rebuild_grids() -> void:
	_populate_spoils_grid()
	_populate_inventory_grid()

# ---- drag/drop handlers ------------------------------------------------
## A spoils box was dropped onto the inventory: KEEP that item.
func _on_inventory_drop(from_source: String, from_index: int, _item_id: String, _onto_index: int) -> void:
	if from_source != "spoils":
		return
	if from_index < 0 or from_index >= _left.size():
		return
	_kept.append(_left[from_index])
	_left.remove_at(from_index)
	_rebuild_grids()

## A kept box was dropped back onto the spoils: give it back up (leave behind).
func _on_spoils_drop(from_source: String, from_index: int, _item_id: String, _onto_index: int) -> void:
	if from_source != "kept":
		return
	if from_index < 0 or from_index >= _kept.size():
		return
	_left.append(_kept[from_index])
	_kept.remove_at(from_index)
	_rebuild_grids()

# ---- proceed -----------------------------------------------------------
func _on_proceed() -> void:
	var ch := get_node_or_null("/root/Character")
	# Only items the player dragged into the inventory are granted; whatever is
	# still sitting in the spoils grid (_left) is left behind.
	if ch and ch.has_method("gain_rewards"):
		ch.gain_rewards(_money, _xp, _kept)
	if BattleState.battle_id != "":
		GameManager.mark_completed(BattleState.battle_id)
	if BattleState.is_campaign and typeof(CampaignDB) != TYPE_NIL:
		# Advance campaign progression (fight counter + totals; marks the campaign
		# complete when its boss falls). The overworld handles fork / completion.
		CampaignDB.record_fight_win()
	BattleState.clear()
	BattleState.clear_result()
	GameManager.go_to_overworld()
