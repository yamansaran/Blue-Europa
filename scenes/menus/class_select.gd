extends Control

## ============================================================================
## CLASS SELECT  —  four tall cards, one per ClassRegistry class
## ============================================================================
## Reached from the main menu's New Game flow (GameManager.go_to_class_select, which
## stashes the chosen slot + save name in GameManager.pending_new_game). Click a card to
## select it, then BEGIN: SaveSlots.create_slot makes the save, and
## GameManager.begin_new_game plays the class's opening cutscene (none yet) and drops
## the player into zone 1.
##
## Cards are data-driven — ClassRegistry.ORDER decides how many and in what order. A
## LOCKED class draws dimmed with a padlock line and can't be picked. Each card's
## portrait is the class's `portrait` art when it exists, else a drawn placeholder.
## ----------------------------------------------------------------------------

const CARD_GAP := 22
var _cards: Dictionary = {}          # class_id -> PanelContainer
var _selected := ""
var _begin: Button

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.04, 0.07)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var header := Label.new()
	header.text = "Choose your class"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.anchor_left = 0.0
	header.anchor_right = 1.0
	header.anchor_top = 0.04
	header.anchor_bottom = 0.12
	header.add_theme_font_size_override("font_size", 40)
	add_child(header)
	var sub := Label.new()
	sub.text = "Save: %s  ·  slot %d" % [str(GameManager.pending_new_game.get("name", "")), int(GameManager.pending_new_game.get("slot", 0))]
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.anchor_left = 0.0
	sub.anchor_right = 1.0
	sub.anchor_top = 0.11
	sub.anchor_bottom = 0.15
	sub.add_theme_color_override("font_color", Color(0.6, 0.65, 0.75))
	add_child(sub)

	var row := HBoxContainer.new()
	row.anchor_left = 0.06
	row.anchor_right = 0.94
	row.anchor_top = 0.18
	row.anchor_bottom = 0.86
	row.add_theme_constant_override("separation", CARD_GAP)
	add_child(row)
	for id in ClassRegistry.ids():
		var card := _make_card(str(id))
		row.add_child(card)
		_cards[str(id)] = card

	var bar := HBoxContainer.new()
	bar.anchor_left = 0.06
	bar.anchor_right = 0.94
	bar.anchor_top = 0.89
	bar.anchor_bottom = 0.96
	bar.add_theme_constant_override("separation", 12)
	add_child(bar)
	var back := Button.new()
	back.text = "‹  Back"
	back.custom_minimum_size = Vector2(140, 0)
	back.pressed.connect(GameManager.go_to_main_menu)
	bar.add_child(back)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(sp)
	_begin = Button.new()
	_begin.text = "Begin"
	_begin.custom_minimum_size = Vector2(240, 0)
	_begin.add_theme_font_size_override("font_size", 20)
	_begin.disabled = true
	_begin.pressed.connect(_on_begin)
	bar.add_child(_begin)

	# Pre-select the first unlocked class.
	for id in ClassRegistry.ids():
		if ClassRegistry.is_unlocked(str(id)):
			_select(str(id))
			break

func _make_card(id: String) -> PanelContainer:
	var info := ClassRegistry.info(id)
	var col: Color = info.get("color", Color.GRAY)
	var unlocked := _playable(id)
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.set_meta("class_id", id)
	_style_card(card, col, false, unlocked)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(v)

	var portrait_path := str(info.get("portrait", ""))
	if portrait_path != "" and ResourceLoader.exists(portrait_path):
		var tr := TextureRect.new()
		tr.texture = load(portrait_path)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.size_flags_vertical = Control.SIZE_EXPAND_FILL
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(tr)
	else:
		var ph := _Placeholder.new()
		ph.tint = col
		ph.size_flags_vertical = Control.SIZE_EXPAND_FILL
		ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(ph)

	var nm := Label.new()
	nm.text = str(info.get("name", id))
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.add_theme_font_size_override("font_size", 24)
	nm.add_theme_color_override("font_color", col.lightened(0.35))
	v.add_child(nm)
	var tag := Label.new()
	tag.text = str(info.get("tagline", ""))
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tag.custom_minimum_size = Vector2(0, 44)
	tag.add_theme_font_size_override("font_size", 14)
	tag.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85))
	v.add_child(tag)
	if not ClassRegistry.is_unlocked(id):
		var lock := Label.new()
		lock.text = "LOCKED (debug: playable)" if unlocked else "LOCKED"
		lock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lock.add_theme_font_size_override("font_size", 18)
		lock.add_theme_color_override("font_color", Color(0.85, 0.35, 0.35))
		v.add_child(lock)
		if not unlocked:
			card.modulate = Color(0.55, 0.55, 0.58)
	card.gui_input.connect(_on_card_input.bind(id))
	card.mouse_entered.connect(func(): if unlocked and _selected != id: _style_card(card, col, true, true))
	card.mouse_exited.connect(func(): if _selected != id: _style_card(card, col, false, unlocked))
	return card

func _style_card(card: PanelContainer, col: Color, hot: bool, unlocked: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.13) if not hot else Color(0.11, 0.12, 0.18)
	sb.border_color = col if unlocked else Color(0.3, 0.3, 0.33)
	sb.set_border_width_all(4 if hot else 2)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(16)
	sb.shadow_color = Color(col.r, col.g, col.b, 0.35) if hot else Color(0, 0, 0, 0.4)
	sb.shadow_size = 14 if hot else 6
	card.add_theme_stylebox_override("panel", sb)

func _on_card_input(event: InputEvent, id: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _playable(id):
			_select(id)
			if event.double_click:
				_on_begin()

## Unlocked for real, or — DEBUG only (GameManager.is_debug()) — any registered class,
## so a locked class (the Nephilic) can be started for testing.
func _playable(id: String) -> bool:
	return ClassRegistry.is_unlocked(id) or GameManager.is_debug()

func _select(id: String) -> void:
	var prev := _selected
	_selected = id
	if prev != "" and _cards.has(prev):
		_style_card(_cards[prev], ClassRegistry.info(prev).get("color", Color.GRAY), false, true)
	if _cards.has(id):
		_style_card(_cards[id], ClassRegistry.info(id).get("color", Color.GRAY), true, true)
	_begin.disabled = false
	_begin.text = "Begin as %s  ›" % ClassRegistry.display_name(id)

func _on_begin() -> void:
	if _selected == "" or not _playable(_selected):
		return
	var slot := int(GameManager.pending_new_game.get("slot", 1))
	var nm := str(GameManager.pending_new_game.get("name", "Save %d" % slot))
	SaveSlots.create_slot(slot, nm, _selected)
	GameManager.begin_new_game(_selected)

# A stand-in portrait until class art exists: a lit silhouette in the class colour.
class _Placeholder extends Control:
	var tint: Color = Color.GRAY
	func _draw() -> void:
		var w := size.x
		var h := size.y
		draw_rect(Rect2(Vector2.ZERO, size), tint.darkened(0.78))
		var c := Vector2(w * 0.5, h * 0.36)
		var head := minf(w, h) * 0.13
		var body := PackedVector2Array([
			Vector2(w * 0.5 - head * 0.9, h * 0.36 + head * 1.1),
			Vector2(w * 0.5 + head * 0.9, h * 0.36 + head * 1.1),
			Vector2(w * 0.5 + head * 2.4, h * 0.98),
			Vector2(w * 0.5 - head * 2.4, h * 0.98),
		])
		var glow := tint.darkened(0.25)
		glow.a = 0.9
		draw_colored_polygon(body, glow)
		draw_circle(c, head, glow)
		draw_rect(Rect2(Vector2.ZERO, size), tint.darkened(0.4), false, 2.0)
