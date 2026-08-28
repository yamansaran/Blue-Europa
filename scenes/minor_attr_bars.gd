class_name MinorAttrBars
extends VBoxContainer

## ============================================================================
## MINOR ATTRIBUTE BARS  —  shared per-element bar-graph panel (class_name global)
## ============================================================================
## Replaces the old "X / Y / Z" text readout of the minor attributes. Shows a row
## of three toggle buttons — Pierce, Defense, Amp (in that order) — and, below
## them, one VERTICAL bar per real element, tinted with that element's colour
## (ElementColors.color), rising from a shared baseline. The bars carry no element
## text; hovering a bar pops a HoverPanel naming the element and its value.
##
## Scaling (per selection, driven by the LARGEST value shown):
##   - Pierce / Defense: bars are drawn out of 100 by default; if any value
##     exceeds 100 the axis grows to fit it (with a little headroom).
##   - Amp: drawn out of 1.0 by default; if any value approaches / exceeds 1 the
##     axis grows to fit it.
##
## Used by BOTH the inventory and abilities screens. Feed it a CharacterBase with
## set_body(); it reads pierce/defense/amp straight off the body. Preserve the
## user's chosen metric across rebuilds by listening to `metric_changed` and
## re-applying it with set_metric().
##
## class_name global — RESTART Godot once after adding this script.
## ----------------------------------------------------------------------------

signal metric_changed(metric: int)

enum Metric { PIERCE, DEFENSE, AMP }

const METRIC_NAMES := ["Pierce", "Defense", "Amp"]
const METRIC_SUFFIX := ["_pierce", "_defense", "_amp"]
const METRIC_DEFAULT_MAX := [100.0, 100.0, 1.0]
const AXIS_HEADROOM := 1.05      # extra room above the peak when the axis grows

const TRACK_BG := Color(0.10, 0.10, 0.12)
const TRACK_BORDER := Color(0.24, 0.24, 0.28)
const LABEL_COL := Color(0.86, 0.86, 0.88)

## Minimum height of the vertical-bar strip (it expands past this to fill the host).
const BARS_HEIGHT := 96.0
## Glow: how far the element-coloured halo bleeds past the fill, and its opacity.
const GLOW_SIZE := 7.0
const GLOW_ALPHA := 0.55

var _metric: int = Metric.PIERCE
var _body: CharacterBase = null
var _buttons: Array = []
var _bars_box: HBoxContainer
var _hover: HoverPanel
var _built := false


func _ready() -> void:
	_build()


func _build() -> void:
	if _built:
		return
	_built = true
	add_theme_constant_override("separation", 6)

	# --- the three metric buttons ---
	var btn_row := HBoxContainer.new()
	btn_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_row.add_theme_constant_override("separation", 4)
	add_child(btn_row)
	for i in METRIC_NAMES.size():
		var b := Button.new()
		b.text = METRIC_NAMES[i]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 11)
		b.pressed.connect(_on_metric_pressed.bind(i))
		btn_row.add_child(b)
		_buttons.append(b)

	# --- the vertical bars live in a horizontal strip ---
	# EXPAND_FILL so that when the host gives this widget extra vertical room the
	# bars grow down to fill it; BARS_HEIGHT is just the floor so they never
	# collapse (e.g. inside the inventory's scroll list).
	_bars_box = HBoxContainer.new()
	_bars_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bars_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_bars_box.custom_minimum_size = Vector2(0, BARS_HEIGHT)
	_bars_box.add_theme_constant_override("separation", 5)
	add_child(_bars_box)

	# one shared hover card, telling you which element a bar is
	_hover = HoverPanel.new()
	_hover.content_width = 130.0
	add_child(_hover)

	_sync_buttons()
	_rebuild()


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------
## Feed the panel the character body it should read pierce/defense/amp from.
func set_body(body: CharacterBase) -> void:
	_body = body
	if _built:
		_rebuild()


## Switch the visible metric programmatically (used to restore the last choice
## after the host rebuilds its attribute list). Does NOT emit metric_changed.
func set_metric(metric: int) -> void:
	_metric = clampi(metric, 0, METRIC_NAMES.size() - 1)
	if _built:
		_sync_buttons()
		_rebuild()


func get_metric() -> int:
	return _metric


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------
func _on_metric_pressed(metric: int) -> void:
	_metric = metric
	_sync_buttons()
	_rebuild()
	metric_changed.emit(metric)


func _sync_buttons() -> void:
	for i in _buttons.size():
		_buttons[i].button_pressed = (i == _metric)


func _rebuild() -> void:
	if _bars_box == null:
		return
	for c in _bars_box.get_children():
		c.queue_free()
	if _body == null:
		return

	var suffix: String = METRIC_SUFFIX[_metric]
	var base_max: float = METRIC_DEFAULT_MAX[_metric]

	# gather every element's value, tracking the largest for the axis
	var values := {}
	var largest := 0.0
	for element in Stats.REAL_ELEMENTS:
		var v := _body.get_effective(str(element) + suffix)
		values[element] = v
		largest = maxf(largest, v)

	# axis stays at the default unless a value pushes past it, then grows to fit
	var axis_max := base_max
	if largest > base_max:
		axis_max = largest * AXIS_HEADROOM

	for element in Stats.REAL_ELEMENTS:
		_add_bar(str(element), float(values[element]), axis_max)


## One vertical bar (a track with a colour fill rising from the bottom). No text —
## the element is revealed on hover via the shared HoverPanel.
func _add_bar(element: String, value: float, axis_max: float) -> void:
	var frac := clampf(value / maxf(axis_max, 0.0001), 0.0, 1.0)

	var cell := Control.new()
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cell.custom_minimum_size = Vector2(14, 0)
	cell.mouse_filter = Control.MOUSE_FILTER_STOP

	var track := Panel.new()
	track.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tsb := StyleBoxFlat.new()
	tsb.bg_color = TRACK_BG
	tsb.set_corner_radius_all(2)
	tsb.set_border_width_all(1)
	tsb.border_color = TRACK_BORDER
	track.add_theme_stylebox_override("panel", tsb)
	cell.add_child(track)

	# The fill is a Panel (not a plain ColorRect) so its StyleBoxFlat can cast a
	# soft shadow IN THE ELEMENT'S OWN COLOUR, centred on the bar — that halo reads
	# as a glow radiating in the right colour.
	var col := ElementColors.color(element)
	var fill := Panel.new()
	fill.anchor_left = 0.0
	fill.anchor_right = 1.0
	fill.anchor_top = 1.0 - frac
	fill.anchor_bottom = 1.0
	fill.offset_left = 1.0
	fill.offset_right = -1.0
	fill.offset_top = 0.0
	fill.offset_bottom = -1.0
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fsb := StyleBoxFlat.new()
	fsb.bg_color = col
	fsb.set_corner_radius_all(2)
	fsb.shadow_color = Color(col.r, col.g, col.b, GLOW_ALPHA)
	fsb.shadow_size = int(GLOW_SIZE)
	fsb.shadow_offset = Vector2.ZERO      # centred halo, not a drop shadow
	fill.add_theme_stylebox_override("panel", fsb)
	cell.add_child(fill)

	cell.mouse_entered.connect(_on_bar_hover.bind(cell, element, value))
	cell.mouse_exited.connect(_on_bar_unhover)

	_bars_box.add_child(cell)


func _on_bar_hover(cell: Control, element: String, value: float) -> void:
	if _hover == null:
		return
	var rows := [
		{"text": element.capitalize(), "bg": HoverPanel.NAME_BG, "fg": HoverPanel.NAME_TX, "font_size": 13},
		{"text": "%s: %s" % [METRIC_NAMES[_metric], _fmt_value(value)], "fg": ElementColors.color(element)},
	]
	_hover.show_rows(rows, cell.get_global_rect())


func _on_bar_unhover() -> void:
	if _hover:
		_hover.hide_panel()


func _fmt_value(value: float) -> String:
	# Amp lives on a 0..1-ish scale, so show two decimals; pierce/defense are ints.
	if _metric == Metric.AMP:
		return "%.2f" % value
	return str(int(round(value)))
