class_name DamageNumber
extends Label

## ============================================================================
## DAMAGE NUMBER  —  the floating combat damage popup (class_name global)
## ============================================================================
## One damage number that animates over a combatant when it takes damage. The
## animation has two phases:
##   PHASE 1 (DROP_TIME, fast): fades IN while dropping DOWN a short distance.
##   PHASE 2 (RISE_TIME, slow): slowly floats UP while fading AWAY, then frees.
## The text colour is the attack element's colour, pulled from ElementColors so
## the palette stays defined in exactly one place.
##
## SIZE SCALES WITH THE DAMAGE. Bigger hits spawn bigger numbers (BASE_FONT_SIZE
## plus a sqrt-scaled bonus, clamped to [MIN_FONT_SIZE, MAX_FONT_SIZE]); the box
## and outline grow with the font so the text stays centred and readable.
##
## CRITS ARE ITALICISED (and a touch bigger, and keep the "!") using the REAL
## Inter italic face (assets/fonts); non-crits use the upright Inter face. Both
## are set as a direct font override, so they render regardless of the project's
## default font.
##
## Each number also gets a random LEFT/RIGHT spawn deviation so a flurry of hits
## fans out instead of stacking on one spot.
##
## HEALS reuse the same popup: pass is_heal (or use spawn_heal) to show "+N" in
## green (scaled the same way, never italic).
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
const DROP_TIME := 0.1          # phase 1 duration (fade-in + quick drop)
const RISE_TIME := 3.0          # phase 2 duration (slow rise + fade-out)

# --- size scaling -----------------------------------------------------------
const BASE_FONT_SIZE := 26      # font for a ~0-damage hit (was a flat 22)
const MIN_FONT_SIZE := 22       # never smaller than this
const MAX_FONT_SIZE := 68       # never larger than this
const SIZE_PER_SQRT := 1.7      # +this much font per sqrt(amount) of damage
const CRIT_SIZE_MULT := 1.22    # crits are additionally this much bigger

# --- fonts ------------------------------------------------------------------
## Inter (added under assets/fonts). Crits use the REAL italic face; everything
## else uses the upright face. Set as a direct font override so the numbers look
## right even if the project default font ever changes.
const FONT_REGULAR := preload("res://assets/fonts/Inter-VariableFont_opsz,wght.ttf")
const FONT_ITALIC := preload("res://assets/fonts/Inter-Italic-VariableFont_opsz,wght.ttf")

# --- spawn spread -----------------------------------------------------------
const HORIZONTAL_DEVIATION := 30.0   # max px a number is nudged left/right on spawn

const OUTLINE_MIN := 5
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

	# --- size scales with the damage/heal amount ---
	var font_size := _font_size_for(amount, is_crit and not is_heal)
	add_theme_font_size_override("font_size", font_size)

	# Box grows with the font so the text stays centred on `point` and isn't
	# vertically clipped for big hits.
	var box_w := maxf(140.0, float(font_size) * 6.0)
	var box_h := float(font_size) * 1.7
	custom_minimum_size = Vector2(box_w, box_h)
	size = Vector2(box_w, box_h)

	# --- face: crits get the REAL Inter italic, everything else upright ---
	add_theme_font_override("font", FONT_ITALIC if (is_crit and not is_heal) else FONT_REGULAR)

	# --- colour + outline ---
	var col := HEAL_COLOR if is_heal else ElementColors.color(element)
	add_theme_color_override("font_color", col)
	# Outline so the number reads over any background/model. Dark element colours
	# (blood, true/black) get a LIGHT outline instead of the usual dark one. The
	# outline thickens a little for bigger numbers.
	var outline := Color(1, 1, 1) if _luminance(col) < 0.22 else Color(0, 0, 0)
	add_theme_color_override("font_outline_color", outline)
	add_theme_constant_override("outline_size", maxi(OUTLINE_MIN, int(round(font_size / 6.0))))


## Font size for a given amount. sqrt keeps huge numbers from ballooning; the
## result is clamped so it always stays legible and never absurd.
func _font_size_for(amount: int, is_crit: bool) -> int:
	var fs := float(BASE_FONT_SIZE) + SIZE_PER_SQRT * sqrt(float(maxi(amount, 0)))
	if is_crit:
		fs *= CRIT_SIZE_MULT
	return clampi(int(round(fs)), MIN_FONT_SIZE, MAX_FONT_SIZE)


func _begin(point: Vector2) -> void:
	# Random left/right spawn deviation so simultaneous hits fan out.
	var dx := randf_range(-HORIZONTAL_DEVIATION, HORIZONTAL_DEVIATION)
	# Centre the box on the (deviated) target point.
	position = Vector2(point.x + dx - size.x * 0.5, point.y - size.y * 0.5)
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
