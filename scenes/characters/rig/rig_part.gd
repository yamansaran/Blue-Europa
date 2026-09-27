@tool
class_name RigPart
extends Sprite2D

## ============================================================================
## RIG PART  —  one visible body part (or weapon socket) of a rig  (@tool)
## ============================================================================
## Parts live FLAT under the rig's `Parts` node, in DRAW ORDER (child order = back to
## front). Each is driven by a RemoteTransform2D on its bone, so the bone tree does
## the moving and this list does the layering. RIG_SPEC §3.
##
## THE JOINT IS THE ORIGIN and the part extends along +x (the Bone2D convention), so
## a capsule runs from (0,0) to (length,0).
##
## PLACEHOLDER. With no art the part draws itself — a capsule, circle or box in
## base_color with a dark outline — in the editor too (@tool), so the mannequin can be
## posed and keyframed before any image exists. Gear with no art draws a slightly
## fatter shape on top in its own colour. A WEAPON SOCKET draws a placeholder weapon
## for its class.
##
## ART. A texture assigned on the node in the editor is its base image (the
## placeholder then hides). At runtime UnitRig adds skin / gear images as child
## sprites ("layers"), so images always sit above the part's own drawing.
##
## class_name global — RESTART Godot once after adding this file.
## ----------------------------------------------------------------------------

enum Shape { CAPSULE, CIRCLE, BOX, SOCKET }

const OUTLINE := 2.0
const GEAR_GROW := 1.22
const STEEL := Color(0.80, 0.82, 0.86)
const WOOD := Color(0.47, 0.31, 0.18)
const DARK := Color(0.16, 0.16, 0.19)
## How a placeholder weapon of each class sits in the fist (radians; 0 = along the
## socket's +x, which points FORWARD in the rest pose).
const CLASS_ANGLE := {
	&"blade": -1.0, &"blunt": -1.0, &"polearm": -1.25, &"staff": -1.25,
	&"gun": 0.0, &"bow": 0.0, &"shield": 0.0,
}
const CLASS_LENGTH := {
	&"blade": 52.0, &"blunt": 44.0, &"polearm": 96.0, &"gun": 40.0,
	&"bow": 58.0, &"staff": 90.0, &"shield": 30.0,
}

@export var part_id: StringName = &""
@export var shape: Shape = Shape.CAPSULE:
	set(v):
		shape = v
		queue_redraw()
@export var length: float = 30.0:
	set(v):
		length = v
		queue_redraw()
@export var thickness: float = 10.0:
	set(v):
		thickness = v
		queue_redraw()
## Keep a capsule's rounded ends INSIDE `length` (a torso) instead of bulging past
## the joints (a limb, where the bulge fills the elbow).
@export var inset_ends: bool = false:
	set(v):
		inset_ends = v
		queue_redraw()
@export var base_color: Color = Color(0.72, 0.62, 0.52):
	set(v):
		base_color = v
		queue_redraw()
## Head only: draw an eye on the FORWARD side so facing reads at a glance.
@export var face_mark: bool = false:
	set(v):
		face_mark = v
		queue_redraw()
## SOCKET only: the weapon class drawn in the EDITOR when nothing is equipped, so a
## clip can be keyframed with a weapon in hand. Never drawn in game.
@export var preview_class: StringName = &"":
	set(v):
		preview_class = v
		queue_redraw()

# ---- runtime state (set by UnitRig) -----------------------------------------
var base_hidden: bool = false
var gear_colors: Array = []           # placeholder armour layers, back to front
var socket_class: StringName = &""    # "" = empty hand
var socket_length: float = 0.0
var socket_accent: Color = Color(0.9, 0.75, 0.3)
var socket_textured: bool = false     # a weapon image is a child layer — skip the shape

func set_base_color(c: Color) -> void:
	base_color = c

func set_gear(colors: Array, hide_base: bool) -> void:
	gear_colors = colors
	base_hidden = hide_base
	queue_redraw()

func set_socket(cls: StringName, len_units: float, accent: Color, textured: bool) -> void:
	socket_class = cls
	socket_length = len_units
	socket_accent = accent
	socket_textured = textured
	queue_redraw()

## Remove every runtime image layer and placeholder gear.
func clear_layers() -> void:
	for c in get_children():
		if c.has_meta(&"rig_layer"):
			remove_child(c)
			c.queue_free()
	gear_colors = []
	base_hidden = false
	socket_class = &""
	socket_textured = false
	queue_redraw()

## Add an image layer on top of this part. `extra_rot` (radians) turns it in place
## (a weapon's class angle). `grip` != null = position by grip point (weapons).
func add_image(tex: Texture2D, p_offset: Vector2, p_scale: Vector2, rot: float, tint: Color, grip = null) -> Sprite2D:
	var s := Sprite2D.new()
	s.set_meta(&"rig_layer", true)
	s.texture = tex
	s.rotation = rot
	s.scale = p_scale
	s.self_modulate = tint
	if grip is Vector2:
		s.centered = false
		s.offset = -(grip as Vector2)
	else:
		s.offset = p_offset
	add_child(s)
	return s

# ---- drawing ------------------------------------------------------------------
func _draw() -> void:
	if shape == Shape.SOCKET:
		var cls := socket_class
		if cls == &"" and Engine.is_editor_hint():
			cls = preview_class
		if cls != &"" and cls != &"unarmed" and not socket_textured:
			_draw_weapon(cls)
		return
	if texture == null and not base_hidden:
		_draw_shape(thickness, base_color)
	for g in gear_colors:
		_draw_shape(thickness * GEAR_GROW, g)

func _draw_shape(w: float, col: Color) -> void:
	var edge := col.darkened(0.55)
	match shape:
		Shape.CAPSULE:
			var r := w * 0.5
			var a := Vector2.ZERO
			var b := Vector2(length, 0)
			if inset_ends:
				a = Vector2(minf(r, length * 0.5), 0)
				b = Vector2(maxf(length - r, length * 0.5), 0)
			_capsule(a, b, w + OUTLINE * 2.0, edge)
			_capsule(a, b, w, col)
		Shape.CIRCLE:
			var c := Vector2(length * 0.5, 0)
			var rad := w * 0.5
			draw_circle(c, rad + OUTLINE, edge)
			draw_circle(c, rad, col)
			if face_mark and not base_hidden:
				draw_circle(c + Vector2(rad * 0.15, rad * 0.5), maxf(1.5, rad * 0.14), edge)
		Shape.BOX:
			var rect := Rect2(-length * 0.5, -w * 0.5, length, w)
			draw_rect(rect.grow(OUTLINE), edge)
			draw_rect(rect, col)

func _capsule(a: Vector2, b: Vector2, w: float, col: Color) -> void:
	var r := w * 0.5
	if a.distance_to(b) > 0.01:
		draw_line(a, b, col, w)
	draw_circle(a, r, col)
	draw_circle(b, r, col)

## A recognisable placeholder per weapon class, drawn from the fist along +x after
## turning by the class angle.
func _draw_weapon(cls: StringName) -> void:
	var L: float = socket_length if socket_length > 0.0 else float(CLASS_LENGTH.get(cls, 48.0))
	var acc := socket_accent
	draw_set_transform(Vector2.ZERO, float(CLASS_ANGLE.get(cls, 0.0)), Vector2.ONE)
	match cls:
		&"blade":
			_bar(-7, 8, 4, WOOD)
			_bar(8, L, 5.5, STEEL)
			draw_colored_polygon(PackedVector2Array([Vector2(L, -2.75), Vector2(L + 7, 0), Vector2(L, 2.75)]), STEEL)
			draw_line(Vector2(8, -7), Vector2(8, 7), acc, 3.5)
		&"blunt":
			_bar(-6, L * 0.72, 4, WOOD)
			draw_rect(Rect2(L * 0.68, -7, L * 0.32, 14).grow(1), DARK)
			draw_rect(Rect2(L * 0.68, -7, L * 0.32, 14), STEEL)
			_bar(L * 0.6, L * 0.66, 5, acc)
		&"polearm":
			_bar(-L * 0.35, L * 0.8, 3.5, WOOD)
			draw_colored_polygon(PackedVector2Array([Vector2(L * 0.78, -5), Vector2(L, 0), Vector2(L * 0.78, 5)]), STEEL)
			_bar(L * 0.74, L * 0.78, 5, acc)
		&"staff":
			_bar(-L * 0.3, L * 0.7, 4, WOOD)
			draw_circle(Vector2(L * 0.7 + 5, 0), 7.5, acc.darkened(0.4))
			draw_circle(Vector2(L * 0.7 + 5, 0), 6, acc)
		&"gun":
			draw_rect(Rect2(-3, 0, 7, 11), DARK)
			draw_rect(Rect2(-9, -8, L * 0.55 + 9, 8), DARK)
			draw_rect(Rect2(L * 0.55, -7, L * 0.45, 4), STEEL)
			draw_rect(Rect2(-9, -8, 5, 8), acc)
		&"bow":
			var c := Vector2(-L * 0.3, 0)
			draw_arc(c, L * 0.5, -1.1, 1.1, 18, WOOD, 4)
			var e1 := c + Vector2(cos(-1.1), sin(-1.1)) * L * 0.5
			var e2 := c + Vector2(cos(1.1), sin(1.1)) * L * 0.5
			draw_line(e1, e2, Color(0.9, 0.9, 0.85), 1.2)
		&"shield":
			var r := Rect2(-6, -L * 0.62, 12, L * 1.24)
			draw_rect(r.grow(1.5), DARK)
			draw_rect(r, WOOD)
			draw_circle(Vector2(0, 0), 4.5, acc)
		_:
			_bar(0, L, 5, STEEL)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _bar(x0: float, x1: float, w: float, col: Color) -> void:
	draw_line(Vector2(x0, 0), Vector2(x1, 0), col.darkened(0.5), w + 2.0)
	draw_line(Vector2(x0, 0), Vector2(x1, 0), col, w)
