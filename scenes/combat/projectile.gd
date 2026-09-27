class_name Projectile
extends Node2D

## ============================================================================
## PROJECTILE  —  one flying effect, spawned into the battle panel
## ============================================================================
## fly() is a coroutine: it returns on ARRIVAL and frees itself. Combat resolves the
## hit after it returns, so the numbers pop exactly as it lands. RIG_SPEC §6.
## ----------------------------------------------------------------------------

var look: ProjectileLook = null
var color: Color = Color.WHITE
var _sprite: Sprite2D = null
var _t: float = 0.0
var _from: Vector2
var _to: Vector2

func setup(p_look: ProjectileLook, element_color: Color) -> void:
	look = p_look if p_look != null else ProjectileLook.new()
	color = look.color if look.color.a > 0.0 else element_color
	if look.texture:
		_sprite = Sprite2D.new()
		_sprite.texture = look.texture
		add_child(_sprite)

## Fly from -> to (battle-panel local). Awaitable; frees the node on arrival.
func fly(from: Vector2, to: Vector2) -> void:
	_from = from
	_to = to
	position = from
	var dist := from.distance_to(to)
	var time := clampf(dist / maxf(look.speed, 1.0), 0.1, 0.6)
	var tw := create_tween()
	tw.tween_method(_step, 0.0, 1.0, time)
	await tw.finished
	queue_free()

func _step(t: float) -> void:
	var prev := position
	_t = t
	var p := _from.lerp(_to, t)
	p.y -= look.arc_height * 4.0 * t * (1.0 - t)
	position = p
	if look.spin_degrees != 0.0:
		rotation += deg_to_rad(look.spin_degrees) * get_process_delta_time()
	elif p != prev:
		rotation = (p - prev).angle()
	queue_redraw()

## Drawn in local space: flight is along +x.
func _draw() -> void:
	if _sprite:
		return
	var r := look.radius
	match look.style:
		ProjectileLook.Style.BULLET:
			# a hot streak
			draw_line(Vector2(-r * 10.0, 0), Vector2.ZERO, Color(color, 0.25), r * 1.4)
			draw_line(Vector2(-r * 3.0, 0), Vector2(r, 0), color, r * 1.4)
		ProjectileLook.Style.ARROW:
			var L := 26.0
			draw_line(Vector2(-L, 0), Vector2(0, 0), Color(0.45, 0.3, 0.18), r * 1.2)
			draw_colored_polygon(PackedVector2Array([Vector2(0, -3.5), Vector2(7, 0), Vector2(0, 3.5)]), Color(0.75, 0.77, 0.8))
			draw_line(Vector2(-L, -3.5), Vector2(-L + 6, 0), color, 2.0)
			draw_line(Vector2(-L, 3.5), Vector2(-L + 6, 0), color, 2.0)
		ProjectileLook.Style.BOLT:
			# a crackling orb: a jagged tail and a bright core
			var pts := PackedVector2Array()
			for i in 6:
				pts.append(Vector2(-r * 0.9 * i, (randf() - 0.5) * r * 1.2))
			draw_polyline(pts, Color(color, 0.6), 2.0)
			draw_circle(Vector2.ZERO, r + 2.0, Color(color, 0.35))
			draw_circle(Vector2.ZERO, r, color)
			draw_circle(Vector2.ZERO, r * 0.45, color.lightened(0.7))
		_:
			draw_line(Vector2(-r * 3.0, 0), Vector2.ZERO, Color(color, 0.35), r * 1.2)
			draw_circle(Vector2.ZERO, r + 1.5, color.darkened(0.5))
			draw_circle(Vector2.ZERO, r, color)
			draw_circle(Vector2(r * 0.25, -r * 0.3), r * 0.35, color.lightened(0.6))
