class_name AbilityTooltip
extends HoverPanel

## ============================================================================
## ABILITY TOOLTIP  —  the shared ability hover card (now on the HoverPanel core)
## ============================================================================
## The single tooltip used everywhere an ability is hovered: the combat wheel,
## the abilities-screen wheel, the ability pool chips, and skill-tree nodes. It is
## now a thin adapter over HoverPanel — HoverPanel owns the look, placement, fade,
## and the KEYWORD COLOURING (element names in the description are tinted via
## Keywords/ElementColors). This file just turns an Ability into the four rows:
##   1. NAME    — light gray, shows INSTANTLY.
##   2. POINTS  — muted gold "x / y points" (skill-tree hovers only; hidden else),
##                shown instantly alongside the name.
##   3. COST    — grayish blue, "Cost: <phrase>" (+ "CD: n"); fades in after a delay.
##   4. DESC    — black, the full description with element keywords COLOURED; fades
##                in with the cost.
##
## USAGE is unchanged from before (each host owns one):
##     var tip := AbilityTooltip.new()
##     add_child(tip)
##     tip.show_for(ability, some_global_rect)          # null ability -> hides
##     tip.show_for(ability, rect, "1 / 3 points")       # skill-tree variant
##     tip.hide_tip()
##
## class_name global. Because it now EXTENDS HoverPanel, add hover_panel.gd (and
## keywords.gd) BEFORE this file and RESTART Godot once.
## ----------------------------------------------------------------------------

const TIP_WIDTH := 200.0
const TIP_DELAY := 0.25          # hover time before cost + description appear

const POINTS_BG := Color(0.62, 0.55, 0.30)  # muted gold band (skill-tree only)
const POINTS_TX := Color(0.10, 0.08, 0.02)

var _ab: Ability = null


func _ready() -> void:
	content_width = TIP_WIDTH
	_ensure_built()


## Show the tooltip for `ab`, positioned beside `anchor_global` (a global Rect2 —
## usually the hovered widget's global rect). Pass null to hide. `points_text`
## fills the optional gold "Points" row (skill tree); leave "" to hide that row.
func show_for(ab: Ability, anchor_global: Rect2, points_text := "") -> void:
	if ab == null:
		hide_tip()
		return
	_ab = ab
	var rows := [
		{"text": ab.display_name, "bg": NAME_BG, "fg": NAME_TX, "stage": 0},
		{"text": points_text, "bg": POINTS_BG, "fg": POINTS_TX, "stage": 0,
			"visible": points_text != ""},
		{"text": ab.cost_text(), "bg": META_BG, "fg": META_TX, "stage": 1},
		{"text": ab.description, "bg": DESC_BG, "fg": DESC_TX, "stage": 1,
			"wrap": true, "rich": true},   # rich -> element keywords are coloured
	]
	# key on the ability id so re-showing the SAME ability (e.g. a skill node
	# refreshing its point count on invest) updates the rows in place instead of
	# restarting the reveal.
	show_rows(rows, anchor_global, TIP_DELAY, "ability:" + String(ab.id))


func hide_tip() -> void:
	_ab = null
	hide_panel()
