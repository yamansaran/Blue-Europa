extends Control

## ABILITIES SCREEN (shell-content panel).
## Skill-tree shell + overview counter + respec, the combat wheel (drag-drop
## editor) and the ability pool — PLUS (rev6) a live attributes readout backed by
## the Character body: majors + minors shown as base / bonus / effective, with
## attribute-point spending and an attribute re-spec.

@export var default_skill_tree_scene: PackedScene

## Nudge the loaded skill tree up a hair so long trees clear the bottom edge.
const SKILL_TREE_Y_OFFSET := -12.0

@onready var _skill_tree_container: Control = $SkillTreePanel/SkillTreeContainer
@onready var _skill_tree_placeholder: Label = $SkillTreePanel/SkillTreePlaceholder
@onready var _respec_button: Button = $SkillTreePanel/RespecButton

var _wheel: ActionWheel
var _pool_list: VBoxContainer
var _attr_list: VBoxContainer

## Overview readout labels (name / level / skill points / attribute points).
var _ov_name: Label
var _ov_level: Label
var _ov_skill: Label
var _ov_attr: Label
## Remembered minor-attribute view (Pierce/Defense/Amp) so it survives refreshes.
var _minor_metric: int = 0


func _ready() -> void:
	_respec_button.pressed.connect(_on_respec_pressed)
	var ch := _character()
	if ch and not ch.changed.is_connected(_refresh_overview):
		ch.changed.connect(_refresh_overview)
	if ch and not ch.changed.is_connected(_refresh_pool):
		ch.changed.connect(_refresh_pool)
	if ch and not ch.changed.is_connected(_refresh_attributes):
		ch.changed.connect(_refresh_attributes)
	if default_skill_tree_scene != null:
		load_skill_tree(default_skill_tree_scene)
	_build_overview_readout()
	_build_combat_action_ui()
	_build_attributes_readout()
	_build_close_button()


# ---------------------------------------------------- close / return button
func _build_close_button() -> void:
	var x := Button.new()
	x.text = "X"
	x.tooltip_text = "Return to overworld"
	x.add_theme_font_size_override("font_size", 16)
	# top-right corner of the whole screen (sits over the combat wheel panel)
	x.anchor_left = 1.0
	x.anchor_right = 1.0
	x.anchor_top = 0.0
	x.anchor_bottom = 0.0
	x.offset_left = -40.0
	x.offset_top = 8.0
	x.offset_right = -8.0
	x.offset_bottom = 40.0
	x.pressed.connect(_on_close_pressed)
	add_child(x)   # added last -> draws on top of the panels


func _on_close_pressed() -> void:
	if typeof(GameManager) != TYPE_NIL and GameManager.has_method("go_to_overworld"):
		GameManager.go_to_overworld()


# ---------------------------------------------------- overview readout
## The OverviewPanel (top-left) shows, in order: the character's name, level,
## skill points available, and attribute points available. Built in code so it
## stays in sync with Character.changed.
func _build_overview_readout() -> void:
	var panel: Control = get_node_or_null("OverviewPanel")
	if panel == null:
		return
	# shrink the "OVERVIEW" title to a top strip so the readout has room below
	var title := panel.get_node_or_null("Title")
	if title is Control:
		(title as Control).anchor_top = 0.0
		(title as Control).anchor_bottom = 0.22

	var vbox := VBoxContainer.new()
	vbox.anchor_left = 0.06
	vbox.anchor_top = 0.26
	vbox.anchor_right = 0.94
	vbox.anchor_bottom = 0.98
	vbox.offset_left = 0.0
	vbox.offset_top = 0.0
	vbox.offset_right = 0.0
	vbox.offset_bottom = 0.0
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	_ov_name = Label.new()
	_ov_name.add_theme_font_size_override("font_size", 22)
	_ov_name.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	_ov_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_ov_name)

	_ov_level = Label.new()
	_ov_level.add_theme_font_size_override("font_size", 16)
	_ov_level.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	_ov_level.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_ov_level)

	_ov_skill = Label.new()
	_ov_skill.add_theme_font_size_override("font_size", 16)
	_ov_skill.add_theme_color_override("font_color", Color(1.0, 0.86, 0.35))
	_ov_skill.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_ov_skill)

	_ov_attr = Label.new()
	_ov_attr.add_theme_font_size_override("font_size", 16)
	_ov_attr.add_theme_color_override("font_color", Color(1.0, 0.86, 0.35))
	_ov_attr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_ov_attr)

	_refresh_overview()


func _refresh_overview() -> void:
	var ch := _character()
	if _ov_name:
		_ov_name.text = str(ch.char_name) if ch else "--"
	if _ov_level:
		_ov_level.text = ("Level %d" % int(ch.level)) if ch else "Level --"
	if _ov_skill:
		_ov_skill.text = ("Skill Points: %d" % int(ch.skill_points)) if ch else "Skill Points: --"
	if _ov_attr:
		_ov_attr.text = ("Attribute Points: %d" % int(ch.get_attribute_points())) if ch else "Attribute Points: --"


func _on_respec_pressed() -> void:
	var ch := _character()
	if ch:
		ch.respec()


func _character() -> Node:
	return get_node_or_null("/root/Character")


# ---------------------------------------------------- attributes readout
func _build_attributes_readout() -> void:
	var panel: Control = get_node_or_null("AttributesPanel")
	if panel == null:
		return
	# shrink the title to a top strip so the readout has room
	var title := panel.get_node_or_null("Title")
	if title is Control:
		(title as Control).anchor_top = 0.0
		(title as Control).anchor_bottom = 0.1

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.anchor_left = 0.04
	scroll.anchor_top = 0.12
	scroll.anchor_right = 0.96
	scroll.anchor_bottom = 0.97
	scroll.offset_left = 0.0
	scroll.offset_top = 0.0
	scroll.offset_right = 0.0
	scroll.offset_bottom = 0.0
	panel.add_child(scroll)

	_attr_list = VBoxContainer.new()
	_attr_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_attr_list.add_theme_constant_override("separation", 2)
	scroll.add_child(_attr_list)
	_refresh_attributes()


func _refresh_attributes() -> void:
	if _attr_list == null:
		return
	for c in _attr_list.get_children():
		c.queue_free()
	var ch := _character()
	if ch == null or not ch.has_method("get_body"):
		return
	var body: CharacterBase = ch.get_body()
	if body == null:
		return

	# --- derived vitals (attribute-points counter now lives in the Overview panel) ---
	_add_stat_line("Max HP", body.max_hp())
	_add_stat_line("Spirit (max)", body.max_spirit())

	# --- major stats, each spendable ---
	_add_header("MAJOR", Color(0.75, 0.85, 1.0))
	for major in Stats.visible_major_keys():
		_add_major_row(ch, body, major)

	var respec := Button.new()
	respec.text = "Respec Attributes"
	respec.add_theme_font_size_override("font_size", 11)
	respec.pressed.connect(func(): ch.respec_attributes())
	_attr_list.add_child(respec)

	# --- minor stats (bar graphs, read-only) ---
	_add_header("RESIST", Color(1.0, 0.8, 0.75))
	var bars := MinorAttrBars.new()
	bars.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_attr_list.add_child(bars)
	bars.set_metric(_minor_metric)
	bars.set_body(body)
	bars.metric_changed.connect(func(m): _minor_metric = m)


func _add_header(text: String, col: Color) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", col)
	_attr_list.add_child(l)

## A plain "Name  value" line. If `override_text` is non-empty it is shown
## instead of the numeric value.
func _add_stat_line(stat_name: String, value: int, override_text: String = "") -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var n := Label.new()
	n.text = stat_name
	n.add_theme_font_size_override("font_size", 12)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := Label.new()
	v.text = override_text if override_text != "" else str(value)
	v.add_theme_font_size_override("font_size", 12)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(n)
	row.add_child(v)
	_attr_list.add_child(row)

## A major-stat row: "Strength  10 (+6) 16   [+]"
func _add_major_row(ch: Node, body: CharacterBase, major: String) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 4)

	var base_v := int(round(body.get_base(major)))
	var bonus_v := int(round(body.get_bonus(major)))
	var mult := body.get_mult_bonus(major)      # fraction: 0.20 = +20%
	var eff_v := body.get_effective_int(major)

	var n := Label.new()
	n.text = major.capitalize()
	n.add_theme_font_size_override("font_size", 12)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(n)

	# Show base, the flat bonus, and the multiplier so the effective value reads as
	# "base (+flat) ×mult = eff". Each modifier segment only appears when present.
	var v := Label.new()
	if bonus_v != 0 or not is_zero_approx(mult):
		var t := str(base_v)
		if bonus_v != 0:
			t += " (%s%d)" % ["+" if bonus_v > 0 else "", bonus_v]
		if not is_zero_approx(mult):
			t += " ×%.2f" % (1.0 + mult)
		t += " = %d" % eff_v
		v.text = t
	else:
		v.text = str(eff_v)
	v.add_theme_font_size_override("font_size", 12)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(v)

	# Non-allocatable majors (e.g. spirit) show no "+" button at all.
	if not Stats.NON_ALLOCATABLE_MAJORS.has(major):
		var plus := Button.new()
		plus.text = "+"
		plus.custom_minimum_size = Vector2(24, 0)
		plus.add_theme_font_size_override("font_size", 12)
		plus.disabled = not ch.can_allocate_attribute(major)
		plus.pressed.connect(func(): ch.allocate_attribute(major))
		row.add_child(plus)

	_attr_list.add_child(row)


# ---------------------------------------------------- combat wheel + pool
func _build_combat_action_ui() -> void:
	var wheel_panel: Control = get_node_or_null("CombatActionPanel/CombatWheelPanel")
	if wheel_panel:
		var wtitle := wheel_panel.get_node_or_null("Title")
		if wtitle is Control:
			(wtitle as Control).anchor_top = 0.0
			(wtitle as Control).anchor_bottom = 0.15
		_wheel = ActionWheel.new()
		wheel_panel.add_child(_wheel)
		_wheel.set_mode_edit()
		_wheel.anchor_left = 0.02
		_wheel.anchor_top = 0.16
		_wheel.anchor_right = 0.98
		_wheel.anchor_bottom = 0.98
		_wheel.offset_left = 0.0
		_wheel.offset_top = 0.0
		_wheel.offset_right = 0.0
		_wheel.offset_bottom = 0.0

	var pool_panel: Control = get_node_or_null("CombatActionPanel/AbilityPoolPanel")
	if pool_panel:
		var ptitle := pool_panel.get_node_or_null("Title")
		if ptitle is Control:
			(ptitle as Control).anchor_top = 0.0
			(ptitle as Control).anchor_bottom = 0.14
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.anchor_left = 0.05
		scroll.anchor_top = 0.16
		scroll.anchor_right = 0.95
		scroll.anchor_bottom = 0.97
		scroll.offset_left = 0.0
		scroll.offset_top = 0.0
		scroll.offset_right = 0.0
		scroll.offset_bottom = 0.0
		pool_panel.add_child(scroll)
		_pool_list = VBoxContainer.new()
		_pool_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_pool_list.add_theme_constant_override("separation", 6)
		scroll.add_child(_pool_list)
		_refresh_pool()


func _refresh_pool() -> void:
	if _pool_list == null:
		return
	for c in _pool_list.get_children():
		c.queue_free()
	var ch := _character()
	var db := get_node_or_null("/root/AbilityDB")
	if ch == null:
		return
	for id in ch.unlocked_abilities:
		var display := str(id)
		if db and db.has_method("get_ability"):
			var ab = db.get_ability(id)
			if ab != null:
				display = ab.display_name
		var entry := AbilityPoolEntry.new()
		_pool_list.add_child(entry)
		entry.setup(str(id), display)


# ---------------------------------------------------- skill-tree shell API
func load_skill_tree(tree_scene: PackedScene) -> void:
	if tree_scene == null:
		return
	_clear_skill_tree()
	var tree: Node = tree_scene.instantiate()
	_skill_tree_container.add_child(tree)
	if tree is Control:
		var c: Control = tree
		c.anchor_left = 0.0
		c.anchor_top = 0.0
		c.anchor_right = 1.0
		c.anchor_bottom = 1.0
		c.offset_left = 0.0
		c.offset_top = SKILL_TREE_Y_OFFSET
		c.offset_right = 0.0
		c.offset_bottom = SKILL_TREE_Y_OFFSET
	if _skill_tree_placeholder != null:
		_skill_tree_placeholder.visible = false


func load_skill_tree_path(path: String) -> void:
	var res: Resource = load(path)
	if res is PackedScene:
		load_skill_tree(res)
	else:
		push_warning("Abilities.load_skill_tree_path: not a PackedScene -> " + path)


func _clear_skill_tree() -> void:
	for child in _skill_tree_container.get_children():
		child.queue_free()
	if _skill_tree_placeholder != null:
		_skill_tree_placeholder.visible = true
