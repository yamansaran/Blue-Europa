class_name ItemBox
extends Panel

## ============================================================================
## ITEM BOX  —  one square cell in an item grid (class_name global)
## ============================================================================
## Shows an item's square image asset, or a PINK SQUARE when no asset is found.
## An empty cell (no item) is just a dark box. Used by both the inventory grid
## and the shop's "for sale" grid. Hovering pops the shared ItemTooltip; the box
## can be selected (highlight) and, in bag mode, dragged onto an equip slot.
##
## USAGE (host owns one shared ItemTooltip and passes it in):
##   var box := ItemBox.new()
##   grid.add_child(box)
##   box.setup(i, bag_entry_or_null, shared_tooltip, true)   # draggable bag cell
##   box.pressed.connect(_on_box_pressed)                     # emits its index
## class_name global — RESTART Godot once after adding this file.
## ----------------------------------------------------------------------------

signal pressed(index: int)

const BOX_SIZE := 56.0
const EMPTY_BG := Color(0.13, 0.13, 0.16)
const FILLED_BG := Color(0.18, 0.18, 0.22)
const SEL_BORDER := Color(1.0, 0.90, 0.40)

## What a drag from this box announces as its source (equip slots check this).
var index: int = -1
var item_id: String = ""
var draggable: bool = false
var drag_source: String = "bag"

var _tooltip: ItemTooltip
var _item: Item = null
var _bag_entry = null
var _sb: StyleBoxFlat
var _icon: TextureRect
var _pink: ColorRect
var _selected := false
var _built := false


func setup(p_index: int, p_bag_entry, p_tooltip: ItemTooltip, p_draggable := false, p_drag_source := "bag") -> void:
	index = p_index
	_bag_entry = p_bag_entry
	_tooltip = p_tooltip
	draggable = p_draggable
	drag_source = p_drag_source
	_build()
	_resolve()
	_refresh()


func _build() -> void:
	if _built:
		return
	_built = true
	custom_minimum_size = Vector2(BOX_SIZE, BOX_SIZE)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_sb = StyleBoxFlat.new()
	_sb.set_corner_radius_all(4)
	_sb.set_border_width_all(1)
	add_theme_stylebox_override("panel", _sb)

	_pink = ColorRect.new()
	_pink.color = Item.NO_ICON_COLOR
	_pink.anchor_left = 0.14
	_pink.anchor_top = 0.14
	_pink.anchor_right = 0.86
	_pink.anchor_bottom = 0.86
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

	mouse_entered.connect(_on_hover)
	mouse_exited.connect(_on_unhover)
	gui_input.connect(_on_gui_input)


func _resolve() -> void:
	_item = null
	item_id = ""
	if typeof(_bag_entry) == TYPE_DICTIONARY:
		item_id = str(_bag_entry.get("id", ""))
		var db := get_node_or_null("/root/ItemDB")
		if db and db.has_method("get_item"):
			_item = db.get_item(item_id)


func _refresh() -> void:
	var filled := _bag_entry != null
	if not filled:
		_sb.bg_color = EMPTY_BG
		_sb.border_color = Color(0.22, 0.22, 0.26)
		_icon.visible = false
		_pink.visible = false
		return
	_sb.bg_color = FILLED_BG
	if _item != null and _item.icon != null:
		_icon.texture = _item.icon
		_icon.visible = true
		_pink.visible = false
	else:
		# item present but no asset found -> pink square
		_icon.visible = false
		_pink.visible = true
	_apply_border()


func _apply_border() -> void:
	if _selected:
		_sb.set_border_width_all(2)
		_sb.border_color = SEL_BORDER
	else:
		_sb.set_border_width_all(1)
		if _item != null:
			_sb.border_color = _item.rarity_color()
		else:
			_sb.border_color = Color(0.35, 0.35, 0.40)


func set_selected(v: bool) -> void:
	_selected = v
	if _built and _bag_entry != null:
		_apply_border()


func _on_hover() -> void:
	if _tooltip == null or _bag_entry == null:
		return
	if _item != null:
		_tooltip.show_for(_item, get_global_rect())
	else:
		_tooltip.show_for_dict(_bag_entry, get_global_rect())


func _on_unhover() -> void:
	if _tooltip:
		_tooltip.hide_tip()


func _on_gui_input(event: InputEvent) -> void:
	if _bag_entry == null:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pressed.emit(index)


func _get_drag_data(_at_position: Vector2) -> Variant:
	if not draggable or _bag_entry == null:
		return null
	if _tooltip:
		_tooltip.hide_tip()
	var preview := Panel.new()
	preview.custom_minimum_size = Vector2(BOX_SIZE, BOX_SIZE)
	preview.size = Vector2(BOX_SIZE, BOX_SIZE)
	var psb := StyleBoxFlat.new()
	psb.bg_color = FILLED_BG
	psb.set_corner_radius_all(4)
	preview.add_theme_stylebox_override("panel", psb)
	if _item != null and _item.icon != null:
		var tr := TextureRect.new()
		tr.texture = _item.icon
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		preview.add_child(tr)
	else:
		var cr := ColorRect.new()
		cr.color = Item.NO_ICON_COLOR
		cr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		preview.add_child(cr)
	set_drag_preview(preview)
	return {"source": drag_source, "index": index, "id": item_id}
