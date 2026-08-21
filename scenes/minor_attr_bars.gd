class_name MinorAttrBars
extends VBoxContainer

## ============================================================================
## MINOR ATTRIBUTE BARS  —  shared per-element bar-graph panel (class_name global)
## ============================================================================
## Replaces the old "X / Y / Z" text readout of the minor attributes. Shows a row
## of three toggle buttons — Pierce, Defense, Amp (in that order) — and, below
## them, one horizontal bar graph per real element, tinted with that element's
## colour (ElementColors.color).
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

var _metric: int = Metric.PIERCE
var _body: CharacterBase = null
var _buttons: Array = []
var _bars_box: VBoxContainer
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

	# --- the bar rows live here ---
	_bars_box = VBoxContainer.new()
	_bars_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bars_box.add_theme_constant_override("separation", 4)
	add_child(_bars_box)

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


func _add_bar(element: String, value: float, axis_max: float) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 6)

	var name_lbl := Label.new()
	name_lbl.text = element.capitalize()
	name_lbl.custom_minimum_size = Vector2(58, 0)
	name_lbl.add_theme_font_size_override("font_size", 11)
	name_lbl.add_theme_color_override("font_color", LABEL_COL)
	row.add_child(name_lbl)

	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = maxf(axis_max, 0.0001)
	bar.value = clampf(value, 0.0, bar.max_value)
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 14)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var fill := StyleBoxFlat.new()
	fill.bg_color = ElementColors.color(element)
	fill.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("fill", fill)

	var track := StyleBoxFlat.new()
	track.bg_color = TRACK_BG
	track.set_corner_radius_all(2)
	track.set_border_width_all(1)
	track.border_color = TRACK_BORDER
	bar.add_theme_stylebox_override("background", track)
	row.add_child(bar)

	var val_lbl := Label.new()
	val_lbl.text = _fmt_value(value)
	val_lbl.custom_minimum_size = Vector2(40, 0)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_lbl.add_theme_font_size_override("font_size", 11)
	val_lbl.add_theme_color_override("font_color", LABEL_COL)
	row.add_child(val_lbl)

	_bars_box.add_child(row)


func _fmt_value(value: float) -> String:
	# Amp lives on a 0..1-ish scale, so show two decimals; pierce/defense are ints.
	if _metric == Metric.AMP:
		return "%.2f" % value
	return str(int(round(value)))
