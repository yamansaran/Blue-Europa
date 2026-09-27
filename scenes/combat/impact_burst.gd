class_name ImpactBurst
extends Node2D

## ============================================================================
## IMPACT BURST  —  the little flash where something lands  (class_name global)
## ============================================================================
## The combat EFFECT LIBRARY (RIG_SPEC Stage 3). One node, three kinds, all drawn in
## code and freed when done:
##   HIT   a ring + sparks where a hit lands (every SOURCED hit that costs HP)
##   CRIT  a bigger, brighter HIT
##   CAST  a soft rising ring at a caster's release (a spell / buff leaving the hand)
##   MUZZLE a quick flash at a weapon socket as a shot leaves
## spawn() puts it in `host` (the battle panel, so the camera zoom applies).
## ----------------------------------------------------------------------------

enum Kind { HIT, CRIT, CAST, MUZZLE }

const LIFE := {Kind.HIT: 0.28, Kind.CRIT: 0.4, Kind.CAST: 0.45, Kind.MUZZLE: 0.12}
const SIZE := {Kind.HIT: 22.0, Kind.CRIT: 36.0, Kind.CAST: 34.0, Kind.MUZZLE: 12.0}

var kind: Kind = Kind.HIT
var color: Color = Color.WHITE
var _t: float = 0.0
var _sparks: Array = []

static func spawn(host: Node, at: Vector2, p_color: Color, p_kind: Kind = Kind.HIT) -> ImpactBurst:
	if host == null:
		return null
	var b := ImpactBurst.new()
	b.kind = p_kind
	b.color = p_color
	b.position = at
	var n := 7 if p_kind == Kind.CRIT else 5
	if p_kind == Kind.HIT or p_kind == Kind.CRIT:
		for i in n:
			b._sparks.append(randf() * TAU)
	host.add_child(b)
	return b

func _ready() -> void:
	var tw := create_tween()
	tw.tween_method(_step, 0.0, 1.0, float(LIFE[kind]))
	tw.tween_callback(queue_free)

func _step(t: float) -> void:
	_t = t
	queue_redraw()

func _draw() -> void:
	var s: float = SIZE[kind]
	var a := 1.0 - _t
	match kind:
		Kind.CAST:
			var y := -s * 0.8 * _t
			draw_arc(Vector2(0, y), s * (0.5 + 0.5 * _t), 0.0, TAU, 28, Color(color, a * 0.8), 3.0)
			draw_arc(Vector2(0, y), s * (0.3 + 0.4 * _t), 0.0, TAU, 24, Color(color.lightened(0.5), a * 0.5), 2.0)
		Kind.MUZZLE:
			draw_circle(Vector2.ZERO, s * (1.0 - 0.5 * _t), Color(color.lightened(0.6), a))
		_:
			var r := s * (0.35 + 0.65 * _t)
			draw_arc(Vector2.ZERO, r, 0.0, TAU, 24, Color(color, a), 3.0 if kind == Kind.HIT else 4.5)
			if _t < 0.35:
				draw_circle(Vector2.ZERO, s * 0.45 * (1.0 - _t / 0.35), Color(color.lightened(0.7), a))
			for ang in _sparks:
				var d := Vector2(cos(ang), sin(ang))
				draw_line(d * r * 0.9, d * r * (1.25 + 0.3 * _t), Color(color.lightened(0.4), a), 2.0)
