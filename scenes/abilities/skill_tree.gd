@tool
class_name SkillTreeView
extends Control

## ============================================================================
## SKILL TREE VIEW  —  root script for a skill tree scene
## ============================================================================
## Put this on the root Control of a tree scene (one scene per class). It:
##   - draws the connecting lines between linked SkillNodes (under the nodes)
##   - owns the hover InfoBox and positions its top-left corner at the mouse
##   - defines node_scale: a global multiplier applied to every node's radius
##     in THIS tree, on top of each node's SizeClass. Leave it at 1.0 for
##     normal sizing, or bump it up for a tree of chunkier nodes.
##
## To author a tree: add SkillNode children (instance skill_node.tscn),
## position them, give each a unique node_id + ability, and set their `links`.
## The InfoBox node (a PanelContainer named "InfoBox") must exist as the LAST
## child so it renders on top of everything.
##
## @tool draws the lines in the editor too, so the tree is visible while you
## build it.
## ----------------------------------------------------------------------------

const LINE_COLOR := Color(0.78, 0.74, 0.55, 0.9)
const LINE_DIM := Color(0.40, 0.38, 0.32, 0.6)   ## parent not yet unlocked
const LINE_WIDTH := 3.0

## Global radius multiplier for every SkillNode in this tree. Each node reads
## this from its parent tree, so one value here rescales the whole tree.
@export var node_scale: float = 1.0: set = _set_node_scale

# The old .tscn InfoBox (if present) is retired in favour of the shared
# AbilityTooltip; we just hide it. get_node_or_null keeps trees without one safe.
@onready var _info_box: Control = get_node_or_null("InfoBox")
var _tooltip: AbilityTooltip


func _set_node_scale(value: float) -> void:
	node_scale = maxf(0.01, value)
	# Nodes size themselves from this; _apply_size re-centers them too.
	for node in _skill_nodes():
		node._apply_size()
		node.queue_redraw()
	queue_redraw()


## Re-place every node from its center. Called when the tree area resizes, so
## nodes using relative_to_tree_center stay anchored to the middle.
func _replace_all_nodes() -> void:
	for node in _skill_nodes():
		node._apply_placement()
	queue_redraw()


func _ready() -> void:
	if _info_box:
		_info_box.visible = false
		if not Engine.is_editor_hint():
			_info_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_replace_all_nodes)
	if not Engine.is_editor_hint():
		_tooltip = AbilityTooltip.new()
		add_child(_tooltip)
		# Redraw the dependency lines when unlock state changes (a parent unlocking
		# brightens the lines to its children).
		var ch := get_node_or_null("/root/Character")
		if ch and ch.has_signal("changed") and not ch.changed.is_connected(queue_redraw):
			ch.changed.connect(queue_redraw)
		# Nodes may set their size in their own _ready; redraw once after this
		# frame so the lines connect to final positions.
		await get_tree().process_frame
	queue_redraw()


func _process(_delta: float) -> void:
	# In the editor, keep the lines following the nodes as you drag them.
	if Engine.is_editor_hint():
		queue_redraw()


func _draw() -> void:
	# Lines connect each node to its dependencies. When ANY node defines `parents`
	# (the rev14b prerequisite system), draw parent lines — brighter when the parent
	# is already unlocked, dim when it's still locked. Otherwise fall back to the
	# legacy `links` (visual-only) so older trees still draw. Drawn here (in the
	# parent) so the child nodes cover the line ends.
	var nodes := _skill_nodes()
	var use_parents := false
	for n in nodes:
		if n.parents.size() > 0:
			use_parents = true
			break

	if use_parents:
		var by_id := {}
		for n in nodes:
			if n.node_id != "":
				by_id[n.node_id] = n
		var ch := get_node_or_null("/root/Character")
		for n in nodes:
			for pid in n.parents:
				var parent = by_id.get(str(pid), null)
				if parent is SkillNode:
					var col := LINE_COLOR
					if ch and ch.has_method("node_unlocked") and not ch.node_unlocked(str(pid)):
						col = LINE_DIM
					draw_line(n.center(), (parent as SkillNode).center(), col, LINE_WIDTH, true)
	else:
		for node in nodes:
			for link_path in node.links:
				var other: Node = node.get_node_or_null(link_path)
				if other is SkillNode:
					draw_line(node.center(), (other as SkillNode).center(), LINE_COLOR, LINE_WIDTH, true)


func _skill_nodes() -> Array[SkillNode]:
	var result: Array[SkillNode] = []
	for child in get_children():
		if child is SkillNode:
			result.append(child)
	return result


# ------------------------------------------------ info (shared AbilityTooltip)
# Same 3-panel card as the wheel and ability pool. Anchored to the hovered node.
func show_info(node: SkillNode) -> void:
	if _tooltip == null or node == null:
		return
	if node.ability == null:
		_tooltip.hide_tip()
		return
	# Skill-tree hover: the tooltip shows the points line, the current-rank
	# description (or "not yet learned"), and the faded-red next-rank panel. Re-shown
	# on Character.changed so it all stays current on invest.
	var ch := get_node_or_null("/root/Character")
	var lvl := 1
	if ch and "level" in ch:
		lvl = int(ch.level)
	var req := node.required_level
	_tooltip.show_for_node(node.ability, node.get_global_rect(),
		node.points(), node.max_points(), req, lvl >= req)


## Pulse each of `node`'s still-locked parent nodes red. Called by a SkillNode when
## the player clicks it but its dependencies aren't met, so the missing prerequisites
## are visually obvious.
func flash_unmet_dependencies(node: SkillNode) -> void:
	if node == null:
		return
	var by_id := {}
	for n in _skill_nodes():
		if n.node_id != "":
			by_id[n.node_id] = n
	var ch := get_node_or_null("/root/Character")
	for pid in node.parents:
		var p = by_id.get(str(pid), null)
		if p is SkillNode:
			var unlocked := true
			if ch and ch.has_method("node_unlocked"):
				unlocked = ch.node_unlocked(str(pid))
			if not unlocked:
				(p as SkillNode).flash_red()

func hide_info() -> void:
	if _tooltip:
		_tooltip.hide_tip()

# Kept for SkillNode compatibility; the tooltip is anchored to the node now, so
# it no longer follows the mouse.
func move_info_to_mouse() -> void:
	pass
