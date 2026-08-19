extends Control
class_name CampaignOverworld
## ============================================================================
## CampaignOverworld  —  the shared script every campaign's overworld scene uses
## ============================================================================
## Renders the CURRENT campaign (read from CampaignDB): its background, title,
## clickable map objects (shop / training / campaign battle — placed from the
## campaign's own overworld_objects, so different campaigns can lay them out
## differently), and a campaign PROGRESS BAR that fills as fights are cleared.
##
## When the current campaign is finished it shows the FORK chooser (pick the next
## campaign) — or, at the end of the map, a "Campaign Complete!" note. Linear
## (single-next) advances happen automatically before this screen loads, in
## GameManager.go_to_overworld().
## ----------------------------------------------------------------------------

var _objects: Array = []          # {name, rect, action}
var _progress: XPProgressBar
var _progress_label: Label
var _fork_overlay: Control = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var camp: Campaign = null
	if typeof(CampaignDB) != TYPE_NIL:
		camp = CampaignDB.get_current()
	_build(camp)
	if typeof(CampaignDB) != TYPE_NIL:
		if CampaignDB.needs_choice():
			_show_fork(camp)
		elif CampaignDB.is_final():
			_show_final(camp)

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
func _build(camp: Campaign) -> void:
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.color = camp.background_color if camp else Color(0.10, 0.50, 0.70)
	add_child(bg)

	_objects = camp.overworld_objects if camp else Campaign.default_objects()

	for o in _objects:
		var r: Rect2 = o["rect"]
		var box := ColorRect.new()
		box.position = r.position
		box.size = r.size
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.color = _object_color(str(o["action"]))
		add_child(box)
		var lbl := Label.new()
		lbl.text = _object_label(str(o["action"]))
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lbl.position = Vector2(r.position.x, r.position.y + r.size.y * 0.5 - 12.0)
		lbl.size = Vector2(r.size.x, 24.0)
		add_child(lbl)

	# --- title ---
	var title := Label.new()
	title.text = camp.display_name if camp else "Overworld"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(1, 1, 1))
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	title.add_theme_constant_override("outline_size", 6)
	title.position = Vector2(40, 24)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title)

	# --- campaign progress bar (bottom strip) ---
	_progress = XPProgressBar.new()
	_progress.anchor_left = 0.30
	_progress.anchor_right = 0.70
	_progress.anchor_top = 0.90
	_progress.anchor_bottom = 0.90
	_progress.offset_top = -16
	_progress.offset_bottom = 16
	_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_progress)

	_progress_label = Label.new()
	_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_progress_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_progress_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_progress_label.add_theme_constant_override("outline_size", 4)
	_progress_label.anchor_left = 0.30
	_progress_label.anchor_right = 0.70
	_progress_label.anchor_top = 0.90
	_progress_label.anchor_bottom = 0.90
	_progress_label.offset_top = -42
	_progress_label.offset_bottom = -18
	_progress_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_progress_label)

	_refresh_progress()

func _refresh_progress() -> void:
	if typeof(CampaignDB) == TYPE_NIL:
		return
	if _progress:
		var frac: float = CampaignDB.progress_fraction()
		_progress.set_progress(frac, int(round(frac * 100.0)))
	if _progress_label:
		_progress_label.text = _progress_text()

func _progress_text() -> String:
	var done: int = CampaignDB.fight_index
	var total: int = CampaignDB.fights_total()
	if CampaignDB.is_current_complete():
		return "Campaign complete — %d / %d fights" % [done, total]
	var f: Dictionary = CampaignDB.current_fight()
	var boss := "  (BOSS)" if bool(f.get("is_boss", false)) else ""
	return "Next: fight %d of %d%s" % [done + 1, total, boss]

# ---------------------------------------------------------------------------
# Object visuals
# ---------------------------------------------------------------------------
func _object_color(action: String) -> Color:
	match action:
		"shop":
			return Color(0.85, 0.2, 0.2)
		"training":
			return Color(0.2, 0.6, 0.85)
		"campaign":
			if typeof(CampaignDB) != TYPE_NIL and CampaignDB.is_current_complete():
				return Color(0.6, 0.6, 0.6)
			return Color(0.9, 0.9, 0.95)
	return Color(0.5, 0.5, 0.5)

func _object_label(action: String) -> String:
	match action:
		"shop":
			return "BLIMP (Shop)"
		"training":
			return "IGLOO (Training)"
		"campaign":
			if typeof(CampaignDB) != TYPE_NIL and CampaignDB.is_current_complete():
				if CampaignDB.needs_choice():
					return "EXPANSE (choose path)"
				return "EXPANSE (cleared)"
			return "EXPANSE (Campaign Battle)"
	return action

# ---------------------------------------------------------------------------
# Input (hit-test the map objects, like the old overworld)
# ---------------------------------------------------------------------------
func _gui_input(event: InputEvent) -> void:
	if _fork_overlay != null:
		return   # the fork chooser is modal; ignore map clicks behind it
	if event is InputEventMouseButton \
	and event.button_index == MOUSE_BUTTON_LEFT \
	and event.pressed:
		var pos: Vector2 = event.position
		for o in _objects:
			if (o["rect"] as Rect2).has_point(pos):
				_do(str(o["action"]))
				accept_event()
				return

func _do(action: String) -> void:
	match action:
		"shop":
			GameManager.go_to_shop()
		"training":
			GameManager.go_to_training()
		"campaign":
			if typeof(CampaignDB) != TYPE_NIL and CampaignDB.is_current_complete():
				# Finished: either open the fork chooser or (at the end) do nothing.
				if CampaignDB.needs_choice():
					_show_fork(CampaignDB.get_current())
			else:
				GameManager.go_to_campaign_battle()

# ---------------------------------------------------------------------------
# Fork chooser (shown when a finished campaign has more than one next)
# ---------------------------------------------------------------------------
func _show_fork(camp: Campaign) -> void:
	if _fork_overlay != null or camp == null:
		return
	var overlay := Panel.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.6)
	overlay.add_theme_stylebox_override("panel", sb)
	add_child(overlay)
	_fork_overlay = overlay

	var box := VBoxContainer.new()
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.anchor_top = 0.5
	box.anchor_bottom = 0.5
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.add_theme_constant_override("separation", 12)
	overlay.add_child(box)

	var q := Label.new()
	q.text = "%s cleared!  Choose your path:" % camp.display_name
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	q.add_theme_font_size_override("font_size", 22)
	q.add_theme_color_override("font_color", Color(1, 1, 1))
	box.add_child(q)

	for nid in camp.next_ids:
		var nc: Campaign = CampaignDB.get_campaign(nid)
		var b := Button.new()
		b.text = nc.display_name if nc else nid
		b.custom_minimum_size = Vector2(300, 46)
		b.pressed.connect(_on_fork_pick.bind(nid))
		box.add_child(b)

func _on_fork_pick(next_id: String) -> void:
	CampaignDB.advance_to(next_id)
	GameManager.go_to_overworld()

# ---------------------------------------------------------------------------
# Map-end note
# ---------------------------------------------------------------------------
func _show_final(camp: Campaign) -> void:
	var lbl := Label.new()
	lbl.text = "%s — Campaign Complete!" % (camp.display_name if camp else "")
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 26)
	lbl.add_theme_color_override("font_color", Color(1, 0.9, 0.5))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	lbl.add_theme_constant_override("outline_size", 6)
	lbl.anchor_left = 0.15
	lbl.anchor_right = 0.85
	lbl.anchor_top = 0.12
	lbl.anchor_bottom = 0.20
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(lbl)
