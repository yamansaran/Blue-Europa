extends RefCounted
class_name BuffIconPainter

## ============================================================================
## BUFF ICON PAINTER  —  draws one buff/debuff icon onto any CanvasItem
## ============================================================================
## Part of the BUFF ICON ENGINE (scenes/ui/buff_icons/):
##   BuffIconStyle    HOW an icon looks (shape, grading, bevel, border, rune stroke)
##   BuffIconCatalog  WHAT an icon shows (colour + rune per buff id)
##   RuneGlyphs       the rune alphabet as stroke data
##   BuffIconPainter  this — turns the three into draw calls
##
## Everything that shows a buff icon (the top-panel BuffBar, the strip under each
## unit's overhead bars, any future tooltip or codex) calls ONE function:
##
##     BuffIconPainter.draw_icon(canvas_item, rect, entry, {"hovered": bool})
##
## from inside that CanvasItem's _draw(). No caller knows the icon's shape, colour
## or rune, so changing the look is an edit to this folder and nothing else.
##
## class_name global — RESTART Godot once after adding this script.
## ----------------------------------------------------------------------------

const STYLE_PATH := "res://scenes/ui/buff_icons/default_buff_icon_style.tres"

static var _style: BuffIconStyle = null

## The active style. Loaded once from STYLE_PATH; a missing / broken file falls back
## to the script defaults so icons always draw.
static func style() -> BuffIconStyle:
	if _style == null:
		if ResourceLoader.exists(STYLE_PATH):
			var res = load(STYLE_PATH)
			if res is BuffIconStyle:
				_style = res
		if _style == null:
			_style = BuffIconStyle.new()
	return _style

## Swap the style at runtime (a settings screen, a test, a colour-blind mode…).
static func set_style(s: BuffIconStyle) -> void:
	_style = s

# ----------------------------------------------------------------------------
## Draw `entry` (a buff entry Dictionary, or a bare id String) into `rect` on `ci`.
## opts: "hovered" (bool), "show_counter" (bool, default style), "empowered" (bool,
## default read from the entry).
static func draw_icon(ci: CanvasItem, rect: Rect2, entry, opts: Dictionary = {}) -> void:
	var st := style()
	var look := BuffIconCatalog.look(entry)
	var is_debuff := false
	if typeof(entry) == TYPE_DICTIONARY:
		is_debuff = str(entry.get("kind", "buff")) == "debuff"
	var base := _grade(look["color"], st, is_debuff)

	var r := rect.grow(-st.margin)
	var outline := shape_points(r, st)
	if outline.size() < 3:
		return

	# 1) drop shadow
	if st.shadow_color.a > 0.0 and st.shadow_offset != Vector2.ZERO:
		var sh := PackedVector2Array()
		for p in outline:
			sh.append(p + st.shadow_offset)
		ci.draw_colored_polygon(sh, st.shadow_color)

	# 2) body with a vertical gradient (lit top, shaded bottom)
	var top_col := base.lightened(st.top_lighten)
	var bot_col := base.darkened(st.bottom_darken)
	ci.draw_polygon(outline, _vertical_gradient(outline, r, top_col, bot_col))

	# 3) bevel: a lighter band hugging the top edge, fading out downward
	if st.bevel_strength > 0.0 and st.bevel_height > 0.0:
		var bevel_rect := r.grow(-st.bevel_inset)
		bevel_rect.size.y *= st.bevel_height
		var bevel := shape_points(Rect2(bevel_rect.position, Vector2(bevel_rect.size.x, r.size.y - st.bevel_inset * 2.0)), st)
		bevel = _clip_above(bevel, bevel_rect.position.y + bevel_rect.size.y)
		if bevel.size() >= 3:
			var hi := Color(1, 1, 1, st.bevel_strength)
			var lo := Color(1, 1, 1, 0.0)
			ci.draw_polygon(bevel, _vertical_gradient(bevel, bevel_rect, hi, lo))

	# 4) rune
	_draw_rune(ci, r, str(look["rune"]), st, base)

	# 5) border (buff / debuff / hovered / empowered)
	var empowered := bool(opts.get("empowered", _is_empowered(entry)))
	var bcol := st.debuff_border_color if is_debuff else st.buff_border_color
	var bw := st.border_width
	if empowered:
		bcol = st.empowered_border_color
		bw = st.empowered_border_width
	if bool(opts.get("hovered", false)):
		bcol = st.hover_border_color
	if bw > 0.0:
		var closed := outline.duplicate()
		closed.append(outline[0])
		ci.draw_polyline(closed, bcol, bw, true)

	# 6) counters
	if typeof(entry) == TYPE_DICTIONARY and r.size.y >= st.min_counter_height:
		if bool(opts.get("show_counter", st.show_counter)):
			var ctext := counter_text(entry)
			if ctext != "":
				_draw_text(ci, ctext, Vector2(r.end.x - 1.0, r.end.y - 1.5), st.counter_font_size, st, true)
		if st.show_stacks:
			# THE POTENCY BADGE. Reads what this instance is actually WORTH rather than
			# its `stacks` count, which is 1 on almost everything now that stacking
			# means independent instances. Two things move it:
			#   - the caster's Disdain, baked in at apply time (potency_applied)
			#   - the entry's own ramp, if it decays or grows (Buff.ramp)
			# The second is the one that matters in play: an Amphetamines counting
			# itself down 1.00 -> 0.85 -> 0.70 has no other tell on the chip, and
			# three of them ticking down at once is the shape of that whole fight.
			# Whole numbers print without decimals so an ordinary x2 still reads clean.
			var pot := float(entry.get("potency_applied", 1.0)) * Buff.ramp(entry)
			if not is_equal_approx(pot, 1.0):
				var plabel := ("x%d" % int(round(pot))) if is_equal_approx(pot, round(pot)) else ("x%.2f" % pot)
				_draw_text(ci, plabel, Vector2(r.position.x + 1.5, r.position.y + float(st.stack_font_size) + 1.5), st.stack_font_size, st, false)

## The turns-left counter. PERMANENT (infinite) effects show NOTHING — no "inf".
static func counter_text(entry: Dictionary) -> String:
	# A grouped field chip (BuffBar.group_entries) stands for several instances.
	if int(entry.get("_group_count", 1)) > 1:
		return "..."
	var dur := int(entry.get("duration", -1))
	return "" if dur < 0 else str(dur)

# ----------------------------------------------------------------------------
# Shapes — every shape is an outline polygon, so the fill / bevel / border code
# never cares which one it is.
# ----------------------------------------------------------------------------
static func shape_points(r: Rect2, st: BuffIconStyle) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var c := r.get_center()
	var hw := r.size.x * 0.5
	var hh := r.size.y * 0.5
	match st.shape:
		BuffIconStyle.Shape.RECT:
			pts = PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
		BuffIconStyle.Shape.ROUNDED_RECT:
			var rad := minf(r.size.x, r.size.y) * st.corner_radius
			if rad <= 0.5:
				return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
			var n := maxi(2, st.corner_detail)
			var corners := [
				[Vector2(r.end.x - rad, r.position.y + rad), -PI * 0.5],   # top-right
				[Vector2(r.end.x - rad, r.end.y - rad), 0.0],              # bottom-right
				[Vector2(r.position.x + rad, r.end.y - rad), PI * 0.5],    # bottom-left
				[Vector2(r.position.x + rad, r.position.y + rad), PI],     # top-left
			]
			for cc in corners:
				for i in n + 1:
					var a: float = float(cc[1]) + (PI * 0.5) * float(i) / float(n)
					pts.append((cc[0] as Vector2) + Vector2(cos(a), sin(a)) * rad)
		BuffIconStyle.Shape.CIRCLE:
			var seg := maxi(12, st.corner_detail * 4)
			for i in seg:
				var a := TAU * float(i) / float(seg) - PI * 0.5
				pts.append(c + Vector2(cos(a) * hw, sin(a) * hh))
		BuffIconStyle.Shape.DIAMOND:
			pts = PackedVector2Array([Vector2(c.x, r.position.y), Vector2(r.end.x, c.y), Vector2(c.x, r.end.y), Vector2(r.position.x, c.y)])
		BuffIconStyle.Shape.HEXAGON:
			var q := r.size.y * 0.25
			pts = PackedVector2Array([Vector2(c.x, r.position.y), Vector2(r.end.x, r.position.y + q), Vector2(r.end.x, r.end.y - q),
				Vector2(c.x, r.end.y), Vector2(r.position.x, r.end.y - q), Vector2(r.position.x, r.position.y + q)])
		BuffIconStyle.Shape.OCTAGON:
			var k := minf(r.size.x, r.size.y) * 0.29
			pts = PackedVector2Array([Vector2(r.position.x + k, r.position.y), Vector2(r.end.x - k, r.position.y), Vector2(r.end.x, r.position.y + k),
				Vector2(r.end.x, r.end.y - k), Vector2(r.end.x - k, r.end.y), Vector2(r.position.x + k, r.end.y),
				Vector2(r.position.x, r.end.y - k), Vector2(r.position.x, r.position.y + k)])
		BuffIconStyle.Shape.SHIELD:
			pts = PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), Vector2(r.end.x, r.position.y + r.size.y * 0.55),
				Vector2(c.x, r.end.y), Vector2(r.position.x, r.position.y + r.size.y * 0.55)])
	return pts

# ----------------------------------------------------------------------------
static func _grade(col: Color, st: BuffIconStyle, is_debuff: bool) -> Color:
	var c := Color.from_hsv(col.h, clampf(col.s * st.saturation, 0.0, 1.0), clampf(col.v * st.value, 0.0, 1.0), 1.0)
	if is_debuff and st.debuff_tint_amount > 0.0:
		c = c.lerp(st.debuff_tint, st.debuff_tint_amount)
	return c

static func _vertical_gradient(pts: PackedVector2Array, r: Rect2, top: Color, bottom: Color) -> PackedColorArray:
	var cols := PackedColorArray()
	var h := maxf(0.001, r.size.y)
	for p in pts:
		cols.append(top.lerp(bottom, clampf((p.y - r.position.y) / h, 0.0, 1.0)))
	return cols

## Keep only the part of a (convex-ish) outline above y = cut, closing it along the cut.
static func _clip_above(pts: PackedVector2Array, cut: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := pts.size()
	for i in n:
		var a := pts[i]
		var b := pts[(i + 1) % n]
		var a_in := a.y <= cut
		var b_in := b.y <= cut
		if a_in:
			out.append(a)
		if a_in != b_in:
			var t := (cut - a.y) / (b.y - a.y)
			out.append(a.lerp(b, t))
	return out

static func _draw_rune(ci: CanvasItem, r: Rect2, rune: String, st: BuffIconStyle, base: Color) -> void:
	var lum := 0.2126 * base.r + 0.7152 * base.g + 0.0722 * base.b
	var col := st.rune_color_on_light if lum > st.light_threshold else st.rune_color
	var box_h := minf(r.size.x / RuneGlyphs.RUNE_ASPECT, r.size.y) * st.rune_scale
	var box_w := box_h * RuneGlyphs.RUNE_ASPECT
	var origin := r.get_center() - Vector2(box_w, box_h) * 0.5 + Vector2(0.0, r.size.y * st.rune_offset_y)

	if st.rune_source == BuffIconStyle.RuneSource.FONT and st.rune_font != null and RuneGlyphs.UNICODE.has(rune):
		var glyph: String = RuneGlyphs.UNICODE[rune]
		var fs := int(round(box_h))
		var gs := st.rune_font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var pos := r.get_center() + Vector2(-gs.x * 0.5, fs * 0.35)
		ci.draw_string(st.rune_font, pos + st.rune_shadow_offset, glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, st.rune_shadow_color)
		ci.draw_string(st.rune_font, pos, glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		return

	var width := maxf(st.rune_min_width, box_h * st.rune_width)
	for stroke in RuneGlyphs.strokes(rune):
		var line := PackedVector2Array()
		for p in stroke:
			line.append(origin + Vector2((p as Vector2).x * box_w, (p as Vector2).y * box_h))
		if line.size() < 2:
			continue
		if st.rune_shadow_color.a > 0.0:
			var sh := PackedVector2Array()
			for q in line:
				sh.append(q + st.rune_shadow_offset)
			ci.draw_polyline(sh, st.rune_shadow_color, width, true)
		ci.draw_polyline(line, col, width, true)

static func _draw_text(ci: CanvasItem, text: String, anchor: Vector2, fs: int, st: BuffIconStyle, right_align: bool) -> void:
	var font := ThemeDB.fallback_font
	if ci is Control:
		font = (ci as Control).get_theme_default_font()
	if font == null:
		return
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pos := Vector2(anchor.x - w, anchor.y) if right_align else anchor
	for off in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
		ci.draw_string(font, pos + off, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, st.counter_outline)
	ci.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, st.counter_color)

static func _is_empowered(entry) -> bool:
	if typeof(entry) != TYPE_DICTIONARY:
		return false
	return CombatResist.is_empowered(entry)
