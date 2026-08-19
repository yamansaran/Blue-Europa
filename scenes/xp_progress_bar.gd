extends Control
class_name XPProgressBar

## ============================================================================
## XP PROGRESS BAR  —  shared level-progress widget (class_name "XPProgressBar")
## ============================================================================
## A reusable horizontal XP bar. Drop it on ANY screen (inventory, victory, and
## anything future). It is built entirely in code, so it needs no .tscn — just:
##       var bar := XPProgressBar.new()
##       some_container.add_child(bar)
##       bar.set_from_xp(Character.xp)          # continuous total XP
## or feed it a raw fraction:  bar.set_progress(0.42)
##
## LOOK (left -> right, all horizontal):
##   [ short BLACK box with the percentage text in it ]  [ long GREY bar that
##   fills from the left with WHITE up to the progress percentage ].
##
## Because the percentage is derived from LevelTable, the bar shows the FAKE
## per-level refresh (xp into the current level / xp span of the level), never
## the raw continuous total. This is a class_name global; RESTART Godot once
## after first adding the file.
## ----------------------------------------------------------------------------

const BLACK      := Color(0.05, 0.05, 0.06)   # percentage box
const GREY       := Color(0.32, 0.32, 0.34)   # empty track
const WHITE_FILL := Color(0.95, 0.95, 0.95)   # filled portion
const TEXT_COL   := Color(0.96, 0.96, 0.96)

## Default height when the parent doesn't force one.
const DEFAULT_HEIGHT := 22.0
## Width of the black percentage box relative to the bar height.
const PCT_BOX_ASPECT := 2.6

var _pct_label: Label
var _fill: ColorRect
var _built := false

var _fraction := 0.0
var _label_text := "0%"


func _ready() -> void:
	_build()
	_apply()


func _build() -> void:
	if _built:
		return
	if custom_minimum_size.y <= 0.0:
		custom_minimum_size.y = DEFAULT_HEIGHT

	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 4)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)

	# --- left: short black box with the percentage in it ---
	var pct_box := Control.new()
	pct_box.custom_minimum_size = Vector2(DEFAULT_HEIGHT * PCT_BOX_ASPECT, 0)
	pct_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pct_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(pct_box)

	var black := ColorRect.new()
	black.color = BLACK
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pct_box.add_child(black)

	_pct_label = Label.new()
	_pct_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pct_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pct_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_pct_label.add_theme_color_override("font_color", TEXT_COL)
	_pct_label.add_theme_font_size_override("font_size", 12)
	_pct_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pct_box.add_child(_pct_label)

	# --- right: long grey track that fills with white ---
	var track := Control.new()
	track.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	track.size_flags_vertical = Control.SIZE_EXPAND_FILL
	track.clip_contents = true
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(track)

	var grey := ColorRect.new()
	grey.color = GREY
	grey.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	grey.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(grey)

	# White fill: anchored 0..fraction, so it scales with the track automatically.
	_fill = ColorRect.new()
	_fill.color = WHITE_FILL
	_fill.anchor_left = 0.0
	_fill.anchor_top = 0.0
	_fill.anchor_bottom = 1.0
	_fill.anchor_right = 0.0
	_fill.offset_left = 0.0
	_fill.offset_top = 0.0
	_fill.offset_right = 0.0
	_fill.offset_bottom = 0.0
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(_fill)

	_built = true


func _apply() -> void:
	if not _built:
		return
	_fill.anchor_right = _fraction
	_fill.offset_right = 0.0
	_pct_label.text = _label_text


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Set the bar directly from a 0.0..1.0 fraction. Pass a percent_override to show
## custom text (e.g. "MAX"); otherwise the whole-number percent is shown.
func set_progress(fraction: float, percent_override: int = -1) -> void:
	_fraction = clampf(fraction, 0.0, 1.0)
	var pct := percent_override if percent_override >= 0 else int(round(_fraction * 100.0))
	_label_text = "%d%%" % pct
	_apply()


## Feed the CONTINUOUS total XP; the level is derived from LevelTable.
func set_from_xp(total_xp: int) -> void:
	set_xp_level(total_xp, LevelTable.level_for_xp(total_xp))


## Feed the continuous total XP AND an explicit level (skips the lookup and shows
## "MAX" text at the top of the curve).
func set_xp_level(total_xp: int, level: int) -> void:
	if LevelTable.is_max_level(level):
		_fraction = 1.0
		_label_text = "MAX"
	else:
		_fraction = LevelTable.progress_fraction(total_xp, level)
		_label_text = "%d%%" % LevelTable.progress_percent(total_xp, level)
	_apply()
