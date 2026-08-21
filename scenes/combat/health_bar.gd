class_name BattleHealthBar
extends VBoxContainer
## Name + HP bar + Spirit bar (rev6), reused for player, allies and enemies in
## the top panel. Spirit sits directly under the HP bar. Both bars carry the
## current/max value AS TEXT INSIDE the bar, in black; HP fills green, Spirit
## fills a medium (not-too-dark) blue.
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

## How long a bar takes to slide to a new value.
const BAR_ANIM_TIME := 0.75

var _name_label: Label
var _bar: ProgressBar
var _hp_text: Label
var _spirit_bar: ProgressBar
var _spirit_text: Label

# True maxima for the "cur / max" text (the ProgressBar.max_value is floored at 1).
var _hp_max: int = 1
var _spirit_max: int = 0

# In-flight fill tweens, killed and replaced on each change.
var _hp_tween: Tween
var _spirit_tween: Tween


func _ensure_built() -> void:
	if _name_label != null:
		return
	add_theme_constant_override("separation", 2)

	_name_label = Label.new()
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_size_override("font_size", 14)
	add_child(_name_label)

	# --- HP bar (green) with the value centred inside it ---
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 18)
	_bar.add_theme_stylebox_override("fill", _stylebox(HP_FILL))
	_bar.add_theme_stylebox_override("background", _stylebox(HP_BG))
	add_child(_bar)
	_hp_text = _value_label(11)
	_bar.add_child(_hp_text)

	# --- Spirit bar (blue), directly under HP, value centred inside ---
	_spirit_bar = ProgressBar.new()
	_spirit_bar.show_percentage = false
	_spirit_bar.custom_minimum_size = Vector2(0, 15)
	_spirit_bar.add_theme_stylebox_override("fill", _stylebox(SPIRIT_FILL))
	_spirit_bar.add_theme_stylebox_override("background", _stylebox(SPIRIT_BG))
	add_child(_spirit_bar)
	_spirit_text = _value_label(10)
	_spirit_bar.add_child(_spirit_text)


func _stylebox(col: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(3)
	return sb


## A black, centred label stretched over its parent bar to show "cur / max".
func _value_label(font_size: int) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", VALUE_TEXT)
	l.add_theme_font_size_override("font_size", font_size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return l


func setup(unit_name: String, max_hp: int, current_hp: int, max_spirit: int, current_spirit: int, tint: Color) -> void:
	_ensure_built()
	custom_minimum_size = Vector2(160, 0)
	_name_label.text = unit_name
	# Health is always green now; the per-unit tint colours the NAME instead so
	# units stay distinguishable without recolouring the HP bar.
	_name_label.add_theme_color_override("font_color", tint)
	# setup() runs before the bar is added to the tree, so these snap instantly.
	set_hp(current_hp, max_hp)
	set_spirit(current_spirit, max_spirit)


func set_hp(current_hp: int, max_hp: int) -> void:
	_ensure_built()
	_hp_max = maxi(max_hp, 0)
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
	_spirit_bar.visible = max_spirit > 0
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
# number always matches the bar as it slides.
func _set_hp_display(v: float) -> void:
	_bar.value = v
	_hp_text.text = "%d / %d" % [int(round(v)), _hp_max]


func _set_spirit_display(v: float) -> void:
	_spirit_bar.value = v
	_spirit_text.text = "%d / %d" % [int(round(v)), _spirit_max]
