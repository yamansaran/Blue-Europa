class_name BattleGrid
extends RefCounted
## THE FORMATION GRID (rev32). Each SIDE of a fight owns one of these: 5 ROWS tall
## by 2 COLUMNS deep, so ten slots per side and twenty on the field.
##
##   COL 0 = BACK   — where everybody starts. The player is the CENTRE of it.
##   COL 1 = FRONT  — reserved for TEMPORARY SUMMONS; nothing fills it by default.
##
## "Front" means "nearer the enemy", so the two front columns face each other
## across the middle of the screen and the two back columns hug the outer edges.
## The party faces RIGHT (facing +1), the foes face LEFT (facing -1); every piece
## of geometry below is written once for the party and mirrored by that sign.
##
## THIS IS SLOTS AND DATA ONLY. Nothing in combat reads a unit's row or column to
## decide anything yet — no row-restricted targeting, no back-row protection, no
## taunt. The point of landing the slots first is that those things can be written
## later against a grid that already exists and is already correct.
##
## OCCUPANCY lives on the instance (`slots`); GEOMETRY is static (anchor_for), so
## the debug overlay can draw an empty slot without asking anyone who is in it.

const ROWS := 5
const COLS := 2

const BACK := 0
const FRONT := 1

const SIDE_PARTY := 0
const SIDE_FOES := 1

## The slot the main character opens every fight in: the centre of the back column.
const PLAYER_ROW := 2

## The order rows are handed out in — CENTRE FIRST, then alternating one above,
## one below, one above, one below. So a party of five fills 2, 1, 3, 0, 4 and a
## party of two sits symmetrically about the centre instead of drifting upward.
const FILL_ORDER := [2, 1, 3, 0, 4]

## Nominal model box, before the unit's own size_scale. Kept here rather than read
## from combat.gd so the overlay can size a slot with no combat instance.
const SLOT_SIZE := Vector2(90, 140)

## Every model is drawn at 85% of its old size so five rows fit the battle band
## with a readable gap. Multiplies the unit's own size_scale, so a boss is still
## bigger than a mook by exactly the ratio its module asked for.
const MODEL_SCALE := 0.85

# ---- geometry, in BATTLE-PANEL anchor fractions -------------------------------
## x of the BACK column for the party. The foes' back column is its mirror (1 - x).
const BACK_X := 0.17
## How far FORWARD (toward the middle) the front column sits.
const COL_STEP := 0.13
## y of the centre row. Sits BELOW the panel's midpoint on purpose: the TurnTimeline
## widget is overlaid on the top-left of the battle area, and the party's top row
## has to clear it. If a fight ever has enough units to make that widget tall enough
## to reach the top row's head, CENTER_Y and ROW_STEP are the two knobs.
const CENTER_Y := 0.58
## Vertical gap between rows. Five rows of model do NOT fit the band without
## overlapping — 5 x 119px against a ~454px band — so they overlap by design; the
## stagger below plus the depth sort in combat.gd is what separates them. The span
## (4 x ROW_STEP) is tuned so the top and bottom rows stay inside the battle band
## at the shortest window the game runs at.
const ROW_STEP := 0.138
## DIAGONAL STAGGER. Each row down nudges the model this much further FORWARD, so
## a column reads as a slanted line receding into the screen rather than as a flat
## stack of overlapping boxes. Lower on screen = nearer the camera = drawn on top.
const ROW_STAGGER := 0.022

var side: int = SIDE_PARTY
## slots[col][row] -> BattleCharacter or null.
var slots: Array = []

func _init(p_side: int = SIDE_PARTY) -> void:
	side = p_side
	clear_all()

func clear_all() -> void:
	slots = []
	for _c in COLS:
		var col: Array = []
		col.resize(ROWS)
		col.fill(null)
		slots.append(col)

# ---- occupancy ----------------------------------------------------------------
func in_bounds(col: int, row: int) -> bool:
	return col >= 0 and col < COLS and row >= 0 and row < ROWS

func at(col: int, row: int):
	if not in_bounds(col, row):
		return null
	return slots[col][row]

func is_free(col: int, row: int) -> bool:
	return in_bounds(col, row) and slots[col][row] == null

## Put `u` in an EXPLICIT slot. Returns false (and changes nothing) if that slot is
## out of bounds or already taken by someone else.
func place(u, col: int, row: int) -> bool:
	if u == null or not in_bounds(col, row):
		return false
	var sitting = slots[col][row]
	if sitting != null and sitting != u:
		return false
	remove(u)
	slots[col][row] = u
	u.grid_col = col
	u.grid_row = row
	return true

## Hand `u` the next free slot: back column centre-out first, then the front
## column centre-out as OVERFLOW (a sixth party member has to stand somewhere).
## Returns false only when all ten slots on this side are taken.
func assign(u) -> bool:
	for col in COLS:
		for row in FILL_ORDER:
			if is_free(col, row):
				return place(u, col, row)
	return false

func remove(u) -> void:
	if u == null:
		return
	for col in COLS:
		for row in ROWS:
			if slots[col][row] == u:
				slots[col][row] = null
	u.grid_col = -1
	u.grid_row = -1

func occupants() -> Array:
	var out: Array = []
	for col in COLS:
		for row in ROWS:
			if slots[col][row] != null:
				out.append(slots[col][row])
	return out

## Everyone in one column, top row first. The seam a future "back row is protected
## while the front row holds" rule would read.
func column(col: int) -> Array:
	var out: Array = []
	if col < 0 or col >= COLS:
		return out
	for row in ROWS:
		if slots[col][row] != null:
			out.append(slots[col][row])
	return out

# ---- geometry (static: an empty slot has a position too) ----------------------
## +1 for the party (forward is right), -1 for the foes (forward is left).
static func facing(p_side: int) -> float:
	return 1.0 if p_side == SIDE_PARTY else -1.0

## The BATTLE-PANEL anchor point (both x and y as 0..1 fractions of the panel) for
## one slot. Everything about where a unit stands comes from here.
static func anchor_for(p_side: int, col: int, row: int) -> Vector2:
	var f := facing(p_side)
	var base_x: float = BACK_X if p_side == SIDE_PARTY else 1.0 - BACK_X
	var x: float = base_x + f * (float(col) * COL_STEP + float(row - PLAYER_ROW) * ROW_STAGGER)
	var y: float = CENTER_Y + float(row - PLAYER_ROW) * ROW_STEP
	return Vector2(x, y)

## Short slot label for the debug overlay / logs: B0..B4, F0..F4.
static func slot_name(col: int, row: int) -> String:
	return "%s%d" % ["B" if col == BACK else "F", row]
