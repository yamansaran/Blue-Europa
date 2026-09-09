class_name BattleGridOverlay
extends Control
## DEBUG ONLY (rev32). Draws all twenty formation slots — both sides, both columns
## — as outlined boxes with their slot name, so the grid can be read while playing.
## Occupied slots get a faint fill and their occupant's name; empty ones are drawn
## dimmer, which is what makes the reserved FRONT column visible as a real thing
## rather than as an absence.
##
## Built ONLY when GameManager.is_debug() is on (combat.gd _build_grid), and added
## as the FIRST child of the battle panel so every model draws over it. Pure
## display: it owns no slot state, it just reads the two BattleGrid instances.

const EMPTY_LINE := 1.0
const FULL_LINE := 2.0

var _grids: Array = []          # [party BattleGrid, foes BattleGrid]

func setup(party_grid: BattleGrid, foe_grid: BattleGrid) -> void:
	_grids = [party_grid, foe_grid]
	queue_redraw()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(queue_redraw)

func _side_color(p_side: int) -> Color:
	return Color(0.42, 0.72, 1.0) if p_side == BattleGrid.SIDE_PARTY else Color(1.0, 0.45, 0.42)

func _draw() -> void:
	if _grids.is_empty() or size.x <= 0.0 or size.y <= 0.0:
		return
	var font := ThemeDB.fallback_font
	var box := BattleGrid.SLOT_SIZE * BattleGrid.MODEL_SCALE

	for p_side in [BattleGrid.SIDE_PARTY, BattleGrid.SIDE_FOES]:
		var grid: BattleGrid = _grids[p_side]
		var tint := _side_color(p_side)
		for col in BattleGrid.COLS:
			for row in BattleGrid.ROWS:
				var a := BattleGrid.anchor_for(p_side, col, row)
				var centre := Vector2(a.x * size.x, a.y * size.y)
				var rect := Rect2(centre - box * 0.5, box)
				var taken = grid.at(col, row) if grid != null else null

				if taken != null:
					draw_rect(rect, Color(tint.r, tint.g, tint.b, 0.10), true)
					draw_rect(rect, Color(tint.r, tint.g, tint.b, 0.85), false, FULL_LINE)
				else:
					# The FRONT column is drawn faintest of all — it is reserved, not free.
					var a_line: float = 0.22 if col == BattleGrid.FRONT else 0.38
					draw_rect(rect, Color(tint.r, tint.g, tint.b, a_line), false, EMPTY_LINE)

				# Centre tick, so an empty slot still has a readable anchor point.
				draw_line(centre + Vector2(-4, 0), centre + Vector2(4, 0), Color(tint.r, tint.g, tint.b, 0.5), 1.0)
				draw_line(centre + Vector2(0, -4), centre + Vector2(0, 4), Color(tint.r, tint.g, tint.b, 0.5), 1.0)

				var label := BattleGrid.slot_name(col, row)
				if taken != null:
					label += "  " + str(taken.unit_name)
				var lc := Color(tint.r, tint.g, tint.b, 0.95 if taken != null else 0.55)
				draw_string(font, rect.position + Vector2(3, 11), label,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 10, lc)
