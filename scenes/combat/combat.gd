extends Control
## Combat engine, rev6. Every combatant is a CharacterBase: the player is a clone
## of Character.body; allies/enemies are built from BattleState specs via
## CharacterBase.from_spec(). Damage routes through CombatMath.resolve_damage().

const TOP_FRAC := 0.15
const MID_FRAC := 0.70

const TEAM_PLAYER := 0
const TEAM_ALLY := 1
const TEAM_ENEMY := 2

const UNIT_SIZE := Vector2(90, 140)

var _battle_panel: Control
var _bottom_panel: Panel
var _healthbar_row: HBoxContainer

var _wheel: ActionWheel
var _units: Array = []
var _player: BattleCharacter = null
var _open_target: BattleCharacter = null
var _battle_over: bool = false

enum Phase { PLAYER, RESOLVING }
var _phase: int = Phase.PLAYER

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_layout()
	_load_units()
	_build_health_bars()
	_place_units()
	_build_wheel()
	_start_battle()

# ---- layout -----------------------------------------------------------
func _band(c: Control, top_frac: float, bottom_frac: float) -> void:
	c.anchor_left = 0.0
	c.anchor_right = 1.0
	c.anchor_top = top_frac
	c.anchor_bottom = bottom_frac
	c.offset_left = 0
	c.offset_right = 0
	c.offset_top = 0
	c.offset_bottom = 0

func _make_panel(top_frac: float, bottom_frac: float, col: Color) -> Panel:
	var p := Panel.new()
	_band(p, top_frac, bottom_frac)
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	p.add_theme_stylebox_override("panel", sb)
	return p

func _build_layout() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.color = BattleState.background_color
	add_child(bg)

	if BattleState.background_path != "" and ResourceLoader.exists(BattleState.background_path):
		var tex = load(BattleState.background_path)
		if tex is Texture2D:
			var tr := TextureRect.new()
			tr.texture = tex
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(tr)

	var top_panel := _make_panel(0.0, TOP_FRAC, Color(0.14, 0.14, 0.18))
	add_child(top_panel)

	_battle_panel = Control.new()
	_band(_battle_panel, TOP_FRAC, TOP_FRAC + MID_FRAC)
	_battle_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_battle_panel)

	_bottom_panel = _make_panel(TOP_FRAC + MID_FRAC, 1.0, Color(0.12, 0.12, 0.15))
	add_child(_bottom_panel)

	_healthbar_row = HBoxContainer.new()
	_healthbar_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_healthbar_row.add_theme_constant_override("separation", 12)
	top_panel.add_child(_healthbar_row)

# ---- units ------------------------------------------------------------
func _load_units() -> void:
	var allies: Array = BattleState.allies.duplicate(true)
	var enemies: Array = BattleState.enemies.duplicate(true)

	# --- player ---
	var pbody := _make_player_body()
	pbody.char_type = Stats.CharType.CHARACTER
	_player = _spawn_unit(pbody, TEAM_PLAYER, "player")

	# --- allies ---
	for a in allies:
		if typeof(a) == TYPE_DICTIONARY:
			_spawn_unit(CharacterBase.from_spec(a), TEAM_ALLY, str(a.get("ai", "none")))

	# --- enemies (default: one Training Dummy) ---
	if enemies.is_empty():
		enemies = [ _training_dummy_spec() ]
	for e in enemies:
		if typeof(e) == TYPE_DICTIONARY:
			var eu := _spawn_unit(CharacterBase.from_spec(e), TEAM_ENEMY, str(e.get("ai", "none")))
			eu.size_scale = float(e.get("size_scale", 1.0))

func _spawn_unit(body: CharacterBase, team: int, ai: String) -> BattleCharacter:
	var u := BattleCharacter.new()
	u.body = body
	u.team = team
	u.ai = ai
	u.unit_name = body.char_name
	_battle_panel.add_child(u)
	_units.append(u)
	u.hovered.connect(_on_unit_hovered)
	u.clicked.connect(_on_unit_clicked)
	return u

## The player's combat body: an explicit spec if one was staged, else a clone of
## the persistent Character body, else a bare default.
func _make_player_body() -> CharacterBase:
	if not BattleState.player_spec.is_empty():
		return CharacterBase.from_spec(BattleState.player_spec)
	var ch := get_node_or_null("/root/Character")
	if ch and ch.has_method("get_body"):
		var b = ch.get_body()
		if b is CharacterBase:
			return (b as CharacterBase).clone()
	var fallback := CharacterBase.new()
	fallback.char_name = "Player"
	fallback.init_vitals()
	return fallback

func _training_dummy_spec() -> Dictionary:
	return {
		"name": "Training Dummy",
		"type": "enemy",
		"max_hp": 9999,
		"ai": "none",
	}

# ---- health bars ------------------------------------------------------
func _build_health_bars() -> void:
	var party_box := HBoxContainer.new()
	party_box.add_theme_constant_override("separation", 10)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var enemy_box := HBoxContainer.new()
	enemy_box.add_theme_constant_override("separation", 10)
	enemy_box.alignment = BoxContainer.ALIGNMENT_END
	_healthbar_row.add_child(party_box)
	_healthbar_row.add_child(spacer)
	_healthbar_row.add_child(enemy_box)

	for u in _units:
		var hb := BattleHealthBar.new()
		if u.team == TEAM_ENEMY:
			enemy_box.add_child(hb)
		else:
			party_box.add_child(hb)
		hb.setup(u.unit_name, u.get_max_hp(), u.get_hp(), u.get_max_spirit(), u.get_spirit(), u.body.model_color())
		u.health_bar = hb

# ---- placement --------------------------------------------------------
func _place_units() -> void:
	var party := _units.filter(func(u): return u.team != TEAM_ENEMY)
	var foes := _units.filter(func(u): return u.team == TEAM_ENEMY)
	_layout_column(party, 0.22)
	_layout_column(foes, 0.78)

func _layout_column(list: Array, x_frac: float) -> void:
	var n := list.size()
	for i in n:
		var u: BattleCharacter = list[i]
		var y_frac := 0.32 + 0.5 * float(i + 1) / float(n + 1)
		var s: float = u.size_scale
		u.anchor_left = x_frac
		u.anchor_right = x_frac
		u.anchor_top = y_frac
		u.anchor_bottom = y_frac
		u.offset_left = -UNIT_SIZE.x * 0.5 * s
		u.offset_right = UNIT_SIZE.x * 0.5 * s
		u.offset_top = -UNIT_SIZE.y * 0.5 * s
		u.offset_bottom = UNIT_SIZE.y * 0.5 * s

# ---- action wheel -----------------------------------------------------
func _build_wheel() -> void:
	_wheel = ActionWheel.new()
	_wheel.set_mode_use()
	_battle_panel.add_child(_wheel)
	_wheel.slot_selected.connect(_on_wheel_slot_selected)

func _on_unit_hovered(_u: BattleCharacter) -> void:
	# Hover only reveals the unit's floating name/level label (done inside
	# BattleCharacter). The wheel now opens on CLICK, not hover.
	pass

func _on_unit_clicked(u: BattleCharacter) -> void:
	if _battle_over:
		return
	_open_wheel_for(u)   # clicking any unit (player / ally / enemy) opens the wheel

func _open_wheel_for(u: BattleCharacter) -> void:
	_open_target = u
	_wheel.open_over(u.position + u.size * 0.5)

func _on_wheel_slot_selected(index: int, ability_id: String) -> void:
	_wheel.close()
	var ability := _get_ability(ability_id)
	if ability == null or _open_target == null:
		return
	if not _valid_target(ability, _open_target):
		print("[combat] %s can't target %s" % [ability.display_name, _open_target.unit_name])
		return
	_use_ability(ability, _open_target)

func _get_ability(id: String) -> Ability:
	var db := get_node_or_null("/root/AbilityDB")
	if db and db.has_method("get_ability"):
		return db.get_ability(id)
	return null

func _valid_target(ability: Ability, tgt: BattleCharacter) -> bool:
	match ability.target:
		Ability.Target.ENEMY: return tgt.team == TEAM_ENEMY
		Ability.Target.ALLY: return tgt.team != TEAM_ENEMY and tgt != _player
		Ability.Target.SELF: return tgt == _player
		Ability.Target.ALL_ENEMIES: return true
		Ability.Target.ALL_ALLIES: return true
	return true

func _use_ability(ability: Ability, tgt: BattleCharacter) -> void:
	if ability.kind == Ability.Kind.ATTACK:
		var sp_cost := ability.spirit_cost()
		if _player and _player.get_spirit() < sp_cost:
			print("[combat] not enough spirit for %s (need %d, have %d)" % [ability.display_name, sp_cost, _player.get_spirit()])
			return
		var atk: CharacterBase = _player.body if _player else null
		var dmg := CombatMath.resolve_damage(atk, tgt.body, ability)
		if _player:
			_player.spend_spirit(sp_cost)
		tgt.take_damage(dmg)
		print("[combat] %s hits %s for %d %s damage" % [ability.display_name, tgt.unit_name, dmg, ability.element_key()])
		_check_victory()
	else:
		print("[combat] %s used on %s (kind %d not yet implemented)" % [ability.display_name, tgt.unit_name, ability.kind])

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _wheel and _wheel.visible:
			_wheel.close()

# ---- victory ----------------------------------------------------------
func _check_victory() -> void:
	if _battle_over:
		return
	for u in _units:
		if u.team == TEAM_ENEMY and u.is_alive():
			return
	_win()

func _win() -> void:
	_battle_over = true
	if _wheel:
		_wheel.close()
	var ch := get_node_or_null("/root/Character")
	var party := []
	for u in _units:
		if u.team != TEAM_ENEMY:
			var lvl := 1
			if u == _player and ch:
				lvl = int(ch.level)
			elif u.body:
				lvl = int(u.body.level)
			party.append({"name": u.unit_name, "level": lvl, "is_player": u == _player})
	var loot: Dictionary = BattleState.roll_loot()
	BattleState.result_money = int(loot.get("money", 0))
	BattleState.result_xp = int(loot.get("xp", 0))
	BattleState.result_items = loot.get("items", [])
	BattleState.result_party = party
	print("[combat] victory! +%d money, +%d xp, %d items" % [BattleState.result_money, BattleState.result_xp, BattleState.result_items.size()])
	if typeof(GameManager) != TYPE_NIL and GameManager.has_method("go_to_victory"):
		GameManager.go_to_victory()

# ---- turn skeleton ----------------------------------------------------
func _start_battle() -> void:
	_phase = Phase.PLAYER
	print("[combat] battle start — %d units. Player's turn." % _units.size())

func end_player_turn() -> void:
	if _phase != Phase.PLAYER or _battle_over:
		return
	_phase = Phase.RESOLVING
	for u in _units:
		if u.team == TEAM_PLAYER:
			continue
		_take_ai_turn(u)
	_phase = Phase.PLAYER

func _take_ai_turn(u: BattleCharacter) -> void:
	if u.ai == "none":
		print("[combat] %s does nothing." % u.unit_name)
	else:
		print("[combat] %s has no AI yet, passing." % u.unit_name)

# ---- leaving ----------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not _battle_over:
		_leave_combat()

func _leave_combat() -> void:
	BattleState.clear()
	BattleState.clear_result()
	if typeof(GameManager) != TYPE_NIL and GameManager.has_method("go_to_overworld"):
		GameManager.go_to_overworld()
	else:
		print("[combat] no GameManager.go_to_overworld() — staying put.")
