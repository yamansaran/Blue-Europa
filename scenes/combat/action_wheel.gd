class_name ActionWheel
extends Control
## Shared 10-slot loadout wheel, backed by Character.equipped_abilities.
##   USE  mode (combat): left-click a filled slot -> slot_selected(index, id).
##   EDIT mode (abilities): drag from the pool onto a slot; drag one slot onto
##        another to move/swap; RIGHT-CLICK a slot to clear it.
## In BOTH modes, hovering a filled slot pops the shared AbilityTooltip (name
## instantly, cost + description after a short delay).

signal slot_selected(index: int, ability_id: String)

enum Mode { USE, EDIT }

const SLOT_COUNT := 10

var mode: int = Mode.USE
var _hover_slot: int = -1
var _tooltip: AbilityTooltip


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var ch := _character()
	if ch and not ch.changed.is_connected(queue_redraw):
		ch.changed.connect(queue_redraw)
	_tooltip = AbilityTooltip.new()
	add_child(_tooltip)
	mouse_exited.connect(_on_wheel_mouse_exited)


func set_mode_use() -> void:
	mode = Mode.USE
	visible = false
	if _tooltip:
		_tooltip.hide_tip()
	queue_redraw()

func set_mode_edit() -> void:
	mode = Mode.EDIT
	visible = true
	if _tooltip:
		_tooltip.hide_tip()
	queue_redraw()

## Combat: pop the wheel up centred on a point in the PARENT's coordinates.
## Fades in via a short tween each time it opens.
func open_over(center_in_parent: Vector2, box: float = 240.0) -> void:
	size = Vector2(box, box)
	position = center_in_parent - size * 0.5
	visible = true
	_hover_slot = -1
	if _tooltip:
		_tooltip.hide_tip()
	queue_redraw()
	# fade in from transparent (prebuilt Tween)
	modulate.a = 0.0
	var t := create_tween()
	t.tween_property(self, "modulate:a", 1.0, 0.15)

func close() -> void:
	if mode == Mode.EDIT:
		return                      # the editor wheel is always shown
	visible = false
	_hover_slot = -1
	if _tooltip:
		_tooltip.hide_tip()

# --- geometry (adaptive to current size) --------------------------------
func _center() -> Vector2:
	return size * 0.5

func _slot_radius() -> float:
	return clampf(minf(size.x, size.y) * 0.10, 11.0, 24.0)

func _ring_radius() -> float:
	return maxf(24.0, minf(size.x, size.y) * 0.5 - _slot_radius() - 6.0)

func _slot_pos(i: int) -> Vector2:
	var ang := -PI * 0.5 + TAU * float(i) / float(SLOT_COUNT)
	return _center() + Vector2(cos(ang), sin(ang)) * _ring_radius()

func _slot_at(p: Vector2) -> int:
	var r := _slot_radius()
	for i in SLOT_COUNT:
		if p.distance_to(_slot_pos(i)) <= r:
			return i
	return -1

# --- data lookups -------------------------------------------------------
func _character() -> Node:
	return get_node_or_null("/root/Character")

func _ability_db() -> Node:
	return get_node_or_null("/root/AbilityDB")

func _id_at_slot(i: int) -> String:
	var ch := _character()
	if ch == null:
		return ""
	var eq = ch.get("equipped_abilities")
	if typeof(eq) == TYPE_ARRAY and i >= 0 and i < eq.size():
		return str(eq[i])
	return ""

func _ability_at_slot(i: int) -> Ability:
	var id := _id_at_slot(i)
	if id == "":
		return null
	var db := _ability_db()
	if db and db.has_method("get_ability"):
		return db.get_ability(id)
	return null

# --- drawing ------------------------------------------------------------
func _draw() -> void:
	var r := _slot_radius()
	var font := get_theme_default_font()
	var fsize := int(clampf(r * 0.55, 9, 14))
	draw_circle(_center(), 5.0, Color(1, 1, 1, 0.18))
	for i in SLOT_COUNT:
		var pos := _slot_pos(i)
		var ab := _ability_at_slot(i)
		var filled := ab != null
		var fill := Color(0.85, 0.90, 1.0, 0.16)
		if filled:
			fill = Color(0.30, 0.45, 0.75, 0.85)
		if i == _hover_slot:
			fill = fill.lightened(0.25)
			fill.a = maxf(fill.a, 0.5)
		draw_circle(pos, r, fill)
		draw_arc(pos, r, 0.0, TAU, 28, Color(1, 1, 1, 0.55), 2.0, true)
		if filled:
			if ab.icon != null:
				var ts := r * 1.4
				draw_texture_rect(ab.icon, Rect2(pos - Vector2(ts, ts) * 0.5, Vector2(ts, ts)), false)
			elif font:
				draw_string(font, pos + Vector2(-r, fsize * 0.35), _short(ab.display_name),
					HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, fsize, Color(1, 1, 1, 0.95))

func _short(s: String) -> String:
	if s.length() <= 6:
		return s
	return s.substr(0, 5) + "…"

# --- tooltip ------------------------------------------------------------
func _update_tooltip(slot: int) -> void:
	if _tooltip == null:
		return
	var ab := _ability_at_slot(slot) if slot >= 0 else null
	if ab == null:
		_tooltip.hide_tip()
		return
	var gp := global_position + _slot_pos(slot)
	var r := _slot_radius()
	_tooltip.show_for(ab, Rect2(gp - Vector2(r, r), Vector2(r, r) * 2.0))

func _on_wheel_mouse_exited() -> void:
	_hover_slot = -1
	if _tooltip:
		_tooltip.hide_tip()
	queue_redraw()

# --- input --------------------------------------------------------------
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var now := _slot_at(event.position)
		if now != _hover_slot:
			_hover_slot = now
			_update_tooltip(now)
			queue_redraw()
		return
	if event is InputEventMouseButton and event.pressed:
		var slot := _slot_at(event.position)
		if mode == Mode.EDIT:
			if event.button_index == MOUSE_BUTTON_RIGHT and slot >= 0:
				var ch := _character()
				if ch and ch.has_method("unequip_slot"):
					ch.unequip_slot(slot)
				accept_event()
			return
		# USE mode
		if event.button_index == MOUSE_BUTTON_LEFT:
			var id := _id_at_slot(slot) if slot >= 0 else ""
			if id != "":
				slot_selected.emit(slot, id)
			else:
				close()
			accept_event()

# --- drag & drop (EDIT only) -------------------------------------------
func _get_drag_data(at_position: Vector2) -> Variant:
	if mode != Mode.EDIT:
		return null
	var slot := _slot_at(at_position)
	if slot < 0:
		return null
	var id := _id_at_slot(slot)
	if id == "":
		return null
	if _tooltip:
		_tooltip.hide_tip()
	var prev := Label.new()
	prev.text = id
	prev.add_theme_color_override("font_color", Color.WHITE)
	set_drag_preview(prev)
	return {"source": "wheel", "slot": slot, "id": id}

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if mode != Mode.EDIT:
		return false
	if typeof(data) != TYPE_DICTIONARY or not data.has("id"):
		return false
	var slot := _slot_at(at_position)
	if slot < 0:
		return false
	if str(data.get("source", "")) == "wheel":
		return true                    # move/swap between slots
	var ch := _character()
	return ch != null and ch.can_equip(slot, str(data["id"]))

func _drop_data(at_position: Vector2, data: Variant) -> void:
	var slot := _slot_at(at_position)
	if slot < 0:
		return
	var ch := _character()
	if ch == null:
		return
	if str(data.get("source", "")) == "wheel":
		ch.move_equipped(int(data["slot"]), slot)
	else:
		ch.equip_ability(slot, str(data["id"]))
