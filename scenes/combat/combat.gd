extends Control
## Combat engine, rev6. Every combatant is a CharacterBase: the player is a clone
## of Character.body; allies/enemies are built from BattleState specs via
## CharacterBase.from_spec(). Damage routes through CombatMath.resolve_damage().
##
## BUFF/DEBUFF UPDATE: combat now runs a real per-turn cycle so buffs, DoT, spirit
## regen, and cooldowns can tick. An "End Turn" button hands off to the enemies
## and starts the player's next turn; at the START of each player turn every unit
## processes its buffs (DoT damage, spirit regen/drain, duration countdown +
## expiry) and every unit's ability cooldowns tick down. HEAL / BUFF / DEBUFF
## abilities now resolve (via CombatBuffs + BuffLibrary), not just ATTACK.
##
## CASTER-AGNOSTIC TURNS. Resolving an ability no longer assumes the player is the one
## doing it: _use_ability(caster, ability, target, slot) reads everything off `caster`,
## and the per-turn state it spends — the action-point budget and the per-SLOT cooldown
## map — lives on each BattleCharacter (u.ap / u.cooldowns) rather than in this script.
## Each unit also carries its own loadout (u.loadout: the wheel for the player,
## body.abilities for everyone else) and its own ranks (body.ability_ranks).
##
## rev32 — THE FORMATION GRID. A fight is no longer two vertical columns of models
## spread to fit. Each SIDE now owns a BattleGrid: 5 rows tall by 2 columns deep,
## BACK (col 0) and FRONT (col 1). Everyone starts in the BACK column, filled
## centre-out — the player takes its centre and allies alternate one above, one
## below — and the FRONT column is left empty, reserved for temporary summons.
## Enemies fill their own back column the same way, mirrored. Slot occupancy lives
## in BattleGrid, the position of a slot is static geometry (BattleGrid.anchor_for),
## and each unit remembers its own slot (u.grid_col / u.grid_row). NOTHING reads a
## row or column to make a decision yet: row-restricted targeting, back-row
## protection and taunts are all still unwritten, and now have a grid to be written
## against. Models draw at 85% (BattleGrid.MODEL_SCALE) so five rows fit the band,
## rows are staggered diagonally, and lower rows draw in front (_sort_unit_depth).
## The whole grid is drawn as an overlay under the models in debug builds.
##
## rev31 — THE UNIT AI. The DECIDING now exists, in scenes/combat/ai/ (AI_PRIMER).
## _take_ai_turn hands a non-player unit to AITurn.run, which owns that unit's whole
## turn: the action loop, the guards, the pacing between actions and the debug
## ledger. Combat's side of the seam is that one call and nothing else — the AI is a
## CLIENT of this engine, filtering with _can_use / _valid_target and resolving
## through _use_ability exactly as the player's wheel does. `ai == "none"` still
## passes the turn, so a creature is inert until its module names a routine.
##
## rev30 — THE TIMELINE. The ROUND IS GONE. Turn order is a continuously scrolling
## timeline: a single float clock (`_clock`, units TICKS) advances, every unit is
## scheduled at a clock value (u.next_turn_at), and the engine repeatedly jumps the
## clock to whichever LIVING unit is scheduled soonest and gives THAT ONE unit a turn.
## A unit's INTERVAL between turns comes from its alacrity and its new hidden
## `turn_rate` stat (CombatTimeline), so a fast character genuinely acts more often
## rather than merely acting earlier within a shared round. Everything that used to
## tick "for all units at the round boundary" — buff durations, DoT, spirit regen,
## shield decay, cooldowns, the action-point refill — now ticks ONLY for the unit
## whose turn is starting, so "3 turns" on a buff means three of THE BEARER'S turns.
## The whole cycle is one `while` loop (_run_turn_loop) that awaits the scroll
## animation and, on the player's turn, a `_turn_finished` signal.
## The visible counter is TurnTimeline, overlaid top-left under the party health bars.

const TOP_FRAC := 0.15
const MID_FRAC := 0.70

const TEAM_PLAYER := 0
const TEAM_ALLY := 1
const TEAM_ENEMY := 2

const UNIT_SIZE := Vector2(90, 140)

# --- the formation grid (rev32) ----------------------------------------
## One BattleGrid per side, 5 rows x 2 columns each. Occupancy only — where a slot
## IS is static geometry on BattleGrid, and what a slot MEANS is not yet anything.
var _grid_party: BattleGrid = null
var _grid_foes: BattleGrid = null
## Debug-only picture of all twenty slots, drawn UNDER the models. Null when the
## debug flag is off (never constructed), so every call site must null-check it.
var _grid_overlay: BattleGridOverlay = null

var _battle_panel: Control
var _bottom_panel: Panel
var _healthbar_row: HBoxContainer

var _wheel: ActionWheel
var _units: Array = []
var _player: BattleCharacter = null
var _open_target: BattleCharacter = null
var _battle_over: bool = false

# --- turn cycle (rev30: a timeline, not rounds) ------------------------
## Emitted when the ACTIVE unit's turn is over. _run_turn_loop awaits it for the
## player's turn (whose end is driven by the End Turn button or by the AP budget
## running out); a non-player turn ends synchronously inside the loop.
signal _turn_finished

## THE CLOCK, in ticks. Monotonically increasing, never reset mid-fight. A default
## character (alacrity 10, turn_rate 1.0) acts every CombatTimeline.TICKS_PER_TURN
## of these. Replaces the old `_round` counter entirely.
var _clock: float = 0.0
## The unit currently taking its turn, or null between turns. The auto-end-of-turn
## check and end_player_turn both key off this rather than off the player.
var _active: BattleCharacter = null
## Set by _use_ability when the ACTIVE caster's action-point budget runs out. The
## turn is NOT ended from inside _use_ability (that would re-enter the turn loop
## halfway through resolving an ability); the caller — the wheel handler, or the AI
## routine's loop — sees the flag and ends the turn cleanly once resolution is done.
var _turn_should_end: bool = false
## Guard so the turn loop can only ever be running once.
var _loop_running: bool = false

## Action-point economy. EVERY unit refills to its `action_points` stat at the start
## of ITS OWN turn; every ability spends its action_cost; when the ACTING unit's
## budget hits 0 its turn ends. AP is a HIDDEN stat — no UI, per the design. Floats
## are compared with a small epsilon so 1.0 - 1.0 reliably reads as "spent".
## The budget and the cooldown map both live PER UNIT on BattleCharacter (`ap` /
## `cooldowns`) rather than here, so an enemy resolves an ability through exactly the
## same economy the player does.
const AP_EPSILON := 0.0001

## SAFETY FLOOR on how far a turn advances the timeline — 1 tick, i.e. 1% of a
## default turn. This is NOT a balance floor (by design there is none: if an
## ability is too strong for its action_cost, raise its action_cost). It exists so
## a 0-advance turn can never spin the turn loop forever.
const MIN_TURN_ADVANCE := 1.0

## When a unit's interval CHANGES mid-fight (a haste buff lands, alacrity is
## drained), rescale the REMAINING wait by the same ratio, so the effect visibly
## slides its next turn closer/further immediately. Set false to have speed changes
## only take effect from the turn after next.
const HASTE_RESCALES_PENDING := true

## Beat between a non-player unit's turn starting and it acting, so an enemy phase
## reads as a sequence of deliberate actions instead of landing in one frame.
const ENEMY_THINK_DELAY := 0.35

## THE PLAYER ALWAYS OPENS THE FIGHT. Their first turn is MOVED FORWARD to the
## earliest moment ANYONE is scheduled to act — the front of the opening queue —
## and a dead heat there goes to them (_next_actor). Everyone else keeps the slot
## their own speed earned them.
##
## THE POINT IS THAT IT COSTS AND GRANTS NOTHING. The player leads the fight, and
## their SECOND turn is then one honest interval from where their first one
## actually happened, so no one gains or loses a turn from the courtesy. Two
## earlier shapes of this both broke that, and both are worth remembering:
##   - parking them on the ORIGIN (0) and scheduling forward from the clock put
##     their second turn at one interval — the same tick every other default-speed
##     unit was already on — which they then WON on the tie. A free extra turn.
##   - parking them on the origin and scheduling forward from their NATURAL first
##     turn instead fixed that, but left a two-interval gap between their first
##     turn and their second: the courtesy now cost them a turn, and the enemy
##     acted twice inside it.
## Moving the first turn to the front of the queue rather than to the origin has
## neither problem, because the player's turn is not displaced in time at all —
## it just goes first among the units already scheduled soonest.
## Set false for a pure timeline start where the fastest unit opens instead.
const PLAYER_OPENS := true

var _end_turn_btn: Button = null
var _timeline: TurnTimeline = null

# --- debug (training fight only) ---------------------------------------
var _debug_panel: DebugStatPanel = null
var _debug_target: BattleCharacter = null
var _debug_button: Button = null
## The floating action terminal (rev31). EVERY fight gets one under the debug
## flag, not just the training fight — it is how an enemy's choices are read.
## Null when GameManager.debug_enabled is off, and never constructed at all in
## that case (CORE_PRIMER §5B), so every call site must null-check it. `_note`
## and `_log_action` below do that once so nothing else has to.
var _combat_log: CombatLog = null

enum Phase { PLAYER, RESOLVING }
var _phase: int = Phase.PLAYER

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_layout()
	_load_units()
	_apply_permanent_buffs()
	_apply_passive_buffs()
	_build_health_bars()
	_build_grid()
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

## Apply the combat buff granted by each PASSIVE ability in the player's wheel (e.g.
## Gliogenesis' per-turn regen). Mirrors _apply_permanent_buffs, but the source is
## the wheel rather than a character's permanent_buffs list: for each equipped PASSIVE
## that names a passive_buff, build "<passive_buff>_<invested rank>" and apply it to
## the player as a permanent (fight-long) buff. Deduped by ability id so two copies of
## the same passive don't double up; rank comes from the persistent Character.
func _apply_passive_buffs() -> void:
	if _player == null or _player.body == null:
		return
	var ch := get_node_or_null("/root/Character")
	if ch == null or not ch.has_method("get_equipped"):
		return
	var applied := {}
	for id in ch.get_equipped():
		var aid := str(id)
		if aid == "" or applied.has(aid):
			continue
		var ab := _get_ability(aid)
		if ab == null or ab.kind != Ability.Kind.PASSIVE:
			continue
		var bid := String(ab.passive_buff)
		var has_cap: bool = ab.has_method("has_capstone_at") and ab.has_capstone_at(_ability_rank(_player, ab))
		if bid == "" and not has_cap:
			continue
		applied[aid] = true
		var rank := _ability_rank(_player, ab)
		if bid != "":
			var built_id := "%s_%d" % [bid, clampi(rank, 1, maxi(1, ab.max_points))]
			var entry := BuffLibrary.build(built_id, _player.body, _player.body)
			if entry.is_empty():
				push_warning("[combat] passive %s names unknown passive_buff '%s'." % [ab.display_name, built_id])
			else:
				CombatBuffs.apply(_player.body, entry)
		# CAPSTONE: a passive may hand out a SECOND, UNSUFFIXED buff once its invested
		# rank reaches passive_buff_capstone_rank (Lightning Shell -> High Voltage at 10).
		if has_cap:
			var cap := BuffLibrary.build(String(ab.passive_buff_capstone), _player.body, _player.body)
			if cap.is_empty():
				push_warning("[combat] passive %s names unknown capstone buff '%s'." % [ab.display_name, String(ab.passive_buff_capstone)])
			else:
				CombatBuffs.apply(_player.body, cap)
	_player.body.init_vitals()

func _spawn_unit(body: CharacterBase, team: int, ai: String) -> BattleCharacter:
	var u := BattleCharacter.new()
	u.body = body
	u.team = team
	u.ai = ai
	u.unit_name = body.char_name
	u.loadout = _loadout_for(body, team)
	_battle_panel.add_child(u)
	_units.append(u)
	u.hovered.connect(_on_unit_hovered)
	u.clicked.connect(_on_unit_clicked)
	return u

## The ability ids a unit brings to this fight, in SLOT order. The PLAYER's loadout is
## the WHEEL (Character.equipped_abilities, sized to wheel_slot_count()); every other
## unit carries its own list on its body (set by its module or a fight spec). Read ONCE
## at spawn: slot indices must stay stable for the whole fight, because per-unit
## cooldowns are keyed by them — and re-equipping only happens out of combat anyway.
func _loadout_for(body: CharacterBase, team: int) -> Array:
	if team == TEAM_PLAYER:
		var ch := get_node_or_null("/root/Character")
		if ch and ch.has_method("get_equipped"):
			return ch.get_equipped()
		return []
	if body == null:
		return []
	return body.abilities.duplicate()

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
		# Enemies mirror: their max box sits on the buff-strip side (the left).
		var mirror: bool = (u.team == TEAM_ENEMY)
		hb.setup(u.unit_name, u.get_max_hp(), u.get_hp(), u.get_max_spirit(), u.get_spirit(), u.body.model_color(), mirror)
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

# ---- the formation grid + placement (rev32) ---------------------------
## Build the two grids and, under the debug flag, the picture of them. Called
## AFTER the units exist (they are what fills the slots) and BEFORE _place_units.
## The overlay goes in as the battle panel's FIRST child so every model, damage
## number and the wheel all draw over it.
func _build_grid() -> void:
	_grid_party = BattleGrid.new(BattleGrid.SIDE_PARTY)
	_grid_foes = BattleGrid.new(BattleGrid.SIDE_FOES)
	if typeof(GameManager) == TYPE_NIL or not GameManager.has_method("is_debug") \
	or not GameManager.is_debug():
		return
	_grid_overlay = BattleGridOverlay.new()
	_battle_panel.add_child(_grid_overlay)
	_battle_panel.move_child(_grid_overlay, 0)
	_grid_overlay.setup(_grid_party, _grid_foes)

func _side_of(u: BattleCharacter) -> int:
	return BattleGrid.SIDE_FOES if u.team == TEAM_ENEMY else BattleGrid.SIDE_PARTY

func _grid_for(u: BattleCharacter) -> BattleGrid:
	return _grid_foes if u.team == TEAM_ENEMY else _grid_party

## SEAT EVERYONE, then position them. Order matters and is the whole rule:
##   1. anyone carrying an EXPLICIT slot (a spec, or a summon placed by hand) keeps it;
##   2. the PLAYER takes the centre of the party's back column;
##   3. everyone else is dealt the next free slot centre-out — allies one above, one
##      below, one above, one below; enemies the same on their own side.
## The FRONT column is never reached unless a side brings more than five units, so
## it stays empty and reserved for summons in every normal fight.
## Safe to re-run mid-fight (a summon, a death that frees a slot).
func _place_units() -> void:
	_grid_party.clear_all()
	_grid_foes.clear_all()

	for u in _units:
		if u.grid_col >= 0 and u.grid_row >= 0:
			_grid_for(u).place(u, u.grid_col, u.grid_row)

	if _player != null and _player.grid_row < 0:
		_grid_party.place(_player, BattleGrid.BACK, BattleGrid.PLAYER_ROW)

	for u in _units:
		if u.grid_row < 0:
			if not _grid_for(u).assign(u):
				push_warning("[combat] no free formation slot for %s — side is full (10)." % u.unit_name)

	_apply_grid_positions()

## Anchor every seated unit to its slot. Position is derived ENTIRELY from
## (side, col, row) — nothing here knows how many units there are, which is what
## makes adding one mid-fight a re-run rather than a re-layout.
func _apply_grid_positions() -> void:
	for u in _units:
		# An unseated unit (its side was full) still has to be drawn somewhere:
		# stack it on the front-column centre rather than leaving it at the origin.
		var col: int = u.grid_col if u.grid_col >= 0 else BattleGrid.FRONT
		var row: int = u.grid_row if u.grid_row >= 0 else BattleGrid.PLAYER_ROW
		var a := BattleGrid.anchor_for(_side_of(u), col, row)
		var s: float = u.size_scale * BattleGrid.MODEL_SCALE
		u.anchor_left = a.x
		u.anchor_right = a.x
		u.anchor_top = a.y
		u.anchor_bottom = a.y
		u.offset_left = -UNIT_SIZE.x * 0.5 * s
		u.offset_right = UNIT_SIZE.x * 0.5 * s
		u.offset_top = -UNIT_SIZE.y * 0.5 * s
		u.offset_bottom = UNIT_SIZE.y * 0.5 * s
	_sort_unit_depth()
	if _grid_overlay:
		_grid_overlay.queue_redraw()

## DEPTH. Rows overlap at MODEL_SCALE, so draw order has to say which is in front:
## LOWER ON SCREEN = NEARER THE CAMERA = DRAWN LAST. Ties inside a row go to the
## front column. Only the units are reordered, into the LOWEST child indices, so
## the action wheel and any live damage numbers (added later) stay above them all,
## and the grid overlay is put back underneath everything afterwards.
func _sort_unit_depth() -> void:
	var ordered := _units.duplicate()
	ordered.sort_custom(func(a, b):
		if a.grid_row != b.grid_row:
			return a.grid_row < b.grid_row
		return a.grid_col < b.grid_col)
	for i in ordered.size():
		var u: BattleCharacter = ordered[i]
		if u.get_parent() == _battle_panel:
			_battle_panel.move_child(u, i)
	if _grid_overlay and _grid_overlay.get_parent() == _battle_panel:
		_battle_panel.move_child(_grid_overlay, 0)

# ---- action wheel -----------------------------------------------------
func _build_wheel() -> void:
	_wheel = ActionWheel.new()
	_wheel.set_mode_use()
	_battle_panel.add_child(_wheel)
	_wheel.slot_selected.connect(_on_wheel_slot_selected)
	_sync_wheel_state()

# ---- turn UI (End Turn button + the scrolling turn counter) -----------
## rev30: the "Turn N" label is gone — there is no round to number. In its place the
## TurnTimeline is OVERLAID on the existing layout (added to the scene root, anchored
## to the bottom edge of the health-bar band at the far left) so it reads as sitting
## directly under the party health bars without reflowing either band. It ignores the
## mouse, so a click meant for a unit still reaches it.
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

	_timeline = TurnTimeline.new()
	_timeline.setup(_units)
	var tl_size := _timeline.desired_size()
	# Anchored to the TOP_FRAC line (the bottom of the health-bar band) at the left
	# edge, so it hangs just under the party health bars whatever the window size.
	_timeline.anchor_left = 0.0
	_timeline.anchor_right = 0.0
	_timeline.anchor_top = TOP_FRAC
	_timeline.anchor_bottom = TOP_FRAC
	_timeline.offset_left = 18.0
	_timeline.offset_right = 18.0 + tl_size.x
	_timeline.offset_top = 8.0
	_timeline.offset_bottom = 8.0 + tl_size.y
	add_child(_timeline)   # on the ROOT, above both panels — an overlay, not a band

# ---- debug (training fight only) --------------------------------------
## True when this is the IGLOO training fight (GameManager.go_to_training set
## battle_id "training" with is_campaign false). Only then is the debug UI built.
func _is_training() -> bool:
	return typeof(BattleState) != TYPE_NIL and BattleState.battle_id == "training" and not BattleState.is_campaign

## The debug overlays. Two of them, with DIFFERENT scopes:
##   - the COMBAT LOG, in every fight — a floating terminal of every ability any
##     unit resolves. This is the one that makes the enemy AI legible.
##   - the "DEBUG" button + dummy stat editor, training fight only.
## Both are gated at BUILD time by the game-wide flag: with
## GameManager.debug_enabled off neither node is constructed, so there is no
## hidden UI and no runtime visibility check to forget (CORE_PRIMER §5B).
func _build_debug_ui() -> void:
	if typeof(GameManager) == TYPE_NIL or not GameManager.has_method("is_debug") \
	or not GameManager.is_debug():
		return

	_combat_log = CombatLog.new()
	add_child(_combat_log)   # on the ROOT, above both bands — an overlay

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

# ---- the combat log ---------------------------------------------------
## Every one of these is a NO-OP when the log was not built (the debug flag is
## off), so no call site needs its own guard.

## Set by _maybe_apply_buff / _maybe_apply_self_buff so _use_ability can fold the
## buff outcome into the ONE log line for this action. It lives here rather than
## in a return value because those two functions are called both as statements
## (the ATTACK branch's rider) and for their bool (the BUFF/DEBUFF branch), and
## widening either signature would touch every call site for a debug feature.
## Cleared at the top of every _use_ability.
var _last_buff_note: String = ""

func _note_buff(text: String) -> void:
	if _last_buff_note == "":
		_last_buff_note = text
	else:
		_last_buff_note += " " + text

## ONE line for a RESOLVED ability use. _use_ability is caster-agnostic, so this
## covers the player, an ally and an enemy with no per-side code anywhere.
func _log_action(caster: BattleCharacter, ability: Ability, detail: String) -> void:
	if _combat_log == null or caster == null or ability == null:
		return
	_combat_log.add_action(caster.unit_name, caster.team, ability.display_name, detail)

## The dim separator that opens a unit's turn, so the log reads as turns rather
## than as one undifferentiated stream.
func _log_turn(u: BattleCharacter) -> void:
	if _combat_log == null or u == null:
		return
	_combat_log.add_turn_header(u.unit_name, u.team, u.turns_taken, _clock)

## Anything that is not an ability use — a lost turn, a pass, the fight ending.
func _log_note(text: String) -> void:
	if _combat_log:
		_combat_log.add_note(text)

func _on_debug_applied() -> void:
	if _debug_target != null:
		_debug_target.refresh_bar()
		_debug_target.refresh_buffs()
	# Editing alacrity / turn_rate moves the dummy's interval — rescale its pending
	# turn now so the timeline reacts to the edit immediately rather than at the next
	# turn boundary.
	_sync_intervals()
	_refresh_turn_ui()
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
	if ability == null or _open_target == null or _player == null:
		return
	# SELF-targeted abilities always act on the CASTER, whatever was clicked.
	var tgt := _open_target
	if ability.target == Ability.Target.SELF:
		tgt = _player
	if not _valid_target(_player, ability, tgt):
		print("[combat] %s can't target %s" % [ability.display_name, tgt.unit_name])
		return
	# Gameplay gates — ONE predicate, shared with the wheel's greying and (later) the
	# enemy AI's filter, so no path can resolve an ability another path would refuse.
	var blocked := _use_blocked(_player, ability, index)
	if blocked != "":
		print("[combat] %s." % blocked)
		return
	_use_ability(_player, ability, tgt, index)
	# The budget ran out during that cast -> the player's turn is over. Ended HERE,
	# once resolution has fully unwound, rather than from inside _use_ability.
	if _turn_should_end and not _battle_over:
		print("[combat] %s is out of action points — ending turn." % _player.unit_name)
		end_player_turn()

func _get_ability(id: String) -> Ability:
	var db := get_node_or_null("/root/AbilityDB")
	if db and db.has_method("get_ability"):
		return db.get_ability(id)
	return null

## The RANK `caster` casts `ability` at — cost, effect, cooldown and duration all
## scale off it. TWO SOURCES, by who is casting:
##   - the PLAYER: the points invested in the skill-tree node that grants the ability,
##     read from the persistent Character autoload (the save).
##   - anyone else: its own body.ability_ranks (id -> rank), so a module or a per-fight
##     spec can hand a creature the rank-3 version without a second .tres.
## Either way the floor is 1 — an unknown ability always resolves at its base rank.
func _ability_rank(caster: BattleCharacter, ability: Ability) -> int:
	if ability == null:
		return 1
	if caster != null and caster != _player:
		if caster.body == null:
			return 1
		return maxi(1, int(caster.body.ability_ranks.get(String(ability.id), 1)))
	var ch := get_node_or_null("/root/Character")
	if ch and ch.has_method("ability_rank"):
		return maxi(1, int(ch.ability_rank(String(ability.id))))
	return 1

## The caster's DEALT heal-power / shield-power multiplier. Healing and shielding a
## character DEALS is scaled by (1 + its stat/100); the matching RECEIVED multiplier is
## applied on the target side (battle_character.heal() / gain_shield()), so an event is
## scaled by both the caster's and the target's stat (a self-cast benefits from both).
func _heal_power_dealt(caster: CharacterBase) -> float:
	if caster == null:
		return 1.0
	return 1.0 + maxf(0.0, caster.get_effective("heal_power")) / 100.0

func _shield_power_dealt(caster: CharacterBase) -> float:
	if caster == null:
		return 1.0
	return 1.0 + maxf(0.0, caster.get_effective("shield_power")) / 100.0

## Do these two units stand on OPPOSITE sides? The player and their allies share a
## side (TEAM_PLAYER / TEAM_ALLY); everything on TEAM_ENEMY is hostile to them.
func _is_hostile(a: BattleCharacter, b: BattleCharacter) -> bool:
	if a == null or b == null:
		return false
	return (a.team == TEAM_ENEMY) != (b.team == TEAM_ENEMY)

## Is `tgt` a legal target for `ability` cast by `caster`? Resolved RELATIVE TO THE
## CASTER, not from the player's seat: Target.ENEMY means "hostile to the caster", so
## an enemy's attack legally targets the party and its heal legally targets its own
## side. (Was hardcoded to TEAM_ENEMY, which would have let an enemy attack itself.)
func _valid_target(caster: BattleCharacter, ability: Ability, tgt: BattleCharacter) -> bool:
	if caster == null or tgt == null or ability == null:
		return false
	match ability.target:
		Ability.Target.ENEMY: return _is_hostile(caster, tgt)
		Ability.Target.ALLY: return not _is_hostile(caster, tgt)   # any friendly unit, caster included
		Ability.Target.SELF: return tgt == caster
		Ability.Target.ALL_ENEMIES: return true
		Ability.Target.ALL_ALLIES: return true
	return true

## Why `caster` cannot use `ability` from `slot` right now — an empty String means it
## CAN. This is the SINGLE gate behind every path that resolves an ability: the
## player's click handler, and (once it exists) the enemy AI's filter for which of its
## abilities are legal this turn. Returning the reason rather than a bare bool keeps
## the log messages as specific as when these checks were inlined in the click handler.
## NB the spirit gate is now RANK-AWARE (spirit_cost_at, not the rank-1 spirit_cost).
func _use_blocked(caster: BattleCharacter, ability: Ability, slot: int) -> String:
	if caster == null or caster.body == null or ability == null:
		return "no caster for that ability"
	if not caster.is_alive():
		return "%s is down and cannot act" % caster.unit_name
	if CombatBuffs.is_stunned(caster.body):
		return "%s is stunned and cannot act" % caster.unit_name
	if caster.on_cooldown(slot):
		return "%s is on cooldown (%d turns)" % [ability.display_name, caster.cooldown_left(slot)]
	var sp_cost := ability.spirit_cost_at(_ability_rank(caster, ability))
	if sp_cost > 0 and CombatBuffs.is_silenced(caster.body):
		return "%s is silenced — cannot use %s" % [caster.unit_name, ability.display_name]
	if caster.get_spirit() < sp_cost:
		return "not enough spirit for %s (need %d, have %d)" % [ability.display_name, sp_cost, caster.get_spirit()]
	if ability.action_cost > caster.ap + AP_EPSILON:
		return "not enough action points for %s (need %.2f, have %.2f)" % [ability.display_name, ability.action_cost, caster.ap]
	return ""

## Convenience bool over _use_blocked, for callers that don't want the reason.
func _can_use(caster: BattleCharacter, ability: Ability, slot: int) -> bool:
	return _use_blocked(caster, ability, slot) == ""

## Resolve a used ability, FOR ANY CASTER. `caster` is the acting unit — the player
## from the wheel, or any other unit from its AI routine; every effect, cost and
## bookkeeping line below reads it rather than assuming the player. Spirit cost is
## checked/spent for every kind; the effect branches on kind. On a successful active
## use the caster's own slot cooldown is started and the wheel state is re-synced.
func _use_ability(caster: BattleCharacter, ability: Ability, tgt: BattleCharacter, slot: int = -1) -> void:
	if caster == null or caster.body == null or ability == null or tgt == null:
		return
	# The caster's rank drives cost, effect and cooldown for this cast.
	var rank := _ability_rank(caster, ability)
	var sp_cost := ability.spirit_cost_at(rank)
	if caster.get_spirit() < sp_cost:
		print("[combat] not enough spirit for %s (need %d, have %d)" % [ability.display_name, sp_cost, caster.get_spirit()])
		return

	var acted := false
	## What this use actually DID, for the combat log's single line. Each branch
	## fills it in its own terms; the buff riders append to _last_buff_note, which
	## is folded in at the bottom once every rider has had its say.
	var detail := ""
	_last_buff_note = ""
	match ability.kind:
		Ability.Kind.ATTACK:
			var atk: CharacterBase = caster.body
			# Upgrade-node scaling bonuses are a PLAYER-only concept (they come from the
			# skill tree); an enemy casting the same ability gets the plain formula.
			var scale_bonus: Dictionary = {}
			if caster == _player:
				var ch_up := get_node_or_null("/root/Character")
				if ch_up and ch_up.has_method("ability_scaling_bonus"):
					scale_bonus = ch_up.ability_scaling_bonus(String(ability.id))
			# Cryonecrosis: gain bonus pierce per debuff of the named element on the
			# target (e.g. +N ice pierce per ice debuff), folded into this hit only.
			var extra_pierce := 0.0
			var pp_elem := String(ability.pierce_per_debuff_element)
			if pp_elem != "":
				extra_pierce = ability.pierce_per_debuff_at(rank) \
					* float(CombatBuffs.count_debuffs_of_element(tgt.body, pp_elem))
			var hit := CombatMath.resolve(atk, tgt.body, ability, rank, -1, scale_bonus, extra_pierce)
			# DODGE (CombatMath stage 0): the target evaded this hit on the alacrity
			# gap. NOTHING the attack carries happens — no damage, no rider debuff, no
			# spirit steal, no Shatter, no on-hit rider. The cast still spends its
			# spirit, its action point and its cooldown below, so a miss costs a turn.
			if bool(hit.get("dodged", false)):
				tgt.float_dodge()
				detail = "→ %s · DODGED" % tgt.unit_name
				print("[combat] %s DODGED %s [chance %.0f%%]" % [
					tgt.unit_name, ability.display_name, float(hit.get("dodge_chance", 0.0))])
			else:
				var dmg := int(hit["damage"])
				# Snap: deal the per-hit value once PER matching debuff element on the target
				# (0 matching debuffs => 0 damage).
				var per_elem := String(ability.damage_per_debuff_element)
				if per_elem != "":
					dmg *= CombatBuffs.count_debuffs_of_element(tgt.body, per_elem)
				# Pass the ACTUAL attacker as the source so the target's "when struck"
				# reactions (thorns, ...) can hit back — plus the hidden delivery class,
				# since those reactions answer ATTACKS only and stay silent for a spell.
				# This used to be hardcoded to _player, so on-struck riders could only
				# ever fire on the player's own hits (COMBAT_PRIMER C4.1).
				tgt.take_damage(dmg, str(hit["element"]), bool(hit["is_crit"]), caster, not ability.skip_ice_amp, ability.is_attack_delivery())
				# SECOND ELEMENT: an attack that is two damage types at once (a claw
				# AND a cold) lands its other half here, as a real hit of the other
				# element so the target's resistance to IT is what answers it.
				_apply_bonus_damage(caster, ability, tgt, rank)
				# CHARGES: this counts as one of "the next N attacks" for every charged
				# buff the ATTACKER carries. Outside the is_alive gate below on purpose —
				# a killing blow is still one of your swings.
				if caster != null and caster.body != null:
					if CombatBuffs.spend_attack_charges(caster.body):
						caster.refresh_buffs()
				# an attack may also drop a buff/debuff on the target (transient effect)
				_maybe_apply_buff(caster, ability, tgt, rank)
				# ...and apply any one-time spirit gain (caster) / steal (target).
				_apply_spirit_effects(caster, ability, tgt, rank)
				# ...and Shatter: consume an ice debuff for a stun + %-max-HP bonus hit.
				_apply_shatter(caster, ability, tgt, rank)
				# ...and any ON-HIT-APPLY buffs the attacker carries (Wraith Form drops
				# Rime Skin on whatever it strikes).
				if tgt.is_alive():
					CombatBuffs.fire_on_hit(caster.body, tgt)
				var crit_tag := " (CRIT x%.2f)" % float(hit["crit_mult"]) if hit["is_crit"] else ""
				detail = "→ %s · %d %s%s" % [tgt.unit_name, dmg, ability.element_key(), crit_tag]
				print("[combat] %s hits %s for %d %s damage%s [chance %.0f%%]" % [
					ability.display_name, tgt.unit_name, dmg, ability.element_key(), crit_tag, float(hit["crit_chance"])])
			acted = true

		Ability.Kind.HEAL:
			var hbody: CharacterBase = caster.body
			# DEALT heal_power: the caster's heal_power (%) increases the healing it deals.
			# The target's RECEIVED heal_power is applied inside tgt.heal().
			var heal_amt := int(round(ability.compute_heal(hbody.effective_stats(), rank) * _heal_power_dealt(hbody)))
			var restored := tgt.heal(heal_amt)
			detail = "→ %s · +%d hp" % [tgt.unit_name, restored]
			print("[combat] %s heals %s for %d." % [ability.display_name, tgt.unit_name, restored])
			acted = true

		Ability.Kind.SHIELD:
			var sbody: CharacterBase = caster.body
			# DEALT shield_power: the caster's shield_power (%) increases the shield it
			# grants. The target's RECEIVED shield_power is applied inside tgt.gain_shield().
			var shield_amt := int(round(ability.compute_shield(sbody.effective_stats(), rank) * _shield_power_dealt(sbody)))
			if shield_amt > 0:
				tgt.gain_shield({
					"id": String(ability.id),
					"source": ability.display_name,
					"element": ability.element_key(),
					"amount": shield_amt,
					"decay": ability.shield_decay_spec(),
				})
				detail = "→ %s · +%d shield" % [tgt.unit_name, shield_amt]
				print("[combat] %s shields %s for %d." % [ability.display_name, tgt.unit_name, shield_amt])
			else:
				detail = "→ %s · no shield (0)" % tgt.unit_name
			acted = true

		Ability.Kind.BUFF, Ability.Kind.DEBUFF:
			if _maybe_apply_buff(caster, ability, tgt, rank):
				# A BUFF may also carry the one-time spirit gain/steal rider (Energized
				# Form gains 75 Spirit on top of its buff). Harmless for every buff that
				# sets neither — has_spirit_effect() gates it.
				_apply_spirit_effects(caster, ability, tgt, rank)
				# NB _maybe_apply_buff prints the outcome itself now (applied / RESISTED /
				# empowered by Disdain), and returns true for BOTH a landed and a resisted
				# debuff — a resisted cast still spends spirit, AP and cooldown.
				detail = "→ %s" % tgt.unit_name
				acted = true
			elif ability.has_spirit_effect(rank):
				# A BUFF-KIND ABILITY WHOSE WHOLE PAYLOAD IS SPIRIT. `applies_buff` is
				# blank and that is not an authoring error — Haunted Choir refuels its
				# caster and its target and applies nothing. Before spirit_grant existed
				# no such ability could exist, so this branch fell through to "no buff to
				# apply", left `acted` false, and silently refunded the action point,
				# which would have let the AI pick it forever.
				_apply_spirit_effects(caster, ability, tgt, rank)
				detail = "→ %s" % tgt.unit_name
				acted = true
			else:
				print("[combat] %s has no buff to apply (applies_buff is blank / unknown)." % ability.display_name)

		_:
			detail = "→ %s · kind %d not implemented" % [tgt.unit_name, ability.kind]
			print("[combat] %s used on %s (kind %d not yet implemented)" % [ability.display_name, tgt.unit_name, ability.kind])

	if not acted:
		return
	# A SELF buff rides on top of whatever the ability just did, for every kind — Pass
	# Current debuffs its target with Arc Burn and buffs its caster with +5 Alacrity.
	_maybe_apply_self_buff(caster, ability, rank)
	# ONE combat-log line per resolved use, emitted here rather than in the branches
	# so every rider above has already had its say — the buff a Pass Current lands on
	# its target and the one it lands on itself both make it into the same line.
	if _last_buff_note != "":
		detail += ("  " if detail != "" else "") + _last_buff_note
	_log_action(caster, ability, detail)
	if sp_cost > 0:
		caster.spend_spirit(sp_cost)
	var cd := ability.cooldown_at(rank)
	if cd > 0:
		# Cool down THIS slot only, on THIS caster — another copy of the same ability in
		# a different slot keeps its own independent cooldown. A slot of -1 (an ability
		# used from no slot at all) simply doesn't cool down.
		caster.start_cooldown(slot, cd)
	# Spend the caster's action points, and REMEMBER how much was spent: rev30 makes
	# the timeline advance at the end of a turn proportional to ap_spent / max_ap, so
	# an ability that costs half a turn only pushes its user half an interval away.
	var spent := minf(ability.action_cost, caster.ap)
	caster.ap = maxf(0.0, caster.ap - ability.action_cost)
	caster.ap_spent += spent
	_sync_wheel_state()
	_check_victory()
	# A "when struck" reaction (e.g. thorns) can damage the player during their own
	# action — and an ENEMY's attack can now kill them outright — so check for defeat
	# here too, not only on the turn tick.
	_check_defeat()
	# Out of action points -> the ACTIVE unit's turn is over (player and enemy alike).
	# Only FLAGGED here, never ended here: ending the turn re-enters the turn loop, and
	# doing that from inside ability resolution would run the next unit's turn on top of
	# this call. The caller (the wheel handler / the AI routine) acts on the flag.
	if caster == _active and not _battle_over and caster.ap <= AP_EPSILON:
		_turn_should_end = true

## Map a bare buff id to its PER-RANK CLONE in BuffLibrary, when it has one. Several
## buffs ship as a family of near-identical entries (one per invested rank of the ability
## that applies them); the .tres names only the family (applies_buff = &"guard") and this
## picks the member (guard_1..guard_4). Anything not listed here is returned unchanged.
## Used by BOTH _maybe_apply_buff (the target's buff) and _maybe_apply_self_buff.
func _rank_clone_id(bid: String, rank: int) -> String:
	match bid:
		# Guard: a different damage-reduction value per rank, 1..4.
		"guard":              return "guard_%d" % clampi(rank, 1, 4)
		# Scaled Skin (Yesod): longer duration + bigger per-turn heal each rank.
		"scaled_skin":        return "scaled_skin_%d" % clampi(rank, 1, 3)
		# Hematopoiesis (Altar of Water): same clone-per-rank pattern.
		"hematopoiesis":      return "hematopoiesis_%d" % clampi(rank, 1, 3)
		"hypothermia":        return "hypothermia_%d" % clampi(rank, 1, 2)
		"frost":              return "frost_%d" % clampi(rank, 1, 2)
		# Arc Burn (Neurostatic / Pass Current): a bigger Instinct-scaled lightning DoT
		# each rank.
		"arc_burn":           return "arc_burn_%d" % clampi(rank, 1, 3)
		# Electromyogenesis: more Alacrity, longer, each rank.
		"electromyogenesis":  return "electromyogenesis_%d" % clampi(rank, 1, 4)
		# Electrostimulation: bigger package, SMALLER per-turn lightning cost, longer.
		"electrostimulated":  return "electrostimulated_%d" % clampi(rank, 1, 3)
	return bid

## Apply the ability's buff (if any) to `tgt`, cast by `caster`. Returns true if a buff
## was applied. The caster matters twice over: BuffLibrary scales some entries off the
## caster's stats, and try_apply rolls the caster's Disdain against the target.
func _maybe_apply_buff(caster: BattleCharacter, ability: Ability, tgt: BattleCharacter, rank: int = 1) -> bool:
	var bid := _rank_clone_id(String(ability.applies_buff), rank)
	if bid == "":
		return false
	var caster_body: CharacterBase = caster.body if caster else null
	var entry := BuffLibrary.build(bid, caster_body, tgt.body)
	if entry.is_empty():
		return false
	# MAGNIFICENCE / DISDAIN. try_apply rolls the target's magnificence against the
	# caster's disdain (debuffs only — a buff on an ally is never resisted), and on a
	# hit amplifies the entry by the caster's surplus disdain before it lands.
	var rep := CombatBuffs.try_apply(tgt.body, entry, caster_body)
	if bool(rep["resisted"]):
		# A RESISTED debuff still consumed the cast — the caller must treat this as a
		# real use (spirit, action point and cooldown are all spent), which is why
		# this returns TRUE. `false` means "this ability names no buff at all".
		tgt.float_resist()
		_note_buff("%s RESISTED" % bid)
		print("[combat] %s RESISTED %s [chance %.0f%%]" % [tgt.unit_name, bid, float(rep["chance"])])
		tgt.refresh_buffs()
		return true
	var landed := "+%s" % bid
	if float(rep["potency"]) > 1.0 or int(rep["extra_turns"]) > 0:
		# Surplus Disdain amplified this debuff — say so on screen, not just in the log.
		# The violet float reports what was gained in the moment; the BuffBar chip
		# carries a lasting marker (gold under-cap + a line in its hover card).
		tgt.float_empowered(float(rep["potency"]), int(rep["extra_turns"]))
		landed += " (empowered)"
		print("[combat] %s empowered by Disdain: potency x%.2f, +%d turn(s) [overpower %.2f]" % [
			bid, float(rep["potency"]), int(rep["extra_turns"]), float(rep["overpower"])])
	_note_buff(landed)
	print("[combat] %s applied %s to %s." % [ability.display_name, bid, tgt.unit_name])
	tgt.refresh_bar()      # a max-HP / max-Spirit buff can move the ceilings
	tgt.refresh_buffs()
	return true

## Apply the ability's SELF buff (applies_buff_self) to the CASTER, whatever the ability
## targeted. Runs for every kind once the ability's own effect resolved, so an attack, a
## heal or a buff can all also buff their user — Pass Current sears its target with Arc
## Burn and gives the caster +5 Alacrity for 3 turns. Goes through the same per-rank clone
## mapping as the target buff. Returns true if a buff was applied.
func _maybe_apply_self_buff(caster: BattleCharacter, ability: Ability, rank: int = 1) -> bool:
	if ability == null or caster == null or caster.body == null:
		return false
	var bid := _rank_clone_id(String(ability.applies_buff_self), rank)
	if bid == "":
		return false
	var entry := BuffLibrary.build(bid, caster.body, caster.body)
	if entry.is_empty():
		push_warning("[combat] %s names unknown applies_buff_self '%s'." % [ability.display_name, bid])
		return false
	CombatBuffs.apply(caster.body, entry)
	caster.refresh_bar()      # a max-HP / max-Spirit buff can move the ceilings
	caster.refresh_buffs()
	_note_buff("+%s (self)" % bid)
	print("[combat] %s buffs %s with %s." % [ability.display_name, caster.unit_name, bid])
	return true

## Apply an ability's one-time spirit effects: the CASTER GAINS
## spirit_gain_at(rank), and the TARGET LOSES spirit_steal_at(rank) — both instant,
## clamped to each unit's [0, max] by change_spirit. Called from the ATTACK branch
## after the hit lands; a no-op unless the ability sets a gain/steal. The GAIN is applied
## first, so a Lightning Shell bearer converts any over-cap remainder before the steal
## lands. NOTE the caster CAN be its own target: ZAP! targets ALLY, which includes the
## player, so self-zapping nets gain - steal (-5 spirit) plus the self-damage. That is a
## known temporary hole — there is no ALLY-but-not-me target class yet, and self-targeting
## is the only way to test ZAP! until a second friendly unit exists.
func _apply_spirit_effects(caster: BattleCharacter, ability: Ability, tgt: BattleCharacter, rank: int) -> void:
	if ability == null or not ability.has_spirit_effect(rank):
		return
	var gain := ability.spirit_gain_at(rank)
	if gain != 0 and caster != null:
		var got := caster.change_spirit(gain)
		print("[combat] %s gains %d spirit from %s." % [caster.unit_name, got, ability.display_name])
	var steal := ability.spirit_steal_at(rank)
	if steal != 0 and tgt != null:
		var lost := tgt.change_spirit(-steal)
		print("[combat] %s loses %d spirit to %s." % [tgt.unit_name, -lost, ability.display_name])
	# GRANT — spirit given TO the target. Applied AFTER the caster's own gain, for the
	# same reason the gain precedes the steal: a caster running an overflow_shield
	# converts its own over-cap remainder first, before it starts handing spirit out.
	var grant := ability.spirit_grant_at(rank)
	if grant != 0 and tgt != null:
		var given := tgt.change_spirit(grant)
		print("[combat] %s grants %s %d spirit." % [ability.display_name, tgt.unit_name, given])

## SECOND ELEMENT: the other half of an attack that is two damage types at once.
## After the main hit lands, deal `bonus_scaling_mult × caster[bonus_scaling_stat]`
## as `bonus_damage_element` to the same target. A no-op for the (overwhelming)
## majority of attacks, which set no bonus element.
##
## Routed through CombatMath.resolve_flat, so the SECOND element's own mitigation
## applies — the target's resistance to it, the caster's pierce and amp for it,
## damage_dealt_mult and damage_taken_mult. That is the whole reason this exists
## rather than folding the second stat into `scaling_mult2`: a two-element attack
## authored as one element is answered by one resistance, and lopsided resistance
## profiles are precisely what the second element is for.
##
## Dealt with NO source (no on-struck reaction, no recursion) and never a crit —
## the same contract as Shatter's bonus hit and the on-hit-damage riders.
func _apply_bonus_damage(caster: BattleCharacter, ability: Ability, tgt: BattleCharacter, rank: int) -> void:
	if ability == null or not ability.has_bonus_damage():
		return
	if tgt == null or tgt.body == null or not tgt.is_alive():
		return
	var caster_body: CharacterBase = caster.body if caster else null
	if caster_body == null:
		return
	var elem := String(ability.bonus_damage_element)
	var raw := ability.compute_bonus_damage(caster_body.effective_stats(), rank)
	if raw <= 0.0:
		return
	var dmg := CombatMath.resolve_flat(caster_body, tgt.body, raw, elem)
	if dmg <= 0:
		return
	tgt.take_damage(dmg, elem, false)
	print("[combat] %s also deals %d %s damage to %s (second element)." % [
		ability.display_name, dmg, elem, tgt.unit_name])


## Shatter: if `ability` consumes a debuff element and `tgt` carries at least one
## debuff of that element, remove the OLDEST such debuff, apply the ability's shatter
## buff (e.g. a stun) to the target, and deal bonus damage equal to a fraction of the
## target's max HP as the shatter element. A no-op for an attack that sets no
## consume_debuff_element, or when the target carries no matching debuff. The bonus
## damage is a real hit of that element — mitigated by the target's resistance, helped
## by the attacker's pierce/amp, and amplified by hoarfrost — but it is dealt with NO
## source, so it triggers no on-struck reaction and cannot recurse.
func _apply_shatter(caster: BattleCharacter, ability: Ability, tgt: BattleCharacter, rank: int) -> void:
	if ability == null or not ability.has_shatter():
		return
	if tgt == null or tgt.body == null:
		return
	var caster_body: CharacterBase = caster.body if caster else null
	var elem := String(ability.consume_debuff_element)
	var s_elem := String(ability.shatter_damage_element)
	# HOARFROST, SAMPLED FIRST. Hoarfrost is itself an ICE-tagged debuff, so the gate
	# below can consume the very entry that carries the amp (it is usually the only ice
	# debuff on the target). Read the bonus BEFORE the gate runs; it is applied to — and
	# consumed by — the shatter damage further down. 0.0 when there is no hoarfrost.
	var ice_amp := 0.0
	if s_elem == "ice" and not ability.skip_ice_amp:
		ice_amp = CombatBuffs.ice_amp_bonus(tgt.body)
	# The gate: consuming succeeds iff the target actually had such a debuff.
	if not CombatBuffs.consume_oldest_debuff_of_element(tgt.body, elem):
		return
	# 1) apply the on-shatter buff/debuff (e.g. stun) to the target
	var bid := String(ability.shatter_apply_buff)
	if bid != "":
		var entry := BuffLibrary.build(bid, caster_body, tgt.body)
		if not entry.is_empty():
			# try_apply, not apply: the shatter buff still earns the caster's DISDAIN
			# scaling (a high-Disdain Shatter can roll a longer stun). It cannot be
			# RESISTED, though — `stunned` sets resistible:false, because the gate
			# above already charged the player an ice debuff for it and whiffing the
			# payoff after paying that would be miserable.
			CombatBuffs.try_apply(tgt.body, entry, caster_body)
	# 2) bonus damage as a fraction of the target's max HP, as the shatter element.
	# The raw %-max-HP figure is only the ABILITY OUTPUT: it is run through the normal
	# damage pipeline (CombatMath.resolve_flat) so the attacker's damage_dealt_mult,
	# the target's resistance (flat + the multiplicative resist layer), the attacker's
	# pierce + amp for the shatter element and the target's damage_taken_mult all apply,
	# exactly as they would for the attack's own hit. Crit is deliberately NOT rolled.
	var pct := ability.shatter_pct_max_hp_at(rank)
	if pct > 0.0 and tgt.is_alive():
		var raw := maxf(0.0, float(tgt.get_max_hp()) * pct)
		var bonus := CombatMath.resolve_flat(caster_body, tgt.body, raw, s_elem)
		# Hoarfrost is applied HERE rather than inside take_damage: this hit is dealt with
		# no source, and take_damage only amps a SOURCED ice hit. `ice_amp` was sampled
		# above the gate, so the boost lands even when the gate ate the hoarfrost entry
		# itself; consume whatever ice-amp debuffs are still on the target either way.
		if bonus > 0 and ice_amp > 0.0:
			bonus = int(round(maxf(0.0, float(bonus) * (1.0 + ice_amp))))
			CombatBuffs.consume_ice_amp(tgt.body)
		if bonus > 0:
			tgt.take_damage(bonus, s_elem, false)
	tgt.refresh_bar()
	tgt.refresh_buffs()
	print("[combat] %s shatters a %s debuff on %s." % [ability.display_name, elem, tgt.unit_name])

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _wheel and _wheel.visible:
			_wheel.close()

# ---- per-unit turn state ----------------------------------------------
## rev30: the _tick_cooldowns_all / _reset_ap_all round-boundary sweeps are GONE.
## A unit's cooldowns tick and its action points refill at the start of ITS OWN
## turn, inside _begin_unit_turn — which is what makes "N turns" on a cooldown or a
## buff mean N of THAT unit's turns.

## Hand the wheel the player's body + the player's own cooldown map (BY REFERENCE,
## so the wheel greys the exact slot that is cooling down) so it can grey out
## silenced / cooling-down / stunned abilities.
func _sync_wheel_state() -> void:
	if _wheel and _wheel.has_method("set_use_state"):
		_wheel.set_use_state(_player.body if _player else null, _player.cooldowns if _player else {})
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
		_log_note("DEFEAT — %s has fallen." % _player.unit_name)
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
	_log_note("VICTORY — +%d money, +%d xp, %d item(s)." % [BattleState.result_money, BattleState.result_xp, BattleState.result_items.size()])
	print("[combat] victory! +%d money, +%d xp, %d items" % [BattleState.result_money, BattleState.result_xp, BattleState.result_items.size()])
	# Let the final blow / death animation read for a beat before the results screen
	# takes over. The battle is already locked (_battle_over = true), so nothing can
	# act during the wait.
	if typeof(GameManager) != TYPE_NIL and GameManager.has_method("go_to_victory"):
		await get_tree().create_timer(2.0).timeout
		if is_inside_tree():
			GameManager.go_to_victory()

# ---- turn cycle: THE TIMELINE (rev30) ---------------------------------
## Battle start. Every unit is scheduled one FULL interval out rather than at 0, so
## the display is honest from the first frame — among the non-player units the
## shortest bar is the one nearest the marker. THE PLAYER IS THE EXCEPTION: their
## first turn is moved to the origin (PLAYER_OPENS) so the fight always opens with
## it, and `_opening_from` keeps that a MOVE rather than an insertion. Then the loop
## takes over.
func _start_battle() -> void:
	_clock = 0.0
	_phase = Phase.RESOLVING
	_active = null
	for unit in _units:
		var u: BattleCharacter = unit
		var iv: float = u.turn_interval()
		u.cached_interval = iv
		u.next_turn_at = iv
		u.reset_ap()
	# The player opens: move their first turn FORWARD to the earliest moment anyone
	# is scheduled to act, and let _next_actor's player-first tie-break do the rest.
	# Never backwards — a player already faster than everyone keeps their own,
	# earlier slot. See PLAYER_OPENS for why it is the front of the queue rather
	# than the origin.
	if PLAYER_OPENS and _player != null:
		var soonest: float = _player.next_turn_at
		for unit in _units:
			var u2: BattleCharacter = unit
			if u2.is_alive():
				soonest = minf(soonest, u2.next_turn_at)
		_player.next_turn_at = soonest
	if _timeline:
		_timeline.snap_to(_clock)
	_refresh_turn_ui()
	_sync_wheel_state()
	_log_note("── battle start · %d units ──" % _units.size())
	print("[combat] battle start — %d units on the timeline." % _units.size())
	# AI PRIMITIVE SELF-TEST — debug builds only, and quiet when healthy (one PASS
	# line). It checks AIGain's curve and AIPick's roulette against the numbers
	# AI_PRIMER quotes, with no units and no fight involved, so a silently wrong
	# exponent or an off-by-one in the cumulative walk is caught here rather than
	# read as "the enemies feel random" weeks later. Turn it off by setting
	# AIDebug.SELF_TEST_ON_BATTLE_START to false.
	if AIDebug.SELF_TEST_ON_BATTLE_START and AITurn.is_debug():
		AIDebug.self_test()
	_run_turn_loop()

## THE TURN LOOP. Pick the living unit scheduled soonest, scroll the clock to it,
## give it a turn, repeat. This is the whole cycle — there is no round, no player
## phase and no enemy phase. It is a coroutine: it suspends on the scroll animation
## and, on the player's turn, on the `_turn_finished` signal, so nothing spins.
func _run_turn_loop() -> void:
	if _loop_running:
		return
	_loop_running = true
	while not _battle_over:
		_sync_intervals()
		var nxt := _next_actor()
		if nxt == null:
			print("[combat] nobody left to act — turn loop stopping.")
			break
		await _scroll_clock_to(nxt.next_turn_at)
		if _battle_over:
			break
		await _begin_unit_turn(nxt)
	_loop_running = false

## The living unit with the smallest next_turn_at. A DEAD HEAT goes to the player
## first, then to higher alacrity, then to spawn order — deterministic all the way
## down, and never random.
##
## The player-first rung is what makes PLAYER_OPENS true rather than usually-true:
## the opening move puts them on the same tick as the soonest unit, and without
## this a faster enemy would take that tie and open the fight instead. It also
## settles every LATER dead heat the same way, which is the behaviour the timeline
## already had by accident (the player is spawned first, so it won ties on spawn
## order whenever alacrity was equal) — now it is deliberate and holds even when
## the tying unit is faster.
func _next_actor() -> BattleCharacter:
	var best: BattleCharacter = null
	var best_at := 0.0
	var best_alac := 0.0
	for unit in _units:
		var u: BattleCharacter = unit
		if not u.is_alive():
			continue
		var at: float = u.next_turn_at
		var alac: float = u.body.get_effective("alacrity") if u.body else 0.0
		# A tie the PLAYER is already holding is never given away.
		if best == _player and best != null and absf(at - best_at) <= 0.0001:
			continue
		if best == null or at < best_at - 0.0001:
			best = u
			best_at = at
			best_alac = alac
		elif absf(at - best_at) <= 0.0001 and alac > best_alac:
			best = u
			best_at = at
			best_alac = alac
	return best

## Advance the clock to `target`, letting the counter scroll there. ALWAYS awaits
## something, so callers can await it unconditionally.
func _scroll_clock_to(target: float) -> void:
	var dt := maxf(0.0, target - _clock)
	_clock = maxf(_clock, target)
	if _timeline == null:
		await get_tree().process_frame
		return
	await _timeline.scroll_to(_clock, dt)

## One unit's turn, from tick to hand-off.
## Order matters: the start-of-turn tick (DoT etc.) can KILL the unit whose turn it
## is, so it runs before anything is handed to the player or an AI routine, and the
## fight is re-checked immediately after.
func _begin_unit_turn(u: BattleCharacter) -> void:
	# Always a coroutine, whatever branch we take below, so `await` on this call in
	# the loop never trips Godot's "awaited a non-coroutine" warning.
	await get_tree().process_frame
	if _battle_over or u == null or u.body == null:
		return
	_active = u
	_turn_should_end = false
	u.turns_taken += 1
	_log_turn(u)
	if _timeline:
		_timeline.set_active(u)

	_process_turn_start(u)
	u.tick_cooldowns()
	u.reset_ap()
	_check_victory()
	_check_defeat()
	if _battle_over:
		return

	# Died to its own DoT during the tick: no turn, and no advance to schedule.
	if not u.is_alive():
		_active = null
		return

	if CombatBuffs.is_stunned(u.body):
		_log_note("%s is stunned and loses its turn." % u.unit_name)
		print("[combat] %s is stunned and loses its turn." % u.unit_name)
		_finish_turn(u)
		return

	_refresh_turn_ui()
	_sync_wheel_state()

	if u == _player:
		_phase = Phase.PLAYER
		print("[combat] %s's turn (turn %d for them, clock %.0f)." % [u.unit_name, u.turns_taken, _clock])
		_refresh_turn_ui()
		# Hand control to the player. end_player_turn() — the button, or the
		# out-of-AP path in the wheel handler — emits _turn_finished.
		await _turn_finished
		return

	_phase = Phase.RESOLVING
	_refresh_turn_ui()
	await get_tree().create_timer(ENEMY_THINK_DELAY).timeout
	if _battle_over:
		return
	# AWAITED (rev31): the AI routine is a coroutine — it paces itself between the
	# actions of a multi-action turn — so the turn loop must suspend here until it
	# has finished. Without the await, _finish_turn would schedule this unit's next
	# slot while it was still mid-decision.
	await _take_ai_turn(u)
	if _battle_over:
		return
	_finish_turn(u)

## Close out the ACTIVE unit's turn: schedule its next one and drop the active seat.
## Idempotent — a second call for a unit that is no longer active is a no-op, which
## is what makes the "AP ran out" and "pressed End Turn" paths safe to overlap.
func _finish_turn(u: BattleCharacter) -> void:
	if u == null or u != _active:
		return
	# ALWAYS forward from the CLOCK — the moment this turn actually happened. There
	# is no special case for the player's opening turn, and there must not be one:
	# PLAYER_OPENS moves that turn to a tick someone was already acting on, so
	# scheduling from the clock is already exactly right for it.
	u.next_turn_at = _clock + _turn_advance(u)
	u.cached_interval = u.turn_interval()
	_active = null
	_turn_should_end = false
	_phase = Phase.RESOLVING
	if _wheel:
		_wheel.close()
	if _timeline:
		_timeline.set_active(null)
	_refresh_turn_ui()

## HOW FAR a finished turn pushes its unit down the timeline, in ticks.
## The unit's interval, scaled by the FRACTION OF ITS ACTION-POINT BUDGET it
## actually spent. That single line covers every case with no special-casing:
##   - default (action_points 1.0, action_cost 1.0): spent 1/1 -> a full interval.
##   - an action_cost 0.5 ability used once, then End Turn: half an interval, so the
##     unit acts again twice as soon. "An attack that costs less than a full turn."
##   - the same ability used twice: spent 1.0 -> a full interval. Two half-actions
##     are one turn.
##   - an action_points 2.0 boss: acts twice, spends 2/2 -> a full interval.
## Spending NOTHING (a deliberate pass, or a turn lost to a stun) costs a FULL
## interval — idling is not a way to act sooner.
## There is deliberately NO balance floor on the fraction: if an ability is too
## strong for its cost, raise its action_cost. MIN_TURN_ADVANCE is only a guard
## against a zero-length turn spinning the loop.
func _turn_advance(u: BattleCharacter) -> float:
	var iv := u.turn_interval()
	if u.ap_spent <= AP_EPSILON:
		return iv
	var budget := maxf(AP_EPSILON, u.max_ap())
	return maxf(MIN_TURN_ADVANCE, iv * clampf(u.ap_spent / budget, 0.0, 1.0))

## Rescale any unit whose INTERVAL has changed since we last looked (a haste buff
## landed, alacrity was drained, a turn_rate debuff stuck). The REMAINING wait moves
## by the same ratio, so speeding a unit up visibly slides its next turn closer
## instead of only helping from the turn after next.
## NB `_units` is an untyped Array, so `u` is a Variant and := cannot infer off it —
## every local read out of a unit in this file is explicitly typed for that reason.
func _sync_intervals() -> void:
	for unit in _units:
		var u: BattleCharacter = unit
		var iv: float = u.turn_interval()
		var cached: float = u.cached_interval
		if cached <= 0.0:
			u.cached_interval = iv
			continue
		if is_equal_approx(iv, cached):
			continue
		if HASTE_RESCALES_PENDING and u.next_turn_at > _clock:
			var remaining: float = u.next_turn_at - _clock
			u.next_turn_at = _clock + remaining * (iv / cached)
		u.cached_interval = iv

## ONE unit's start-of-turn tick: DoT, heal-over-turn, spirit, expiries, shield
## decay. rev30: this is the old _process_turn_start_all's loop body, run for the
## single unit whose turn is beginning. That is the whole of "durations count the
## bearer's own turns" — a 3-turn buff on a slow unit now spans more of the fight in
## real time, and a fast unit burns through its own buffs faster.
func _process_turn_start(u: BattleCharacter) -> void:
	if u == null or u.body == null or not u.is_alive():
		return
	var report := CombatBuffs.collect_turn_start(u.body)
	# 1) DoT damage (routed through take_damage so it animates + handles death)
	for d in report["dots"]:
		if u.is_alive():
			u.take_damage(int(d["amount"]), str(d["element"]), false)
	# 1b) heal-over-turn (Scaled Skin, ...): restore HP via heal() so it
	# animates and respects the healing-received multiplier.
	for h in report["heals"]:
		if u.is_alive():
			u.heal(int(h["amount"]))
	# 2) spirit: default per-turn regen + this unit's buff/debuff spirit delta
	if u.is_alive():
		var regen := int(round(u.body.get_effective("spirit_regen")))
		var delta := int(round(float(report["spirit_delta"])))
		u.change_spirit(regen + delta)
	# 3) on-expire events for anything that fell off this turn
	for e in report["expired"]:
		CombatBuffs.fire_expiry(u, e)
	# 4) shields decay at the turn boundary (each decaying instance loses its
	# flat / %-of-current / %-of-value-at-apply amount; non-decaying ones persist).
	CombatShields.tick_decay(u.body)
	u.refresh_bar()
	u.refresh_buffs()

## The player ends their turn — from the End Turn button, or from the wheel handler
## once the action-point budget is spent. Wakes _run_turn_loop, which is parked on
## _turn_finished.
func end_player_turn() -> void:
	if _battle_over or _phase != Phase.PLAYER or _active != _player:
		return
	_finish_turn(_player)
	_turn_finished.emit()

## One non-player unit's turn. rev30: it gets its OWN scheduled slot on the
## timeline rather than being run in a batch after the player, and the dead / the
## stunned are filtered out by _begin_unit_turn before this is ever called.
##
## rev31 — THE DECIDING NOW EXISTS. Everything from here is AITurn's: the action
## loop, the guards, the pacing between actions, the fallback ladder and the debug
## ledger (scenes/combat/ai/, see AI_PRIMER). This function is the whole of
## combat's side of the seam, and it stays this small on purpose — the AI is a
## CLIENT of combat, not a part of it. It filters with _can_use / _valid_target,
## carries the real slot index, and resolves through _use_ability like any caster.
##
## `ai == "none"` still means "pass the turn", and is still the default on every
## character module, so a creature only starts acting once its module names a
## routine AND lists an `abilities` loadout for it to act with.
##
## ALWAYS A COROUTINE. The leading await costs one frame and guarantees the caller
## can `await _take_ai_turn(u)` unconditionally without tripping Godot's
## "awaited a non-coroutine" warning on the early-return paths — the same reason
## _begin_unit_turn opens with one.
func _take_ai_turn(u: BattleCharacter) -> void:
	await get_tree().process_frame
	if u == null or u.body == null or not u.is_alive():
		return
	if u.ai == "none":
		_log_note("%s does nothing." % u.unit_name)
		print("[combat] %s does nothing." % u.unit_name)
		return
	await AITurn.run(self, u)

## May this unit take ANOTHER action inside its current turn? The loop condition for
## any multi-action AI routine.
func _ai_can_continue(u: BattleCharacter) -> bool:
	return not _battle_over and not _turn_should_end \
		and u != null and u == _active and u.is_alive() and u.ap > AP_EPSILON

func _refresh_turn_ui() -> void:
	if _end_turn_btn:
		_end_turn_btn.disabled = _battle_over or _phase != Phase.PLAYER or _active != _player
	if _timeline:
		_timeline.queue_redraw()

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
