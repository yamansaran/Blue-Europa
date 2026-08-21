class_name AbilityTooltip
extends VBoxContainer

## ============================================================================
## ABILITY TOOLTIP  —  shared 3-panel ability hover card (class_name global)
## ============================================================================
## The single tooltip used everywhere an ability is hovered: the combat wheel,
## the abilities-screen wheel, the ability pool chips, and skill-tree nodes.
## Three flush-stacked panels (no gap between them):
##   1. NAME  — light gray, one line, appears INSTANTLY on hover.
##   2. COST  — grayish blue, "Cost: <phrase>" (+ "CD: n"); height grows to fit.
##   3. DESC  — black, the full description, wraps.
## The name shows immediately; the cost and description fade in together after a
## short hover delay.
##
## USAGE (each host owns one):
##   var tip := AbilityTooltip.new()
##   add_child(tip)
##   tip.show_for(ability, some_global_rect)   # null ability -> hides
##   tip.hide_tip()
## It sets top_level = true, so it draws over everything and is NOT clipped by a
## ScrollContainer/Panel around the host; position it in GLOBAL coordinates
## (show_for does this for you from the anchor rect). This is a class_name global
## — RESTART Godot once after adding the file.
## ----------------------------------------------------------------------------

const TIP_WIDTH := 200.0
const TIP_DELAY := 0.25          # hover time before cost + description appear
const TIP_FADE  := 0.2

const NAME_BG := Color(0.80, 0.80, 0.82)   # light gray
const POINTS_BG := Color(0.62, 0.55, 0.30)  # muted gold band (skill-tree only)
const COST_BG := Color(0.34, 0.42, 0.56)   # grayish blue
const DESC_BG := Color(0.03, 0.03, 0.05)   # black
const NAME_TX := Color(0.08, 0.08, 0.10)
const POINTS_TX := Color(0.10, 0.08, 0.02)
const COST_TX := Color(0.96, 0.96, 0.98)
const DESC_TX := Color(0.92, 0.92, 0.94)

var _name_panel: PanelContainer
var _points_panel: PanelContainer
var _cost_panel: PanelContainer
var _desc_panel: PanelContainer
var _name_lbl: Label
var _points_lbl: Label
var _cost_lbl: Label
var _desc_lbl: Label
var _timer: Timer
var _tween: Tween
var _ab: Ability = null
var _built := false


func _ready() -> void:
	_ensure_built()


func _ensure_built() -> void:
	if _built:
		return
	_built = true
	top_level = true                       # escape parent clipping; global coords
	z_index = 1000
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 0)   # no buffer between panels
	visible = false

	_name_panel = _panel(NAME_BG)
	_name_lbl = _label(NAME_TX, false)
	_name_panel.add_child(_name_lbl)
	add_child(_name_panel)

	# Optional "Points" line (skill-tree hovers pass it; other hosts leave it blank
	# and this panel stays hidden). Shows immediately, alongside the name.
	_points_panel = _panel(POINTS_BG)
	_points_lbl = _label(POINTS_TX, false)
	_points_panel.add_child(_points_lbl)
	add_child(_points_panel)

	_cost_panel = _panel(COST_BG)
	_cost_lbl = _label(COST_TX, false)
	_cost_panel.add_child(_cost_lbl)
	add_child(_cost_panel)

	_desc_panel = _panel(DESC_BG)
	_desc_lbl = _label(DESC_TX, true)      # description wraps
	_desc_panel.add_child(_desc_lbl)
	add_child(_desc_panel)

	_timer = Timer.new()
	_timer.one_shot = true
	_timer.wait_time = TIP_DELAY
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


func _label(col: Color, wrap: bool) -> Label:
	var l := Label.new()
	l.add_theme_color_override("font_color", col)
	l.add_theme_font_size_override("font_size", 12)
	l.custom_minimum_size = Vector2(TIP_WIDTH, 0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


## Show the tooltip for `ab`, positioned beside `anchor_global` (a Rect2 in
## global/viewport coordinates — usually the hovered widget's global rect). Pass
## null to hide. Re-calling with the same ability is a cheap no-op.
func show_for(ab: Ability, anchor_global: Rect2, points_text := "") -> void:
	_ensure_built()
	if ab == null:
		hide_tip()
		return
	if ab == _ab and visible:
		# Same ability already shown — but the point count can change on invest, so
		# refresh that line in place rather than treating it as a no-op.
		_update_points(points_text)
		return
	_ab = ab
	_name_lbl.text = ab.display_name
	_update_points(points_text)
	_cost_lbl.text = ab.cost_text()
	_desc_lbl.text = ab.description

	if _tween and _tween.is_valid():
		_tween.kill()
	# name shows now; cost + description wait for the delay, then fade in
	_cost_panel.visible = false
	_desc_panel.visible = false
	_cost_panel.modulate.a = 1.0
	_desc_panel.modulate.a = 1.0
	visible = true
	reset_size()
	_place(anchor_global)
	_timer.stop()
	_timer.start()


## Set (or hide) the optional "Points" line. Blank text hides the panel entirely,
## so hosts that don't deal in points (combat wheel, ability pool) look unchanged.
func _update_points(points_text: String) -> void:
	if _points_panel == null:
		return
	if points_text != "":
		_points_lbl.text = points_text
		_points_panel.visible = true
	else:
		_points_panel.visible = false


func hide_tip() -> void:
	_ab = null
	if _timer:
		_timer.stop()
	if _tween and _tween.is_valid():
		_tween.kill()
	visible = false


func _reveal_details() -> void:
	if not visible or _ab == null:
		return
	_cost_panel.visible = true
	_desc_panel.visible = true
	_cost_panel.modulate.a = 0.0
	_desc_panel.modulate.a = 0.0
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(_cost_panel, "modulate:a", 1.0, TIP_FADE)
	_tween.tween_property(_desc_panel, "modulate:a", 1.0, TIP_FADE)


## Place the card just to the right of the anchor, flipping to the left when it
## would run off the right edge of the screen; clamped to stay on-screen.
func _place(anchor: Rect2) -> void:
	var w := TIP_WIDTH + 16.0
	var vp := get_viewport_rect().size
	var x := anchor.end.x + 8.0
	if x + w > vp.x:
		x = anchor.position.x - w - 8.0
	x = clampf(x, 4.0, maxf(4.0, vp.x - w - 4.0))
	var y := clampf(anchor.position.y, 4.0, maxf(4.0, vp.y - size.y - 4.0))
	global_position = Vector2(x, y)
