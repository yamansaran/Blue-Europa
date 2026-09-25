extends PanelContainer
class_name DebugCheatsPanel

## ============================================================================
## DEBUG CHEATS PANEL  —  level / god mode / skillful mode / money  (DEBUG ONLY)
## ============================================================================
## Opened from the small floating "DEBUG" button on the overworld
## (campaign_overworld.gd). Built ONLY when GameManager.is_debug() is on, and every
## Character.debug_* call it makes checks the flag again (CORE_PRIMER §5B).
##
##   LEVEL         set a level; skill + attribute points are granted for levels
##                 gained and TAKEN BACK for levels lost (Character.debug_set_level)
##   GOD MODE      max health = 9,999,999,999 while on; lost when switched off
##   SKILLFUL MODE +9999 skill AND attribute points; subtracted when switched off
##   MONEY         add any amount; the running CHEATED total is tracked, purchases
##                 spend it first, and DEFLATE removes exactly what is left of it
##
## class_name global — RESTART Godot once after adding this script.
## ----------------------------------------------------------------------------

signal closed

var _level: SpinBox
var _god: CheckButton
var _skill: CheckButton
var _money_amt: SpinBox
var _status: Label

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.05, 0.05, 0.97)
	sb.border_color = Color(0.85, 0.25, 0.25)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(14)
	add_theme_stylebox_override("panel", sb)
	custom_minimum_size = Vector2(360, 0)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	add_child(v)

	var head := HBoxContainer.new()
	var title := Label.new()
	title.text = "DEBUG — cheats"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_color_override("font_color", Color(1.0, 0.55, 0.55))
	title.add_theme_font_size_override("font_size", 18)
	head.add_child(title)
	var x := Button.new()
	x.text = "✕"
	x.focus_mode = Control.FOCUS_NONE
	x.pressed.connect(func(): closed.emit(); queue_free())
	head.add_child(x)
	v.add_child(head)

	# --- level ---
	var lr := HBoxContainer.new()
	lr.add_theme_constant_override("separation", 8)
	lr.add_child(_label("Level"))
	_level = SpinBox.new()
	_level.min_value = 1
	_level.max_value = LevelTable.MAX_LEVEL
	_level.step = 1
	_level.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lr.add_child(_level)
	var set_lvl := Button.new()
	set_lvl.text = "Set level"
	set_lvl.pressed.connect(func(): Character.debug_set_level(int(_level.value)); _refresh())
	lr.add_child(set_lvl)
	v.add_child(lr)

	# --- modes ---
	_god = CheckButton.new()
	_god.text = "God mode (max health 9,999,999,999)"
	_god.toggled.connect(func(on: bool): Character.debug_set_god_mode(on); _refresh())
	v.add_child(_god)
	_skill = CheckButton.new()
	_skill.text = "Skillful mode (+9999 skill & attribute points)"
	_skill.toggled.connect(func(on: bool): Character.debug_set_skillful(on); _refresh())
	v.add_child(_skill)

	# --- money ---
	var mr := HBoxContainer.new()
	mr.add_theme_constant_override("separation", 8)
	mr.add_child(_label("Money"))
	_money_amt = SpinBox.new()
	_money_amt.min_value = 1
	_money_amt.max_value = 100000000
	_money_amt.step = 1
	_money_amt.value = 1000
	_money_amt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mr.add_child(_money_amt)
	var add := Button.new()
	add.text = "Add"
	add.pressed.connect(func(): Character.debug_add_money(int(_money_amt.value)); _refresh())
	mr.add_child(add)
	v.add_child(mr)
	var deflate := Button.new()
	deflate.text = "Deflate (remove unspent cheated money)"
	deflate.pressed.connect(func(): Character.debug_deflate(); _refresh())
	v.add_child(deflate)

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 13)
	_status.add_theme_color_override("font_color", Color(0.8, 0.8, 0.85))
	v.add_child(_status)
	_refresh()

func _label(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.custom_minimum_size = Vector2(56, 0)
	return l

func _refresh() -> void:
	_level.set_value_no_signal(Character.level)
	_god.set_pressed_no_signal(Character.debug_god_mode)
	_skill.set_pressed_no_signal(Character.debug_skillful)
	_status.text = "Lv %d · %d skill pts · %d attribute pts\nMoney %d  (cheated, unspent: %d) · max HP %d" % [
		Character.level, Character.skill_points, Character.attribute_points,
		Character.money, Character.debug_cheated_money, Character.body.max_hp()]

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		accept_event()   # never let a click fall through to the map behind
