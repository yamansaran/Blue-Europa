extends Control
## Combat engine, rev6. Every combatant is a CharacterBase: the player is a clone
## of Character.body; allies/enemies are built from BattleState specs via
## CharacterBase.from_spec(). Damage routes through CombatMath.resolve_damage().
##
## BUFF/DEBUFF UPDATE: combat now runs a real per-turn cycle so buffs, DoT, spirit
## regen, and cooldowns can tick. An "End Turn" button hands off to the enemies
## and starts the player's next turn; at the START of each player turn every unit
## processes its buffs (DoT damage, spirit regen/drain, duration countdown +
## expiry) and the player's ability cooldowns tick down. HEAL / BUFF / DEBUFF
## abilities now resolve (via CombatBuffs + BuffLibrary), not just ATTACK.

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

# --- turn cycle --------------------------------------------------------
var _round: int = 1
## Player ability cooldowns: ability id (String) -> turns remaining. Shared by
## reference with the wheel so it can grey out abilities that are cooling down.
var _player_cooldowns: Dictionary = {}

## Action-point economy. The player refills to their `action_points` stat at the
## start of each turn; every ability spends its action_cost; when the budget hits
## 0 the turn auto-ends. AP is a HIDDEN stat — no UI, per the design. Floats are
## compared with a small epsilon so 1.0 - 1.0 reliably reads as "spent".
const AP_EPSILON := 0.0001
var _player_ap: float = 0.0
var _end_turn_btn: Button = null
var _turn_label: Label = null

# --- debug (training fight only) ---------------------------------------
var _debug_panel: DebugStatPanel = null
var _debug_target: BattleCharacter = null
var _debug_button: Button = null

enum Phase { PLAYER, RESOLVING }
var _phase: int = Phase.PLAYER

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_layout()
	_load_units()
	_apply_permanent_buffs()
	_build_health_bars()
	_place_units()
	_build_wheel()
	_build_turn_ui()
	_build_debug_ui()
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
	# Built via CharacterRegistry: a spec that names a "character" module is built
	# from that module (its own stats + permanent buffs); a plain dict still works.
	# ai / size_scale now live ON THE BODY (the module sets them), so we read them
	# from there rather than off the spec.
	for a in allies:
		if typeof(a) == TYPE_DICTIONARY:
			var abody := CharacterRegistry.build(a)
			var au := _spawn_unit(abody, TEAM_ALLY, abody.ai)
			au.size_scale = abody.size_scale

	# --- enemies (default: one Training Dummy) ---
	if enemies.is_empty():
		enemies = [ _training_dummy_spec() ]
	for e in enemies:
		if typeof(e) == TYPE_DICTIONARY:
			var ebody := CharacterRegistry.build(e)
			var eu := _spawn_unit(ebody, TEAM_ENEMY, ebody.ai)
			eu.size_scale = ebody.size_scale
			if _debug_target == null:
				_debug_target = eu   # first enemy = the training dummy in debug fights

## Auto-apply every unit's PERMANENT buffs at the start of combat. Each character
## carries a `permanent_buffs` list of BuffLibrary ids (set by its module, or by a
## spec / the player's PlayerCharacter); we build each one and apply it to the body
## BEFORE the health + buff bars are built, so the ceilings and the visible buff
## strip are correct from turn one. A permanent buff should have duration -1 so it
## never counts down. init_vitals() re-fulls the unit in case a buff moved max HP.
func _apply_permanent_buffs() -> void:
	for u in _units:
		if u.body == null:
			continue
		for bid in u.body.permanent_buffs:
			var entry := BuffLibrary.build(str(bid))
			if entry.is_empty():
				push_warning("[combat] %s lists unknown permanent buff '%s'." % [u.unit_name, str(bid)])
				continue
			CombatBuffs.apply(u.body, entry)
		u.body.init_vitals()

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
## Each unit gets a health bar AND a visible buff strip. The strip sits on the
## RIGHT of the bar for the player party, on the LEFT for enemies (they mirror in
## from their side of the screen). Bar+strip live in a small per-unit HBox.
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
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 4)

		var hb := BattleHealthBar.new()
		hb.setup(u.unit_name, u.get_max_hp(), u.get_hp(), u.get_max_spirit(), u.get_spirit(), u.body.model_color())
		u.health_bar = hb

		var bb := BuffBar.new()

		if u.team == TEAM_ENEMY:
			bb.setup(u.body, BuffBar.SIDE_LEFT)
			cell.add_child(bb)      # buffs on the LEFT of the enemy's bar
			cell.add_child(hb)
			enemy_box.add_child(cell)
		else:
			cell.add_child(hb)
			bb.setup(u.body, BuffBar.SIDE_RIGHT)
			cell.add_child(bb)      # buffs on the RIGHT of the party's bar
			party_box.add_child(cell)
		u.buff_bar = bb

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
	_sync_wheel_state()

# ---- turn UI (End Turn button + turn counter) -------------------------
func _build_turn_ui() -> void:
	_end_turn_btn = Button.new()
	_end_turn_btn.text = "End Turn"
	_end_turn_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_end_turn_btn.anchor_left = 1.0
	_end_turn_btn.anchor_right = 1.0
	_end_turn_btn.anchor_top = 0.5
	_end_turn_btn.anchor_bottom = 0.5
	_end_turn_btn.offset_left = -150.0
	_end_turn_btn.offset_right = -18.0
	_end_turn_btn.offset_top = -22.0
	_end_turn_btn.offset_bottom = 22.0
	_end_turn_btn.pressed.connect(end_player_turn)
	_bottom_panel.add_child(_end_turn_btn)

	_turn_label = Label.new()
	_turn_label.text = "Turn %d" % _round
	_turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_turn_label.add_theme_font_size_override("font_size", 15)
	_turn_label.anchor_left = 1.0
	_turn_label.anchor_right = 1.0
	_turn_label.anchor_top = 0.0
	_turn_label.anchor_bottom = 0.0
	_turn_label.offset_left = -150.0
	_turn_label.offset_right = -18.0
	_turn_label.offset_top = 6.0
	_turn_label.offset_bottom = 28.0
	_bottom_panel.add_child(_turn_label)

# ---- debug (training fight only) --------------------------------------
## True when this is the IGLOO training fight (GameManager.go_to_training set
## battle_id "training" with is_campaign false). Only then is the debug UI built.
func _is_training() -> bool:
	return typeof(BattleState) != TYPE_NIL and BattleState.battle_id == "training" and not BattleState.is_campaign

## A small "DEBUG" button centred at the top (over the gap between the party and
## enemy health bars) that toggles the dummy-stat editor. Training fight only.
func _build_debug_ui() -> void:
	if not _is_training() or _debug_target == null:
		return
	_debug_button = Button.new()
	_debug_button.text = "DEBUG"
	_debug_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_debug_button.anchor_left = 0.5
	_debug_button.anchor_right = 0.5
	_debug_button.anchor_top = 0.0
	_debug_button.anchor_bottom = 0.0
	_debug_button.offset_left = -38.0
	_debug_button.offset_right = 38.0
	_debug_button.offset_top = 4.0
	_debug_button.offset_bottom = 30.0
	_debug_button.pressed.connect(_toggle_debug_panel)
	add_child(_debug_button)   # added last -> drawn above the health-bar band

func _toggle_debug_panel() -> void:
	if _debug_target == null or _debug_target.body == null:
		return
	if _debug_panel == null:
		_debug_panel = DebugStatPanel.new()
		add_child(_debug_panel)
		_debug_panel.applied.connect(_on_debug_applied)
	if _debug_panel.visible:
		_debug_panel.hide()
	else:
		# Re-read the dummy's current values each time it opens.
		_debug_panel.setup(_debug_target.body, _debug_target.unit_name)
		_debug_panel.popup_centered(Vector2i(480, 600))

func _on_debug_applied() -> void:
	if _debug_target != null:
		_debug_target.refresh_bar()
		_debug_target.refresh_buffs()
	print("[combat][debug] applied new stats to %s (max_hp=%d)" % [
		_debug_target.unit_name if _debug_target else "?",
		_debug_target.get_max_hp() if _debug_target else 0])

func _on_unit_hovered(_u: BattleCharacter) -> void:
	# Hover only reveals the unit's floating name/level label (done inside
	# BattleCharacter). The wheel now opens on CLICK, not hover.
	pass

func _on_unit_clicked(u: BattleCharacter) -> void:
	if _battle_over or _phase != Phase.PLAYER:
		return
	_open_wheel_for(u)   # clicking any unit (player / ally / enemy) opens the wheel

func _open_wheel_for(u: BattleCharacter) -> void:
	_open_target = u
	_sync_wheel_state()
	_wheel.open_over(u.position + u.size * 0.5)

func _on_wheel_slot_selected(index: int, ability_id: String) -> void:
	_wheel.close()
	var ability := _get_ability(ability_id)
	if ability == null or _open_target == null:
		return
	# SELF-targeted abilities always act on the player, whatever was clicked.
	var tgt := _open_target
	if ability.target == Ability.Target.SELF and _player:
		tgt = _player
	if not _valid_target(ability, tgt):
		print("[combat] %s can't target %s" % [ability.display_name, tgt.unit_name])
		return
	# gameplay gates (also enforced visually by the wheel graying)
	if CombatBuffs.is_stunned(_player.body):
		print("[combat] %s is stunned and cannot act." % _player.unit_name)
		return
	if _ability_on_cooldown(ability_id):
		print("[combat] %s is on cooldown (%d turns)." % [ability.display_name, _cooldown_left(ability_id)])
		return
	if ability.spirit_cost() > 0 and CombatBuffs.is_silenced(_player.body):
		print("[combat] %s is silenced — cannot use %s." % [_player.unit_name, ability.display_name])
		return
	# action-point gate: block an ability the player can't afford this turn.
	if ability.action_cost > _player_ap + AP_EPSILON:
		print("[combat] not enough action points for %s (need %.2f, have %.2f)." % [ability.display_name, ability.action_cost, _player_ap])
		return
	_use_ability(ability, tgt)

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

## Resolve a used ability. Spirit cost is checked/spent for EVERY kind now; the
## effect branches on kind. On a successful active use the ability's cooldown is
## started and the wheel state is re-synced.
func _use_ability(ability: Ability, tgt: BattleCharacter) -> void:
	var sp_cost := ability.spirit_cost()
	if _player and _player.get_spirit() < sp_cost:
		print("[combat] not enough spirit for %s (need %d, have %d)" % [ability.display_name, sp_cost, _player.get_spirit()])
		return

	var acted := false
	match ability.kind:
		Ability.Kind.ATTACK:
			var atk: CharacterBase = _player.body if _player else null
			var hit := CombatMath.resolve(atk, tgt.body, ability)
			var dmg := int(hit["damage"])
			# Pass the attacker as the source so the target's "when struck"
			# reactions (thorns, ...) can hit back.
			tgt.take_damage(dmg, str(hit["element"]), bool(hit["is_crit"]), _player)
			# an attack may also drop a buff/debuff on the target (transient effect)
			_maybe_apply_buff(ability, tgt)
			var crit_tag := " (CRIT x%.2f)" % float(hit["crit_mult"]) if hit["is_crit"] else ""
			print("[combat] %s hits %s for %d %s damage%s [chance %.0f%%]" % [
				ability.display_name, tgt.unit_name, dmg, ability.element_key(), crit_tag, float(hit["crit_chance"])])
			acted = true

		Ability.Kind.HEAL:
			var caster: CharacterBase = _player.body if _player else null
			var heal_amt := int(round(ability.compute_heal(caster.effective_stats() if caster else {})))
			var restored := tgt.heal(heal_amt)
			print("[combat] %s heals %s for %d." % [ability.display_name, tgt.unit_name, restored])
			acted = true

		Ability.Kind.BUFF, Ability.Kind.DEBUFF:
			if _maybe_apply_buff(ability, tgt):
				print("[combat] %s applied %s to %s." % [ability.display_name, String(ability.applies_buff), tgt.unit_name])
				acted = true
			else:
				print("[combat] %s has no buff to apply (applies_buff is blank / unknown)." % ability.display_name)

		_:
			print("[combat] %s used on %s (kind %d not yet implemented)" % [ability.display_name, tgt.unit_name, ability.kind])

	if not acted:
		return
	if _player and sp_cost > 0:
		_player.spend_spirit(sp_cost)
	if ability.cooldown > 0:
		_player_cooldowns[String(ability.id)] = ability.cooldown
	# spend action points; when the budget is exhausted the player's turn ends.
	_player_ap = maxf(0.0, _player_ap - ability.action_cost)
	_sync_wheel_state()
	_check_victory()
	# A "when struck" reaction (e.g. thorns) can damage the player during their own
	# action, so check for defeat here too — not only on the turn tick.
	_check_defeat()
	# Out of action points -> auto-end the turn (unless the fight just ended).
	if not _battle_over and _player_ap <= AP_EPSILON:
		print("[combat] %s is out of action points — ending turn." % _player.unit_name)
		end_player_turn()

## Apply the ability's buff (if any) to `tgt`. Returns true if a buff was applied.
func _maybe_apply_buff(ability: Ability, tgt: BattleCharacter) -> bool:
	var bid := String(ability.applies_buff)
	if bid == "":
		return false
	var caster: CharacterBase = _player.body if _player else null
	var entry := BuffLibrary.build(bid, caster, tgt.body)
	if entry.is_empty():
		return false
	CombatBuffs.apply(tgt.body, entry)
	tgt.refresh_bar()      # a max-HP / max-Spirit buff can move the ceilings
	tgt.refresh_buffs()
	return true

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _wheel and _wheel.visible:
			_wheel.close()

# ---- cooldowns --------------------------------------------------------
func _ability_on_cooldown(id: String) -> bool:
	return int(_player_cooldowns.get(id, 0)) > 0

func _cooldown_left(id: String) -> int:
	return int(_player_cooldowns.get(id, 0))

func _decrement_player_cooldowns() -> void:
	for id in _player_cooldowns.keys():
		var v := int(_player_cooldowns[id]) - 1
		if v <= 0:
			_player_cooldowns.erase(id)
		else:
			_player_cooldowns[id] = v

## Hand the wheel the current caster body + the (shared) cooldown map so it can
## grey out silenced / cooling-down / stunned abilities.
func _sync_wheel_state() -> void:
	if _wheel and _wheel.has_method("set_use_state"):
		_wheel.set_use_state(_player.body if _player else null, _player_cooldowns)
	if _wheel:
		_wheel.queue_redraw()

# ---- victory / defeat -------------------------------------------------
func _check_victory() -> void:
	if _battle_over:
		return
	for u in _units:
		if u.team == TEAM_ENEMY and u.is_alive():
			return
	_win()

func _check_defeat() -> void:
	if _battle_over:
		return
	if _player == null:
		return
	if not _player.is_alive():
		_battle_over = true
		if _wheel:
			_wheel.close()
		print("[combat] defeat — %s has fallen." % _player.unit_name)
		_leave_combat()

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
	# Let the final blow / death animation read for a beat before the results screen
	# takes over. The battle is already locked (_battle_over = true), so nothing can
	# act during the wait.
	if typeof(GameManager) != TYPE_NIL and GameManager.has_method("go_to_victory"):
		await get_tree().create_timer(2.0).timeout
		if is_inside_tree():
			GameManager.go_to_victory()

# ---- turn cycle -------------------------------------------------------
func _start_battle() -> void:
	_round = 1
	_phase = Phase.PLAYER
	_reset_player_ap()
	_refresh_turn_ui()
	_sync_wheel_state()
	print("[combat] battle start — %d units. Turn %d (player's turn)." % [_units.size(), _round])

## Refill the player's action-point budget to their (buffable) action_points stat.
func _reset_player_ap() -> void:
	if _player and _player.body:
		_player_ap = maxf(0.0, _player.body.get_effective("action_points"))
	else:
		_player_ap = 0.0

## Player ends their turn: run the (do-nothing) enemy turns, then begin the next
## player turn — which is where the start-of-turn tick happens.
func end_player_turn() -> void:
	if _phase != Phase.PLAYER or _battle_over:
		return
	_phase = Phase.RESOLVING
	if _wheel:
		_wheel.close()
	_refresh_turn_ui()
	for u in _units:
		if u.team == TEAM_PLAYER:
			continue
		_take_ai_turn(u)
	if _battle_over:
		return
	_begin_player_turn()

## Begin a new player turn: advance the round, process every unit's start-of-turn
## effects (DoT, spirit regen/drain, duration countdown + expiries), tick the
## player's cooldowns, then hand control back.
func _begin_player_turn() -> void:
	_round += 1
	_process_turn_start_all()
	_decrement_player_cooldowns()
	if _battle_over:
		return
	_phase = Phase.PLAYER
	_reset_player_ap()
	_refresh_turn_ui()
	_sync_wheel_state()
	print("[combat] Turn %d — player's turn." % _round)

## Every living unit processes its buffs for the new turn.
func _process_turn_start_all() -> void:
	for u in _units:
		if u.body == null or not u.is_alive():
			continue
		var report := CombatBuffs.collect_turn_start(u.body)
		# 1) DoT damage (routed through take_damage so it animates + handles death)
		for d in report["dots"]:
			if u.is_alive():
				u.take_damage(int(d["amount"]), str(d["element"]), false)
		# 2) spirit: default per-turn regen + this unit's buff/debuff spirit delta
		if u.is_alive():
			var regen := int(round(u.body.get_effective("spirit_regen")))
			var delta := int(round(float(report["spirit_delta"])))
			u.change_spirit(regen + delta)
		# 3) on-expire events for anything that fell off this turn
		for e in report["expired"]:
			CombatBuffs.fire_expiry(u, e)
		u.refresh_bar()
		u.refresh_buffs()
	_check_victory()
	_check_defeat()

func _take_ai_turn(u: BattleCharacter) -> void:
	if u.ai == "none":
		print("[combat] %s does nothing." % u.unit_name)
	else:
		print("[combat] %s has no AI yet, passing." % u.unit_name)

func _refresh_turn_ui() -> void:
	if _turn_label:
		_turn_label.text = "Turn %d" % _round
	if _end_turn_btn:
		_end_turn_btn.disabled = _battle_over or _phase != Phase.PLAYER

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
