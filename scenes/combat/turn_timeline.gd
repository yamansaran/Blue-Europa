class_name TurnTimeline
extends Control

## ============================================================================
## TURN TIMELINE  —  the scrolling analogue turn counter (rev30)
## ============================================================================
## A horizontal, continuously scrolling counter — a mechanical odometer laid on
## its side. ONE ROW PER ACTING UNIT. Each row is a repeating sequence of bars;
## a bar is exactly that unit's turn INTERVAL long (CombatTimeline), so:
##
##      shorter bar  =  faster character  =  more frequent turns
##
## Every row scrolls at the SAME rate, so the relative bar lengths ARE the turn
## frequencies — the display doesn't compute "turns per second", the geometry is
## the statement. A fixed vertical MARKER runs through every row; a unit takes
## its turn the instant one of its bars' LEADING EDGES crosses that marker, and
## the bar then keeps travelling left and off the strip. The strip is wide enough
## to show roughly a third of a turn behind the marker and two and a half turns
## ahead of it, so you can read at a glance how soon everyone acts next.
##
## PURE DISPLAY. It owns no turn state: `units` are the live BattleCharacters and
## every bar position is derived from `u.next_turn_at` + `u.turn_interval()`,
## both read fresh each frame. So a haste buff visibly SHORTENS a unit's bars in
## place, and combat.gd never has to tell this widget anything except the clock.
##
## Driven by combat.gd: setup(units) once, then `await scroll_to(clock, dt)` for
## each advance and set_active(u) when a unit's turn begins.
## ----------------------------------------------------------------------------

# --- geometry ---------------------------------------------------------------
const ROW_H       := 13.0    # height of one unit's bar row
const ROW_SEP     := 4.0     # vertical gap between rows
const GUTTER      := 66.0    # left name column
const STRIP_W     := 300.0   # width of the scrolling strip
const PAD         := 7.0     # padding inside the backing panel
const SIDE_GAP    := 5.0     # extra gap between the party block and the enemy block
const PPU         := 1.15    # PIXELS PER TICK — with STRIP_W 300 that is ~260 ticks visible
const MARKER_FRAC := 0.30    # marker position across the strip (0.30 = a third of a turn of past)
const SEG_GAP     := 3.0     # pixel gap drawn between consecutive bars
const CAP_W       := 3.0     # width of the bright leading-edge cap
const MAX_SEGMENTS := 64     # per-row draw guard for very short intervals

# --- animation --------------------------------------------------------------
## Seconds to scroll one FULL default turn (CombatTimeline.TICKS_PER_TURN). Short
## hops are proportionally quicker, floored so they still read as motion.
const SCROLL_TIME     := 0.30
const SCROLL_TIME_MIN := 0.07

# --- palette ----------------------------------------------------------------
const BG           := Color(0.07, 0.07, 0.10, 0.80)
const BORDER       := Color(1.0, 1.0, 1.0, 0.13)
const ROW_BG       := Color(1.0, 1.0, 1.0, 0.05)
const ROW_BG_FOE   := Color(0.85, 0.25, 0.25, 0.09)
const ROW_BG_ACTIVE:= Color(1.0, 0.95, 0.70, 0.16)
const MARKER_COL   := Color(1.0, 1.0, 1.0, 0.92)
const DIVIDER_COL  := Color(1.0, 1.0, 1.0, 0.10)
const NAME_COL     := Color(0.86, 0.88, 0.93)
const NAME_COL_DEAD:= Color(0.45, 0.45, 0.48)
const DEAD_BAR     := Color(0.30, 0.30, 0.33, 0.55)
const NAME_SIZE    := 11
const NAME_CHARS   := 9

## Mirrors combat.gd's TEAM_ENEMY. Only used to sort rows and tint the enemy
## block; nothing about the timeline's behaviour depends on side.
const TEAM_ENEMY := 2

## Every BattleCharacter of the fight, party first then enemies. Set by setup().
var _all: Array = []
## The rows actually DRAWN this frame, in draw order (_refresh_rows). DEAD-ROW RULE
## (dev, 2026-09-25): a dead party unit (the player, allies) keeps its row, greyed; a
## dead ENEMY's row is REMOVED — and comes back if the enemy is ever revived — unless
## its body sets `revives` (a built-in revive mechanic), which greys it like an ally.
var units: Array = []
## The DISPLAY clock, in ticks. Tweened by scroll_to(); combat.gd's own _clock is
## the authority and this only ever chases it.
## Redraws itself on every change (perf, 2026-09-25) so a scroll animates at full rate
## while the idle poll in _process can run slowly.
var clock: float = 0.0:
	set(v):
		clock = v
		queue_redraw()
## The unit currently taking its turn, so its row can be highlighted. May be null
## between turns.
var active: BattleCharacter = null

var _party_rows: int = 0

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------
## Point the widget at the fight's units and size it to fit them. Party units are
## listed first, enemies below, with a divider between the two blocks.
func setup(all_units: Array) -> void:
	_all.clear()
	for u in all_units:
		if u is BattleCharacter and u.team != TEAM_ENEMY:
			_all.append(u)
	for u in all_units:
		if u is BattleCharacter and u.team == TEAM_ENEMY:
			_all.append(u)
	_refresh_rows()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	custom_minimum_size = desired_size()
	size = desired_size()
	set_process(true)
	queue_redraw()

## Rebuild the drawn rows from _all by the dead-row rule. Returns true when the row
## count changed (the widget then resizes — it grows back when an enemy is revived).
func _refresh_rows() -> bool:
	var before := units.size()
	units.clear()
	_party_rows = 0
	for u in _all:
		var bc: BattleCharacter = u
		if bc == null or not is_instance_valid(bc):
			continue
		if bc.team != TEAM_ENEMY:
			units.append(bc)
			_party_rows += 1
		elif _row_shown(bc):
			units.append(bc)
	return units.size() != before

## An ENEMY row is drawn while the enemy is alive, or dead but flagged `revives`.
static func _row_shown(u: BattleCharacter) -> bool:
	if u.is_alive():
		return true
	return u.body != null and bool(u.body.get("revives"))

## The pixel size this widget wants for its current unit list. combat.gd reads it
## to place the overlay.
func desired_size() -> Vector2:
	var rows := maxi(1, units.size())
	var h := PAD * 2.0 + float(rows) * ROW_H + float(rows - 1) * ROW_SEP
	if _party_rows > 0 and _party_rows < units.size():
		h += SIDE_GAP
	return Vector2(GUTTER + STRIP_W + PAD * 2.0, h)

func set_active(u: BattleCharacter) -> void:
	active = u
	queue_redraw()

# ---------------------------------------------------------------------------
# Scrolling
# ---------------------------------------------------------------------------
## Animate the display clock to `target`. `dt` is how far the fight's clock
## actually jumped, so a short hop scrolls proportionally faster. ALWAYS a
## coroutine — callers can `await` it unconditionally.
func scroll_to(target: float, dt: float) -> void:
	if is_equal_approx(clock, target):
		clock = target
		queue_redraw()
		await get_tree().process_frame
		return
	var frac: float = absf(dt) / CombatTimeline.TICKS_PER_TURN
	var dur := clampf(frac * SCROLL_TIME, SCROLL_TIME_MIN, SCROLL_TIME)
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(self, "clock", target, dur)
	await tw.finished
	clock = target
	queue_redraw()

## Jump with no animation (battle start, or a rebuild).
func snap_to(target: float) -> void:
	clock = target
	queue_redraw()

## The idle poll's period (perf, 2026-09-25). It used to redraw EVERY frame for the
## whole fight — each redraw re-reads every unit's interval (full basket scans) and
## redraws the names. Scrolls still animate every frame (the `clock` setter); combat's
## _refresh_turn_ui redraws at once after every action; this poll only has to catch
## what changes with no signal (a death, a revive, a haste landing), and 10 Hz does.
const IDLE_REFRESH := 0.1
var _idle_acc := 0.0

func _process(delta: float) -> void:
	_idle_acc += delta
	if _idle_acc < IDLE_REFRESH:
		return
	_idle_acc = 0.0
	# Keeps the bars honest without combat.gd having to signal every stat change that
	# moves an interval. Rows are re-derived here too, so a death or a revive needs no
	# signal from combat.
	if _refresh_rows():
		var ds := desired_size()
		custom_minimum_size = ds
		size = ds
	queue_redraw()

# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------
func _draw() -> void:
	if units.is_empty():
		return
	var font := get_theme_default_font()
	var strip_x := GUTTER + PAD
	var strip_w := maxf(20.0, size.x - strip_x - PAD)
	var marker_x := strip_x + strip_w * MARKER_FRAC

	# backing panel
	draw_rect(Rect2(Vector2.ZERO, size), BG, true)
	draw_rect(Rect2(Vector2.ZERO, size), BORDER, false, 1.0)

	var y := PAD
	for i in units.size():
		var u: BattleCharacter = units[i]
		# gap + divider between the party block and the enemy block
		if i == _party_rows and _party_rows > 0:
			var dy := y + SIDE_GAP * 0.5 - ROW_SEP * 0.5
			draw_line(Vector2(PAD, dy), Vector2(size.x - PAD, dy), DIVIDER_COL, 1.0)
			y += SIDE_GAP
		_draw_row(u, i, y, strip_x, strip_w, marker_x, font)
		y += ROW_H + ROW_SEP

	# THE MARKER, last so it sits over every bar: a full-height line plus a small
	# pointer at the top. A unit acts when a bar's leading edge reaches this.
	draw_line(Vector2(marker_x, 2.0), Vector2(marker_x, size.y - 2.0), MARKER_COL, 2.0)
	draw_colored_polygon(PackedVector2Array([
		Vector2(marker_x - 4.0, 1.0),
		Vector2(marker_x + 4.0, 1.0),
		Vector2(marker_x, 6.0),
	]), MARKER_COL)

func _draw_row(u: BattleCharacter, index: int, y: float, strip_x: float, strip_w: float, marker_x: float, font: Font) -> void:
	var alive: bool = u.is_alive()
	var is_foe: bool = u.team == TEAM_ENEMY

	# row background: side tint, brightened while this unit is acting
	var row_bg := ROW_BG_FOE if is_foe else ROW_BG
	if u == active and alive:
		row_bg = ROW_BG_ACTIVE
	draw_rect(Rect2(strip_x, y, strip_w, ROW_H), row_bg, true)

	# name gutter
	var label := u.unit_name
	if label.length() > NAME_CHARS:
		label = label.substr(0, NAME_CHARS - 1) + "."
	draw_string(font, Vector2(PAD, y + ROW_H - 2.0), label,
		HORIZONTAL_ALIGNMENT_LEFT, GUTTER - 4.0, NAME_SIZE,
		NAME_COL if alive else NAME_COL_DEAD)

	if not alive:
		# A downed unit keeps its row (so the layout doesn't jump) but has no
		# scheduled turns left to draw.
		draw_rect(Rect2(strip_x, y + ROW_H * 0.5 - 1.0, strip_w, 2.0), DEAD_BAR, true)
		return

	var col: Color = u.body.model_color() if u.body else Color.GRAY
	var cap_col := col.lightened(0.55)
	var iv: float = maxf(1.0, u.turn_interval())
	var seg_w := iv * PPU
	var strip_r := strip_x + strip_w

	# The clock value sitting at the LEFT edge of the strip. Start one bar before
	# it so the bar entering from the left is drawn clipped, not omitted — that is
	# what makes the motion read as continuous.
	var left_clock: float = clock - (marker_x - strip_x) / PPU
	var k: int = int(floor((left_clock - u.next_turn_at) / iv)) - 1
	var edge: float = u.next_turn_at + float(k) * iv

	for _n in MAX_SEGMENTS:
		var x := marker_x + (edge - clock) * PPU
		if x > strip_r:
			break
		var x0 := maxf(x, strip_x)
		var x1 := minf(x + seg_w - SEG_GAP, strip_r)
		if x1 > x0:
			draw_rect(Rect2(x0, y, x1 - x0, ROW_H), col, true)
			# the LEADING EDGE cap — the part that actually triggers the turn
			if x >= strip_x and x <= strip_r - CAP_W:
				draw_rect(Rect2(x, y, CAP_W, ROW_H), cap_col, true)
		edge += iv
