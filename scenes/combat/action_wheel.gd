class_name ActionWheel
extends Control
## Shared 10-slot loadout wheel, backed by Character.equipped_abilities.
##   USE  mode (combat): left-click a filled slot -> slot_selected(index, id).
##   EDIT mode (abilities): drag from the pool onto a slot; drag one slot onto
##        another to move/swap; RIGHT-CLICK a slot to clear it.
## In BOTH modes, hovering a filled slot pops the shared AbilityTooltip (name
## instantly, cost + description after a short delay).
##
## USE-mode STATE: combat feeds the wheel the caster's body + the ability-cooldown
## map via set_use_state(). Slots whose ability is on cooldown, or is silenced
## (a spirit-cost ability while the caster is silenced), or all slots while the
## caster is stunned, are drawn GREYED and cannot be selected. A cooldown slot
## shows the turns remaining.

signal slot_selected(index: int, ability_id: String)

enum Mode { USE, EDIT }

## The wheel is DATA-DRIVEN: it shows one slot per entry in
## Character.equipped_abilities, so a future skill / piece of equipment that grows
## or shrinks that array automatically changes the number of slots. Set
## `slot_count_override` (>0) to force a specific count without touching the
## character (-1 = auto).
const DEFAULT_SLOT_COUNT := 10          # fallback when no character is present
const SLOT_GAP := 0.82                  # fraction of the neighbour gap a slot fills
const SLOT_MARGIN := 6.0                # px kept between the slots and the box edge
const SLOT_R_MIN := 8.0
const SLOT_R_MAX := 24.0
const RING_FRACTION := 0.72             # provisional ring radius (fraction of half-box)

var slot_count_override: int = -1

var mode: int = Mode.USE
var _hover_slot: int = -1
var _tooltip: AbilityTooltip

# --- USE-mode gameplay state (set by combat via set_use_state) --------------
var _caster_body: CharacterBase = null
var _cooldowns: Dictionary = {}


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

## Combat hands over the caster's body + the (shared-by-reference) cooldown map so
## the wheel can grey out unusable abilities. Safe to call with null.
func set_use_state(caster_body: CharacterBase, cooldowns: Dictionary) -> void:
	_caster_body = caster_body
	_cooldowns = cooldowns
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

## How many slots the wheel draws. Reads Character.equipped_abilities so it adapts
## to future features that add/remove ability slots; `slot_count_override` wins.
func _slot_count() -> int:
	if slot_count_override > 0:
		return slot_count_override
	var ch := _character()
	if ch:
		var eq = ch.get("equipped_abilities")
		if typeof(eq) == TYPE_ARRAY and (eq as Array).size() > 0:
			return (eq as Array).size()
	return DEFAULT_SLOT_COUNT

func _slot_radius() -> float:
	var n := _slot_count()
	var half := minf(size.x, size.y) * 0.5
	if n <= 1:
		return clampf(half * RING_FRACTION, SLOT_R_MIN, SLOT_R_MAX)
	# Largest radius that fits n slots evenly around the ring without overlapping:
	# half the chord between neighbours (ring * sin(PI/n)), times a gap factor. This
	# both SPREADS the circles automatically and shrinks them — moderately — as the
	# count climbs, then clamps so a handful of slots don't balloon.
	var ring := half * RING_FRACTION
	var fit := ring * sin(PI / float(n)) * SLOT_GAP
	return clampf(fit, SLOT_R_MIN, SLOT_R_MAX)

func _ring_radius() -> float:
	# Derive the real ring from the final slot size so the circles always sit
	# inside the box with a small margin, whatever size they ended up.
	return maxf(24.0, minf(size.x, size.y) * 0.5 - _slot_radius() - SLOT_MARGIN)

func _slot_pos(i: int) -> Vector2:
	var ang := -PI * 0.5 + TAU * float(i) / float(_slot_count())
	return _center() + Vector2(cos(ang), sin(ang)) * _ring_radius()

func _slot_at(p: Vector2) -> int:
	var r := _slot_radius()
	for i in _slot_count():
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

# --- USE-mode usability -------------------------------------------------
func _cooldown_of(i: int) -> int:
	if mode != Mode.USE:
		return 0
	return int(_cooldowns.get(_id_at_slot(i), 0))

## An ability is unusable (greyed, unselectable) when the caster is stunned, the
## slot is on cooldown, or it costs spirit while the caster is silenced.
func _slot_disabled(i: int) -> bool:
	if mode != Mode.USE:
		return false
	var ab := _ability_at_slot(i)
	if ab == null:
		return false
	if _caster_body != null:
		if CombatBuffs.is_stunned(_caster_body):
			return true
		if ab.spirit_cost() > 0 and CombatBuffs.is_silenced(_caster_body):
			return true
	return _cooldown_of(i) > 0

# --- drawing ------------------------------------------------------------
func _draw() -> void:
	var r := _slot_radius()
	var font := get_theme_default_font()
	var fsize := int(clampf(r * 0.55, 9, 14))
	draw_circle(_center(), 5.0, Color(1, 1, 1, 0.18))
	for i in _slot_count():
		var pos := _slot_pos(i)
		var ab := _ability_at_slot(i)
		var filled := ab != null
		var disabled := filled and _slot_disabled(i)
		var fill := Color(0.85, 0.90, 1.0, 0.16)
		if filled:
			fill = Color(0.30, 0.45, 0.75, 0.85)
		if disabled:
			fill = Color(0.28, 0.28, 0.30, 0.75)   # greyed out
		if i == _hover_slot and not disabled:
			fill = fill.lightened(0.25)
			fill.a = maxf(fill.a, 0.5)
		draw_circle(pos, r, fill)
		draw_arc(pos, r, 0.0, TAU, 28, Color(1, 1, 1, 0.55), 2.0, true)
		var content_alpha := 0.35 if disabled else 0.95
		if filled:
			if ab.icon != null:
				var ts := r * 1.4
				draw_texture_rect(ab.icon, Rect2(pos - Vector2(ts, ts) * 0.5, Vector2(ts, ts)), false, Color(1, 1, 1, content_alpha))
			elif font:
				draw_string(font, pos + Vector2(-r, fsize * 0.35), _short(ab.display_name),
					HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, fsize, Color(1, 1, 1, content_alpha))
			# cooldown count over the slot
			var cd := _cooldown_of(i)
			if cd > 0 and font:
				var ctext := str(cd)
				var cfs := int(clampf(r * 0.9, 12, 22))
				var cw := font.get_string_size(ctext, HORIZONTAL_ALIGNMENT_LEFT, -1, cfs)
				var cpos := pos + Vector2(-cw.x * 0.5, cfs * 0.4)
				draw_string(font, cpos + Vector2(1, 1), ctext, HORIZONTAL_ALIGNMENT_LEFT, -1, cfs, Color(0, 0, 0, 0.9))
				draw_string(font, cpos, ctext, HORIZONTAL_ALIGNMENT_LEFT, -1, cfs, Color(1, 0.85, 0.35))

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
				if _slot_disabled(slot):
					accept_event()          # greyed: swallow the click, keep the wheel open
				else:
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
