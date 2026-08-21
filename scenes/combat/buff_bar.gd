class_name BuffBar
extends HBoxContainer

## ============================================================================
## BUFF BAR  —  the visible buff/debuff strip beside a health bar (class_name)
## ============================================================================
## A row of thin vertical "chips", one per VISIBLE buff/debuff on a unit. It sits
## next to the unit's health bar in the top band — combat places it on the RIGHT
## of the bar for the player party and on the LEFT for enemies. Chips stack side
## by side; hovering one fades in a small description panel; each chip shows a
## turns-until-expiry counter at its bottom-right (an "inf" for permanent effects)
## and a small "xN" stack badge at its top-left when stacked.
##
## Chip colour = the effect's element colour (ElementColors) when it has an
## element tag, otherwise green for a buff / red for a debuff.
##
## Rebuild it with refresh() whenever a unit's buffs change (combat calls this via
## BattleCharacter.refresh_buffs()).
##
## class_name global — RESTART Godot once after adding this script.
## ----------------------------------------------------------------------------

enum { SIDE_RIGHT, SIDE_LEFT }

const CHIP_W := 12.0
const CHIP_H := 34.0
const CHIP_SEP := 3

const BUFF_COLOR := Color(0.28, 0.70, 0.34)     # green
const DEBUFF_COLOR := Color(0.78, 0.28, 0.30)   # red
const BORDER_COLOR := Color(0, 0, 0, 0.85)
const HOVER_BORDER := Color(1, 1, 1, 0.9)
const COUNTER_COLOR := Color(1, 1, 1)
const COUNTER_OUTLINE := Color(0, 0, 0)

var _body: CharacterBase = null
var _side: int = SIDE_RIGHT
var _tooltip: PanelContainer = null
var _tip_title: Label = null
var _tip_meta: Label = null
var _tip_desc: Label = null


func setup(body: CharacterBase, side: int) -> void:
	_body = body
	_side = side
	add_theme_constant_override("separation", CHIP_SEP)
	# Enemy strip grows toward the health bar (which is on its right), so hug the
	# right edge; the player strip hugs the left edge next to its bar.
	alignment = BoxContainer.ALIGNMENT_END if side == SIDE_LEFT else BoxContainer.ALIGNMENT_BEGIN
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(0, CHIP_H)
	refresh()


func refresh() -> void:
	# clear existing chips
	for c in get_children():
		if c is _Chip:
			c.queue_free()
	if _body == null:
		return
	var entries := CombatBuffs.visible_entries(_body)
	for e in entries:
		var chip := _Chip.new()
		chip.setup(self, e)
		add_child(chip)
	# keep the tooltip (if any) drawn above chips
	if _tooltip and is_instance_valid(_tooltip):
		_tooltip.move_to_front()


# ------------------------------------------------------------------ tooltip
func _ensure_tooltip() -> void:
	if _tooltip != null and is_instance_valid(_tooltip):
		return
	_tooltip = PanelContainer.new()
	_tooltip.set_as_top_level(true)          # position in canvas space, no clipping
	_tooltip.z_index = 200
	_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip.visible = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.08, 0.09, 0.97)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.8, 0.75, 0.55, 0.9)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(8)
	_tooltip.add_theme_stylebox_override("panel", sb)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	vb.custom_minimum_size = Vector2(200, 0)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip.add_child(vb)

	_tip_title = Label.new()
	_tip_title.add_theme_font_size_override("font_size", 15)
	_tip_title.add_theme_color_override("font_color", Color(1, 1, 1))
	vb.add_child(_tip_title)

	_tip_meta = Label.new()
	_tip_meta.add_theme_font_size_override("font_size", 12)
	_tip_meta.add_theme_color_override("font_color", Color(1.0, 0.86, 0.35))
	vb.add_child(_tip_meta)

	_tip_desc = Label.new()
	_tip_desc.add_theme_font_size_override("font_size", 12)
	_tip_desc.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	_tip_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip_desc.custom_minimum_size = Vector2(200, 0)
	vb.add_child(_tip_desc)

	add_child(_tooltip)


func show_tip(entry: Dictionary, anchor_global: Rect2) -> void:
	_ensure_tooltip()
	_tip_title.text = str(entry.get("source", "Buff"))
	_tip_meta.text = _meta_line(entry)
	_tip_desc.text = str(entry.get("desc", ""))
	_tip_desc.visible = _tip_desc.text != ""
	_tooltip.reset_size()
	# place below the chip; nudge left/up to stay on screen
	var pos := anchor_global.position + Vector2(0, anchor_global.size.y + 4)
	var vp := get_viewport_rect().size
	var tip_size := _tooltip.size
	pos.x = clampf(pos.x, 4.0, maxf(4.0, vp.x - tip_size.x - 4.0))
	if pos.y + tip_size.y > vp.y - 4.0:
		pos.y = anchor_global.position.y - tip_size.y - 4.0
	_tooltip.global_position = pos
	_tooltip.visible = true
	_tooltip.modulate.a = 0.0
	var t := create_tween()
	t.tween_property(_tooltip, "modulate:a", 1.0, 0.15)


func hide_tip() -> void:
	if _tooltip and is_instance_valid(_tooltip):
		_tooltip.visible = false


func _meta_line(entry: Dictionary) -> String:
	var parts := []
	var dur := int(entry.get("duration", -1))
	parts.append("Permanent" if dur < 0 else "%d turn%s left" % [dur, "" if dur == 1 else "s"])
	var st := int(entry.get("stacks", 1))
	if st > 1:
		parts.append("x%d stacks" % st)
	var elem := str(entry.get("element", ""))
	if elem != "":
		parts.append(elem.capitalize())
	parts.append("Debuff" if Buff.is_debuff(entry) else "Buff")
	return "  ·  ".join(parts)


static func _counter_text(entry: Dictionary) -> String:
	var dur := int(entry.get("duration", -1))
	return "inf" if dur < 0 else str(dur)


static func chip_color(entry: Dictionary) -> Color:
	var elem := str(entry.get("element", ""))
	if elem != "":
		return ElementColors.color(elem)
	return DEBUFF_COLOR if Buff.is_debuff(entry) else BUFF_COLOR


# ============================================================================
# One chip: a thin vertical rectangle for a single buff/debuff.
# ============================================================================
class _Chip extends Control:
	var _bar: BuffBar = null
	var _entry: Dictionary = {}
	var _hovered := false

	func setup(bar: BuffBar, entry: Dictionary) -> void:
		_bar = bar
		_entry = entry
		custom_minimum_size = Vector2(BuffBar.CHIP_W, BuffBar.CHIP_H)
		mouse_filter = Control.MOUSE_FILTER_STOP
		tooltip_text = ""   # we draw our own panel

	func _ready() -> void:
		mouse_entered.connect(_on_enter)
		mouse_exited.connect(_on_exit)

	func _on_enter() -> void:
		_hovered = true
		queue_redraw()
		if _bar:
			_bar.show_tip(_entry, get_global_rect())

	func _on_exit() -> void:
		_hovered = false
		queue_redraw()
		if _bar:
			_bar.hide_tip()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, BuffBar.chip_color(_entry), true)
		# a top cap in white/black to distinguish buff vs debuff at a glance
		var cap := Color(1, 1, 1, 0.55) if Buff.is_buff(_entry) else Color(0, 0, 0, 0.55)
		draw_rect(Rect2(Vector2.ZERO, Vector2(size.x, 3)), cap, true)
		# border
		var border := BuffBar.HOVER_BORDER if _hovered else BuffBar.BORDER_COLOR
		draw_rect(r, border, false, 1.5)

		var font := get_theme_default_font()
		if font == null:
			return
		# turns-until-expiry counter, bottom-right
		var ctext := BuffBar._counter_text(_entry)
		var cfs := 9
		var cw := font.get_string_size(ctext, HORIZONTAL_ALIGNMENT_LEFT, -1, cfs)
		var cpos := Vector2(size.x - cw.x - 1.0, size.y - 1.5)
		# faux outline for readability over any chip colour
		for off in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
			draw_string(font, cpos + off, ctext, HORIZONTAL_ALIGNMENT_LEFT, -1, cfs, BuffBar.COUNTER_OUTLINE)
		draw_string(font, cpos, ctext, HORIZONTAL_ALIGNMENT_LEFT, -1, cfs, BuffBar.COUNTER_COLOR)
		# stack badge, top-left
		var st := int(_entry.get("stacks", 1))
		if st > 1:
			var stext := "x%d" % st
			var sfs := 8
			var spos := Vector2(1.0, float(sfs) + 3.0)
			for off in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
				draw_string(font, spos + off, stext, HORIZONTAL_ALIGNMENT_LEFT, -1, sfs, BuffBar.COUNTER_OUTLINE)
			draw_string(font, spos, stext, HORIZONTAL_ALIGNMENT_LEFT, -1, sfs, BuffBar.COUNTER_COLOR)
