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
## @tool makes the circle + counter draw in the editor so you can see the tree
## while you build it. Hover shows the tree's info box; left-click invests a
## point (up to max_points, while the character has points free).
## ----------------------------------------------------------------------------

enum SizeClass { SMALL, MEDIUM, LARGE }

## The single source of truth for what each size class means, in pixels.
const RADII := {
	SizeClass.SMALL: 14.0,
	SizeClass.MEDIUM: 20.0,
	SizeClass.LARGE: 28.0,
}

@export var ability: Ability: set = _set_ability
@export var node_id: String = ""              ## MUST be unique within a tree
@export var links: Array[NodePath] = []        ## other SkillNodes to connect to
@export var size_class: SizeClass = SizeClass.MEDIUM: set = _set_size_class

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

var _hovered := false


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
	if ch and not ch.changed.is_connected(_on_character_changed):
		ch.changed.connect(_on_character_changed)
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


# Only the circle is clickable/hoverable at runtime. In the editor the whole
# box is selectable so it's easy to click on.
func _has_point(point: Vector2) -> bool:
	if Engine.is_editor_hint():
		return Rect2(Vector2.ZERO, size).has_point(point)
	return point.distance_to(size * 0.5) <= radius


func _draw() -> void:
	var r := radius
	var c := size * 0.5
	# --- fill: icon if the ability has one, else a dark-green circle ---
	if ability and ability.icon:
		var dest := Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0)
		draw_texture_rect(ability.icon, dest, false)
	else:
		draw_circle(c, r, COLOR_FILL)

	# --- ring shows how full the node is ---
	var pts := points()
	var maxp := max_points()
	var ring_col := COLOR_EMPTY_RING
	if pts > 0:
		ring_col = COLOR_MAXED_RING if pts >= maxp else COLOR_PARTIAL_RING
	draw_arc(c, r, 0.0, TAU, 48, ring_col, (4.0 if pts > 0 else 2.0), true)

	# --- hover highlight ---
	if _hovered:
		draw_arc(c, r + 3.0, 0.0, TAU, 48, Color(1, 1, 1, 0.5), 2.0, true)

	# --- "x/max" counter under the circle ---
	var font := get_theme_default_font()
	if font:
		var fs := 14
		var label := "%d/%d" % [pts, maxp]
		var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var pos := c + Vector2(-tw.x * 0.5, r + float(fs) + 2.0)
		draw_string(font, pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.95, 0.95, 0.95, 1))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_try_invest()
		accept_event()
	elif event is InputEventMouseMotion and _hovered:
		var tree := _skill_tree()
		if tree:
			tree.move_info_to_mouse()


func _try_invest() -> void:
	var ch := _character()
	if ch == null or ability == null or node_id == "":
		return
	ch.invest(node_id, ability.max_points)


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
