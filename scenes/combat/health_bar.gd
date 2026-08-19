class_name BattleHealthBar
extends VBoxContainer
## Name + HP bar + Spirit bar (rev6), reused for player, allies and enemies in
## the top panel. Spirit sits directly under the HP bar. Both bars carry the
## current/max value AS TEXT INSIDE the bar, in black; HP fills green, Spirit
## fills a medium (not-too-dark) blue.

const HP_FILL     := Color(0.20, 0.78, 0.32)   # green
const SPIRIT_FILL := Color(0.20, 0.42, 0.82)   # medium blue (darker than before)
const HP_BG       := Color(0.15, 0.15, 0.15)
const SPIRIT_BG   := Color(0.12, 0.12, 0.18)
const VALUE_TEXT  := Color(0.0, 0.0, 0.0)       # black numbers, inside the bars

var _name_label: Label
var _bar: ProgressBar
var _hp_text: Label
var _spirit_bar: ProgressBar
var _spirit_text: Label


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
	set_hp(current_hp, max_hp)
	set_spirit(current_spirit, max_spirit)


func set_hp(current_hp: int, max_hp: int) -> void:
	_ensure_built()
	_bar.max_value = maxi(max_hp, 1)
	_bar.value = current_hp
	_hp_text.text = "%d / %d" % [current_hp, max_hp]


func set_spirit(current_spirit: int, max_spirit: int) -> void:
	_ensure_built()
	_spirit_bar.visible = max_spirit > 0
	_spirit_bar.max_value = maxi(max_spirit, 1)
	_spirit_bar.value = current_spirit
	_spirit_text.text = "%d / %d" % [current_spirit, max_spirit]
