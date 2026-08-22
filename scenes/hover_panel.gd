class_name HoverPanel
extends VBoxContainer

## ============================================================================
## HOVER PANEL  —  the shared hover-card CORE for every hover in the game
## ============================================================================
## One reusable card so all hover panels (ability tooltips, buff tooltips, and
## anything added later) share ONE look, ONE placement logic, ONE fade, and ONE
## keyword-colouring pipeline (via Keywords). Change the card here and every
## hover changes at once — that is the whole point.
##
## A card is a vertical stack of flush "rows"; each row is a coloured panel with a
## single line/paragraph of text. You describe the rows with plain Dictionaries
## and hand them to show_rows(); the card builds/re-uses the label nodes, colours
## any rich row's text through Keywords, reveals the rows, and positions itself
## beside an anchor rect.
##
## ROW SPEC (all keys optional except "text"):
##   {
##     "text": String,               # the row's text
##     "bg":   Color,                # panel background      (default DESC_BG)
##     "fg":   Color,                # font colour           (default DESC_TX)
##     "font_size": int,             # default 12
##     "wrap": bool,                 # wrap long text         (default false)
##     "rich": bool,                 # run text through Keywords.colorize + use a
##                                   #   RichTextLabel so element names colour
##                                   #   (default false)
##     "stage": int,                 # 0 = show immediately, 1 = fade in after the
##                                   #   reveal delay (default 0)
##     "visible": bool,              # hide this row entirely (default true)
##   }
##
## USAGE (each host owns ONE, re-used across its hover targets):
##     var card := HoverPanel.new()
##     add_child(card)
##     card.show_rows(rows, anchor_global_rect, reveal_delay, key)
##     card.hide_panel()
## `key` lets a repeated show of the SAME content refresh text in place without
## restarting the reveal (e.g. a skill node refreshing its point count on invest).
##
## It sets top_level = true so it draws over everything and is not clipped by a
## ScrollContainer/Panel around the host; positions are in GLOBAL coordinates.
##
## class_name global — RESTART Godot once after adding this script.
## ----------------------------------------------------------------------------

const DEFAULT_WIDTH := 200.0
const REVEAL_FADE := 0.2

# Shared palette (the old AbilityTooltip colours, kept so nothing looks different).
const NAME_BG := Color(0.80, 0.80, 0.82)   # light gray
const NAME_TX := Color(0.08, 0.08, 0.10)
const META_BG := Color(0.34, 0.42, 0.56)   # grayish blue
const META_TX := Color(0.96, 0.96, 0.98)
const DESC_BG := Color(0.03, 0.03, 0.05)   # black
const DESC_TX := Color(0.92, 0.92, 0.94)

## Width of the card's text column, in pixels.
var content_width: float = DEFAULT_WIDTH

var _built := false
var _timer: Timer
var _tween: Tween
## One record per row currently realised: { panel, label, spec, rich }.
var _rows: Array = []
var _key: String = ""


func _ready() -> void:
	_ensure_built()


func _ensure_built() -> void:
	if _built:
		return
	_built = true
	top_level = true                 # escape parent clipping; global coords
	z_index = 1000
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 0)   # rows sit flush
	visible = false

	_timer = Timer.new()
	_timer.one_shot = true
	_timer.timeout.connect(_reveal_delayed)
	add_child(_timer)


# ============================================================================
# Public API
# ============================================================================
## Show the card with the given rows, anchored beside `anchor_global` (a global
## Rect2, usually the hovered widget's get_global_rect()). `reveal_delay` seconds
## controls when stage-1 rows fade in (0 = everything instant). Passing a non-empty
## `key` that matches the currently shown card refreshes the row TEXT in place
## (no rebuild, no re-reveal) — handy for live-updating one line while hovered.
func show_rows(rows: Array, anchor_global: Rect2, reveal_delay: float = 0.0, key: String = "") -> void:
	_ensure_built()
	if rows.is_empty():
		hide_panel()
		return

	# Same content already shown -> update texts in place, keep reveal state.
	if key != "" and key == _key and visible and _rows.size() == rows.size():
		_update_in_place(rows)
		reset_size()
		_place(anchor_global)
		return

	_key = key
	_rebuild(rows)
	visible = true
	reset_size()
	_place(anchor_global)
	_reveal(reveal_delay)


func hide_panel() -> void:
	_key = ""
	if _timer:
		_timer.stop()
	if _tween and _tween.is_valid():
		_tween.kill()
	visible = false


# ============================================================================
# Row construction
# ============================================================================
func _rebuild(rows: Array) -> void:
	# drop the old rows
	for r in _rows:
		if is_instance_valid(r["panel"]):
			r["panel"].queue_free()
	_rows.clear()

	for spec in rows:
		if typeof(spec) != TYPE_DICTIONARY:
			continue
		var rich := bool(spec.get("rich", false))
		var panel := _make_panel(spec.get("bg", DESC_BG))
		var label: Control
		if rich:
			label = _make_rich(spec)
		else:
			label = _make_label(spec)
		panel.add_child(label)
		add_child(panel)
		panel.visible = bool(spec.get("visible", true))
		_rows.append({"panel": panel, "label": label, "spec": spec, "rich": rich})


## Update just the text of the already-built rows (used when the SAME content is
## re-shown, e.g. a skill node refreshing its point count while hovered). Only
## stage-0 rows have their visibility re-applied here; stage-1 rows keep whatever
## visibility the reveal gave them, so a mid-delay refresh doesn't skip the fade.
func _update_in_place(rows: Array) -> void:
	for i in _rows.size():
		var rec = _rows[i]
		var spec = rows[i]
		if typeof(spec) != TYPE_DICTIONARY:
			continue
		_apply_text(rec["label"], bool(rec["rich"]), str(spec.get("text", "")))
		if int(spec.get("stage", 0)) <= 0:
			rec["panel"].visible = bool(spec.get("visible", true))
		rec["spec"] = spec


func _make_panel(col) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = col if col is Color else DESC_BG
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	p.add_theme_stylebox_override("panel", sb)
	return p


func _make_label(spec: Dictionary) -> Label:
	var l := Label.new()
	l.add_theme_color_override("font_color", spec.get("fg", DESC_TX))
	l.add_theme_font_size_override("font_size", int(spec.get("font_size", 12)))
	l.custom_minimum_size = Vector2(content_width, 0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if bool(spec.get("wrap", false)):
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.text = str(spec.get("text", ""))
	return l


func _make_rich(spec: Dictionary) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.add_theme_color_override("default_color", spec.get("fg", DESC_TX))
	r.add_theme_font_size_override("normal_font_size", int(spec.get("font_size", 12)))
	r.add_theme_font_size_override("bold_font_size", int(spec.get("font_size", 12)))
	r.custom_minimum_size = Vector2(content_width, 0)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.text = Keywords.colorize(str(spec.get("text", "")))
	return r


func _apply_text(label: Control, rich: bool, text: String) -> void:
	if rich and label is RichTextLabel:
		(label as RichTextLabel).text = Keywords.colorize(text)
	elif label is Label:
		(label as Label).text = text


# ============================================================================
# Reveal
# ============================================================================
## Reveal the rows. Stage-0 rows show at once; stage-1 rows are hidden now and
## fade in after `delay` seconds (delay <= 0 => everything shows immediately).
func _reveal(delay: float) -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_timer.stop()

	if delay <= 0.0:
		for rec in _rows:
			if bool(rec["spec"].get("visible", true)):
				rec["panel"].visible = true
				rec["panel"].modulate.a = 1.0
		return

	# stage 0 shows now; stage 1 hides, then fades in on the timer
	for rec in _rows:
		var wants := bool(rec["spec"].get("visible", true))
		var stage := int(rec["spec"].get("stage", 0))
		if not wants:
			rec["panel"].visible = false
		elif stage <= 0:
			rec["panel"].visible = true
			rec["panel"].modulate.a = 1.0
		else:
			rec["panel"].visible = false
	_timer.wait_time = delay
	_timer.start()


func _reveal_delayed() -> void:
	if not visible:
		return
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_parallel(true)
	for rec in _rows:
		if int(rec["spec"].get("stage", 0)) >= 1 and bool(rec["spec"].get("visible", true)):
			rec["panel"].visible = true
			rec["panel"].modulate.a = 0.0
			_tween.tween_property(rec["panel"], "modulate:a", 1.0, REVEAL_FADE)
	reset_size()


# ============================================================================
# Placement
# ============================================================================
## Place the card just right of the anchor, flipping left when it would run off
## the right edge; clamped to stay fully on-screen.
func _place(anchor: Rect2) -> void:
	var w := content_width + 16.0
	var vp := get_viewport_rect().size
	var x := anchor.end.x + 8.0
	if x + w > vp.x:
		x = anchor.position.x - w - 8.0
	x = clampf(x, 4.0, maxf(4.0, vp.x - w - 4.0))
	var y := clampf(anchor.position.y, 4.0, maxf(4.0, vp.y - size.y - 4.0))
	global_position = Vector2(x, y)
