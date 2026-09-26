class_name CombatLog
extends Control

## ============================================================================
## COMBAT LOG  —  a floating debug terminal of everything that happens (rev31)
## ============================================================================
## One line per RESOLVED ability use, for EVERY combatant — player, ally and
## enemy alike. It reads its lines from combat.gd's `_use_ability`, which is
## caster-agnostic, so nothing here has to know or care who acted: if a unit's
## ability resolved, it is in the log.
##
## WHY IT EXISTS. The Output panel already prints all of this, but it is
## interleaved with the AI ledger, the buff tick and everything else Godot is
## saying, and it is not on screen while you are playing. This is the same
## information, in the fight, in order, colour-coded by side — which is the only
## way to actually see whether an enemy is choosing sensibly.
##
## DEBUG-ONLY, gated at BUILD time (CORE_PRIMER §5B): with
## GameManager.debug_enabled false, combat never constructs this node at all.
## There is no runtime `visible` check to forget — the panel does not exist.
##
## FLOATING: drag it by its title bar, resize it from the grip in its
## bottom-right corner, collapse it to just the title bar with the [-] button,
## clear it with [x]. Position and size are per-fight; it does not persist.
##
## class_name global — RESTART Godot once after adding this script.
## ----------------------------------------------------------------------------

# --- geometry ---------------------------------------------------------------
const DEFAULT_SIZE := Vector2(430.0, 236.0)
const MIN_SIZE     := Vector2(240.0, 96.0)
const MARGIN       := 14.0     # gap from the viewport edge at its starting position
const BOTTOM_PANEL_FRAC := 0.15  # combat's bottom panel (dialogue) — the log starts above it
const HEADER_H     := 22.0
const PAD          := 8.0
const GRIP         := 14.0     # size of the bottom-right resize grip

## Lines kept before the oldest are dropped. A long fight is thousands of turns;
## the panel is for reading the last few, not for archaeology (that is the
## Output log, which keeps everything).
const MAX_LINES := 300

# --- palette (matched to TurnTimeline so the two overlays read as one UI) ----
const BG          := Color(0.07, 0.07, 0.10, 0.86)
const BG_HEADER   := Color(1.0, 1.0, 1.0, 0.07)
const BORDER      := Color(1.0, 1.0, 1.0, 0.13)
const GRIP_COL    := Color(1.0, 1.0, 1.0, 0.35)
const TITLE_COL   := Color(0.72, 0.76, 0.84)
const BODY_COL    := Color(0.82, 0.84, 0.90)
const DIM_COL     := Color(0.52, 0.55, 0.62)
## Speaker colours by side. Deliberately NOT the unit's model_color() — that is a
## name hash and can land on anything, including near-black.
const PLAYER_COL  := Color(0.60, 0.82, 1.00)
const ALLY_COL    := Color(0.60, 0.90, 0.68)
const ENEMY_COL   := Color(1.00, 0.55, 0.48)

const TEXT_SIZE  := 12
const TITLE_SIZE := 10

## Mirrors combat.gd's team constants. Only used to pick a speaker colour.
const TEAM_PLAYER := 0
const TEAM_ALLY := 1
const TEAM_ENEMY := 2

var _panel: Panel
var _header: Panel
var _title: Label
var _text: RichTextLabel
var _collapse_btn: Button
var _grip: Control

var _collapsed := false
var _expanded_size := DEFAULT_SIZE
var _dragging := false
var _resizing := false
var _drag_from := Vector2.ZERO
var _lines := 0

# ----------------------------------------------------------------------------
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP   # its own rect only; units behind stay clickable
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	size = DEFAULT_SIZE
	_expanded_size = DEFAULT_SIZE
	_build()
	_place_bottom_left()

func _build() -> void:
	_panel = Panel.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG
	sb.border_color = BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)

	# --- title bar (the drag handle) ---
	_header = Panel.new()
	_header.mouse_filter = Control.MOUSE_FILTER_STOP
	_header.anchor_left = 0.0
	_header.anchor_right = 1.0
	_header.anchor_top = 0.0
	_header.anchor_bottom = 0.0
	_header.offset_top = 0.0
	_header.offset_bottom = HEADER_H
	var hsb := StyleBoxFlat.new()
	hsb.bg_color = BG_HEADER
	hsb.set_corner_radius_all(3)
	_header.add_theme_stylebox_override("panel", hsb)
	_header.gui_input.connect(_on_header_input)
	add_child(_header)

	_title = Label.new()
	_title.text = "COMBAT LOG"
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.add_theme_color_override("font_color", TITLE_COL)
	_title.add_theme_font_size_override("font_size", TITLE_SIZE)
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_title.offset_left = PAD
	_header.add_child(_title)

	var clear_btn := _mini_button("x", "Clear the log")
	clear_btn.anchor_left = 1.0
	clear_btn.anchor_right = 1.0
	clear_btn.offset_left = -22.0
	clear_btn.offset_right = -4.0
	clear_btn.pressed.connect(clear_log)
	_header.add_child(clear_btn)

	_collapse_btn = _mini_button("–", "Collapse / expand")
	_collapse_btn.anchor_left = 1.0
	_collapse_btn.anchor_right = 1.0
	_collapse_btn.offset_left = -42.0
	_collapse_btn.offset_right = -24.0
	_collapse_btn.pressed.connect(toggle_collapsed)
	_header.add_child(_collapse_btn)

	# --- the terminal itself ---
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.scroll_following = true          # stay pinned to the newest line
	_text.selection_enabled = true         # so a line can be copied into a bug report
	_text.fit_content = false
	_text.mouse_filter = Control.MOUSE_FILTER_STOP
	_text.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_text.offset_left = PAD
	_text.offset_right = -PAD
	_text.offset_top = HEADER_H + 2.0
	_text.offset_bottom = -PAD * 0.5
	_text.add_theme_color_override("default_color", BODY_COL)
	_text.add_theme_font_size_override("normal_font_size", TEXT_SIZE)
	_text.add_theme_font_size_override("bold_font_size", TEXT_SIZE)
	# A terminal wants a terminal face. SystemFont falls back to the theme font on
	# any machine that has none of these, so this is safe to ask for.
	var mono := _mono_font()
	_text.add_theme_font_override("normal_font", mono)
	_text.add_theme_font_override("bold_font", mono)
	add_child(_text)

	# --- resize grip ---
	_grip = Control.new()
	_grip.mouse_filter = Control.MOUSE_FILTER_STOP
	_grip.anchor_left = 1.0
	_grip.anchor_top = 1.0
	_grip.anchor_right = 1.0
	_grip.anchor_bottom = 1.0
	_grip.offset_left = -GRIP
	_grip.offset_top = -GRIP
	_grip.offset_right = 0.0
	_grip.offset_bottom = 0.0
	_grip.mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
	_grip.gui_input.connect(_on_grip_input)
	_grip.draw.connect(_draw_grip)
	add_child(_grip)

## ONE SystemFont for the whole session (perf, 2026-09-25). Building a fresh one in
## every fight meant an OS font lookup, a font-file load and new glyph caches per
## fight, all thrown away when the fight ended.
static var _mono: SystemFont = null

static func _mono_font() -> SystemFont:
	if _mono == null:
		_mono = SystemFont.new()
		_mono.font_names = PackedStringArray(["Consolas", "Cascadia Mono", "DejaVu Sans Mono", "Courier New", "monospace"])
	return _mono

func _mini_button(label: String, tip: String) -> Button:
	var b := Button.new()
	b.text = label
	b.tooltip_text = tip
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", TITLE_SIZE)
	b.add_theme_color_override("font_color", TITLE_COL)
	b.anchor_top = 0.0
	b.anchor_bottom = 1.0
	b.offset_top = 2.0
	b.offset_bottom = -2.0
	return b

func _draw_grip() -> void:
	# Three short diagonals, the usual "you can drag this corner" hint.
	for i in 3:
		var o := 3.0 + float(i) * 4.0
		_grip.draw_line(Vector2(GRIP - o, GRIP - 2.0), Vector2(GRIP - 2.0, GRIP - o), GRIP_COL, 1.0)

## Bottom-left by default. That corner is the only one nothing already occupies:
## the turn timeline is top-left, the health bars are the top band, the End Turn
## button is bottom-RIGHT, and the party column sits well above this at the
## default window size. Drag it anywhere if a fight proves otherwise.
func _place_bottom_left() -> void:
	var vp := get_viewport_rect().size
	# rev33: start ABOVE combat's bottom panel (the bottom 15%), which now carries the
	# dialogue boxes — a log parked over them would hide the story.
	position = Vector2(MARGIN, vp.y * (1.0 - BOTTOM_PANEL_FRAC) - size.y - MARGIN)

# ----------------------------------------------------------------------------
# Writing
# ----------------------------------------------------------------------------
## The core call: ONE resolved ability use. `detail` is whatever the resolving
## branch has to say about the outcome ("hits Sonny for 12 ice", "RESISTED",
## "shields itself for 30"); pass "" for a bare "X used Y".
func add_action(actor_name: String, team: int, ability_name: String, detail: String) -> void:
	var col := speaker_color(team)
	var line := "[color=#%s]%s[/color]  [b]%s[/b]" % [col.to_html(false), _esc(actor_name), _esc(ability_name)]
	if detail != "":
		line += "  [color=#%s]%s[/color]" % [DIM_COL.to_html(false), _esc(detail)]
	_append(line)

## A dim separator when a unit's turn begins, so the log reads as turns rather
## than as an undifferentiated stream.
func add_turn_header(actor_name: String, team: int, turn_no: int, clock: float) -> void:
	var col := speaker_color(team)
	_append("[color=#%s]——[/color] [color=#%s]%s[/color] [color=#%s]· turn %d · clock %d[/color]" % [
		DIM_COL.to_html(false), col.to_html(false), _esc(actor_name),
		DIM_COL.to_html(false), turn_no, int(round(clock))])

## Anything that is not an ability use — "passes", "is stunned", "battle start".
func add_note(text: String, col: Color = DIM_COL) -> void:
	_append("[color=#%s]%s[/color]" % [col.to_html(false), _esc(text)])

## Everything written here is authored content (a character name, an ability's
## display_name, a buff id), so a stray "[" is a formatting accident rather than
## an attack — but an accident that would silently eat the rest of the line as a
## malformed tag, which is exactly the sort of thing you would waste an hour on.
static func _esc(text: String) -> String:
	return text.replace("[", "[lb]")

func _append(bbcode_line: String) -> void:
	if _text == null:
		return
	if _lines > 0:
		_text.newline()
	_text.append_text(bbcode_line)
	_lines += 1
	# Trim from the FRONT off the node's real paragraph count, not off our own
	# counter — a dropped paragraph has to leave the RichTextLabel's store, or a
	# long fight grows it without bound however little of it is on screen.
	while _text.get_paragraph_count() > MAX_LINES:
		if not _text.remove_paragraph(0):
			break

func clear_log() -> void:
	if _text:
		_text.clear()
	_lines = 0

# ----------------------------------------------------------------------------
# Chrome
# ----------------------------------------------------------------------------
static func speaker_color(team: int) -> Color:
	match team:
		TEAM_ENEMY: return ENEMY_COL
		TEAM_ALLY:  return ALLY_COL
	return PLAYER_COL

func toggle_collapsed() -> void:
	_collapsed = not _collapsed
	if _collapsed:
		_expanded_size = size
		size = Vector2(size.x, HEADER_H)
	else:
		size = _expanded_size
	if _text:
		_text.visible = not _collapsed
	if _grip:
		_grip.visible = not _collapsed
	if _collapse_btn:
		_collapse_btn.text = "+" if _collapsed else "–"

func _on_header_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			_drag_from = event.position
		else:
			_dragging = false
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		position += event.position - _drag_from
		_clamp_to_viewport()
		accept_event()

func _on_grip_input(event: InputEvent) -> void:
	if _collapsed:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_resizing = event.pressed
		accept_event()
	elif event is InputEventMouseMotion and _resizing:
		size = Vector2(maxf(MIN_SIZE.x, size.x + event.relative.x), maxf(MIN_SIZE.y, size.y + event.relative.y))
		_expanded_size = size
		_clamp_to_viewport()
		accept_event()

## Never let it be dragged fully off screen — a debug panel you cannot get back
## is worse than no debug panel.
func _clamp_to_viewport() -> void:
	var vp := get_viewport_rect().size
	position.x = clampf(position.x, -size.x + 60.0, vp.x - 60.0)
	position.y = clampf(position.y, 0.0, vp.y - HEADER_H)
