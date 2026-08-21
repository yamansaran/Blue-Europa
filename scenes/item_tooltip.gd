class_name ItemTooltip
extends VBoxContainer

## ============================================================================
## ITEM TOOLTIP  —  shared 3-panel item hover card (class_name global)
## ============================================================================
## The item counterpart to AbilityTooltip. Three flush-stacked panels, plus an
## optional italic flavour footer:
##   1. NAME   — tinted by rarity, one line.
##   2. TYPE   — "Lv:X   <type>".
##   3. BODY   — stat lines when the item is equippable, otherwise the
##               description.
##   (4.) FLAVOUR — italic, shown only when the item has flavour text.
##
## Per the inventory spec the panels appear INSTANTLY together (no fade delay).
## `reveal_delay` is kept as a knob (default 0) in case a future host wants the
## staggered ability-style reveal.
##
## USAGE (each host owns ONE, shared across its boxes/slots):
##   var tip := ItemTooltip.new()
##   add_child(tip)
##   tip.show_for(item, some_global_rect)     # `item` is an Item or null
##   tip.show_for_dict({"name": "?"}, rect)    # fallback when the id is unknown
##   tip.hide_tip()
## top_level = true so it draws over everything; position is in GLOBAL coords.
## class_name global — RESTART Godot once after adding this file.
## ----------------------------------------------------------------------------

const TIP_WIDTH := 210.0
const TIP_FADE := 0.18

const TYPE_BG := Color(0.30, 0.30, 0.34)
const BODY_BG := Color(0.03, 0.03, 0.05)
const FLAV_BG := Color(0.03, 0.03, 0.05)
const NAME_TX := Color(0.08, 0.08, 0.10)
const TYPE_TX := Color(0.90, 0.90, 0.94)
const BODY_TX := Color(0.90, 0.90, 0.92)
const STAT_TX := Color(0.66, 0.90, 0.66)      # greenish for stat gains
const FLAV_TX := Color(0.72, 0.72, 0.78)

## Seconds to wait before panels 2+ appear. 0 = instant (inventory default).
var reveal_delay: float = 0.0

var _name_panel: PanelContainer
var _type_panel: PanelContainer
var _body_panel: PanelContainer
var _flav_panel: PanelContainer
var _name_lbl: Label
var _type_lbl: Label
var _body_lbl: RichTextLabel
var _flav_lbl: RichTextLabel
var _name_sb: StyleBoxFlat
var _timer: Timer
var _tween: Tween
var _key: String = ""
var _built := false


func _ready() -> void:
	_ensure_built()


func _ensure_built() -> void:
	if _built:
		return
	_built = true
	top_level = true
	z_index = 1000
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 0)
	visible = false

	_name_sb = StyleBoxFlat.new()
	_name_sb.bg_color = Color(0.78, 0.78, 0.80)
	_name_sb.content_margin_left = 6
	_name_sb.content_margin_right = 6
	_name_sb.content_margin_top = 3
	_name_sb.content_margin_bottom = 3
	_name_panel = PanelContainer.new()
	_name_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_panel.add_theme_stylebox_override("panel", _name_sb)
	_name_lbl = _plain_label(NAME_TX)
	_name_panel.add_child(_name_lbl)
	add_child(_name_panel)

	_type_panel = _panel(TYPE_BG)
	_type_lbl = _plain_label(TYPE_TX)
	_type_panel.add_child(_type_lbl)
	add_child(_type_panel)

	_body_panel = _panel(BODY_BG)
	_body_lbl = _rich_label(BODY_TX)
	_body_panel.add_child(_body_lbl)
	add_child(_body_panel)

	_flav_panel = _panel(FLAV_BG)
	_flav_lbl = _rich_label(FLAV_TX)
	_flav_panel.add_child(_flav_lbl)
	add_child(_flav_panel)

	_timer = Timer.new()
	_timer.one_shot = true
	_timer.timeout.connect(_reveal_details)
	add_child(_timer)


func _panel(col: Color) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	p.add_theme_stylebox_override("panel", sb)
	return p


func _plain_label(col: Color) -> Label:
	var l := Label.new()
	l.add_theme_color_override("font_color", col)
	l.add_theme_font_size_override("font_size", 12)
	l.custom_minimum_size = Vector2(TIP_WIDTH, 0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _rich_label(col: Color) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.add_theme_color_override("default_color", col)
	r.add_theme_font_size_override("normal_font_size", 12)
	r.add_theme_font_size_override("italics_font_size", 12)
	r.custom_minimum_size = Vector2(TIP_WIDTH, 0)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## Show the card for an Item. Pass null to hide.
func show_for(item: Item, anchor_global: Rect2) -> void:
	_ensure_built()
	if item == null:
		hide_tip()
		return
	var key := "item:" + String(item.id)
	if key == _key and visible:
		_place(anchor_global)
		return
	_key = key

	_name_sb.bg_color = item.rarity_color()
	_name_lbl.text = item.display_name
	_type_lbl.text = item.type_line()

	if item.equippable:
		var lines := item.stat_lines()
		if lines.is_empty():
			_body_lbl.text = "[color=#9a9aa2]No stat bonuses.[/color]"
		else:
			_body_lbl.text = "[color=#a8e6a8]" + "\n".join(lines) + "[/color]"
	else:
		_body_lbl.text = item.description if item.description != "" else "—"

	_set_flavor(item.flavor)
	_present(anchor_global)


## Fallback card when the id has no Item in ItemDB — shows just the name.
func show_for_dict(bag_entry: Dictionary, anchor_global: Rect2) -> void:
	_ensure_built()
	var nm := str(bag_entry.get("name", bag_entry.get("id", "Item")))
	var key := "dict:" + nm
	if key == _key and visible:
		_place(anchor_global)
		return
	_key = key
	_name_sb.bg_color = Item.RARITY_COLORS[Item.Rarity.COMMON]
	_name_lbl.text = nm
	_type_lbl.text = "Lv:?   Unknown"
	_body_lbl.text = "—"
	_set_flavor("")
	_present(anchor_global)


func _set_flavor(flavor: String) -> void:
	if flavor.strip_edges() == "":
		_flav_panel.visible = false
		_flav_lbl.text = ""
	else:
		_flav_panel.visible = true
		_flav_lbl.text = "[i]" + flavor + "[/i]"


func _present(anchor_global: Rect2) -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	visible = true
	if reveal_delay <= 0.0:
		# instant: everything visible at full opacity, no timer
		_type_panel.visible = true
		_body_panel.visible = true
		_type_panel.modulate.a = 1.0
		_body_panel.modulate.a = 1.0
		_flav_panel.modulate.a = 1.0
		reset_size()
		_place(anchor_global)
	else:
		# staggered (ability-style): name now, the rest after the delay
		_type_panel.visible = false
		_body_panel.visible = false
		var had_flavor := _flav_panel.visible
		_flav_panel.visible = false
		_flav_panel.set_meta("wanted", had_flavor)
		reset_size()
		_place(anchor_global)
		_timer.wait_time = reveal_delay
		_timer.stop()
		_timer.start()


func hide_tip() -> void:
	_key = ""
	if _timer:
		_timer.stop()
	if _tween and _tween.is_valid():
		_tween.kill()
	visible = false


func _reveal_details() -> void:
	if not visible:
		return
	_type_panel.visible = true
	_body_panel.visible = true
	_flav_panel.visible = bool(_flav_panel.get_meta("wanted", false))
	_type_panel.modulate.a = 0.0
	_body_panel.modulate.a = 0.0
	_flav_panel.modulate.a = 0.0
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(_type_panel, "modulate:a", 1.0, TIP_FADE)
	_tween.tween_property(_body_panel, "modulate:a", 1.0, TIP_FADE)
	_tween.tween_property(_flav_panel, "modulate:a", 1.0, TIP_FADE)


func _place(anchor: Rect2) -> void:
	var w := TIP_WIDTH + 16.0
	var vp := get_viewport_rect().size
	var x := anchor.end.x + 8.0
	if x + w > vp.x:
		x = anchor.position.x - w - 8.0
	x = clampf(x, 4.0, maxf(4.0, vp.x - w - 4.0))
	var y := clampf(anchor.position.y, 4.0, maxf(4.0, vp.y - size.y - 4.0))
	global_position = Vector2(x, y)
