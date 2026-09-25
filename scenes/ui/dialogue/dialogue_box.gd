class_name DialogueBox
extends PanelContainer

## ============================================================================
## DIALOGUE BOX  —  one speaker's line: portrait, name, typed-out text
## ============================================================================
## A reusable widget. Combat puts one in the LEFT and one in the RIGHT third of its
## bottom panel (party speakers on the left, the other side on the right); a cutscene
## can put one anywhere. It knows nothing about who is speaking or why — it is handed
## a LINE dictionary and emits `advanced` when the player moves on:
##
##     box.show_line({"speaker": "Sonny", "text": "...", "portrait": "res://...", "color": Color.WHITE})
##     await box.advanced
##
## LINE KEYS (all optional except text):
##   text      String   what is said. BBCode is allowed ([i], [color]...).
##   speaker   String   the name shown above the text.
##   portrait  String (res:// path) or Texture2D. Missing -> a coloured placeholder
##             with the speaker's initial, until portrait art exists.
##   color     Color    tints the name and the placeholder portrait.
##
## ADVANCING: a click on the box, or ui_accept (Space / Enter). The first press while
## text is still typing completes it; the next press advances.
##
## class_name global — RESTART Godot once after adding this script.
## ----------------------------------------------------------------------------

signal advanced

const PORTRAIT_SIZE := 92.0
const CHARS_PER_SECOND := 55.0
const NAME_FONT_SIZE := 17
const TEXT_FONT_SIZE := 15
const BG := Color(0.07, 0.07, 0.10, 0.96)
const BORDER := Color(0.55, 0.60, 0.72)
const TEXT_COLOR := Color(0.93, 0.93, 0.96)

## Portrait on the right-hand end instead of the left (for the right-side box).
var mirrored: bool = false

var _row: HBoxContainer
var _portrait_frame: Panel
var _portrait_tex: TextureRect
var _portrait_initial: Label
var _name: Label
var _text: RichTextLabel
var _hint: Label
var _type_tween: Tween
var _typing := false
var _active := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG
	sb.border_color = BORDER
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	add_theme_stylebox_override("panel", sb)

	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 12)
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_row)

	_portrait_frame = Panel.new()
	_portrait_frame.custom_minimum_size = Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE)
	_portrait_frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_portrait_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait_tex = TextureRect.new()
	_portrait_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_portrait_tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_portrait_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait_frame.add_child(_portrait_tex)
	_portrait_initial = Label.new()
	_portrait_initial.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_portrait_initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_portrait_initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_portrait_initial.add_theme_font_size_override("font_size", 44)
	_portrait_initial.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_portrait_initial.add_theme_constant_override("outline_size", 6)
	_portrait_initial.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait_frame.add_child(_portrait_initial)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name = Label.new()
	_name.add_theme_font_size_override("font_size", NAME_FONT_SIZE)
	_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_name)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = false
	_text.scroll_active = false
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text.add_theme_font_size_override("normal_font_size", TEXT_FONT_SIZE)
	_text.add_theme_color_override("default_color", TEXT_COLOR)
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_text)
	_hint = Label.new()
	_hint.text = "▶"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.add_theme_font_size_override("font_size", 12)
	_hint.modulate.a = 0.0
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_hint)

	if mirrored:
		_row.add_child(col)
		_row.add_child(_portrait_frame)
		_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	else:
		_row.add_child(_portrait_frame)
		_row.add_child(col)
	visible = false

## Show one line and start typing it. Await `advanced` for the player to move on.
func show_line(line: Dictionary) -> void:
	if _row == null:
		push_warning("[dialogue] show_line called before the DialogueBox entered the tree.")
		return
	var tint: Color = line.get("color", Color(0.85, 0.85, 0.90)) if line.get("color") is Color else Color(0.85, 0.85, 0.90)
	var speaker := str(line.get("speaker", ""))
	_name.text = speaker
	_name.add_theme_color_override("font_color", tint)
	_set_portrait(line.get("portrait", null), speaker, tint)
	_text.text = str(line.get("text", ""))
	_text.visible_ratio = 0.0
	_hint.modulate.a = 0.0
	visible = true
	_active = true
	_typing = true
	if _type_tween and _type_tween.is_valid():
		_type_tween.kill()
	var n := maxi(1, _text.get_total_character_count())
	_type_tween = create_tween()
	_type_tween.tween_property(_text, "visible_ratio", 1.0, float(n) / CHARS_PER_SECOND)
	_type_tween.tween_callback(_finish_typing)

func hide_box() -> void:
	_active = false
	_typing = false
	visible = false

func is_active() -> bool:
	return _active

func _set_portrait(p, speaker: String, tint: Color) -> void:
	var tex: Texture2D = null
	if p is Texture2D:
		tex = p
	elif typeof(p) == TYPE_STRING and str(p) != "" and ResourceLoader.exists(str(p)):
		var r = load(str(p))
		if r is Texture2D:
			tex = r
	_portrait_tex.texture = tex
	_portrait_initial.visible = tex == null
	var sb := StyleBoxFlat.new()
	sb.bg_color = tint.darkened(0.55) if tex == null else Color(0, 0, 0)
	sb.border_color = tint
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	_portrait_frame.add_theme_stylebox_override("panel", sb)
	_portrait_initial.text = speaker.substr(0, 1).to_upper() if speaker != "" else "?"
	_portrait_initial.add_theme_color_override("font_color", tint.lightened(0.3))

func _finish_typing() -> void:
	_typing = false
	_text.visible_ratio = 1.0
	var t := create_tween().set_loops()
	t.tween_property(_hint, "modulate:a", 1.0, 0.45)
	t.tween_property(_hint, "modulate:a", 0.25, 0.45)
	_type_tween = t

func _press() -> void:
	if not _active:
		return
	if _typing:
		if _type_tween and _type_tween.is_valid():
			_type_tween.kill()
		_finish_typing()
		return
	if _type_tween and _type_tween.is_valid():
		_type_tween.kill()
	_active = false
	advanced.emit()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_press()
		accept_event()

func _unhandled_input(event: InputEvent) -> void:
	if _active and visible and event.is_action_pressed("ui_accept"):
		_press()
		get_viewport().set_input_as_handled()
