class_name BattleCharacter
extends Control
## Combat model, rev6: driven by a CharacterBase `body`. The placeholder model is
## a rectangle tinted by the name-hash colour (or the character's portrait if one
## is assigned). HP and Spirit are read from / written to the body.

signal hovered(unit: BattleCharacter)
signal unhovered(unit: BattleCharacter)
signal clicked(unit: BattleCharacter)

var body: CharacterBase = null
var team: int = 0
var ai: String = "none"
var unit_name: String = "Unit"
var health_bar: BattleHealthBar = null
## Visual size multiplier for the model (e.g. bosses are drawn bigger). The
## combat engine reads an enemy spec's "size_scale" and applies it in layout.
var size_scale: float = 1.0

var _rect: ColorRect
var _portrait: TextureRect
var _label: Label

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	if body != null:
		unit_name = body.char_name

	if body != null and body.portrait != null:
		_portrait = TextureRect.new()
		_portrait.texture = body.portrait
		_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(_portrait)
	else:
		_rect = ColorRect.new()
		_rect.color = _model_color()
		_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(_rect)

	# Name + level, floating just ABOVE the model. Hidden until hovered.
	var lvl := body.level if body != null else 1
	_label = Label.new()
	_label.text = "%s  Lv %d" % [unit_name, lvl]
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.anchor_left = 0.0
	_label.anchor_right = 1.0
	_label.anchor_top = 0.0
	_label.anchor_bottom = 0.0
	_label.offset_left = -24.0
	_label.offset_right = 24.0
	_label.offset_top = -28.0
	_label.offset_bottom = -4.0
	# white text with a black outline so it reads over any model colour
	_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_label.add_theme_constant_override("outline_size", 5)
	_label.add_theme_font_size_override("font_size", 13)
	_label.visible = false
	add_child(_label)

	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)


func _on_mouse_entered() -> void:
	if _label:
		_label.visible = true
	hovered.emit(self)


func _on_mouse_exited() -> void:
	if _label:
		_label.visible = false
	unhovered.emit(self)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit(self)
		accept_event()

func _model_color() -> Color:
	if body != null:
		return body.model_color()
	return Color.GRAY

# ---- vitals (read from the body) --------------------------------------
func get_max_hp() -> int:
	return body.max_hp() if body else 1

func get_hp() -> int:
	return body.current_hp if body else 0

func get_max_spirit() -> int:
	return body.max_spirit() if body else 0

func get_spirit() -> int:
	return body.current_spirit if body else 0

func is_alive() -> bool:
	return get_hp() > 0

func refresh_bar() -> void:
	if health_bar:
		health_bar.set_hp(get_hp(), get_max_hp())
		health_bar.set_spirit(get_spirit(), get_max_spirit())

# ---- mutations --------------------------------------------------------
func take_damage(amount: int) -> void:
	if body == null:
		return
	body.current_hp = clampi(body.current_hp - amount, 0, body.max_hp())
	refresh_bar()
	if _rect:
		var base := _model_color()
		_rect.color = Color(1, 1, 1)
		var t := create_tween()
		t.tween_property(_rect, "color", base, 0.25)
	if not is_alive():
		modulate = Color(0.45, 0.45, 0.45, 0.7)

## Spend spirit (the resource formerly called focus). Returns false if short.
func spend_spirit(amount: int) -> bool:
	if body == null:
		return amount <= 0
	if body.current_spirit < amount:
		return false
	body.current_spirit -= amount
	refresh_bar()
	return true
