class_name BuffBar
extends HBoxContainer

## ============================================================================
## BUFF BAR  —  the visible buff/debuff strip beside a health bar (class_name)
## ============================================================================
## A row of icons, one per VISIBLE buff/debuff on a unit. TWO placements use it:
##   - the TOP PANEL, beside an IMPORTANT unit's big health bar (right of the party's,
##     left of an enemy boss's);
##   - COMPACT, centred under EVERY unit's overhead bars (UnitOverhead).
## Hovering an icon pops a description card; each icon shows a turns-until-expiry
## counter at its bottom-right (NOTHING for a permanent effect) and an "xN" stack
## badge at its top-left when stacked.
##
## HOW AN ICON LOOKS IS NOT DECIDED HERE. Shape, colour, rune, shading and counters
## all come from the BUFF ICON ENGINE in scenes/ui/buff_icons/ (BuffIconPainter +
## BuffIconStyle + BuffIconCatalog + RuneGlyphs), so the icons can be restyled
## without touching this file.
##
## The hover card is now the SHARED HoverPanel (same core the ability tooltip
## uses), so buff descriptions get the same look, placement, and element-name
## KEYWORD COLOURING as everything else.
##
## class_name global — RESTART Godot once after adding this script.
## ----------------------------------------------------------------------------

enum { SIDE_RIGHT, SIDE_LEFT, SIDE_CENTER }

## Chip geometry now comes from the BUFF ICON ENGINE's style (scenes/ui/buff_icons/):
## BuffIconStyle.panel_icon_size for the top panel, overhead_icon_size under a unit.
## These two constants remain only as the fallback / the top panel's row height.
const CHIP_W := 24.0
const CHIP_H := 39.0
const CHIP_SEP := 3
const COMPACT_SEP := 2
const TIP_WIDTH := 210.0

## Kept for callers that still colour things by buff kind; icons themselves are now
## coloured by BuffIconCatalog.
const BUFF_COLOR := Color(0.28, 0.70, 0.34)     # green
const DEBUFF_COLOR := Color(0.78, 0.28, 0.30)   # red
const EMPOWER_COLOR := Color(0.76, 0.55, 0.98)

# Row colours for the hover card (title reads like an ability name).
const TITLE_BG := Color(0.80, 0.80, 0.82)
const TITLE_TX := Color(0.08, 0.08, 0.10)
const META_TX := Color(1.0, 0.86, 0.35)         # gold meta line

var _body: CharacterBase = null
var _side: int = SIDE_RIGHT
var _tooltip: HoverPanel = null
## COMPACT = the small strip under a unit's overhead bars (smaller icons, no counters
## on icons too small to read, and at most `max_icons` shown with a "+N" overflow).
var compact: bool = false
var max_icons: int = 0          # 0 = unlimited
## GROUP BY TYPE (FUTURE_PLANS §6): one chip per buff/debuff ID however many
## instances stand. DISPLAY ONLY — the instances stay separate in the data. Used by
## the field strip (UnitOverhead); the top panel keeps one chip per instance.
var group_by_id: bool = false
var _overflow_label: Label = null


func setup(body: CharacterBase, side: int, p_compact: bool = false, p_max_icons: int = 0) -> void:
	_body = body
	_side = side
	compact = p_compact
	max_icons = p_max_icons
	add_theme_constant_override("separation", COMPACT_SEP if compact else CHIP_SEP)
	match side:
		SIDE_LEFT:
			alignment = BoxContainer.ALIGNMENT_END
		SIDE_CENTER:
			alignment = BoxContainer.ALIGNMENT_CENTER
		_:
			alignment = BoxContainer.ALIGNMENT_BEGIN
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(0, icon_size().y)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	refresh()


func icon_size() -> Vector2:
	var st := BuffIconPainter.style()
	return st.overhead_icon_size if compact else st.panel_icon_size


## COALESCED (perf, 2026-09-25): combat calls refresh_buffs several times inside one
## action (a rider, the apply, the bar refresh...), and each call used to free and
## rebuild every chip. Now any number of calls in a frame rebuild ONCE, at the end of
## that frame (before it is drawn), so nothing visible changes.
var _refresh_pending := false

func refresh() -> void:
	if _refresh_pending:
		return
	_refresh_pending = true
	_rebuild.call_deferred()


func _rebuild() -> void:
	_refresh_pending = false
	# clear existing chips
	for c in get_children():
		if c is _Chip:
			remove_child(c)
			c.queue_free()
	if _overflow_label and is_instance_valid(_overflow_label):
		_overflow_label.queue_free()
		_overflow_label = null
	if _body == null:
		return
	var entries := CombatBuffs.visible_entries(_body)
	if group_by_id:
		entries = group_entries(entries)
	var shown := entries.size()
	if max_icons > 0 and entries.size() > max_icons:
		shown = max_icons - 1
	for i in shown:
		var chip := _Chip.new()
		chip.setup(self, entries[i])
		add_child(chip)
	if shown < entries.size():
		_overflow_label = Label.new()
		_overflow_label.text = "+%d" % (entries.size() - shown)
		_overflow_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_overflow_label.add_theme_font_size_override("font_size", 10)
		_overflow_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		_overflow_label.add_theme_constant_override("outline_size", 3)
		add_child(_overflow_label)
	# keep the tooltip (if any) drawn above chips
	if _tooltip and is_instance_valid(_tooltip):
		_tooltip.move_to_front()


## Collapse instances sharing an `id` into ONE representative entry (first-seen
## order). A group of one is the real entry, untouched (real turn count, real badge).
## A group of N is a shallow copy of the first instance carrying `_group_count` N and
## `_group_max_turns` (the longest remaining, -1 if any is permanent); its counter
## reads "..." (BuffIconPainter.counter_text) and it drops the potency badge, since
## the instances may disagree. Never written back to the body.
static func group_entries(entries: Array) -> Array:
	var order: Array = []
	var groups := {}
	for e in entries:
		var id := str(e.get("id", ""))
		if not groups.has(id):
			groups[id] = []
			order.append(id)
		groups[id].append(e)
	var out: Array = []
	for id in order:
		var g: Array = groups[id]
		if g.size() == 1:
			out.append(g[0])
			continue
		var rep: Dictionary = (g[0] as Dictionary).duplicate(false)
		var longest := 0
		for inst in g:
			var d := int(inst.get("duration", -1))
			if d < 0:
				longest = -1
				break
			longest = maxi(longest, d)
		rep["_group_count"] = g.size()
		rep["_group_max_turns"] = longest
		rep["potency_applied"] = 1.0
		rep["ramp"] = 1.0
		rep["duration_bonus"] = 0
		out.append(rep)
	return out

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
	# Buff.describe, not the raw `desc`: an entry empowered by its caster's Disdain
	# re-renders its description from its LIVE numbers, so the card states what THIS
	# instance actually does rather than the base figure it was authored with.
	var desc := Buff.describe(entry)
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
	var n := int(entry.get("_group_count", 1))
	if n > 1:
		# A grouped field chip: the count and the longest remaining. The per-instance
		# detail lives in the loaded-unit top panel (FUTURE_PLANS §7).
		parts.append("%d instances" % n)
		var lt := int(entry.get("_group_max_turns", -1))
		parts.append("Permanent" if lt < 0 else "longest %d turn%s" % [lt, "" if lt == 1 else "s"])
		var el := str(entry.get("element", ""))
		if el != "":
			parts.append(el.capitalize())
		parts.append("Debuff" if Buff.is_debuff(entry) else "Buff")
		return "  ·  ".join(parts)
	var dur := int(entry.get("duration", -1))
	parts.append("Permanent" if dur < 0 else "%d turn%s left" % [dur, "" if dur == 1 else "s"])
	var st := int(entry.get("stacks", 1))
	if st > 1:
		parts.append("x%d stacks" % st)
	# A ramping entry states its current level in words, since the chip's badge is the
	# only other place it shows and a number alone does not say which way it is going.
	var rmp := Buff.ramp(entry)
	if not is_equal_approx(rmp, 1.0):
		var dir := "fading" if Buff.potency_per_turn(entry) < 0.0 else "building"
		parts.append("%s — at %d%% strength" % [dir, int(round(rmp * 100.0))])
	# What the caster's Disdain bought, spelled out: the potency multiplier baked into
	# this entry and any extra turns its duration roll won. Absent on an ordinary
	# debuff, so unempowered meta lines are unchanged.
	var pot := float(entry.get("potency_applied", 1.0))
	if pot > 1.0:
		parts.append("Empowered x%.2f" % pot)
	var dbonus := int(entry.get("duration_bonus", 0))
	if dbonus > 0:
		parts.append("+%d turn%s from Disdain" % [dbonus, "" if dbonus == 1 else "s"])
	var elem := str(entry.get("element", ""))
	if elem != "":
		parts.append(elem.capitalize())
	parts.append("Debuff" if Buff.is_debuff(entry) else "Buff")
	return "  ·  ".join(parts)


## Turns left, or NOTHING for a permanent (infinite) effect.
static func _counter_text(entry: Dictionary) -> String:
	return BuffIconPainter.counter_text(entry)


static func chip_color(entry: Dictionary) -> Color:
	return BuffIconCatalog.look(entry)["color"]


# ============================================================================
# One chip: a single buff/debuff icon. ALL drawing is the buff icon engine's
# (BuffIconPainter) — this class only handles size, hover and the tooltip.
# ============================================================================
class _Chip extends Control:
	var _bar: BuffBar = null
	var _entry: Dictionary = {}
	var _hovered := false

	func setup(bar: BuffBar, entry: Dictionary) -> void:
		_bar = bar
		_entry = entry
		custom_minimum_size = bar.icon_size()
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
		BuffIconPainter.draw_icon(self, Rect2(Vector2.ZERO, size), _entry, {"hovered": _hovered})
