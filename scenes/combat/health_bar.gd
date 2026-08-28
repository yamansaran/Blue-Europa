class_name BattleHealthBar
extends HBoxContainer
## Name + HP bar + Spirit bar (rev21), reused for player, allies and enemies in
## the top panel. Spirit sits directly under the HP bar. The two bars now carry:
##   - the CHARACTER NAME inside the HP bar at the START edge (tinted per-unit),
##   - the CURRENT hp / spirit value inside each bar at the END edge (black),
## and a dark-grey MAX BOX sits right after the bars (before the buff strip),
## as tall as the two bars together, holding MAX hp (next to the HP bar) and MAX
## spirit (next to the spirit bar) in white.
##
## The whole widget is an HBox of [bars_box][max_box]. For enemies (mirror=true)
## the order flips to [max_box][bars_box] and the in-bar text mirrors too, so the
## box always ends up on the side facing that unit's buff strip.
##
## ANIMATION: a value change SLIDES the bar (and its counting text) to the new
## value over BAR_ANIM_TIME instead of snapping. The very first fill (during
## setup(), before the bar is in the tree) is instant; only later changes animate.
## A new change kills any in-flight tween on that bar so rapid hits don't fight.

const HP_FILL     := Color(0.20, 0.78, 0.32)   # green
const SPIRIT_FILL := Color(0.20, 0.42, 0.82)   # medium blue (darker than before)
const HP_BG       := Color(0.15, 0.15, 0.15)
const SPIRIT_BG   := Color(0.12, 0.12, 0.18)
const VALUE_TEXT  := Color(0.0, 0.0, 0.0)       # black numbers, inside the bars
const MAX_TEXT    := Color(1.0, 1.0, 1.0)       # white numbers, inside the max box
const MAX_BOX_BG  := Color(0.16, 0.16, 0.16)    # the dark-grey box behind the maxima

## Bar heights (rev21: ~10% taller than the old 18 / 15).
const HP_BAR_H     := 20.0
const SPIRIT_BAR_H := 17.0
const BAR_SEP      := 2
## Combined height of the HP + Spirit stack. The buff strip matches this
## (BuffBar.CHIP_H) and the max box is exactly this tall.
const DUO_HEIGHT   := HP_BAR_H + BAR_SEP + SPIRIT_BAR_H   # 39

## Padding of the in-bar text from the bar's edges.
const TEXT_PAD := 5.0

## SHIELD: a medium-grey bar that floats just ABOVE the HP bar whenever the unit
## carries any absorbing shield, showing a drawn shield glyph + the TOTAL shield.
## It is a child of the HP bar (anchored above it), so it never disturbs the HP /
## Spirit / max-box layout; it simply appears and disappears with the shield.
const SHIELD_BAR_BG   := Color(0.42, 0.42, 0.46)   # medium grey
const SHIELD_ICON_COL := Color(0.93, 0.93, 0.97)   # near-white shield glyph
const SHIELD_TEXT_COL := Color(1.0, 1.0, 1.0)
const SHIELD_BAR_H    := 15.0     # height of the shield bar
const SHIELD_BAR_GAP  := 2.0      # gap between the shield bar and the HP bar

## Width of the HP / Spirit bars (the max box + buff strip add their own width).
const BARS_WIDTH := 160.0

## How long a bar takes to slide to a new value.
const BAR_ANIM_TIME := 0.75

var _mirror: bool = false

var _bars_box: VBoxContainer
var _max_box: PanelContainer

var _name_label: Label
var _bar: ProgressBar
var _hp_text: Label
var _hp_max_label: Label
var _spirit_bar: ProgressBar
var _spirit_text: Label
var _spirit_max_label: Label

# Shield bar (grey), floating above the HP bar; hidden when there is no shield.
var _shield_overlay: Control
var _shield_text: Label

# True maxima for the value text (the ProgressBar.max_value is floored at 1).
var _hp_max: int = 1
var _spirit_max: int = 0

# In-flight fill tweens, killed and replaced on each change.
var _hp_tween: Tween
var _spirit_tween: Tween


func _ensure_built() -> void:
	if _bars_box != null:
		return
	add_theme_constant_override("separation", 4)
	# Sit at the natural height (DUO_HEIGHT) and centre in the top band instead of
	# stretching to fill it — otherwise the dark max box balloons vertically.
	size_flags_vertical = Control.SIZE_SHRINK_CENTER

	# --- the two bars, stacked ---
	_bars_box = VBoxContainer.new()
	_bars_box.add_theme_constant_override("separation", BAR_SEP)
	# The bars carry the width; the max box only takes what its text needs.
	_bars_box.custom_minimum_size = Vector2(BARS_WIDTH, 0)
	_bars_box.size_flags_horizontal = Control.SIZE_FILL
	_bars_box.size_flags_vertical = Control.SIZE_FILL

	# HP bar (green): name at the START edge, current value at the END edge.
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, HP_BAR_H)
	_bar.add_theme_stylebox_override("fill", _stylebox(HP_FILL))
	_bar.add_theme_stylebox_override("background", _stylebox(HP_BG))
	_bars_box.add_child(_bar)

	_name_label = _edge_label(12, _start_align())
	_bar.add_child(_name_label)
	_hp_text = _edge_label(11, _end_align())
	_bar.add_child(_hp_text)

	# Shield bar: a grey strip anchored just ABOVE the HP bar (a child of it, so it
	# stays out of the VBox flow). Hidden until the unit has shield. The glyph is
	# drawn in _draw_shield_overlay; the amount hugs the value-side edge.
	_shield_overlay = Control.new()
	_shield_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shield_overlay.clip_contents = false
	_shield_overlay.anchor_left = 0.0
	_shield_overlay.anchor_right = 1.0
	_shield_overlay.anchor_top = 0.0
	_shield_overlay.anchor_bottom = 0.0
	_shield_overlay.offset_left = 0.0
	_shield_overlay.offset_right = 0.0
	_shield_overlay.offset_top = -(SHIELD_BAR_H + SHIELD_BAR_GAP)
	_shield_overlay.offset_bottom = -SHIELD_BAR_GAP
	_shield_overlay.visible = false
	_shield_overlay.draw.connect(_draw_shield_overlay)
	_bar.add_child(_shield_overlay)

	_shield_text = Label.new()
	_shield_text.horizontal_alignment = _end_align()
	_shield_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_shield_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shield_text.add_theme_color_override("font_color", SHIELD_TEXT_COL)
	_shield_text.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_shield_text.add_theme_constant_override("outline_size", 3)
	_shield_text.add_theme_font_size_override("font_size", 11)
	_shield_text.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Leave room for the drawn glyph on the START edge; the amount hugs the END edge.
	var glyph_room := SHIELD_BAR_H + TEXT_PAD
	if _mirror:
		_shield_text.offset_left = TEXT_PAD
		_shield_text.offset_right = -glyph_room
	else:
		_shield_text.offset_left = glyph_room
		_shield_text.offset_right = -TEXT_PAD
	_shield_overlay.add_child(_shield_text)

	# Spirit bar (blue), directly under HP: current value at the END edge.
	_spirit_bar = ProgressBar.new()
	_spirit_bar.show_percentage = false
	_spirit_bar.custom_minimum_size = Vector2(0, SPIRIT_BAR_H)
	_spirit_bar.add_theme_stylebox_override("fill", _stylebox(SPIRIT_FILL))
	_spirit_bar.add_theme_stylebox_override("background", _stylebox(SPIRIT_BG))
	_bars_box.add_child(_spirit_bar)

	_spirit_text = _edge_label(10, _end_align())
	_spirit_bar.add_child(_spirit_text)

	# --- the dark-grey MAX box, as tall as the two bars together ---
	_max_box = PanelContainer.new()
	_max_box.add_theme_stylebox_override("panel", _max_box_style())
	var mvb := VBoxContainer.new()
	mvb.add_theme_constant_override("separation", BAR_SEP)
	mvb.size_flags_vertical = Control.SIZE_FILL
	_max_box.add_child(mvb)

	_hp_max_label = _max_label(11)
	_hp_max_label.custom_minimum_size = Vector2(0, HP_BAR_H)
	mvb.add_child(_hp_max_label)
	_spirit_max_label = _max_label(10)
	_spirit_max_label.custom_minimum_size = Vector2(0, SPIRIT_BAR_H)
	mvb.add_child(_spirit_max_label)

	# Order the two blocks; the box faces the buff strip.
	if _mirror:
		add_child(_max_box)
		add_child(_bars_box)
	else:
		add_child(_bars_box)
		add_child(_max_box)


# ----------------------------------------------------------------- helpers
func _start_align() -> int:
	# "start" edge of the HP bar: right for a mirrored (enemy) unit, else left.
	return HORIZONTAL_ALIGNMENT_RIGHT if _mirror else HORIZONTAL_ALIGNMENT_LEFT


func _end_align() -> int:
	# "end" edge (where the current value + box are): the opposite side.
	return HORIZONTAL_ALIGNMENT_LEFT if _mirror else HORIZONTAL_ALIGNMENT_RIGHT


func _stylebox(col: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(3)
	return sb


func _max_box_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = MAX_BOX_BG
	sb.set_corner_radius_all(3)
	# horizontal breathing room, but NO vertical margin so the two rows line up
	# exactly with the HP / Spirit bars beside them.
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	return sb


## A label stretched over its parent bar, showing text flush to one edge.
func _edge_label(font_size: int, align: int) -> Label:
	var l := Label.new()
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", VALUE_TEXT)  # name is re-coloured to tint in setup()
	l.add_theme_font_size_override("font_size", font_size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	l.offset_left = TEXT_PAD
	l.offset_right = -TEXT_PAD
	return l


## The max number, with a single space "after" it (in the bar's reading direction).
func _max_text(v: int) -> String:
	return (" %d" % v) if _mirror else ("%d " % v)


## A white label inside the max box, aligned toward the bar it labels.
func _max_label(font_size: int) -> Label:
	var l := Label.new()
	l.horizontal_alignment = _start_align()   # hug the box edge facing the bars
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", MAX_TEXT)
	l.add_theme_font_size_override("font_size", font_size)
	return l


func setup(unit_name: String, max_hp: int, current_hp: int, max_spirit: int, current_spirit: int, tint: Color, mirror: bool = false) -> void:
	_mirror = mirror
	_ensure_built()
	custom_minimum_size = Vector2(180, 0)
	_name_label.text = unit_name
	# The per-unit tint colours the NAME (health fill stays green), so units stay
	# distinguishable without recolouring the HP bar.
	_name_label.add_theme_color_override("font_color", tint)
	# setup() runs before the bar is added to the tree, so these snap instantly.
	set_hp(current_hp, max_hp)
	set_spirit(current_spirit, max_spirit)


func set_hp(current_hp: int, max_hp: int) -> void:
	_ensure_built()
	_hp_max = maxi(max_hp, 0)
	_hp_max_label.text = _max_text(_hp_max)
	_bar.max_value = maxi(max_hp, 1)
	if _hp_tween and _hp_tween.is_valid():
		_hp_tween.kill()
	if not is_inside_tree():
		_set_hp_display(float(current_hp))       # instant (initial setup)
		return
	_hp_tween = create_tween()
	_hp_tween.tween_method(_set_hp_display, float(_bar.value), float(current_hp), BAR_ANIM_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func set_spirit(current_spirit: int, max_spirit: int) -> void:
	_ensure_built()
	_spirit_max = maxi(max_spirit, 0)
	var has_spirit := max_spirit > 0
	_spirit_bar.visible = has_spirit
	_spirit_max_label.visible = has_spirit
	_spirit_max_label.text = _max_text(_spirit_max)
	_spirit_bar.max_value = maxi(max_spirit, 1)
	if _spirit_tween and _spirit_tween.is_valid():
		_spirit_tween.kill()
	if not is_inside_tree():
		_set_spirit_display(float(current_spirit))
		return
	_spirit_tween = create_tween()
	_spirit_tween.tween_method(_set_spirit_display, float(_spirit_bar.value), float(current_spirit), BAR_ANIM_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


# The tweened setters: move the fill and update the counting text together so the
# number always matches the bar as it slides. The value is now the CURRENT amount
# only; the maximum lives in the dark box beside the bars.
func _set_hp_display(v: float) -> void:
	_bar.value = v
	_hp_text.text = "%d" % int(round(v))


func _set_spirit_display(v: float) -> void:
	_spirit_bar.value = v
	_spirit_text.text = "%d" % int(round(v))


## Show the unit's TOTAL absorbing shield on the grey bar above the HP bar. 0 hides
## the bar entirely; any positive value shows the glyph + amount.
func set_shield(total_shield: int) -> void:
	_ensure_built()
	var has := total_shield > 0
	_shield_overlay.visible = has
	if has:
		_shield_text.text = "%d" % total_shield
		_shield_overlay.queue_redraw()


## Draw the shield bar: a rounded medium-grey background + a small shield glyph at
## the START edge. Bound to _shield_overlay.draw, so the draws target that node.
func _draw_shield_overlay() -> void:
	var ov := _shield_overlay
	var w := ov.size.x
	var h := ov.size.y
	if w <= 0.0 or h <= 0.0:
		return
	var sb := StyleBoxFlat.new()
	sb.bg_color = SHIELD_BAR_BG
	sb.set_corner_radius_all(3)
	ov.draw_style_box(sb, Rect2(Vector2.ZERO, ov.size))
	# Shield glyph (flat top, pointed bottom) hugging the start edge.
	var pad := 3.0
	var iw := h - pad * 2.0
	var ih := h - pad * 2.0
	var ix := (w - pad - iw) if _mirror else pad
	var iy := pad
	var pts := PackedVector2Array([
		Vector2(ix, iy),
		Vector2(ix + iw, iy),
		Vector2(ix + iw, iy + ih * 0.52),
		Vector2(ix + iw * 0.5, iy + ih),
		Vector2(ix, iy + ih * 0.52),
	])
	ov.draw_colored_polygon(pts, SHIELD_ICON_COL)
