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
const WHITE_FILL := Color(0.95, 0.95, 0.95)   # filled portion (progress / pre-fight)
const GAIN_FILL  := Color(0.64, 0.64, 0.68)   # faded gray: xp gained this fight
const TEXT_COL   := Color(0.96, 0.96, 0.96)

## Default height when the parent doesn't force one.
const DEFAULT_HEIGHT := 22.0
## Width of the black percentage box relative to the bar height.
const PCT_BOX_ASPECT := 2.6

var _pct_label: Label
var _fill: ColorRect
var _gain_fill: ColorRect
var _built := false

var _fraction := 0.0
var _label_text := "0%"

## Gain-overlay mode: the white fill is pinned to the PRE-fight progress
## (_base_fraction) and the faded-gray _gain_fill grows from there to _fraction to
## show the xp earned this fight. Off = plain white bar (the default everywhere).
var _gain_mode := false
var _base_xp := 0
var _base_fraction := 0.0

## A queued XP-gain animation ({from, to, dur}), kicked off in _ready() when the
## bar is set to animate before it has entered the tree (create_tween needs the
## node in the tree). Empty when there's nothing pending.
var _pending_anim := {}
var _xp_tween: Tween


func _ready() -> void:
	_build()
	_apply()
	if not _pending_anim.is_empty():
		var a := _pending_anim
		_pending_anim = {}
		if bool(a.get("gain", false)):
			_start_gain_anim(int(a["from"]), int(a["to"]), float(a["dur"]))
		else:
			_start_xp_anim(int(a["from"]), int(a["to"]), float(a["dur"]))


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

	# Faded-gray "gained" overlay: anchored base_fraction..fraction, drawn on TOP
	# of the white fill so it reads as the xp earned this fight. Hidden unless in
	# gain mode.
	_gain_fill = ColorRect.new()
	_gain_fill.color = GAIN_FILL
	_gain_fill.anchor_left = 0.0
	_gain_fill.anchor_top = 0.0
	_gain_fill.anchor_bottom = 1.0
	_gain_fill.anchor_right = 0.0
	_gain_fill.offset_left = 0.0
	_gain_fill.offset_top = 0.0
	_gain_fill.offset_right = 0.0
	_gain_fill.offset_bottom = 0.0
	_gain_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gain_fill.visible = false
	track.add_child(_gain_fill)

	_built = true


func _apply() -> void:
	if not _built:
		return
	if _gain_mode:
		# white = pre-fight progress; gray = pre-fight .. current (the gain)
		_fill.anchor_right = _base_fraction
		_fill.offset_right = 0.0
		_gain_fill.visible = true
		_gain_fill.anchor_left = _base_fraction
		_gain_fill.offset_left = 0.0
		_gain_fill.anchor_right = _fraction
		_gain_fill.offset_right = 0.0
	else:
		_fill.anchor_right = _fraction
		_fill.offset_right = 0.0
		if _gain_fill:
			_gain_fill.visible = false
	_pct_label.text = _label_text


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Set the bar directly from a 0.0..1.0 fraction. Pass a percent_override to show
## custom text (e.g. "MAX"); otherwise the whole-number percent is shown.
func set_progress(fraction: float, percent_override: int = -1) -> void:
	_gain_mode = false
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
	_gain_mode = false
	if LevelTable.is_max_level(level):
		_fraction = 1.0
		_label_text = "MAX"
	else:
		_fraction = LevelTable.progress_fraction(total_xp, level)
		_label_text = "%d%%" % LevelTable.progress_percent(total_xp, level)
	_apply()


## Animate the bar from one continuous total-XP value UP to another over
## `duration` seconds. The level is re-derived each frame from LevelTable, so a
## gain that crosses a level boundary naturally shows the bar fill, snap back to
## empty, and keep filling into the next level. Safe to call before the widget is
## in the tree — the animation is queued and started in _ready().
func animate_to_xp(from_xp: int, to_xp: int, duration: float = 2.0) -> void:
	# Show the starting value immediately (paints even before _ready runs).
	set_from_xp(from_xp)
	if to_xp <= from_xp or duration <= 0.0:
		set_from_xp(to_xp)
		return
	if not is_inside_tree():
		_pending_anim = {"from": from_xp, "to": to_xp, "dur": duration}
		return
	_start_xp_anim(from_xp, to_xp, duration)


func _start_xp_anim(from_xp: int, to_xp: int, duration: float) -> void:
	set_from_xp(from_xp)
	if _xp_tween and _xp_tween.is_valid():
		_xp_tween.kill()
	_xp_tween = create_tween()
	_xp_tween.tween_method(_anim_set_xp, float(from_xp), float(to_xp), duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _anim_set_xp(v: float) -> void:
	set_from_xp(int(round(v)))


# ---------------------------------------------------------------------------
# Gain overlay (victory screen)
# ---------------------------------------------------------------------------
## Show the PRE-fight progress in solid white and animate the xp gained this fight
## as a rising faded-gray overlay from `from_xp` up to `to_xp`. The level is
## re-derived each frame, so a gain that crosses a level boundary naturally shows
## the gray fill to 100%, snap to the next level (where the white base is 0), and
## keep rising. Safe to call before the widget is in the tree.
func animate_gain(from_xp: int, to_xp: int, duration: float = 2.0) -> void:
	_gain_mode = true
	_base_xp = from_xp
	_set_gain_frame(from_xp)          # paint the pre-fight bar immediately
	if to_xp <= from_xp or duration <= 0.0:
		_set_gain_frame(to_xp)
		return
	if not is_inside_tree():
		_pending_anim = {"from": from_xp, "to": to_xp, "dur": duration, "gain": true}
		return
	_start_gain_anim(from_xp, to_xp, duration)


func _start_gain_anim(from_xp: int, to_xp: int, duration: float) -> void:
	_gain_mode = true
	_base_xp = from_xp
	_set_gain_frame(from_xp)
	if _xp_tween and _xp_tween.is_valid():
		_xp_tween.kill()
	_xp_tween = create_tween()
	_xp_tween.tween_method(_set_gain_frame, float(from_xp), float(to_xp), duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## Paint one frame of the gain animation at the given (animated) continuous total.
func _set_gain_frame(v: float) -> void:
	var cur_total := int(round(v))
	var lvl := LevelTable.level_for_xp(cur_total)
	if LevelTable.is_max_level(lvl):
		_fraction = 1.0
		_label_text = "MAX"
		# base white = whatever of THIS (max) level the player already had
		_base_fraction = 1.0 if LevelTable.level_for_xp(_base_xp) >= lvl else 0.0
	else:
		_fraction = LevelTable.progress_fraction(cur_total, lvl)
		_label_text = "%d%%" % LevelTable.progress_percent(cur_total, lvl)
		# The pre-fight (white) portion only exists on the pre-fight level; once the
		# gain crosses into a higher level the whole level was earned this fight.
		if LevelTable.level_for_xp(_base_xp) >= lvl:
			_base_fraction = LevelTable.progress_fraction(_base_xp, lvl)
		else:
			_base_fraction = 0.0
	_base_fraction = minf(_base_fraction, _fraction)
	_apply()
