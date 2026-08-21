extends Window
class_name DebugStatPanel

## ============================================================================
## DEBUG STAT PANEL  —  a popup that live-edits a CharacterBase's stats
## ============================================================================
## DEBUG-ONLY tool. combat.gd builds one of these for the training-dummy fight so
## the dummy's stats can be tweaked mid-battle to exercise the damage system.
## Feed it a CharacterBase with setup(body, title); it fills a scrollable form of
## SpinBoxes from the body's CURRENT base stats. Hit "Apply" and it writes the
## values back into body.base_stats, re-solves Max HP into hp_base, re-inits
## vitals, and emits `applied` so the host can refresh the health bar.
##
## It edits the BASE stats directly (the training dummy carries no item/buff
## baskets, so base == effective for it). class_name global — RESTART Godot once
## after adding this script.
## ----------------------------------------------------------------------------

signal applied

var _body: CharacterBase = null
## stat_key -> SpinBox. Two synthetic keys drive derived values: "__max_hp" and
## "__level".
var _fields: Dictionary = {}

const MAX_HP_KEY := "__max_hp"
const LEVEL_KEY := "__level"

func _ready() -> void:
	# Window chrome / behaviour.
	title = "DEBUG — Dummy Stats"
	unresizable = false
	always_on_top = true
	# Closing the window (X) just hides it so it can be re-opened by the button.
	close_requested.connect(hide)

## Point the panel at a body and (re)build the form from its current values.
func setup(body: CharacterBase, dummy_name: String = "") -> void:
	_body = body
	if dummy_name != "":
		title = "DEBUG — %s" % dummy_name
	_build_form()

# ---------------------------------------------------------------------------
# Form construction
# ---------------------------------------------------------------------------
func _build_form() -> void:
	for c in get_children():
		if c is Control:
			c.queue_free()
	_fields.clear()
	if _body == null:
		return

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)

	# --- scrollable body ---
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	var form := VBoxContainer.new()
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_theme_constant_override("separation", 4)
	scroll.add_child(form)

	# --- VITALS ---
	_section(form, "Vitals")
	var vitals_grid := _grid(form)
	_add_field(vitals_grid, MAX_HP_KEY, "Max HP", float(_body.max_hp()), 1.0, 99999999.0, 1.0)
	_add_field(vitals_grid, LEVEL_KEY, "Level", float(_body.level), 1.0, 999.0, 1.0)

	# --- MAJORS (+ hidden luck) ---
	_section(form, "Majors")
	var majors_grid := _grid(form)
	for k in Stats.major_keys():
		_add_field(majors_grid, str(k), str(k).capitalize(), _body.get_base(str(k)), 0.0, 100000.0, 1.0)

	# --- MISC ---
	_section(form, "Misc")
	var misc_grid := _grid(form)
	_add_field(misc_grid, "crit_damage_mult", "Crit Dmg Mult", _body.get_base("crit_damage_mult"), 0.0, 100.0, 0.05)
	_add_field(misc_grid, "mitigation_stiffness", "Mit. Stiffness (m)", _body.get_base("mitigation_stiffness"), 0.0, 10.0, 0.005)

	# --- PER-ELEMENT defense / pierce / amp ---
	for e in Stats.REAL_ELEMENTS:
		_section(form, str(e).capitalize())
		var eg := _grid(form)
		_add_field(eg, Stats.defense_key(e), "Defense", _body.get_base(Stats.defense_key(e)), 0.0, 100000.0, 1.0)
		_add_field(eg, Stats.pierce_key(e), "Pierce", _body.get_base(Stats.pierce_key(e)), 0.0, 100000.0, 1.0)
		_add_field(eg, Stats.amp_key(e), "Amp", _body.get_base(Stats.amp_key(e)), 0.0, 100.0, 0.05)

	# --- buttons ---
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	btn_row.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(btn_row)

	var reset_btn := Button.new()
	reset_btn.text = "Reset fields"
	reset_btn.pressed.connect(_build_form)   # re-read current body values
	btn_row.add_child(reset_btn)

	var apply_btn := Button.new()
	apply_btn.text = "Apply"
	apply_btn.pressed.connect(_apply)
	btn_row.add_child(apply_btn)

	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.pressed.connect(hide)
	btn_row.add_child(close_btn)

func _section(parent: Control, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 15)
	lbl.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0))
	parent.add_child(lbl)

## A 4-column grid: [label][spin][label][spin], so two fields sit per row.
func _grid(parent: Control) -> GridContainer:
	var g := GridContainer.new()
	g.columns = 4
	g.add_theme_constant_override("h_separation", 8)
	g.add_theme_constant_override("v_separation", 4)
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(g)
	return g

func _add_field(grid: GridContainer, key: String, label: String, value: float, mn: float, mx: float, step: float) -> void:
	var lbl := Label.new()
	lbl.text = label
	lbl.custom_minimum_size = Vector2(96, 0)
	grid.add_child(lbl)

	var spin := SpinBox.new()
	spin.min_value = mn
	spin.max_value = mx
	spin.step = step
	spin.value = clampf(value, mn, mx)
	spin.custom_minimum_size = Vector2(110, 0)
	grid.add_child(spin)

	_fields[key] = spin

# ---------------------------------------------------------------------------
# Apply
# ---------------------------------------------------------------------------
func _apply() -> void:
	if _body == null:
		return

	# 1) plain base-stat fields (majors, crit_damage_mult, per-element def/pierce/amp).
	for key in _fields:
		if key == MAX_HP_KEY or key == LEVEL_KEY:
			continue
		_body.base_stats[key] = float((_fields[key] as SpinBox).value)

	# 2) level (identity, not a base_stat).
	if _fields.has(LEVEL_KEY):
		_body.level = int((_fields[LEVEL_KEY] as SpinBox).value)

	# 3) Max HP LAST: back-solve hp_base from the (possibly just-edited) vitality,
	#    exactly like CharacterBase.from_spec's "max_hp" bridge.
	if _fields.has(MAX_HP_KEY):
		var target_hp := float((_fields[MAX_HP_KEY] as SpinBox).value)
		_body.base_stats["hp_base"] = target_hp - _body.get_effective("vitality") * Stats.HP_PER_VITALITY

	# Refill vitals to the new maxima and tell the host to refresh its bar.
	_body.init_vitals()
	applied.emit()
