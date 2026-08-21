class_name LoadoutSlots
extends Control

## ============================================================================
## LOADOUT SLOTS  —  shared equipped-gear display (class_name global)
## ============================================================================
## The character model surrounded by the nine equip slots. Used by BOTH the
## inventory screen (left panel) and the shop (middle-top panel) — because both
## instances read the SAME source of truth (Character.equipped_items) and both
## refresh on Character.`changed`, equipping in one screen updates the other. It
## is just a smaller copy in the shop.
##
## Interaction:
##   - DROP a bag ItemBox onto a slot it fits  -> equips it.
##   - RIGHT-CLICK an occupied slot            -> unequips it back to the bag.
##   - HOVER an occupied slot                  -> shows the shared ItemTooltip.
##
## The widget stretches to fill its parent; drop it into any panel and it lays
## out by fractions. class_name global — RESTART Godot once after adding it.
## ----------------------------------------------------------------------------

const SLOT_BG := Color(0.15, 0.15, 0.17)
const SLOT_BORDER := Color(0.30, 0.30, 0.34)
const SLOT_TEXT := Color(0.62, 0.62, 0.66)
const MODEL_BORDER := Color(0.28, 0.28, 0.32)

var _tooltip: ItemTooltip
var _slots: Array = []          # of Slot
var _model_rect: ColorRect
var _model_tex: TextureRect
var _model_name: Label
var _built := false


func _ready() -> void:
	_build()
	var ch := get_node_or_null("/root/Character")
	if ch and not ch.changed.is_connected(_on_changed):
		ch.changed.connect(_on_changed)
	refresh()


func _build() -> void:
	if _built:
		return
	_built = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_tooltip = ItemTooltip.new()
	add_child(_tooltip)

	# --- central model area ---
	var model := Control.new()
	model.anchor_left = 0.30
	model.anchor_top = 0.14
	model.anchor_right = 0.70
	model.anchor_bottom = 0.66
	model.offset_left = 0.0
	model.offset_top = 0.0
	model.offset_right = 0.0
	model.offset_bottom = 0.0
	model.mouse_filter = Control.MOUSE_FILTER_IGNORE
	model.clip_contents = true
	add_child(model)

	var frame := Panel.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fsb := StyleBoxFlat.new()
	fsb.bg_color = Color(0.10, 0.10, 0.12)
	fsb.set_corner_radius_all(4)
	fsb.set_border_width_all(1)
	fsb.border_color = MODEL_BORDER
	frame.add_theme_stylebox_override("panel", fsb)
	model.add_child(frame)

	_model_rect = ColorRect.new()
	_model_rect.anchor_left = 0.18
	_model_rect.anchor_top = 0.12
	_model_rect.anchor_right = 0.82
	_model_rect.anchor_bottom = 0.80
	_model_rect.offset_left = 0.0
	_model_rect.offset_top = 0.0
	_model_rect.offset_right = 0.0
	_model_rect.offset_bottom = 0.0
	_model_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	model.add_child(_model_rect)

	_model_tex = TextureRect.new()
	_model_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_model_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_model_tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_model_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_model_tex.visible = false
	model.add_child(_model_tex)

	_model_name = Label.new()
	_model_name.anchor_left = 0.0
	_model_name.anchor_top = 0.82
	_model_name.anchor_right = 1.0
	_model_name.anchor_bottom = 1.0
	_model_name.offset_left = 0.0
	_model_name.offset_top = 0.0
	_model_name.offset_right = 0.0
	_model_name.offset_bottom = 0.0
	_model_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_model_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_model_name.add_theme_font_size_override("font_size", 11)
	_model_name.add_theme_color_override("font_color", SLOT_TEXT)
	_model_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	model.add_child(_model_name)

	# --- the nine slots ---
	var lx0 := 0.05
	var lx1 := 0.28
	var rx0 := 0.72
	var rx1 := 0.95
	var rows := [[0.12, 0.27], [0.30, 0.45], [0.48, 0.63], [0.66, 0.81]]
	# left column
	_add_slot("head",        lx0, rows[0][0], lx1, rows[0][1])
	_add_slot("body",        lx0, rows[1][0], lx1, rows[1][1])
	_add_slot("legs",        lx0, rows[2][0], lx1, rows[2][1])
	_add_slot("gloves",      lx0, rows[3][0], lx1, rows[3][1])
	# right column
	_add_slot("feet",        rx0, rows[0][0], rx1, rows[0][1])
	_add_slot("weapon_main", rx0, rows[1][0], rx1, rows[1][1])
	_add_slot("weapon_off",  rx0, rows[2][0], rx1, rows[2][1])
	_add_slot("accessory_1", rx0, rows[3][0], rx1, rows[3][1])
	# ninth, centred below the model
	_add_slot("accessory_2", 0.36, 0.70, 0.64, 0.85)


func _add_slot(key: String, l: float, t: float, r: float, b: float) -> void:
	var s := Slot.new()
	s.anchor_left = l
	s.anchor_top = t
	s.anchor_right = r
	s.anchor_bottom = b
	s.offset_left = 0.0
	s.offset_top = 0.0
	s.offset_right = 0.0
	s.offset_bottom = 0.0
	add_child(s)
	s.configure(key, _tooltip)
	_slots.append(s)


func _on_changed() -> void:
	refresh()


func refresh() -> void:
	if not _built:
		return
	var ch := get_node_or_null("/root/Character")
	# model colour / portrait / name
	if ch and ch.has_method("get_body"):
		var body = ch.get_body()
		if body != null:
			if body.portrait != null:
				_model_tex.texture = body.portrait
				_model_tex.visible = true
				_model_rect.visible = false
			else:
				_model_rect.color = body.model_color()
				_model_rect.visible = true
				_model_tex.visible = false
		_model_name.text = str(ch.char_name)
	for s in _slots:
		s.refresh()


# ============================================================================
# One equip slot — a drop target that equips the dragged bag item.
# ============================================================================
class Slot:
	extends Panel

	var slot_key: String = ""
	var tooltip: ItemTooltip
	var _sb: StyleBoxFlat
	var _icon: TextureRect
	var _pink: ColorRect
	var _label: Label
	var _entry = null
	var _item = null

	func configure(key: String, tip: ItemTooltip) -> void:
		slot_key = key
		tooltip = tip
		mouse_filter = Control.MOUSE_FILTER_STOP
		_sb = StyleBoxFlat.new()
		_sb.bg_color = Color(0.15, 0.15, 0.17)          # SLOT_BG
		_sb.set_corner_radius_all(3)
		_sb.set_border_width_all(1)
		_sb.border_color = Color(0.30, 0.30, 0.34)      # SLOT_BORDER
		add_theme_stylebox_override("panel", _sb)

		_pink = ColorRect.new()
		_pink.color = Item.NO_ICON_COLOR
		_pink.anchor_left = 0.15
		_pink.anchor_top = 0.15
		_pink.anchor_right = 0.85
		_pink.anchor_bottom = 0.85
		_pink.offset_left = 0.0
		_pink.offset_top = 0.0
		_pink.offset_right = 0.0
		_pink.offset_bottom = 0.0
		_pink.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_pink.visible = false
		add_child(_pink)

		_icon = TextureRect.new()
		_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_icon.anchor_left = 0.08
		_icon.anchor_top = 0.08
		_icon.anchor_right = 0.92
		_icon.anchor_bottom = 0.92
		_icon.offset_left = 0.0
		_icon.offset_top = 0.0
		_icon.offset_right = 0.0
		_icon.offset_bottom = 0.0
		_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_icon.visible = false
		add_child(_icon)

		_label = Label.new()
		_label.text = Item.SLOT_LABELS.get(slot_key, slot_key)
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_label.add_theme_color_override("font_color", Color(0.62, 0.62, 0.66))   # SLOT_TEXT
		_label.add_theme_font_size_override("font_size", 9)
		_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_label)

		mouse_entered.connect(_on_hover)
		mouse_exited.connect(_on_unhover)
		gui_input.connect(_on_gui_input)

	func refresh() -> void:
		_entry = null
		_item = null
		var ch := get_node_or_null("/root/Character")
		if ch and ch.has_method("get_equipped_item"):
			_entry = ch.get_equipped_item(slot_key)
		if typeof(_entry) == TYPE_DICTIONARY:
			var db := get_node_or_null("/root/ItemDB")
			if db and db.has_method("get_item"):
				_item = db.get_item(str(_entry.get("id", "")))
		if _entry == null:
			_label.visible = true
			_icon.visible = false
			_pink.visible = false
			_sb.border_color = Color(0.30, 0.30, 0.34)   # SLOT_BORDER
			return
		_label.visible = false
		if _item != null and _item.icon != null:
			_icon.texture = _item.icon
			_icon.visible = true
			_pink.visible = false
		else:
			_icon.visible = false
			_pink.visible = true
		if _item != null:
			_sb.border_color = _item.rarity_color()
		else:
			_sb.border_color = Color(0.30, 0.30, 0.34)   # SLOT_BORDER

	func _on_hover() -> void:
		if tooltip == null or _entry == null:
			return
		if _item != null:
			tooltip.show_for(_item, get_global_rect())
		else:
			tooltip.show_for_dict(_entry, get_global_rect())

	func _on_unhover() -> void:
		if tooltip:
			tooltip.hide_tip()

	func _on_gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			if _entry != null:
				var ch := get_node_or_null("/root/Character")
				if ch and ch.has_method("unequip_item_slot"):
					if tooltip:
						tooltip.hide_tip()
					ch.unequip_item_slot(slot_key)

	func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
		if typeof(data) != TYPE_DICTIONARY:
			return false
		if str(data.get("source", "")) != "bag":
			return false
		var db := get_node_or_null("/root/ItemDB")
		if db == null or not db.has_method("get_item"):
			return false
		var item = db.get_item(str(data.get("id", "")))
		return item != null and item.fits_slot_key(slot_key)

	func _drop_data(_pos: Vector2, data: Variant) -> void:
		var ch := get_node_or_null("/root/Character")
		if ch and ch.has_method("equip_from_bag"):
			if tooltip:
				tooltip.hide_tip()
			ch.equip_from_bag(int(data.get("index", -1)), slot_key)
