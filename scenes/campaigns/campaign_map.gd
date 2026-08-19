extends Control
## ============================================================================
## Campaign map  —  the World Map screen (a shell-content panel)
## ============================================================================
## DEBUG feature: draws the whole campaign GRAPH (nodes + links) and lets you
## click any node to JUMP to that campaign (CampaignDB.jump_to), then drops you
## into that campaign's overworld. Highlights the current campaign, marks
## completed ones, and shows total progression. Built entirely in code.
## ----------------------------------------------------------------------------

const BG := Color(0.06, 0.10, 0.16)
const NODE_SIZE := Vector2(160, 66)

var _graph: LinkLayer
var _node_buttons: Dictionary = {}   # id -> Button
var _totals_label: Label

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var title := Label.new()
	title.text = "WORLD MAP   (debug — click a node to jump to that campaign)"
	title.add_theme_font_size_override("font_size", 22)
	title.position = Vector2(24, 16)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title)

	_totals_label = Label.new()
	_totals_label.text = _totals_text()
	_totals_label.position = Vector2(24, 50)
	_totals_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_totals_label)

	# graph area (links drawn here; node buttons are its children)
	_graph = LinkLayer.new()
	_graph.anchor_left = 0.0
	_graph.anchor_right = 1.0
	_graph.anchor_top = 0.0
	_graph.anchor_bottom = 1.0
	_graph.offset_left = 30
	_graph.offset_right = -30
	_graph.offset_top = 90
	_graph.offset_bottom = -30
	_graph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_graph)
	_graph.resized.connect(_relayout)

	if typeof(CampaignDB) != TYPE_NIL:
		for id in CampaignDB.order:
			var b := Button.new()
			b.custom_minimum_size = NODE_SIZE
			b.size = NODE_SIZE
			b.clip_text = true
			b.pressed.connect(_on_node_pressed.bind(id))
			_graph.add_child(b)
			_node_buttons[id] = b

	# return button
	var x := Button.new()
	x.text = "X"
	x.anchor_left = 1.0
	x.anchor_right = 1.0
	x.offset_left = -52
	x.offset_right = -14
	x.offset_top = 14
	x.offset_bottom = 48
	x.pressed.connect(func(): GameManager.go_to_overworld())
	add_child(x)

	call_deferred("_relayout")

func _totals_text() -> String:
	if typeof(CampaignDB) == TYPE_NIL:
		return ""
	return "Total fights cleared: %d      Current: %s      (%d / %d in this campaign)" % [
		CampaignDB.total_fights_done, _name_of(CampaignDB.current_id),
		CampaignDB.fight_index, CampaignDB.fights_total()]

func _name_of(id: String) -> String:
	var c: Campaign = CampaignDB.get_campaign(id)
	return c.display_name if c else id

func _relayout() -> void:
	if _graph == null or typeof(CampaignDB) == TYPE_NIL:
		return
	var sz: Vector2 = _graph.size
	var positions: Dictionary = {}
	for id in CampaignDB.order:
		var c: Campaign = CampaignDB.get_campaign(id)
		if c == null:
			continue
		var center := Vector2(c.map_position.x * sz.x, c.map_position.y * sz.y)
		positions[id] = center
		var b: Button = _node_buttons.get(id)
		if b:
			b.position = center - NODE_SIZE * 0.5
			b.text = _node_text(id, c)
			_style_node(b, id)
	_graph.node_pos = positions
	_graph.queue_redraw()

func _node_text(id: String, c: Campaign) -> String:
	var mark := ""
	if CampaignDB.completed_campaigns.get(id, false):
		mark = "  [done]"
	elif id == CampaignDB.current_id:
		mark = "  [current]"
	return "%s%s\n(%d fights)" % [c.display_name, mark, c.fight_count()]

func _style_node(b: Button, id: String) -> void:
	var col := Color(0.20, 0.24, 0.32)              # default / not reached
	if id == CampaignDB.current_id:
		col = Color(0.20, 0.46, 0.30)               # current = green
	elif CampaignDB.completed_campaigns.get(id, false):
		col = Color(0.16, 0.30, 0.46)               # completed = blue
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(6)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.6, 0.7, 0.85)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	b.add_theme_stylebox_override("normal", sb)
	var hb: StyleBoxFlat = sb.duplicate()
	hb.bg_color = col.lightened(0.15)
	b.add_theme_stylebox_override("hover", hb)
	var pb: StyleBoxFlat = sb.duplicate()
	pb.bg_color = col.darkened(0.1)
	b.add_theme_stylebox_override("pressed", pb)

func _on_node_pressed(id: String) -> void:
	CampaignDB.jump_to(id)
	GameManager.go_to_overworld()

# ---------------------------------------------------------------------------
# Inner draw layer: draws the links between campaign nodes behind the buttons.
# ---------------------------------------------------------------------------
class LinkLayer extends Control:
	var node_pos: Dictionary = {}

	func _draw() -> void:
		if typeof(CampaignDB) == TYPE_NIL:
			return
		for id in CampaignDB.order:
			var c: Campaign = CampaignDB.get_campaign(id)
			if c == null or not node_pos.has(id):
				continue
			var a: Vector2 = node_pos[id]
			for nid in c.next_ids:
				if node_pos.has(nid):
					draw_line(a, node_pos[nid], Color(0.45, 0.55, 0.75), 3.0)
