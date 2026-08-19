extends Control
## END-OF-COMBAT (victory) screen — a shell-content panel (toolbar stays).
## Left 25%: party (blank portrait / level / blank xp bar). Center 25%: loot
## rolled for this fight + a Proceed button. Right 40%: player inventory.
## 2.5% buffers at both edges and between panels.

const SCREEN_BG := Color(0.24, 0.03, 0.03)   # dark red
const PANEL_BG  := Color(0.20, 0.20, 0.20)   # dark gray

var _money := 0
var _xp := 0
var _items: Array = []
var _party: Array = []

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_money = int(BattleState.result_money)
	_xp = int(BattleState.result_xp)
	_items = BattleState.result_items.duplicate()
	_party = BattleState.result_party.duplicate()

	var bg := ColorRect.new()
	bg.color = SCREEN_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

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

func _item_name(it) -> String:
	if typeof(it) == TYPE_DICTIONARY:
		return str(it.get("name", it.get("id", "item")))
	return str(it)

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
			xpbar.set_xp_level(int(ch.xp), int(ch.level))
	else:
		xpbar.set_xp_level(0, int(member.get("level", 1)))
	return card

# ---- center: loot + proceed -------------------------------------------
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
	vb.add_child(_title_small("Items"))
	if _items.is_empty():
		var none := Label.new()
		none.text = "  (none)"
		vb.add_child(none)
	else:
		for it in _items:
			var il := Label.new()
			il.text = "  •  " + _item_name(it)
			vb.add_child(il)

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
	l.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	return l

# ---- right: inventory --------------------------------------------------
func _build_inventory(panel: Panel) -> void:
	var vb := _vbox_in(panel)
	vb.add_child(_title("INVENTORY"))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)
	var ch := get_node_or_null("/root/Character")
	var items: Array = []
	if ch and typeof(ch.get("items")) == TYPE_ARRAY:
		items = ch.items
	if items.is_empty():
		var none := Label.new()
		none.text = "(empty)"
		list.add_child(none)
	else:
		for it in items:
			var il := Label.new()
			il.text = "•  " + _item_name(it)
			list.add_child(il)

# ---- proceed -----------------------------------------------------------
func _on_proceed() -> void:
	var ch := get_node_or_null("/root/Character")
	if ch and ch.has_method("gain_rewards"):
		ch.gain_rewards(_money, _xp, _items)
	if BattleState.battle_id != "":
		GameManager.mark_completed(BattleState.battle_id)
	if BattleState.is_campaign and typeof(CampaignDB) != TYPE_NIL:
		# Advance campaign progression (fight counter + totals; marks the campaign
		# complete when its boss falls). The overworld handles fork / completion.
		CampaignDB.record_fight_win()
	BattleState.clear()
	BattleState.clear_result()
	GameManager.go_to_overworld()