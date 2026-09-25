extends Control

## ============================================================================
## INTRO SCREEN  —  the first thing the game shows
## ============================================================================
## A black screen, the title fading up and away, then the main menu. Any key or click
## skips it. Built from a Tween (no extra assets); swap in a logo TextureRect, an
## AnimationPlayer or a video later without touching anything else — the only contract
## is "call GameManager.go_to_main_menu() when done".
## ----------------------------------------------------------------------------

const FADE_IN := 1.4
const HOLD := 1.8
const FADE_OUT := 0.9

var _left := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.01, 0.015, 0.03)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 10)
	col.modulate.a = 0.0
	add_child(col)
	var title := Label.new()
	title.text = "BLUE EUROPA"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 84)
	title.add_theme_color_override("font_color", Color(0.72, 0.80, 0.98))
	col.add_child(title)
	var sub := Label.new()
	sub.text = "1941"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 22)
	sub.add_theme_color_override("font_color", Color(0.55, 0.60, 0.70))
	col.add_child(sub)

	var t := create_tween()
	t.tween_property(col, "modulate:a", 1.0, FADE_IN).set_trans(Tween.TRANS_SINE)
	t.tween_interval(HOLD)
	t.tween_property(col, "modulate:a", 0.0, FADE_OUT).set_trans(Tween.TRANS_SINE)
	t.tween_callback(_leave)

func _leave() -> void:
	if _left:
		return
	_left = true
	GameManager.go_to_main_menu()

func _input(event: InputEvent) -> void:
	if (event is InputEventKey and event.pressed) or (event is InputEventMouseButton and event.pressed):
		get_viewport().set_input_as_handled()
		_leave()
