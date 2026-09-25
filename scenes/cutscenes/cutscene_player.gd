extends Control

## ============================================================================
## CUTSCENE PLAYER  —  plays one CutsceneDB entry, then hands off
## ============================================================================
## Reached through GameManager.play_cutscene(id, then). Reads
## GameManager.pending_cutscene, plays it (or nothing, if the id isn't registered),
## and calls GameManager.finish_cutscene(), which routes to `then`.
## Esc skips.
## ----------------------------------------------------------------------------

var _bg: ColorRect
var _image: TextureRect
var _title: Label
var _box: DialogueBox
var _done := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg = ColorRect.new()
	_bg.color = Color(0, 0, 0)
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_bg)
	_image = TextureRect.new()
	_image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	add_child(_image)
	_title = Label.new()
	_title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 38)
	_title.modulate.a = 0.0
	add_child(_title)
	_box = DialogueBox.new()
	_box.anchor_left = 0.12
	_box.anchor_right = 0.88
	_box.anchor_top = 0.74
	_box.anchor_bottom = 0.95
	add_child(_box)
	_play.call_deferred()

func _play() -> void:
	var id := str(GameManager.pending_cutscene.get("id", ""))
	if not CutsceneDB.has(id):
		_finish()
		return
	var cs := CutsceneDB.get_cutscene(id)
	if cs.has("scene") and ResourceLoader.exists(str(cs["scene"])):
		var packed = load(str(cs["scene"]))
		if packed is PackedScene:
			var node: Node = (packed as PackedScene).instantiate()
			add_child(node)
			if node.has_signal("finished"):
				await node.finished
		_finish()
		return
	for step in cs.get("steps", []):
		if _done or not is_inside_tree():
			return
		if typeof(step) != TYPE_DICTIONARY:
			continue
		if step.has("background"):
			var b = step["background"]
			if b is Color:
				_bg.color = b
				_image.texture = null
			elif typeof(b) == TYPE_STRING and ResourceLoader.exists(str(b)):
				_image.texture = load(str(b))
		if step.has("title"):
			_title.text = str(step["title"])
			var t := create_tween()
			t.tween_property(_title, "modulate:a", 1.0, 0.6)
			await t.finished
		if step.has("wait"):
			await get_tree().create_timer(float(step["wait"])).timeout
		if step.has("line") and typeof(step["line"]) == TYPE_DICTIONARY:
			_title.modulate.a = 0.0
			_box.show_line(step["line"])
			await _box.advanced
			_box.hide_box()
	_finish()

func _finish() -> void:
	if _done:
		return
	_done = true
	GameManager.finish_cutscene()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_finish()
