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

# The "next rank" panel (skill-tree only): a faded red band with yellow text that
# previews what the NEXT rank grants — or why it can't be taken yet.
const NEXTRANK_BG := Color(0.30, 0.08, 0.08, 0.92)  # faded red
const NEXTRANK_TX := Color(1.0, 0.88, 0.35)         # yellow

const NOT_LEARNED := "You have not yet learned this ability."
const MASTERED := "You have mastered this ability."

var _ab: Ability = null


func _ready() -> void:
	content_width = TIP_WIDTH
	_ensure_built()


## Show the tooltip for `ab`, positioned beside `anchor_global` (a global Rect2 —
## usually the hovered widget's global rect). Pass null to hide. `points_text`
## fills the optional gold "Points" row (skill tree); leave "" to hide that row.
## `rank` (>0) shows that rank's cost/description; 0 shows the plain rank-1 values.
## This is the wheel / ability-pool variant — no "next rank" panel.
func show_for(ab: Ability, anchor_global: Rect2, points_text := "", rank := 0) -> void:
	if ab == null:
		hide_tip()
		return
	_ab = ab
	var r := rank if rank > 0 else 1
	# Live scaling bonus from invested upgrade nodes (e.g. Sinewed -> Claw/Scour), so
	# the description shows the UPGRADED percentages via the "{scaling}" token.
	var bonus := _scaling_bonus_for(ab)
	var rows := [
		{"text": ab.display_name, "bg": NAME_BG, "fg": NAME_TX, "stage": 0},
		{"text": points_text, "bg": POINTS_BG, "fg": POINTS_TX, "stage": 0,
			"visible": points_text != ""},
		{"text": ab.cost_text_at(r), "bg": META_BG, "fg": META_TX, "stage": 1},
		{"text": ab.description_resolved(r, bonus), "bg": DESC_BG, "fg": DESC_TX, "stage": 1,
			"wrap": true, "rich": true},   # rich -> element keywords are coloured
	]
	# key on the ability id (+ a signature of the live bonus) so re-showing the SAME
	# ability refreshes the rows in place, and a change in the upgrade bonus (invest
	# Sinewed while hovering) re-renders the description instead of showing stale text.
	show_rows(rows, anchor_global, TIP_DELAY, "ability:" + String(ab.id) + _bonus_sig(bonus))


## SKILL-TREE variant. Adds two things over show_for: the current DESC panel reads
## for the currently-invested rank (or "not yet learned" at rank 0), and a final
## faded-red / yellow NEXT-RANK panel previews the next rank — or explains why it
## can't be taken ("mastered" when maxed, "requires level X" when the level gate is
## unmet). `points` = points invested here, `max_points` = the ability's cap,
## `required_level` / `level_ok` = the node's level gate and whether it's satisfied.
func show_for_node(ab: Ability, anchor_global: Rect2, points: int, max_points: int, required_level: int, level_ok: bool) -> void:
	if ab == null:
		hide_tip()
		return
	_ab = ab
	var learned := points > 0
	# Live scaling bonus from invested upgrade nodes, folded into the "{scaling}"
	# token (a no-op for descriptions without it).
	var bonus := _scaling_bonus_for(ab)
	# COST + current DESC read for the current rank (rank 1's values when unlearned,
	# so the panel still previews what the ability does).
	var shown_rank := points if learned else 1
	var desc_text := ab.description_resolved(shown_rank, bonus) if learned else NOT_LEARNED

	# The next-rank / status line.
	var next_text := ""
	if not level_ok:
		# Level-locked: still PREVIEW what the ability does (its rank-1 description) in
		# the description panel, then show the level requirement on the line below.
		# Previously the description panel showed only the "not learned" placeholder
		# here, so a locked node revealed the level gate but never what it grants.
		if not learned:
			desc_text = ab.description_resolved(1, bonus)
		next_text = "Requires level %d to learn." % required_level
	elif points >= max_points:
		next_text = MASTERED
	else:
		var nr := points + 1
		next_text = "Rank %d: %s" % [nr, ab.description_resolved(nr, bonus)]

	var rows := [
		{"text": ab.display_name, "bg": NAME_BG, "fg": NAME_TX, "stage": 0},
		{"text": "%d / %d points" % [points, max_points], "bg": POINTS_BG,
			"fg": POINTS_TX, "stage": 0},
		{"text": ab.cost_text_at(shown_rank), "bg": META_BG, "fg": META_TX, "stage": 1},
		{"text": desc_text, "bg": DESC_BG, "fg": DESC_TX, "stage": 1,
			"wrap": true, "rich": true},
		{"text": next_text, "bg": NEXTRANK_BG, "fg": NEXTRANK_TX, "stage": 1,
			"wrap": true, "rich": true},
	]
	# Key includes the state that changes the rows, so an invest (points change)
	# refreshes the text in place while a mere re-hover keeps the reveal.
	var key := "abilitynode:%s:%d:%d" % [String(ab.id), points, int(level_ok)]
	show_rows(rows, anchor_global, TIP_DELAY, key)


func hide_tip() -> void:
	_ab = null
	hide_panel()


## The player's live upgrade-node scaling bonus for `ab` (e.g. Sinewed -> Claw/Scour),
## read from the persistent Character. Empty when nothing upgrades this ability or the
## Character autoload isn't reachable.
func _scaling_bonus_for(ab: Ability) -> Dictionary:
	if ab == null:
		return {}
	var ch := get_node_or_null("/root/Character")
	if ch and ch.has_method("ability_scaling_bonus"):
		return ch.ability_scaling_bonus(String(ab.id))
	return {}


## A stable string signature of a scaling-bonus dict, appended to the hover's refresh
## key so the description re-renders when the bonus changes (empty => no suffix).
func _bonus_sig(bonus: Dictionary) -> String:
	if bonus == null or bonus.is_empty():
		return ""
	var keys := bonus.keys()
	keys.sort()
	var s := "|"
	for k in keys:
		s += "%s=%.3f;" % [str(k), float(bonus[k])]
	return s
