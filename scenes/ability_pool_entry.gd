class_name AbilityPoolEntry
extends PanelContainer
## One draggable ability chip in the ability pool. Drag it onto a wheel slot.
## Hovering it pops the shared AbilityTooltip (name / cost / description).

var ability_id: String = ""
var _label: Label
var _tooltip: AbilityTooltip

func setup(id: String, display: String) -> void:
	ability_id = id
	custom_minimum_size = Vector2(0, 40)
	mouse_filter = Control.MOUSE_FILTER_STOP
	if _label == null:
		_label = Label.new()
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_label)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.18, 0.30, 0.50)
		sb.set_corner_radius_all(5)
		sb.content_margin_left = 8
		sb.content_margin_right = 8
		add_theme_stylebox_override("panel", sb)
		_tooltip = AbilityTooltip.new()
		add_child(_tooltip)
		mouse_entered.connect(_on_hover)
		mouse_exited.connect(_on_unhover)
	_label.text = display

func _get_drag_data(_at_position: Vector2) -> Variant:
	if _tooltip:
		_tooltip.hide_tip()
	var prev := Label.new()
	prev.text = _label.text
	prev.add_theme_color_override("font_color", Color.WHITE)
	set_drag_preview(prev)
	return {"source": "pool", "id": ability_id}

func _on_hover() -> void:
	if _tooltip == null:
		return
	var db := get_node_or_null("/root/AbilityDB")
	if db and db.has_method("get_ability"):
		_tooltip.show_for(db.get_ability(ability_id), get_global_rect())

func _on_unhover() -> void:
	if _tooltip:
		_tooltip.hide_tip()
