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
		# Nodes may set their size in their own _ready; redraw once after this
		# frame so the lines connect to final positions.
		await get_tree().process_frame
	queue_redraw()


func _process(_delta: float) -> void:
	# In the editor, keep the lines following the nodes as you drag them.
	if Engine.is_editor_hint():
		queue_redraw()


func _draw() -> void:
	# One line per link. Drawn here (in the parent) so child nodes cover the
	# line ends.
	for node in _skill_nodes():
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
	_tooltip.show_for(node.ability, node.get_global_rect())

func hide_info() -> void:
	if _tooltip:
		_tooltip.hide_tip()

# Kept for SkillNode compatibility; the tooltip is anchored to the node now, so
# it no longer follows the mouse.
func move_info_to_mouse() -> void:
	pass
