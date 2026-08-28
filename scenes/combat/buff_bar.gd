class_name BuffBar
extends HBoxContainer

## ============================================================================
## BUFF BAR  —  the visible buff/debuff strip beside a health bar (class_name)
## ============================================================================
## A row of thin vertical "chips", one per VISIBLE buff/debuff on a unit. It sits
## next to the unit's health bar in the top band — combat places it on the RIGHT
## of the bar for the player party and on the LEFT for enemies. Chips stack side
## by side; hovering one pops a description card; each chip shows a turns-until-
## expiry counter at its bottom-right (an "inf" for permanent effects) and a small
## "xN" stack badge at its top-left when stacked.
##
## The hover card is now the SHARED HoverPanel (same core the ability tooltip
## uses), so buff descriptions get the same look, placement, and element-name
## KEYWORD COLOURING as everything else. Chip drawing is unchanged.
##
## Chip colour = the effect's element colour (ElementColors) when it has an
## element tag, otherwise green for a buff / red for a debuff.
##
## class_name global — RESTART Godot once after adding this script.
## ----------------------------------------------------------------------------

enum { SIDE_RIGHT, SIDE_LEFT }

const CHIP_W := 24.0   # rev21: twice the old 12 (wider chips = twice-as-wide strip)
const CHIP_H := 39.0   # rev21: matches BattleHealthBar.DUO_HEIGHT (HP+Spirit stack)
const CHIP_SEP := 3
const TIP_WIDTH := 210.0

const BUFF_COLOR := Color(0.28, 0.70, 0.34)     # green
const DEBUFF_COLOR := Color(0.78, 0.28, 0.30)   # red
const BORDER_COLOR := Color(0, 0, 0, 0.85)
const HOVER_BORDER := Color(1, 1, 1, 0.9)
const COUNTER_COLOR := Color(1, 1, 1)
const COUNTER_OUTLINE := Color(0, 0, 0)

# Row colours for the hover card (title reads like an ability name).
const TITLE_BG := Color(0.80, 0.80, 0.82)
const TITLE_TX := Color(0.08, 0.08, 0.10)
const META_TX := Color(1.0, 0.86, 0.35)         # gold meta line

var _body: CharacterBase = null
var _side: int = SIDE_RIGHT
var _tooltip: HoverPanel = null


func setup(body: CharacterBase, side: int) -> void:
	_body = body
	_side = side
	add_theme_constant_override("separation", CHIP_SEP)
	# Enemy strip grows toward the health bar (which is on its right), so hug the
	# right edge; the player strip hugs the left edge next to its bar.
	alignment = BoxContainer.ALIGNMENT_END if side == SIDE_LEFT else BoxContainer.ALIGNMENT_BEGIN
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(0, CHIP_H)
	# Match the health bar: sit at CHIP_H and centre vertically in the top band
	# rather than stretching to fill it, so the strip lines up with the bars.
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
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
	_tooltip = HoverPanel.new()
	_tooltip.content_width = TIP_WIDTH
	add_child(_tooltip)


## Pop the shared hover card for `entry`, anchored to the chip's global rect.
func show_tip(entry: Dictionary, anchor_global: Rect2) -> void:
	_ensure_tooltip()
	var desc := str(entry.get("desc", ""))
	var rows := [
		{"text": str(entry.get("source", "Buff")), "bg": TITLE_BG, "fg": TITLE_TX, "stage": 0},
		# meta is rich so an element tag ("Fire", ...) colours to match the chip.
		{"text": _meta_line(entry), "bg": HoverPanel.META_BG, "fg": META_TX, "stage": 0, "rich": true},
		{"text": desc, "bg": HoverPanel.DESC_BG, "fg": HoverPanel.DESC_TX,
			"stage": 0, "wrap": true, "rich": true, "visible": desc != ""},
	]
	# instant reveal (reveal_delay 0); key on the id so a re-hover refreshes in place
	_tooltip.show_rows(rows, anchor_global, 0.0, "buff:" + str(entry.get("id", "")))


func hide_tip() -> void:
	if _tooltip and is_instance_valid(_tooltip):
		_tooltip.hide_panel()


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
