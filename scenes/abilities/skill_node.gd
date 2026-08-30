@tool
class_name SkillNode
extends Control

## ============================================================================
## SKILL NODE  —  one circular node in a skill tree
## ============================================================================
## The easy way to use this: instance  skill_node.tscn  into your tree scene
## (Scene dock > "Instantiate Child Scene"), drag it where you want it, then in
## the Inspector set:
##   - ability    : the .tres template it represents
##   - node_id    : a UNIQUE id string within this tree (e.g. "top", "left")
##   - links      : NodePaths to other SkillNodes to draw a line to
##   - size_class : SMALL / MEDIUM / LARGE (picks the radius)
##
## Radius is no longer a raw number per node. Instead each node picks a
## SizeClass, and the actual pixel radius for each class is defined ONCE in the
## RADII dictionary below. Change a class's size there and every node of that
## class updates across every tree. A tree can also globally scale all its
## nodes via SkillTreeView.node_scale (see skill_tree.gd).
##
## UNLOCKING: investing the FIRST point in a node also UNLOCKS its ability on the
## Character (so it appears in the ability pool and can be equipped to the wheel).
## That is how the four new abilities (Alef/Bet/Gimel/Dalet) come online — they
## start locked and are unlocked by spending a point on their tree node.
##
## @tool makes the circle + counter draw in the editor so you can see the tree
## while you build it. Hover shows the tree's info box; left-click invests a
## point (up to max_points, while the character has points free).
## ----------------------------------------------------------------------------

enum SizeClass { SMALL, MEDIUM, LARGE }

## The single source of truth for what each size class means, in pixels.
const RADII := {
	SizeClass.SMALL: 10.0,
	SizeClass.MEDIUM: 18.0,
	SizeClass.LARGE: 26.0,
}

@export var ability: Ability: set = _set_ability
@export var node_id: String = ""              ## MUST be unique within a tree
@export var links: Array[NodePath] = []        ## legacy visual links (see `parents`)
@export var size_class: SizeClass = SizeClass.MEDIUM: set = _set_size_class

## UNLOCK PREREQUISITES (rev14b). `parents` = node_ids that must ALL be unlocked
## (>=1 point) before this node can be invested; a root node leaves it empty.
## `required_level` = the player level needed to unlock this node. Default 0 means
## NO level gate (most nodes) — set it only on nodes that should demand a level
## (the furnishing nodes require 5). When any node in a tree defines `parents`, the
## tree draws its connecting lines from `parents` instead of the legacy `links`.
@export var parents: Array[String] = []
@export var required_level: int = 0

## Where the CENTER of this node sits. This is the authored placement — the
## node offsets its own top-left by its radius, so changing size_class keeps
## the center fixed and never skews the tree.
##   - relative_to_tree_center = false : center is in tree-local pixels
##     (0,0 = top-left of the tree area), same space as before.
##   - relative_to_tree_center = true  : center is measured from the MIDDLE of
##     the tree area, so (0,0) is dead center and symmetric layouts are just
##     mirrored +/- x values. Great for keeping a tree symmetric.
@export var center_position: Vector2 = Vector2.ZERO: set = _set_center_position
@export var relative_to_tree_center: bool = false: set = _set_relative

const COLOR_FILL := Color(0.10, 0.42, 0.16, 1.0)        ## dark-green placeholder
const COLOR_EMPTY_RING := Color(0.0, 0.0, 0.0, 0.55)
const COLOR_MAXED_RING := Color(1.0, 0.86, 0.35, 1.0)   ## gold when maxed
const COLOR_PARTIAL_RING := Color(0.55, 0.85, 0.55, 1.0)
const COLOR_LOCKED_FILL := Color(0.11, 0.12, 0.13, 1.0) ## prerequisites not met
const COLOR_LOCKED_RING := Color(0.45, 0.42, 0.45, 0.7)

var _hovered := false

## Red "unmet dependency" flash. When the player clicks a locked node, each of its
## still-locked parent nodes pulses this ring (1.0 -> 0.0 over ~1s) so it's obvious
## which prerequisites are missing. Runtime-only (never in the editor).
var _red_glow: float = 0.0
var _glow_tween: Tween


## The effective pixel radius: the class's base size, times the tree's global
## scale (if the parent tree defines one). This is what everything draws with.
var radius: float:
	get:
		var base: float = RADII[size_class]
		var tree := _skill_tree()
		if tree and "node_scale" in tree:
			return base * tree.node_scale
		return base


func _set_ability(value: Ability) -> void:
	ability = value
	queue_redraw()

func _set_size_class(value: SizeClass) -> void:
	size_class = value
	_apply_size()
	queue_redraw()

func _set_center_position(value: Vector2) -> void:
	center_position = value
	_apply_placement()

func _set_relative(value: bool) -> void:
	relative_to_tree_center = value
	_apply_placement()

## Recompute the Control's box from the current radius, then re-place it so its
## center stays at center_position regardless of size.
func _apply_size() -> void:
	custom_minimum_size = Vector2(radius * 2.0, radius * 2.0)
	size = custom_minimum_size
	_apply_placement()

## Convert the authored center into a top-left position. The Control's origin is
## its top-left corner, so we subtract the radius on both axes. When
## relative_to_tree_center is on, the center is measured from the tree's middle.
func _apply_placement() -> void:
	var target := center_position
	if relative_to_tree_center:
		var tree := _skill_tree()
		if tree and tree is Control:
			target += (tree as Control).size * 0.5
	position = target - Vector2(radius, radius)


func _ready() -> void:
	_apply_size()   ## also calls _apply_placement()
	if Engine.is_editor_hint():
		queue_redraw()
		return
	# --- runtime only below ---
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	var ch := _character()
	if ch:
		if not ch.changed.is_connected(_on_character_changed):
			ch.changed.connect(_on_character_changed)
		# Announce which ability this node grants so Character can resolve an
		# equipped ability back to its invested rank, even on a save made before
		# that map existed (opening the tree once repairs it).
		if ability and ch.has_method("register_node"):
			ch.register_node(node_id, String(ability.id))
	queue_redraw()


func center() -> Vector2:
	return position + size * 0.5

func points() -> int:
	var ch := _character()
	if ch and node_id != "":
		return ch.get_points(node_id)
	return 0

func max_points() -> int:
	return ability.max_points if ability else 1

## Unlocked = at least one point invested here.
func is_unlocked() -> bool:
	return points() > 0

## Prerequisites currently met (player level + every parent unlocked)?
func can_unlock() -> bool:
	var ch := _character()
	if ch and ch.has_method("can_unlock_node"):
		return ch.can_unlock_node(required_level, parents)
	return true

## Locked = not yet unlocked AND prerequisites unmet (so it can't be bought yet).
func is_locked() -> bool:
	return not is_unlocked() and not can_unlock()


# Only the circle is clickable/hoverable at runtime. In the editor the whole
# box is selectable so it's easy to click on.
func _has_point(point: Vector2) -> bool:
	if Engine.is_editor_hint():
		return Rect2(Vector2.ZERO, size).has_point(point)
	return point.distance_to(size * 0.5) <= radius


func _draw() -> void:
	var r := radius
	var c := size * 0.5
	var locked := is_locked()
	# --- fill: icon if the ability has one, else a circle (dimmed when locked) ---
	if ability and ability.icon:
		var dest := Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0)
		draw_texture_rect(ability.icon, dest, false, Color(1, 1, 1, 0.35 if locked else 1.0))
	else:
		draw_circle(c, r, COLOR_LOCKED_FILL if locked else COLOR_FILL)

	# --- ring: locked (grey) / maxed (gold) / partial (green) / empty ---
	var pts := points()
	var maxp := max_points()
	var ring_col := COLOR_EMPTY_RING
	var ring_w := 2.0
	if locked:
		ring_col = COLOR_LOCKED_RING
	elif pts > 0:
		ring_col = COLOR_MAXED_RING if pts >= maxp else COLOR_PARTIAL_RING
		ring_w = 4.0
	draw_arc(c, r, 0.0, TAU, 48, ring_col, ring_w, true)

	# --- hover highlight ---
	if _hovered:
		draw_arc(c, r + 3.0, 0.0, TAU, 48, Color(1, 1, 1, 0.5), 2.0, true)

	# --- "unmet dependency" red flash (see flash_red) ---
	if _red_glow > 0.0:
		draw_arc(c, r + 3.0, 0.0, TAU, 48, Color(0.95, 0.15, 0.15, _red_glow), 3.0, true)

	# The x/max point count is no longer drawn under the node — it now lives in the
	# hover tooltip's "Points" line (see skill_tree.show_info / AbilityTooltip).


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_try_invest()
		accept_event()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_try_refund()
		accept_event()
	elif event is InputEventMouseMotion and _hovered:
		var tree := _skill_tree()
		if tree:
			tree.move_info_to_mouse()


func _try_invest() -> void:
	var ch := _character()
	if ch == null or ability == null or node_id == "":
		return
	# Gated by the node's level requirement + parent prerequisites (enforced inside
	# Character.invest). Investing the first point unlocks the ability (idempotent —
	# unlock_ability ignores an already-unlocked id).
	if ch.invest(node_id, ability.max_points, required_level, parents, String(ability.id)):
		if ch.has_method("unlock_ability"):
			ch.unlock_ability(String(ability.id))
	elif is_locked():
		# Blocked by prerequisites — flash the still-locked parent nodes red so the
		# player can see exactly which dependencies are unmet.
		var tree := _skill_tree()
		if tree and tree.has_method("flash_unmet_dependencies"):
			tree.flash_unmet_dependencies(self)
		print("[skilltree] %s is locked — needs level %d and parents %s." % [node_id, required_level, str(parents)])


## RIGHT-CLICK: hand one point back from this node to the pool (the inverse of
## _try_invest). Does nothing on a node with no points.
##
## THE DEPENDENCY GUARD: refunding the LAST point re-locks this node, which would
## strand any child that lists it in `parents` — the child would keep its invested
## points while its prerequisite reads locked. So when this node is down to its final
## point we refuse if any dependent still holds points, and flash those dependents red
## (the same cue an unmet prerequisite gets on invest) so it's obvious what to refund
## first. Refunding 3->2->1 is always free; only the last point is gated.
func _try_refund() -> void:
	var ch := _character()
	if ch == null or node_id == "" or not ch.has_method("refund"):
		return
	if points() <= 0:
		return
	if points() == 1:
		var tree := _skill_tree()
		if tree and tree.has_method("invested_dependents"):
			var blockers: Array = tree.invested_dependents(self)
			if blockers.size() > 0:
				for b in blockers:
					if b is SkillNode:
						(b as SkillNode).flash_red()
				print("[skilltree] can't refund %s — %d dependent node(s) still have points." % [node_id, blockers.size()])
				return
	ch.refund(node_id)


## Pulse a red ring on this node (1.0 -> 0.0 over ~1s). Called on each still-locked
## parent when the player clicks a node whose dependencies aren't met yet, and on each
## still-invested CHILD when the player tries to refund a node they still depend on.
func flash_red() -> void:
	if Engine.is_editor_hint():
		return
	_red_glow = 1.0
	queue_redraw()
	if _glow_tween and _glow_tween.is_valid():
		_glow_tween.kill()
	_glow_tween = create_tween()
	_glow_tween.tween_method(_set_red_glow, 1.0, 0.0, 1.0)


func _set_red_glow(v: float) -> void:
	_red_glow = v
	queue_redraw()


func _on_mouse_entered() -> void:
	_hovered = true
	queue_redraw()
	var tree := _skill_tree()
	if tree:
		tree.show_info(self)

func _on_mouse_exited() -> void:
	_hovered = false
	queue_redraw()
	var tree := _skill_tree()
	if tree:
		tree.hide_info()

func _on_character_changed() -> void:
	queue_redraw()
	var tree := _skill_tree()
	if tree and _hovered:
		tree.show_info(self)   ## keep the open info box's numbers current


func _character() -> Node:
	return get_node_or_null("/root/Character")

# Nearest ancestor that behaves like a skill tree (has the info-box methods).
func _skill_tree() -> Node:
	var n := get_parent()
	while n:
		if n.has_method("show_info"):
			return n
		n = n.get_parent()
	return null
