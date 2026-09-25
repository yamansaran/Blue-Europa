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
## When the current campaign is finished it shows the ADVANCE popup — one button
## per campaign this one leads to. Nothing ever advances by itself: a single way
## on is a one-button popup, a real choice (c1's opening split, the level-5 fork)
## is two or three. At the end of the map there is a "Campaign Complete!" note
## instead.
## ----------------------------------------------------------------------------

var _objects: Array = []          # {name, rect, action}
var _fork_overlay: Control = null
## DEBUG ONLY (GameManager.is_debug): the fight-picker overlay opened from the small
## box on the campaign panel. Null whenever it is closed, and — like the fork chooser
## — modal: while either is up, clicks on the map itself are ignored.
var _debug_overlay: Control = null
# NOTE: the campaign PROGRESSION bar lives in the persistent toolbar (right
# panel), wired in shell.gd -> refresh_progress(). It is intentionally NOT drawn
# on this screen.

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var camp: Campaign = null
	if typeof(CampaignDB) != TYPE_NIL:
		camp = CampaignDB.get_current()
	_build(camp)
	if typeof(CampaignDB) != TYPE_NIL:
		if CampaignDB.can_advance():
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

	# --- debug-only map controls (GameManager.debug_enabled) ---
	# Built ONLY with the flag on, so with debug off these are not hidden buttons —
	# they do not exist. Each is a small control floating over the panel it belongs
	# to, added AFTER the panels so it sits on top and eats its own click before
	# _gui_input's hit-test ever sees it.
	if _debug_on():
		_add_debug_controls()

## True while the game's debug features are switched on (the one master flag,
## GameManager.debug_enabled — CORE_PRIMER §5B). Same shape as shell.gd's.
func _debug_on() -> bool:
	return typeof(GameManager) != TYPE_NIL and GameManager.has_method("is_debug") \
		and GameManager.is_debug()

## One small control per debug-able panel, positioned from that panel's own rect so
## a campaign that lays its overworld out differently still gets them in the right
## place. Skips any panel this campaign does not have.
func _add_debug_controls() -> void:
	_add_cheats_button()
	for o in _objects:
		var r: Rect2 = o["rect"]
		match str(o["action"]):
			"training":
				_add_float_button(r, "DUMMY", "Fight the practice dummy instead of a\nrolled training fight (debug)",
						_on_debug_dummy_pressed)
			"campaign":
				_add_float_button(r, "FIGHT ▾", "Choose which campaign fight is next —\nsets this zone's progress (debug)",
						_on_debug_fight_picker_pressed)

## DEBUG: the small floating "DEBUG" button in the overworld's top-right corner that
## opens / closes the cheats panel (level, god mode, skillful mode, money).
var _cheats: DebugCheatsPanel = null

func _add_cheats_button() -> void:
	var b := Button.new()
	b.text = "DEBUG"
	b.tooltip_text = "Level / god mode / skillful mode / money (debug)"
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	b.add_theme_font_size_override("font_size", 11)
	b.add_theme_color_override("font_color", Color(1.0, 0.6, 0.6))
	b.anchor_left = 1.0
	b.anchor_right = 1.0
	b.offset_left = -78
	b.offset_right = -10
	b.offset_top = 10
	b.offset_bottom = 34
	b.pressed.connect(_toggle_cheats)
	add_child(b)

func _toggle_cheats() -> void:
	if _cheats and is_instance_valid(_cheats):
		_cheats.queue_free()
		_cheats = null
		return
	_cheats = DebugCheatsPanel.new()
	add_child(_cheats)
	_cheats.anchor_left = 1.0
	_cheats.anchor_right = 1.0
	_cheats.offset_left = -380
	_cheats.offset_right = -10
	_cheats.offset_top = 40
	_cheats.grow_horizontal = Control.GROW_DIRECTION_BEGIN   # widen to the LEFT, never off-screen
	_cheats.closed.connect(func(): _cheats = null)

## A small button pinned to the TOP-LEFT corner of a map panel, overlapping it. The
## panel's own ColorRect is left completely untouched — the overlap is the point, the
## same way the shell's "CS" button rides on the Save button.
func _add_float_button(r: Rect2, text: String, tip: String, handler: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE            # never steal keyboard focus
	b.mouse_filter = Control.MOUSE_FILTER_STOP   # consume the click so the panel behind it doesn't also fire
	b.add_theme_font_size_override("font_size", 10)
	b.pressed.connect(handler)
	add_child(b)
	b.position = r.position + Vector2(4, 4)
	b.size = Vector2(62, 20)

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
				if CampaignDB.can_advance():
					return "EXPANSE (move on)"
				return "EXPANSE (cleared)"
			return "EXPANSE (Campaign Battle)"
	return action

# ---------------------------------------------------------------------------
# Input (hit-test the map objects, like the old overworld)
# ---------------------------------------------------------------------------
func _gui_input(event: InputEvent) -> void:
	if _fork_overlay != null or _debug_overlay != null:
		return   # the fork chooser / debug picker is modal; ignore map clicks behind it
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
				# Finished: re-open the advance popup, or (at the map end) do nothing.
				if CampaignDB.can_advance():
					_show_fork(CampaignDB.get_current())
			else:
				GameManager.go_to_campaign_battle()

# ---------------------------------------------------------------------------
# Advance popup (shown whenever a finished campaign has ANY next campaign —
# one button per next, so a single way on is still a deliberate click)
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
	var many: bool = camp.next_ids.size() > 1
	q.text = "%s cleared!  %s" % [camp.display_name,
			"Choose your path:" if many else "Press on to:"]
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
# DEBUG controls  (built only under GameManager.is_debug — see _add_debug_controls)
# ---------------------------------------------------------------------------
## The IGLOO's debug button: the unkillable practice dummy, bypassing the campaign's
## training pool. The normal igloo click now ROLLS a real fight out of that pool, and
## a real fight is no use for exercising a stat edit, a new buff or a damage formula —
## which is exactly what the dummy exists for.
func _on_debug_dummy_pressed() -> void:
	GameManager.go_to_training_dummy()

## The EXPANSE's debug box: pick which of this campaign's fights is the next one.
## Effectively an editor for the player's progress through the current zone — the
## cheapest way to reach fight 6 without playing fights 1-5, and the only way to see
## the post-boss advance popup on demand (pick "campaign complete" at the bottom).
func _on_debug_fight_picker_pressed() -> void:
	if _debug_overlay != null or _fork_overlay != null:
		return
	if typeof(CampaignDB) == TYPE_NIL:
		return
	var camp: Campaign = CampaignDB.get_current()
	if camp == null:
		return

	var overlay := Panel.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.72)
	overlay.add_theme_stylebox_override("panel", sb)
	add_child(overlay)
	_debug_overlay = overlay

	var box := VBoxContainer.new()
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.anchor_top = 0.5
	box.anchor_bottom = 0.5
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.add_theme_constant_override("separation", 6)
	overlay.add_child(box)

	var q := Label.new()
	q.text = "DEBUG — %s: set the next fight  (now %d/%d)" % [
			camp.display_name, CampaignDB.fight_index, camp.fight_count()]
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	q.add_theme_font_size_override("font_size", 18)
	q.add_theme_color_override("font_color", Color(1, 0.85, 0.5))
	box.add_child(q)

	# One button per fight. The index IS the progress value: choosing fight i means
	# "i fights are cleared", so the labels read 1-based and set the 0-based index.
	for i in camp.fight_count():
		var f: Dictionary = camp.fight_at(i)
		var b := Button.new()
		var boss_tag := "  ★" if bool(f.get("is_boss", false)) else ""
		var here := "  ←" if i == CampaignDB.fight_index else ""
		b.text = "%d.  %s%s%s" % [i + 1, str(f.get("name", f.get("id", "?"))), boss_tag, here]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(380, 30)
		b.pressed.connect(_on_debug_fight_picked.bind(i))
		box.add_child(b)

	# The one entry that is not a fight: everything cleared, which is what puts the
	# campaign into its completed state and makes the advance popup testable.
	var done := Button.new()
	done.text = "✔  campaign complete (show the advance popup)"
	done.custom_minimum_size = Vector2(380, 30)
	done.pressed.connect(_on_debug_fight_picked.bind(camp.fight_count()))
	box.add_child(done)

	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.custom_minimum_size = Vector2(380, 28)
	cancel.pressed.connect(_close_debug_overlay)
	box.add_child(cancel)

## Commit the picked index and rebuild the screen, so the EXPANSE panel's label and
## colour, the toolbar's progress bar and (if the campaign is now complete) the
## advance popup all reflect the new position immediately.
func _on_debug_fight_picked(index: int) -> void:
	CampaignDB.debug_set_fight_index(index)
	_close_debug_overlay()
	GameManager.go_to_overworld()

func _close_debug_overlay() -> void:
	if _debug_overlay != null:
		_debug_overlay.queue_free()
		_debug_overlay = null

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
