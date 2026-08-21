class_name DamageNumber
extends Label

## ============================================================================
## DAMAGE NUMBER  —  the floating combat damage popup (class_name global)
## ============================================================================
## One damage number that animates over a combatant when it takes damage. The
## animation has two phases, matching the spec:
##   PHASE 1 (0.5s): fades IN while dropping DOWN a short distance, quickly.
##   PHASE 2 (3.0s): slowly floats UP while fading AWAY to nothing, then frees.
## The text colour is the attack element's colour, pulled from ElementColors so
## the palette stays defined in exactly one place.
##
## HEALS reuse the same popup: pass is_heal (or use spawn_heal) to show "+N" in
## green instead of a coloured damage number.
##
## Spawn it with the static helper — the caller never manages the node itself:
##   DamageNumber.spawn(parent, point, amount, element, is_crit)
##   DamageNumber.spawn_heal(parent, point, amount)
## `point` is where the number floats, in `parent`'s LOCAL coordinate space.
##
## class_name global — RESTART Godot once after adding this script.
## ----------------------------------------------------------------------------

const DROP_DISTANCE := 22.0     # px the number drops during phase 1
const RISE_DISTANCE := 60.0     # px the number floats up during phase 2
const DROP_TIME := 0.5          # phase 1 duration (fade-in + drop)
const RISE_TIME := 3.0          # phase 2 duration (rise + fade-out)
const BOX_WIDTH := 140.0        # fixed width so the text stays centred on `point`
const BOX_HEIGHT := 34.0        # real height so the label actually draws its text
const FONT_SIZE := 22
const CRIT_FONT_SIZE := 32
const OUTLINE_SIZE := 6
const HEAL_COLOR := Color(0.30, 0.85, 0.38)   # green for healing "+N"


## Build a damage number, add it to `parent`, and start its animation.
static func spawn(parent: Node, point: Vector2, amount: int, element: String = "physical", is_crit: bool = false, is_heal: bool = false) -> DamageNumber:
	var dn := DamageNumber.new()
	dn._configure(amount, element, is_crit, is_heal)
	parent.add_child(dn)
	dn._begin(point)
	return dn

## Convenience: a green "+N" healing popup.
static func spawn_heal(parent: Node, point: Vector2, amount: int) -> DamageNumber:
	return spawn(parent, point, amount, "physical", false, true)


func _configure(amount: int, element: String, is_crit: bool, is_heal: bool = false) -> void:
	if is_heal:
		text = "+%d" % amount
	else:
		text = ("%d!" % amount) if is_crit else str(amount)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 100                # draw above the combat models
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	custom_minimum_size = Vector2(BOX_WIDTH, BOX_HEIGHT)
	size = Vector2(BOX_WIDTH, BOX_HEIGHT)

	var col := HEAL_COLOR if is_heal else ElementColors.color(element)
	add_theme_font_size_override("font_size", CRIT_FONT_SIZE if (is_crit and not is_heal) else FONT_SIZE)
	add_theme_color_override("font_color", col)
	# Outline so the number reads over any background/model. Dark element colours
	# (blood, true/black) get a LIGHT outline instead of the usual dark one.
	var outline := Color(1, 1, 1) if _luminance(col) < 0.22 else Color(0, 0, 0)
	add_theme_color_override("font_outline_color", outline)
	add_theme_constant_override("outline_size", OUTLINE_SIZE)


func _begin(point: Vector2) -> void:
	# Centre the fixed-size box on the target point.
	position = Vector2(point.x - BOX_WIDTH * 0.5, point.y - BOX_HEIGHT * 0.5)
	modulate.a = 0.0
	var base_y := position.y

	# Sequential tween by default; parallel() marks a tweener to run alongside the
	# PREVIOUS one. This is the reliable idiom — mixing set_parallel()+chain() can
	# fire the final queue_free() at t=0 and free the label before it ever draws.
	var t := create_tween()
	# PHASE 1 — fade in (0->1) while dropping down quickly.
	t.tween_property(self, "modulate:a", 1.0, DROP_TIME)
	t.parallel().tween_property(self, "position:y", base_y + DROP_DISTANCE, DROP_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# PHASE 2 — runs AFTER phase 1: slowly float up while fading away to nothing.
	t.tween_property(self, "position:y", base_y + DROP_DISTANCE - RISE_DISTANCE, RISE_TIME).set_trans(Tween.TRANS_LINEAR)
	t.parallel().tween_property(self, "modulate:a", 0.0, RISE_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	# free the node once the whole animation has finished.
	t.tween_callback(queue_free)


static func _luminance(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
