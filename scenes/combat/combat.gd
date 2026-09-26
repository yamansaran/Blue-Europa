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
##
## rev33 — PRESENTATION PASS.
##   - OVERHEAD BARS: every unit carries compact HP / spirit / shield bars and its buff
##     icons ABOVE its model (UnitOverhead). The TOP PANEL holds the two LOADED units
##     (one ally, one enemy — _load_unit, FUTURE_PLANS §7) so a nine-enemy fight never
##     floods the band.
##   - THE CAMERA: clicking a unit, and every hostile action (an attack or debuff aimed
##     at the other side, by anyone), pans + zooms CAM_ZOOM onto the target and then
##     returns to centre. The battle panel sits inside a clipping Control (_battle_clip)
##     and the "camera" is that panel's position + scale. Every action now resolves
##     through _perform_action, which owns the pan / hold / return around _use_ability.
##   - THE BOTTOM PANEL is three panels, like the shell toolbar: LEFT and RIGHT hold the
##     DIALOGUE boxes (empty until someone speaks), CENTRE holds a big round END TURN
##     button with a small red LEAVE FIGHT square over it.
##   - COMBAT DIALOGUE: a fight spec's "dialogue" plays at safe points (CombatDialogue).

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
## Clips the battle panel to its band, so the camera zoom never spills over the top /
## bottom panels. The panel's position + scale inside it IS the camera.
var _battle_clip: Control
var _bottom_panel: Panel
var _healthbar_row: HBoxContainer

# --- the bottom panel: three panels (rev33) ------------------------------
## Fractions match the shell toolbar (Left 0..0.4, Center 0.4..0.6, Right 0.6..1).
const BOTTOM_SPLIT_LEFT := 0.4
const BOTTOM_SPLIT_RIGHT := 0.6
var _bottom_left: Panel = null
var _bottom_center: Panel = null
var _bottom_right: Panel = null
var _dialogue_left: DialogueBox = null
var _dialogue_right: DialogueBox = null
var _leave_btn: Button = null
const END_TURN_DIAMETER := 108.0
const LEAVE_BTN_SIZE := 26.0

# --- combat dialogue (rev33) ----------------------------------------------
var _dialogue: CombatDialogue = null
## True while a line is on screen: the player cannot act or end the turn.
var _dialogue_busy: bool = false

# --- the camera (rev33) ----------------------------------------------------
## Master switch for the pan + zoom. False = the old static battlefield.
const CAMERA_ENABLED := true
## 1.25 = 25% closer.
const CAM_ZOOM := 1.25
const CAM_IN_TIME := 0.28
const CAM_OUT_TIME := 0.32
## How long the camera lingers on the target after an action resolves, so the damage
## number reads before it pulls back.
const CAM_HOLD_TIME := 0.55
var _cam_tween: Tween = null
## The unit the camera is currently centred on (null = centre of the battlefield).
var _cam_target: BattleCharacter = null
## True while an action is panning / resolving / holding. Blocks clicks, End Turn and
## a second action, so two actions can never overlap.
var _action_busy: bool = false

var _wheel: ActionWheel
var _units: Array = []
var _player: BattleCharacter = null
var _open_target: BattleCharacter = null
var _battle_over: bool = false
## True for the bare practice dummy (a fight with no enemies authored). Its damage is
## not filed into Character.damage_history — hitting a dummy is not a fight.
var _dummy_fight: bool = false
## Guard: the history is written ONCE per fight, whichever way it ends.
var _history_recorded: bool = false

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

## The debug flag, read ONCE per fight. Every Output-log line combat writes goes through
## _dbg (perf, 2026-09-25): run from the editor, each print() crosses the debugger to the
## Output panel, and a multi-hit / AoE turn printed dozens. With debug off, none of them.
var _debug := false

func _dbg(msg: String) -> void:
	if _debug:
		print(msg)

func _ready() -> void:
	_debug = typeof(GameManager) != TYPE_NIL and GameManager.has_method("is_debug") and GameManager.is_debug()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_layout()
	_load_units()
	_apply_permanent_buffs()
	_apply_passive_buffs()
	_setup_player_perks()
	_build_health_bars()
	_build_grid()
	_place_units()
	_build_wheel()
	_build_turn_ui()
	_build_debug_ui()
	_dialogue = CombatDialogue.from_config(BattleState.dialogue)
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

	# The battle band is a CLIP holding the battle panel, so the camera (the panel's
	# position + scale) can zoom without drawing over the top or bottom panels.
	_battle_clip = Control.new()
	_band(_battle_clip, TOP_FRAC, TOP_FRAC + MID_FRAC)
	_battle_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_battle_clip.clip_contents = true
	add_child(_battle_clip)

	_battle_panel = Control.new()
	_battle_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_battle_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_battle_clip.add_child(_battle_panel)

	_bottom_panel = _make_panel(TOP_FRAC + MID_FRAC, 1.0, Color(0.12, 0.12, 0.15))
	add_child(_bottom_panel)
	_build_bottom_sections()

	_healthbar_row = HBoxContainer.new()
	_healthbar_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_healthbar_row.add_theme_constant_override("separation", 12)
	top_panel.add_child(_healthbar_row)

## The bottom panel's three sections. LEFT and RIGHT are empty until dialogue plays
## (each holds a hidden DialogueBox); CENTRE gets the End Turn / Leave buttons in
## _build_turn_ui.
func _build_bottom_sections() -> void:
	_bottom_left = _section_panel(0.0, BOTTOM_SPLIT_LEFT)
	_bottom_center = _section_panel(BOTTOM_SPLIT_LEFT, BOTTOM_SPLIT_RIGHT)
	_bottom_right = _section_panel(BOTTOM_SPLIT_RIGHT, 1.0)
	_dialogue_left = _dialogue_box_in(_bottom_left, false)
	_dialogue_right = _dialogue_box_in(_bottom_right, true)

func _section_panel(left: float, right: float) -> Panel:
	var p := Panel.new()
	p.anchor_left = left
	p.anchor_right = right
	p.anchor_top = 0.0
	p.anchor_bottom = 1.0
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.13, 0.13, 0.17)
	sb.border_color = Color(0.30, 0.30, 0.36)
	sb.set_border_width_all(2)
	p.add_theme_stylebox_override("panel", sb)
	_bottom_panel.add_child(p)
	return p

func _dialogue_box_in(host: Control, mirrored: bool) -> DialogueBox:
	var box := DialogueBox.new()
	box.mirrored = mirrored
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 6
	box.offset_top = 6
	box.offset_right = -6
	box.offset_bottom = -6
	host.add_child(box)
	return box

# ---- units ------------------------------------------------------------
func _load_units() -> void:
	var allies: Array = BattleState.allies.duplicate(true)
	var enemies: Array = BattleState.enemies.duplicate(true)

	# --- player ---
	var pbody := _make_player_body()
	pbody.char_type = Stats.CharType.CHARACTER
	_player = _spawn_unit(pbody, TEAM_PLAYER, "player", "player")

	# --- allies ---
	# Built via CharacterRegistry: a spec that names a "character" module is built
	# from that module (its own stats + permanent buffs); a plain dict still works.
	# ai / size_scale now live ON THE BODY (the module sets them), so we read them
	# from there rather than off the spec.
	for a in allies:
		if typeof(a) == TYPE_DICTIONARY:
			var abody := CharacterRegistry.build(a)
			var au := _spawn_unit(abody, TEAM_ALLY, abody.ai, str(a.get("character", "")))
			au.size_scale = abody.size_scale
			_seat_from_spec(au, a)

	# --- enemies (default: one Training Dummy) ---
	if enemies.is_empty():
		enemies = [ _training_dummy_spec() ]
		_dummy_fight = true
	for e in enemies:
		if typeof(e) == TYPE_DICTIONARY:
			var ebody := CharacterRegistry.build(e)
			var eu := _spawn_unit(ebody, TEAM_ENEMY, ebody.ai, str(e.get("character", "")))
			eu.size_scale = ebody.size_scale
			_seat_from_spec(eu, e)
			if _debug_target == null:
				_debug_target = eu   # first enemy = the training dummy in debug fights

## EXPLICIT SEATING FROM A FIGHT SPEC. "col" (0 BACK / 1 FRONT) and "row" (0 top ..
## 4 bottom) pin a unit to one formation slot; _place_units honours a pre-set seat
## before it deals anyone else a slot. A spec that names neither is dealt a slot by
## BattleGrid.assign exactly as before, so DEFAULT FILLING IS UNCHANGED and only the
## fights that care about position (the Registrar behind his line; six corpses seated
## 3 by 3) say anything at all.
##
## BOTH OR NEITHER. _place_units seats a unit only when BOTH ints are >= 0, but its
## second pass tests `grid_row` ALONE to decide who still needs dealing — so a spec
## with "row" and no "col" would be skipped by the first pass AND by the second, and
## the unit would never be seated at all. Rather than half-apply it, drop the seat
## and name the mistake.
##
## NB these live on the BattleCharacter, not on CharacterBase: seating is a combat
## concept, and putting it on the body would push it into the save dict for no reason.
func _seat_from_spec(u: BattleCharacter, spec: Dictionary) -> void:
	if u == null or typeof(spec) != TYPE_DICTIONARY:
		return
	if not spec.has("col") and not spec.has("row"):
		return
	if not (spec.has("col") and spec.has("row")):
		push_warning("[combat] %s names only one of \"col\" / \"row\" — a seat needs both. Ignoring it." % u.unit_name)
		return
	var col := clampi(int(spec["col"]), 0, BattleGrid.COLS - 1)
	var row := clampi(int(spec["row"]), 0, BattleGrid.ROWS - 1)
	u.grid_col = col
	u.grid_row = row

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

func _spawn_unit(body: CharacterBase, team: int, ai: String, spec_id: String = "") -> BattleCharacter:
	var u := BattleCharacter.new()
	u.body = body
	u.team = team
	u.ai = ai
	u.spec_id = spec_id
	u.unit_name = body.char_name
	u.loadout = _loadout_for(body, team)
	_battle_panel.add_child(u)
	_units.append(u)
	u.hovered.connect(_on_unit_hovered)
	u.clicked.connect(_on_unit_clicked)
	u.health_damaged.connect(_on_unit_health_damaged)
	u.hp_lost.connect(_on_unit_hp_lost)
	u.hp_paid.connect(_on_unit_hp_paid)
	u.struck.connect(_on_unit_struck)
	u.death_guard = _death_guard
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

# ---- the top panel: LOADED units (FUTURE_PLANS §7) --------------------
## The top panel holds exactly TWO slots — the LOADED ally (left) and the LOADED enemy
## (right). Each shows a portrait, the big health + spirit bar and the DETAILED buff
## strip (one chip per INSTANCE — the full picture; the field strip under each model
## groups by type, §6). This replaces the old "important units only" band: boss and
## miniboss bars are gone, loading is the only way onto the panel.
##   - The PLAYER is loaded on the ally side at fight start; the enemy side starts blank.
##   - CLICKING any unit loads it for its side — ALWAYS, before any other click rule
##     (covered, not your turn, busy), and then the click carries on as before.
##   - A loaded unit stays until another unit of its side is clicked.
##   - When a loaded unit DIES its slot goes blank (no fallback).
## Only the loaded unit holds `health_bar` / `buff_bar`; everyone else's are null, and
## BattleCharacter.refresh_bar / refresh_buffs already skip a null bar.
const PORTRAIT_SIZE := 44.0

var _ally_slot: HBoxContainer
var _enemy_slot: HBoxContainer
var _loaded_ally: BattleCharacter = null
var _loaded_enemy: BattleCharacter = null

func _build_health_bars() -> void:
	_ally_slot = HBoxContainer.new()
	_ally_slot.add_theme_constant_override("separation", 6)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_enemy_slot = HBoxContainer.new()
	_enemy_slot.add_theme_constant_override("separation", 6)
	_enemy_slot.alignment = BoxContainer.ALIGNMENT_END
	_healthbar_row.add_child(_ally_slot)
	_healthbar_row.add_child(spacer)
	_healthbar_row.add_child(_enemy_slot)
	_load_unit(_player)

## Make `u` the loaded unit for its side and rebuild that slot. A dead unit is never
## loaded (its slot would only go straight back to blank).
func _load_unit(u: BattleCharacter) -> void:
	if u == null or u.body == null or not u.is_alive() or _ally_slot == null:
		return
	var enemy := u.team == TEAM_ENEMY
	var prev: BattleCharacter = _loaded_enemy if enemy else _loaded_ally
	if prev == u:
		return
	_unbind_loaded(prev)
	var slot: HBoxContainer = _enemy_slot if enemy else _ally_slot
	_clear_slot(slot)

	var portrait := ColorRect.new()
	portrait.color = u.body.model_color()
	portrait.custom_minimum_size = Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE)
	portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var hb := BattleHealthBar.new()
	# Enemies mirror: their max box sits on the buff-strip side (the left).
	hb.setup(u.unit_name, u.get_max_hp(), u.get_hp(), u.get_max_spirit(), u.get_spirit(), u.body.model_color(), enemy)
	var bb := BuffBar.new()
	bb.setup(u.body, BuffBar.SIDE_LEFT if enemy else BuffBar.SIDE_RIGHT)   # per INSTANCE

	if enemy:
		slot.add_child(bb)          # buffs | bar | portrait — mirrored in from the right
		slot.add_child(hb)
		slot.add_child(portrait)
		_loaded_enemy = u
	else:
		slot.add_child(portrait)    # portrait | bar | buffs
		slot.add_child(hb)
		slot.add_child(bb)
		_loaded_ally = u
	u.health_bar = hb
	u.buff_bar = bb
	u.refresh_bar()
	u.refresh_buffs()

## Blank `u`'s slot if it is loaded (death). Safe on any unit.
func _unload_unit(u: BattleCharacter) -> void:
	if u == null:
		return
	if u == _loaded_ally:
		_unbind_loaded(u)
		_clear_slot(_ally_slot)
		_loaded_ally = null
	elif u == _loaded_enemy:
		_unbind_loaded(u)
		_clear_slot(_enemy_slot)
		_loaded_enemy = null

func _unbind_loaded(u: BattleCharacter) -> void:
	if u != null and is_instance_valid(u):
		u.health_bar = null
		u.buff_bar = null

func _clear_slot(slot: HBoxContainer) -> void:
	if slot == null:
		return
	for c in slot.get_children():
		slot.remove_child(c)
		c.queue_free()

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

## THE ONE BACK-ROW-PROTECTION PREDICATE. `u` is unreachable by the other side while
## its own front row shields it (BattleGrid.is_covered).
##
## BOTH the player's click path (_valid_target, _on_unit_clicked) and the AI's
## candidate filter (AIContext.targets_for, which resolves through _valid_target)
## call THIS — never a second copy. If the AI and the click handler ever disagree
## about who is reachable, that is a bug in the gate rather than in either caller
## (AI_PRIMER §3). An unseated unit (grid_col -1) is never covered.
func _is_covered(u: BattleCharacter) -> bool:
	if u == null or u.grid_col < 0:
		return false
	var g := _grid_for(u)
	return g != null and g.is_covered(u)

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
			# A SLOT COLLISION IS AN AUTHORING ERROR, NOT A CRASH. place() refuses a
			# slot someone else already holds and changes nothing — which would leave
			# this unit carrying coordinates it is not actually seated at: skipped by
			# the pass below (which tests grid_row alone), absent from the occupancy
			# map that back-row protection reads, and drawn on top of whoever does
			# hold the slot. Clear the seat and let it be dealt a free one instead.
			if not _grid_for(u).place(u, u.grid_col, u.grid_row):
				push_warning("[combat] %s wants slot %s but it is taken — dealing it a free one." % [
					u.unit_name, BattleGrid.slot_name(u.grid_col, u.grid_row)])
				u.grid_col = -1
				u.grid_row = -1

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
	# The wheel closing WITHOUT an action (a click on empty space / an empty slot)
	# sends the camera back to centre.
	_wheel.visibility_changed.connect(_on_wheel_visibility_changed)
	_sync_wheel_state()

# ---- turn UI (End Turn button + the scrolling turn counter) -----------
## rev30: the "Turn N" label is gone — there is no round to number. In its place the
## TurnTimeline is OVERLAID on the existing layout (added to the scene root, anchored
## to the bottom edge of the health-bar band at the far left) so it reads as sitting
## directly under the party health bars without reflowing either band. It ignores the
## mouse, so a click meant for a unit still reaches it.
func _build_turn_ui() -> void:
	# END TURN — a big round button in the centre third of the bottom panel. Ends the
	# player's turn without doing anything (a pass costs a full interval, C7).
	_end_turn_btn = Button.new()
	_end_turn_btn.text = "End Turn"
	_end_turn_btn.tooltip_text = "End your turn without acting"
	_end_turn_btn.focus_mode = Control.FOCUS_NONE
	_end_turn_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_end_turn_btn.anchor_left = 0.5
	_end_turn_btn.anchor_right = 0.5
	_end_turn_btn.anchor_top = 0.5
	_end_turn_btn.anchor_bottom = 0.5
	var r := END_TURN_DIAMETER * 0.5
	_end_turn_btn.offset_left = -r
	_end_turn_btn.offset_right = r
	_end_turn_btn.offset_top = -r
	_end_turn_btn.offset_bottom = r
	_end_turn_btn.add_theme_font_size_override("font_size", 17)
	_style_round_button(_end_turn_btn, Color(0.22, 0.36, 0.62), r)
	_end_turn_btn.pressed.connect(end_player_turn)
	_bottom_center.add_child(_end_turn_btn)

	# LEAVE FIGHT — a small red square riding on the End Turn button's top-right edge.
	# Added AFTER the round button so it draws on top and takes its own clicks.
	_leave_btn = Button.new()
	_leave_btn.text = "×"   # U+00D7: Inter has it; ✕ forced a slow system-font fallback
	_leave_btn.tooltip_text = "Leave the fight"
	_leave_btn.focus_mode = Control.FOCUS_NONE
	_leave_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_leave_btn.anchor_left = 0.5
	_leave_btn.anchor_right = 0.5
	_leave_btn.anchor_top = 0.5
	_leave_btn.anchor_bottom = 0.5
	_leave_btn.offset_left = r * 0.62
	_leave_btn.offset_right = r * 0.62 + LEAVE_BTN_SIZE
	_leave_btn.offset_top = -r - 2.0
	_leave_btn.offset_bottom = -r - 2.0 + LEAVE_BTN_SIZE
	_leave_btn.add_theme_font_size_override("font_size", 14)
	_style_square_button(_leave_btn, Color(0.78, 0.16, 0.16))
	_leave_btn.pressed.connect(_on_leave_pressed)
	_bottom_center.add_child(_leave_btn)

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

func _style_round_button(b: Button, col: Color, radius: float) -> void:
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb := StyleBoxFlat.new()
		match state:
			"hover": sb.bg_color = col.lightened(0.15)
			"pressed": sb.bg_color = col.darkened(0.2)
			"disabled": sb.bg_color = col.darkened(0.55)
			"focus": sb.bg_color = Color(0, 0, 0, 0)
			_: sb.bg_color = col
		sb.set_corner_radius_all(int(radius))
		sb.set_corner_detail(16)
		sb.border_color = Color(0.85, 0.88, 0.95, 0.9) if state != "disabled" else Color(0.4, 0.4, 0.45)
		sb.set_border_width_all(3)
		sb.shadow_color = Color(0, 0, 0, 0.45)
		sb.shadow_size = 4 if state != "pressed" else 1
		b.add_theme_stylebox_override(state, sb)

func _style_square_button(b: Button, col: Color) -> void:
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb := StyleBoxFlat.new()
		match state:
			"hover": sb.bg_color = col.lightened(0.18)
			"pressed": sb.bg_color = col.darkened(0.25)
			"disabled": sb.bg_color = col.darkened(0.6)
			"focus": sb.bg_color = Color(0, 0, 0, 0)
			_: sb.bg_color = col
		sb.set_corner_radius_all(3)
		sb.border_color = Color(0.12, 0.02, 0.02)
		sb.set_border_width_all(2)
		b.add_theme_stylebox_override(state, sb)

func _on_leave_pressed() -> void:
	if _battle_over:
		return
	_log_note("LEFT — %s withdraws from the fight." % (_player.unit_name if _player else "the party"))
	_leave_combat()

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
## NEPHILIC (2026-09-24): the per-CAST context the hooks read — HP paid, spirit at
## the moment of casting (Brimming), Rebuke stacks spent, whether a target died.
var _cast_ctx: Dictionary = {}
const LEAD_ID := "lead"
const CRASH_ID := "crash_blow"

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
	_dbg("[combat][debug] applied new stats to %s (max_hp=%d)" % [
		_debug_target.unit_name if _debug_target else "?",
		_debug_target.get_max_hp() if _debug_target else 0])

## A unit lost ACTUAL HEALTH. Two sweeps, and only combat can run the second one
## because only combat holds the unit list:
##   1. what THIS unit was carrying that cannot survive being hurt (Covering, if the
##      officer keeps a self-buff at all);
##   2. what ANYONE ELSE is carrying that was anchored to this unit as its caster —
##      Protected on the ally, when the officer shielding them is struck. That is
##      "hit the shield man to free his friend", with no two-way link anywhere.
func _on_unit_health_damaged(u: BattleCharacter) -> void:
	if u == null or u.body == null:
		return
	for e in CombatBuffs.break_on_health_damage(u.body):
		u.refresh_buffs()
		u.refresh_bar()
		_log_note("%s loses %s" % [u.unit_name, str(e.get("source", e.get("id", "?")))])
		_dbg("[combat] %s loses %s — took health damage." % [u.unit_name, str(e.get("id", "?"))])
	var uid := u.body.get_instance_id()
	for other in _units:
		if other == null or other.body == null or other == u:
			continue
		for e in CombatBuffs.break_caster_linked(other.body, uid):
			other.refresh_buffs()
			other.refresh_bar()
			_log_note("%s loses %s — %s was hit" % [other.unit_name, str(e.get("source", e.get("id", "?"))), u.unit_name])
			_dbg("[combat] %s loses %s — its caster %s took health damage." % [
				other.unit_name, str(e.get("id", "?")), u.unit_name])

func _on_unit_hovered(_u: BattleCharacter) -> void:
	# Hover only reveals the unit's floating name/level label (done inside
	# BattleCharacter). The wheel now opens on CLICK, not hover.
	pass

func _on_unit_clicked(u: BattleCharacter) -> void:
	# LOADING comes first and ALWAYS happens (FUTURE_PLANS §7): whatever else the
	# click is refused for below, the unit's detailed view still loads.
	_load_unit(u)
	if _battle_over or _phase != Phase.PLAYER or _action_busy or _dialogue_busy:
		return
	# BACK-ROW PROTECTION, AT THE CLICK. Opening the wheel over a covered enemy would
	# offer a full set of abilities and then refuse every one of them, which reads as
	# a broken wheel rather than as a rule — so the CLICK is what gets refused, with a
	# float that names the reason. Only hostiles are covered from the player's seat,
	# so clicking a covered ally to heal it is unaffected.
	if _player != null and _is_hostile(_player, u) and _is_covered(u):
		u.float_covered()
		_dbg("[combat] %s is covered by the front row — pick a front-row target." % u.unit_name)
		return
	# The camera pans + zooms onto the clicked unit while the wheel opens over it.
	_camera_focus(u)
	_open_wheel_for(u)   # clicking any unit (player / ally / enemy) opens the wheel

func _on_wheel_visibility_changed() -> void:
	if _wheel and not _wheel.visible and not _action_busy and _cam_target != null:
		_camera_reset()

func _open_wheel_for(u: BattleCharacter) -> void:
	_open_target = u
	_sync_wheel_state()
	_wheel.open_over(u.position + u.size * 0.5)

func _on_wheel_slot_selected(index: int, ability_id: String) -> void:
	if _action_busy or _dialogue_busy:
		return
	# Busy BEFORE the wheel closes, so its visibility handler doesn't yank the camera
	# back to centre in the middle of the action.
	_action_busy = true
	_wheel.close()
	var ability := _get_ability(ability_id)
	if ability == null or _open_target == null or _player == null:
		_cancel_action()
		return
	# SELF-targeted abilities always act on the CASTER, whatever was clicked.
	var tgt := _open_target
	if ability.target == Ability.Target.SELF:
		tgt = _player
	if not _valid_target(_player, ability, tgt):
		_dbg("[combat] %s can't target %s" % [ability.display_name, tgt.unit_name])
		_cancel_action()
		return
	# Gameplay gates — ONE predicate, shared with the wheel's greying and the enemy
	# AI's filter, so no path can resolve an ability another path would refuse.
	var blocked := _use_blocked(_player, ability, index)
	if blocked != "":
		_dbg("[combat] %s." % blocked)
		_cancel_action()
		return
	await _perform_action(_player, ability, tgt, index)
	# The budget ran out during that cast -> the player's turn is over. Ended HERE,
	# once resolution has fully unwound, rather than from inside _use_ability.
	if _turn_should_end and not _battle_over and is_inside_tree():
		_dbg("[combat] %s is out of action points — ending turn." % _player.unit_name)
		end_player_turn()

func _cancel_action() -> void:
	_action_busy = false
	_camera_reset()
	_refresh_turn_ui()

# ---- actions + the camera (rev33) --------------------------------------
## THE ONE WAY AN ACTION HAPPENS NOW, for the player's wheel and every AI routine.
## It wraps _use_ability in the presentation: for a HOSTILE action (an attack or
## debuff aimed at the other side) the camera pans + zooms onto the target, the
## ability resolves, the camera holds for a beat so the numbers read, then returns to
## the centre of the battlefield. A friendly action (a heal, a self-buff) resolves
## without the pan. ALWAYS a coroutine; callers must await it.
## _use_ability itself is untouched and still synchronous — nothing that resolves an
## ability had to learn about the camera.
func _perform_action(caster: BattleCharacter, ability: Ability, tgt: BattleCharacter, slot: int = -1) -> void:
	_action_busy = true
	_refresh_turn_ui()
	var focus := CAMERA_ENABLED and _camera_wants(caster, ability, tgt)
	if focus and _cam_target != tgt:
		_camera_focus(tgt)
		await get_tree().create_timer(CAM_IN_TIME).timeout
	else:
		await get_tree().process_frame
	if not is_inside_tree():
		return
	if _battle_over:
		_action_busy = false
		return
	_use_ability(caster, ability, tgt, slot)
	# Resolution can end the fight and leave the scene (belt and braces — defeat and
	# victory both defer their exit now, but nothing below may assume a tree).
	if not is_inside_tree():
		return
	if focus:
		await get_tree().create_timer(CAM_HOLD_TIME).timeout
		if not is_inside_tree():
			return
	if _cam_target != null or (_battle_panel and _battle_panel.scale != Vector2.ONE):
		_camera_reset()
	_action_busy = false
	_refresh_turn_ui()

## Does this action get the pan + zoom? Anything aimed at the OTHER side that is an
## attack or a debuff — whoever casts it, player, ally or enemy.
func _camera_wants(caster: BattleCharacter, ability: Ability, tgt: BattleCharacter) -> bool:
	if caster == null or ability == null or tgt == null:
		return false
	# AN AoE HAS NO SINGLE UNIT TO FRAME. Zooming onto whichever unit happened to be
	# clicked would hide the rest of the fan, which is the only part worth watching,
	# so an ALL_* ability resolves wide and the numbers fan across the whole field.
	# (rev33's burst fanning already handles simultaneous numbers on ONE unit;
	# numbers on different units need nothing.)
	# A RANDOM-TARGET MULTI-HIT (Spray) is the same case: its shots land wherever
	# the dice put them, so framing the clicked unit would frame the wrong one.
	if ability.is_area_target() or ability.retargets_each_hit():
		return false
	if not _is_hostile(caster, tgt):
		return false
	return ability.kind == Ability.Kind.ATTACK or ability.kind == Ability.Kind.DEBUFF

## Pan + zoom so `u` sits at the centre of the battle band, CAM_ZOOM closer. The
## "camera" is the battle panel's position + scale inside _battle_clip: a point p on
## the panel lands at position + p * scale, so centring c needs position =
## centre - c * scale. Not awaited here — callers that must wait await CAM_IN_TIME.
func _camera_focus(u: BattleCharacter) -> void:
	if not CAMERA_ENABLED or _battle_panel == null or u == null:
		return
	_cam_target = u
	var c := u.position + u.size * 0.5
	var centre := _battle_panel.size * 0.5
	_camera_to(centre - c * CAM_ZOOM, Vector2(CAM_ZOOM, CAM_ZOOM), CAM_IN_TIME)

## Back to the centre of the battlefield at 1x.
func _camera_reset() -> void:
	if _battle_panel == null:
		return
	_cam_target = null
	_camera_to(Vector2.ZERO, Vector2.ONE, CAM_OUT_TIME)

func _camera_to(pos: Vector2, scl: Vector2, t: float) -> void:
	if _cam_tween and _cam_tween.is_valid():
		_cam_tween.kill()
	_cam_tween = create_tween().set_parallel(true)
	_cam_tween.tween_property(_battle_panel, "position", pos, t).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_cam_tween.tween_property(_battle_panel, "scale", scl, t).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

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
		# BACK-ROW PROTECTION applies to HOSTILE targeting only: a covered unit is
		# shielded FROM THE OTHER SIDE, so its own healers still reach it.
		Ability.Target.ENEMY: return _is_hostile(caster, tgt) and not _is_covered(tgt)
		Ability.Target.ALLY: return not _is_hostile(caster, tgt)   # any friendly unit, caster included
		Ability.Target.SELF: return tgt == caster
		Ability.Target.ALL_ENEMIES: return true
		Ability.Target.ALL_ALLIES: return true
		Ability.Target.ALLY_OTHER: return not _is_hostile(caster, tgt) and tgt != caster
		Ability.Target.ALL_OTHER_ALLIES: return true
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
	var b_rank := _ability_rank(caster, ability)
	var sp_cost := _spirit_cost(caster, ability, b_rank)
	if ability.uses_per_combat > 0 and _uses_this_combat(caster, ability) >= ability.uses_per_combat:
		return "%s can only be used %d time(s) per fight" % [ability.display_name, ability.uses_per_combat]
	var hp_cost := _hp_cost(caster, ability, b_rank)
	if hp_cost > 0 and hp_cost >= caster.get_hp():
		return "%s would cost more health than %s has (%d)" % [ability.display_name, caster.unit_name, hp_cost]
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

## THE AoE FAN-OUT SET (COMBAT C4.2) — which units a cast actually lands on.
##   ALL_ENEMIES -> every LIVING unit hostile to the caster
##   ALL_ALLIES  -> every LIVING friendly, the caster INCLUDED (there is still no
##                  ally-but-not-me target class)
##   anything else -> the single unit that was clicked or retargeted.
##
## AN AoE IGNORES BACK-ROW PROTECTION, BY DESIGN. _valid_target refuses a covered
## unit for a single-target attack, and this function deliberately does NOT — area
## damage is the player's (and the AI's) answer to a formation, and the reason to
## carry one. Flip it by filtering `_is_covered(u)` out of the ALL_ENEMIES branch;
## AIContext.targets_for routes through here, so that one edit moves both sides.
##
## THE SIDE TEST HAS TO LIVE HERE. `_valid_target` answers TRUE for any unit when
## the ability is ALL_*, because it is written for the player's click path where the
## clicked unit is already on the right side. An AoE aimed by the AI would otherwise
## sweep its own line. Returns [] when nothing is left to hit, which the caller
## treats as "the cast does not happen" — no spirit, no cooldown, no action point.
func _affected_targets(caster: BattleCharacter, ability: Ability, tgt: BattleCharacter) -> Array:
	if caster == null or ability == null:
		return []
	var want_hostile := ability.target == Ability.Target.ALL_ENEMIES
	var others_only := ability.target == Ability.Target.ALL_OTHER_ALLIES
	if not want_hostile and ability.target != Ability.Target.ALL_ALLIES and not others_only:
		return [tgt] if tgt != null else []
	var out: Array = []
	for u in _units:
		if u == null or not u.is_alive():
			continue
		if others_only and u == caster:
			continue
		if _is_hostile(caster, u) == want_hostile:
			out.append(u)
	return out

## ALL THE HITS OF ONE ATTACK (Ability.hit_count). A single-hit attack — every
## ability shipped before this existed — goes straight to _resolve_attack_on and
## comes back unchanged, so this is a pass-through for the whole existing roster.
##
## For a MULTI-HIT, each strike is its own _resolve_attack_on: its own dodge roll,
## its own crit roll, its own applies_buff roll (Flail's 50% On Fire rolls three
## times), its own shield absorption. What the hits SHARE is decided up here:
##   - damage_scale: 1/N for a split ability, so the TOTAL matches one hit (Flurry)
##   - the caster's one-time spirit_gain rides only on the very first strike
##   - the target: the same unit every hit, or a fresh random legal hostile per hit
##     for HitRetarget.RANDOM (Spray)
##
## A SAME-TARGET attack stops when its target dies. The remaining strikes are LOST,
## not redirected — overkill wastes a multi-hit, which is part of what makes it a
## different tool from one big swing. A RANDOM-TARGET attack picks again instead,
## and stops only when nothing legal is left standing.
##
## All strikes resolve in the same frame. rev33's damage-number bursts
## (BURST_WINDOW_MS) fan simultaneous numbers on one unit left / centre / right,
## which is the presentation — _use_ability stays synchronous by design.
##
## Returns { any_hit: bool, detail: String } — one combat-log fragment for the lot.
func _resolve_hits_on(caster: BattleCharacter, ability: Ability, tgt: BattleCharacter, rank: int, scale_bonus: Dictionary, include_caster_gain: bool = true) -> Dictionary:
	var n := ability.hit_count_at(rank)
	var retarget := ability.retargets_each_hit()
	if n <= 1 and not retarget:
		var one := _resolve_attack_on(caster, ability, tgt, rank, scale_bonus, include_caster_gain)
		return {"any_hit": not bool(one.get("dodged", false)), "detail": str(one.get("detail", ""))}

	var scale := ability.hit_damage_scale(rank)
	var attempted := 0
	var dodged := 0
	var crits := 0
	var total := 0
	var struck: Array = []
	for i in n:
		# A reflect can kill the caster mid-flurry; the fight can end on hit two.
		if _battle_over or caster == null or not caster.is_alive():
			break
		var t: BattleCharacter = _random_legal_target(caster, ability) if retarget else tgt
		if t == null or t.body == null or not t.is_alive():
			break
		var r := _resolve_attack_on(caster, ability, t, rank, scale_bonus, include_caster_gain and i == 0, scale)
		attempted += 1
		if bool(r.get("dodged", false)):
			dodged += 1
		else:
			total += int(r.get("damage", 0))
			if bool(r.get("is_crit", false)):
				crits += 1
		if not struck.has(t):
			struck.append(t)

	# ONE log fragment for the whole attack rather than one per strike.
	var names := PackedStringArray()
	for x in struck:
		names.append((x as BattleCharacter).unit_name)
	var extras := PackedStringArray()
	if dodged > 0:
		extras.append("%d dodged" % dodged)
	if crits > 0:
		extras.append("%d crit" % crits)
	var tail := (" (%s)" % ", ".join(extras)) if not extras.is_empty() else ""
	var who := ", ".join(names) if not names.is_empty() else "nobody"
	return {
		"any_hit": attempted > dodged,
		"detail": "→ %s · %d hits · %d %s%s" % [who, attempted, total, ability.element_key(), tail],
	}

## A random LEGAL target for one strike of a HitRetarget.RANDOM attack (Spray).
## "Legal" is _valid_target, so back-row protection applies to every shot — a
## scatter-shot is not an AoE and does not reach a covered unit. Null when nothing
## legal is left standing.
func _random_legal_target(caster: BattleCharacter, ability: Ability) -> BattleCharacter:
	var pool: Array = []
	for u in _units:
		if u != null and u.is_alive() and _valid_target(caster, ability, u):
			pool.append(u)
	if pool.is_empty():
		return null
	return pool[randi() % pool.size()]

## ONE ATTACK, AGAINST ONE UNIT. Everything between "this attack is aimed at that
## unit" and "the numbers are on screen": the dodge roll, the damage, Snap's
## per-debuff multiply, the strike itself, the second element, the rider debuff, the
## per-target spirit riders, Shatter, and the attacker's on-hit riders.
##
## EXTRACTED FROM _use_ability's ATTACK branch so it can run MORE THAN ONCE per cast
## — once per affected unit for an AoE today, and once per hit for a multi-hit
## ability later. Everything that is per-CAST rather than per-TARGET stays in
## _use_ability: the spirit cost, the slot cooldown, the action-point debit, attack
## charges, applies_buff_self and the one combat-log line. That split IS the point of
## the extraction; do not move any of them in here.
##
## `scale_bonus` is the caster's upgrade-node scaling (a PLAYER-only skill-tree
## concept), computed once per cast and passed down.
## `include_caster_gain` carries the ability's one-time spirit_gain, which belongs to
## the CAST — only the first unit in a fan-out is given it.
##
## `damage_scale` is the MULTI-HIT split (Ability.hit_damage_scale): 1/N for a split
## multi-hit, 1.0 otherwise. It divides the ability's OWN damage terms — the main hit,
## the second element, the %-of-max-HP term — and nothing else. Every rider fires at
## full value on every hit (see Ability.hit_split).
##
## Returns { dodged: bool, damage: int, is_crit: bool, element: String, detail: String }.
func _resolve_attack_on(caster: BattleCharacter, ability: Ability, tgt: BattleCharacter, rank: int, scale_bonus: Dictionary, include_caster_gain: bool = true, damage_scale: float = 1.0) -> Dictionary:
	var atk: CharacterBase = caster.body
	# Cryonecrosis: bonus pierce per debuff of the named element ON THIS UNIT, so in
	# a fan-out it is re-read per target rather than sampled once from the first.
	var extra_pierce := 0.0
	var pp_elem := String(ability.pierce_per_debuff_element)
	if pp_elem != "":
		extra_pierce = ability.pierce_per_debuff_at(rank) \
			* float(CombatBuffs.count_debuffs_of_element(tgt.body, pp_elem))
	# FLAT PIERCE: unconditional, and SUMMED with the per-debuff term rather than
	# replacing it — an ability may legitimately carry both. CombatMath skips the
	# whole mitigation stage for a TRUE-element hit, so this is inert there.
	extra_pierce += ability.pierce_flat_at(rank)
	var hit := CombatMath.resolve(atk, tgt.body, ability, rank, -1, scale_bonus, extra_pierce, _extra_crit(caster, ability, tgt))
	# ANTI-FRUSTRATION: count this dodge (or reset on a hit) BEFORE anything else
	# happens — the NEXT attack against this unit reads the streak.
	_note_dodge_outcome(caster, tgt, bool(hit.get("dodged", false)))
	# DODGE (CombatMath stage 0): this unit evaded on the alacrity gap. NOTHING the
	# attack carries happens to IT — no damage, no rider debuff, no spirit steal, no
	# Shatter, no on-hit rider. In a fan-out every other unit still rolls its own.
	if bool(hit.get("dodged", false)):
		tgt.float_dodge()
		_dbg("[combat] %s DODGED %s [chance %.0f%%]" % [
			tgt.unit_name, ability.display_name, float(hit.get("dodge_chance", 0.0))])
		return {
			"dodged": true, "damage": 0, "is_crit": false,
			"element": str(hit.get("element", ability.element_key())),
			"detail": "→ %s · DODGED" % tgt.unit_name,
		}

	var dmg := int(hit["damage"])
	# Snap: deal the per-hit value once PER matching debuff element on the target
	# (0 matching debuffs => 0 damage).
	var per_elem := String(ability.damage_per_debuff_element)
	if per_elem != "":
		dmg *= CombatBuffs.count_debuffs_of_element(tgt.body, per_elem)
	# MULTI-HIT SPLIT. Applied after mitigation, which is equivalent (mitigation is
	# multiplicative) and keeps the dodge/crit roll above untouched. A LANDED hit
	# never rounds down to zero — three strikes of a 2-damage attack should read as
	# three hits, not as a miss — but a Snap with nothing to snap stays at zero.
	if damage_scale != 1.0 and dmg > 0:
		dmg = maxi(1, int(round(float(dmg) * damage_scale)))
	# NEPHILIC OUTGOING MULTIPLIERS (Brimming, Ire, Epiphany, Stoker, the Crash
	# riders). Post-mitigation, like the split above; the ability's own second
	# element and %-max-HP terms get the same factor below.
	var out_mult := _outgoing_mult(caster, ability, tgt)
	if out_mult != 1.0 and dmg > 0:
		dmg = maxi(1, int(round(float(dmg) * out_mult)))
	# INTERCEDE: part of a hit aimed at a guarded unit lands on its guardian instead.
	dmg = _apply_intercede(tgt, dmg, str(hit["element"]))
	# Pass the ACTUAL attacker as the source so the target's "when struck" reactions
	# (thorns, ...) can hit back — plus the hidden delivery class, since those
	# reactions answer ATTACKS only and stay silent for a spell.
	tgt.take_damage(dmg, str(hit["element"]), bool(hit["is_crit"]), caster, not ability.skip_ice_amp, ability.is_attack_delivery())
	caster.damage_dealt += float(dmg)
	# SECOND ELEMENT: an attack that is two damage types at once (a claw AND a cold)
	# lands its other half here, as a real hit of the other element so the target's
	# resistance to IT is what answers it.
	_apply_bonus_damage(caster, ability, tgt, rank, damage_scale * out_mult)
	# ...and a %-OF-MAX-HP term, if it carries one (Disembowel). Same contract as
	# the second element: a real hit of its own element, no source, never a crit.
	_apply_pct_max_hp_damage(caster, ability, tgt, rank, damage_scale * out_mult)
	# NEPHILIC hit riders: Excise, and Crash's Turning Sword + Fall of the Watchers.
	_apply_nephilic_hit_riders(caster, ability, tgt, rank, dmg, str(hit["element"]), out_mult)
	# an attack may also drop a buff/debuff on the target (transient effect)
	_maybe_apply_buff(caster, ability, tgt, rank)
	# ...and apply the one-time spirit riders. The caster's own GAIN is per cast, so
	# it rides only on the first unit of a fan; steal and grant are per target.
	_apply_spirit_effects(caster, ability, tgt, rank, include_caster_gain)
	# ...and Shatter: consume an ice debuff for a stun + %-max-HP bonus hit.
	_apply_shatter(caster, ability, tgt, rank)
	# ...and any ON-HIT-APPLY buffs the attacker carries (Wraith Form drops Rime Skin
	# on whatever it strikes).
	if tgt.is_alive():
		caster.damage_dealt += float(CombatBuffs.fire_on_hit(caster.body, tgt))
	if not tgt.is_alive():
		_cast_ctx["killed"] = true
	var crit_tag := " (CRIT x%.2f)" % float(hit["crit_mult"]) if hit["is_crit"] else ""
	_dbg("[combat] %s hits %s for %d %s damage%s [chance %.0f%%]" % [
		ability.display_name, tgt.unit_name, dmg, ability.element_key(), crit_tag, float(hit["crit_chance"])])
	return {
		"dodged": false, "damage": dmg, "is_crit": bool(hit["is_crit"]),
		"element": str(hit["element"]),
		"detail": "→ %s · %d %s%s" % [tgt.unit_name, dmg, ability.element_key(), crit_tag],
	}

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
	var sp_cost := _spirit_cost(caster, ability, rank)
	if caster.get_spirit() < sp_cost:
		_dbg("[combat] not enough spirit for %s (need %d, have %d)" % [ability.display_name, sp_cost, caster.get_spirit()])
		return

	# AoE FAN-OUT (COMBAT C4.2). An ALL_ENEMIES / ALL_ALLIES ability resolves its
	# EFFECT once per affected unit. Everything that costs the CASTER something —
	# the spirit, the slot cooldown, the action point, its own spirit_gain, its
	# attack charges, applies_buff_self and the single combat-log line — happens
	# ONCE, below the loop. A single-target ability yields a one-element set and
	# behaves exactly as it did before this landed.
	var targets := _affected_targets(caster, ability, tgt)
	if targets.is_empty():
		return

	# NEPHILIC CAST CONTEXT. Spirit is read BEFORE anything this cast does (Brimming
	# asks "was the bar full when you swung"); the HP cost is paid up front so a heal
	# that scales off it (Bloodletting) can read it.
	_cast_ctx = {"spirit_at_cast": caster.get_spirit(), "hp_paid": 0, "killed": false, "rebuke": 0}
	if String(ability.id) == CRASH_ID:
		caster.fight_flags["crash_count"] = int(caster.fight_flags.get("crash_count", 0)) + 1
		_cast_ctx["rebuke"] = int(caster.fight_flags.get("rebuke", 0))
		caster.fight_flags["rebuke"] = 0
	var hp_cost := _hp_cost(caster, ability, rank)
	if hp_cost > 0:
		_cast_ctx["hp_paid"] = caster.pay_hp(hp_cost)

	var acted := false
	## What this use actually DID, for the combat log's single line — one fragment
	## per affected unit, joined at the bottom. The buff riders append to
	## _last_buff_note, which is folded in once every rider has had its say.
	var details := PackedStringArray()
	_last_buff_note = ""

	# Upgrade-node scaling bonuses are a PLAYER-only concept (they come from the
	# skill tree); an enemy casting the same ability gets the plain formula. Read
	# ONCE per cast rather than once per affected unit.
	var scale_bonus: Dictionary = {}
	if ability.kind == Ability.Kind.ATTACK and caster == _player:
		var ch_up := get_node_or_null("/root/Character")
		if ch_up and ch_up.has_method("ability_scaling_bonus"):
			scale_bonus = ch_up.ability_scaling_bonus(String(ability.id))

	## Did any hit of an ATTACK actually land? Attack charges are spent per CAST,
	## not per target, so a cast that everyone dodged spends none.
	var any_hit := false
	## The caster's own one-time spirit_gain is a per-CAST rider, so only the FIRST
	## affected unit carries it; the steal and the grant stay per target.
	var first := true

	for t in targets:
		# A thorns / High Voltage reflect can kill the caster in the middle of its
		# own fan, and an earlier iteration can kill a unit a later one would have
		# struck. Neither should keep swinging.
		if _battle_over or caster == null or not caster.is_alive():
			break
		var u: BattleCharacter = t
		if u == null or u.body == null or not u.is_alive():
			continue
		match ability.kind:
			Ability.Kind.ATTACK:
				# ONE ATTACK AGAINST THIS UNIT — which may be several strikes. The
				# fan-out is OUTSIDE the hit loop on purpose: an AoE multi-hit is
				# "N hits on each of M units", never N hits scattered across them.
				var res := _resolve_hits_on(caster, ability, u, rank, scale_bonus, first)
				if bool(res.get("any_hit", false)):
					any_hit = true
				details.append(str(res.get("detail", "")))
				acted = true

			Ability.Kind.HEAL:
				var hbody: CharacterBase = caster.body
				# DEALT heal_power: the caster's heal_power (%) increases the healing it deals.
				# The target's RECEIVED heal_power is applied inside u.heal().
				var raw_heal := ability.compute_heal(hbody.effective_stats(), rank)
				# SECOND WIND: more healing the more of the TARGET's health is missing,
				# full bonus at 30% HP.
				var miss_b := ability.heal_missing_hp_bonus_at(rank)
				if miss_b > 0.0:
					var frac := float(u.get_hp()) / float(maxi(1, u.get_max_hp()))
					raw_heal *= 1.0 + miss_b * clampf((1.0 - frac) / 0.7, 0.0, 1.0)
				# BLOODLETTING: a multiple of the HP the caster just paid.
				raw_heal += ability.heal_from_hp_paid_at(rank) * float(_cast_ctx.get("hp_paid", 0))
				var heal_amt := int(round(raw_heal * _heal_power_dealt(hbody)))
				var restored := u.heal(heal_amt)
				details.append("→ %s · +%d hp" % [u.unit_name, restored])
				_dbg("[combat] %s heals %s for %d." % [ability.display_name, u.unit_name, restored])
				acted = true

			Ability.Kind.SHIELD:
				var sbody: CharacterBase = caster.body
				# DEALT shield_power: the caster's shield_power (%) increases the shield it
				# grants. The target's RECEIVED shield_power is applied inside u.gain_shield().
				var shield_amt := int(round(ability.compute_shield(sbody.effective_stats(), rank) * _shield_power_dealt(sbody)))
				if shield_amt > 0:
					u.gain_shield({
						"id": String(ability.id),
						"source": ability.display_name,
						"element": ability.element_key(),
						"amount": shield_amt,
						"decay": ability.shield_decay_spec(),
					})
					details.append("→ %s · +%d shield" % [u.unit_name, shield_amt])
					_dbg("[combat] %s shields %s for %d." % [ability.display_name, u.unit_name, shield_amt])
				else:
					details.append("→ %s · no shield (0)" % u.unit_name)
				acted = true

			Ability.Kind.BUFF, Ability.Kind.DEBUFF:
				# NEPHILIC riders that need no buff: Catalyze's extension, Ablution's
				# cleanse, Tithe's shield. They count as the cast having acted.
				var special := _apply_nephilic_riders(caster, ability, u, rank)
				if _maybe_apply_buff(caster, ability, u, rank):
					# A BUFF may also carry the one-time spirit gain/steal rider (Energized
					# Form gains 75 Spirit on top of its buff). Harmless for every buff that
					# sets neither — has_spirit_effect() gates it.
					_apply_spirit_effects(caster, ability, u, rank, first)
					# NB _maybe_apply_buff prints the outcome itself now (applied / RESISTED /
					# empowered by Disdain), and returns true for BOTH a landed and a resisted
					# debuff — a resisted cast still spends spirit, AP and cooldown.
					details.append("→ %s" % u.unit_name)
					acted = true
				elif ability.has_spirit_effect(rank):
					# A BUFF-KIND ABILITY WHOSE WHOLE PAYLOAD IS SPIRIT. `applies_buff` is
					# blank and that is not an authoring error — Haunted Choir refuels its
					# caster and its target and applies nothing. Before spirit_grant existed
					# no such ability could exist, so this branch fell through to "no buff to
					# apply", left `acted` false, and silently refunded the action point,
					# which would have let the AI pick it forever.
					_apply_spirit_effects(caster, ability, u, rank, first)
					details.append("→ %s" % u.unit_name)
					acted = true
				elif special:
					details.append("→ %s" % u.unit_name)
					acted = true
				else:
					_dbg("[combat] %s has no buff to apply (applies_buff is blank / unknown)." % ability.display_name)

			_:
				details.append("→ %s · kind %d not implemented" % [u.unit_name, ability.kind])
				_dbg("[combat] %s used on %s (kind %d not yet implemented)" % [ability.display_name, u.unit_name, ability.kind])

		first = false

	# CHARGES: one CAST is one of "the next N attacks", however many units it
	# touched. Spent outside the per-target loop and outside the is_alive gate on
	# purpose — a killing blow is still one of your swings.
	if any_hit and caster != null and caster.body != null:
		if CombatBuffs.spend_attack_charges(caster.body):
			caster.refresh_buffs()

	var detail := "  ".join(details)

	if not acted:
		return
	# THE AI'S ONE PIECE OF MEMORY BETWEEN DECISIONS: what this unit last resolved.
	# AITurn reads it to honour an ability's `ai_follow_up` ("after Riot Shield,
	# always Shield Bash"). Written for EVERY caster, player included, because it
	# costs nothing and a future ally routine will want the same hook.
	caster.last_ability_id = String(ability.id)
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
	if ability.uses_per_combat > 0:
		var uk := "uses_%s" % String(ability.id)
		caster.fight_flags[uk] = int(caster.fight_flags.get(uk, 0)) + 1
	if String(ability.id) == CRASH_ID:
		_after_crash(caster, ability, targets, rank, scale_bonus, sp_cost)
	var cd := ability.cooldown_at(rank)
	if cd > 0:
		# Cool down THIS slot only, on THIS caster — another copy of the same ability in
		# a different slot keeps its own independent cooldown. A slot of -1 (an ability
		# used from no slot at all) simply doesn't cool down.
		caster.start_cooldown(slot, cd)
		# §1.16: freeze it while what this cast applied still stands. Swept right
		# away below, so a cast whose buff never landed is released on the spot.
		if ability.cooldown_while_applied:
			caster.hold_cooldown(slot, _hold_key(caster, ability))
	_sweep_cooldown_holds()
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

## ANTI-FRUSTRATION bookkeeping (CombatDodge.anti_frustration_mult). Every attack the
## PLAYER'S SIDE throws at `tgt` either lengthens its dodge streak (a dodge) or resets
## it (a hit). The streak is mirrored onto the body as metadata because the dodge roll
## lives in CombatMath, which only ever sees bodies. Enemy attacks never feed it — the
## mechanic exists for the player's frustration, not the AI's.
func _note_dodge_outcome(caster: BattleCharacter, tgt: BattleCharacter, dodged: bool) -> void:
	if caster == null or tgt == null or tgt.body == null:
		return
	if caster.team == TEAM_ENEMY:
		return
	if dodged:
		tgt.dodge_streak += 1
	else:
		tgt.dodge_streak = 0
	tgt.body.set_meta(CombatDodge.STREAK_META, tgt.dodge_streak)

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
	# GENERIC per-rank families (Nephilic, 2026-09-24): "<id>_<rank>" when the
	# library knows it — no match line needed for a new family.
	if bid != "":
		var ranked := "%s_%d" % [bid, rank]
		if BuffLibrary.has(ranked):
			return ranked
	return bid

## Apply the ability's buff (if any) to `tgt`, cast by `caster`. Returns true if a buff
## was applied. The caster matters twice over: BuffLibrary scales some entries off the
## caster's stats, and try_apply rolls the caster's Disdain against the target.
func _maybe_apply_buff(caster: BattleCharacter, ability: Ability, tgt: BattleCharacter, rank: int = 1) -> bool:
	var bid := _rank_clone_id(String(ability.applies_buff), rank)
	if bid == "":
		return false
	# PESTILENCE: N independent instances per cast.
	var n := ability.applies_buff_count_at(rank)
	var any := false
	for i in n:
		if _apply_buff_instance(caster, ability, tgt, rank, bid, true):
			any = true
		if tgt == null or not tgt.is_alive():
			break
	# WORMWOOD: a second entry beside the first (the resistance shred).
	var extra := _rank_clone_id(String(ability.applies_buff_extra), rank)
	if extra != "" and tgt != null and tgt.is_alive():
		_apply_buff_instance(caster, ability, tgt, rank, extra, false)
	return any

## ONE application of buff `bid` from `ability` onto `tgt` (the body of what
## _maybe_apply_buff did before Pestilence made it loop). `use_ability_duration`
## applies Ability.applies_buff_duration (the extra entry keeps its own length).
func _apply_buff_instance(caster: BattleCharacter, ability: Ability, tgt: BattleCharacter, rank: int, bid: String, use_ability_duration: bool) -> bool:
	var caster_body: CharacterBase = caster.body if caster else null
	var entry := BuffLibrary.build(bid, caster_body, tgt.body)
	if entry.is_empty():
		return false
	if use_ability_duration:
		var dur := ability.applies_buff_duration_at(rank)
		if dur > 0:
			entry["duration"] = dur
	_nephilic_shape_entry(caster, entry)
	# APPLY CHANCE. Does this application even get ATTEMPTED? Rolled BEFORE
	# CombatResist, so a 25% rider means three casts in four never reach the
	# Magnificence-vs-Disdain roll at all, and the two chances MULTIPLY.
	#
	# Rolled AFTER the build so the contract on the return value holds: `false` means
	# "this ability names no buff, or names one that does not exist" — an authoring
	# error the caller reports — whereas a failed proc is a real, resolved use and
	# returns TRUE, spending spirit, the action point and the cooldown exactly as a
	# resisted debuff does.
	var chance := ability.apply_chance_at(rank)
	if chance < 1.0 and randf() >= chance:
		# A failed proc floats RESIST, like a resisted debuff (dev call, 2026-09-25),
		# for every caster. The log keeps the distinction.
		tgt.float_resist()
		_note_buff("%s did not proc" % bid)
		_dbg("[combat] %s did not proc on %s [%.0f%% chance]" % [bid, tgt.unit_name, chance * 100.0])
		return true
	# COOLDOWN HOLD (§1.16): stamp the entry with this cast's hold key, so the sweep
	# can tell whether anything this ability applied is still standing. A string, not
	# a unit reference — an applied instance stays disconnected from its caster.
	if ability.cooldown_while_applied and caster != null:
		entry["cooldown_hold"] = _hold_key(caster, ability)
	# TOXIC LANDS EASILY (FUTURE_PLANS §2a): an AoE cast earns the larger Disdain
	# bonus in CombatResist.resist_chance.
	if ability.is_area_target():
		entry["from_aoe"] = true
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
		_dbg("[combat] %s RESISTED %s [chance %.0f%%]" % [tgt.unit_name, bid, float(rep["chance"])])
		tgt.refresh_buffs()
		return true
	var landed := "+%s" % bid
	if float(rep["potency"]) > 1.0 or int(rep["extra_turns"]) > 0:
		# Surplus Disdain amplified this debuff — say so on screen, not just in the log.
		# The violet float reports what was gained in the moment; the BuffBar chip
		# carries a lasting marker (gold under-cap + a line in its hover card).
		tgt.float_empowered(float(rep["potency"]), int(rep["extra_turns"]))
		landed += " (empowered)"
		_dbg("[combat] %s empowered by Disdain: potency x%.2f, +%d turn(s) [overpower %.2f]" % [
			bid, float(rep["potency"]), int(rep["extra_turns"]), float(rep["overpower"])])
	_note_buff(landed)
	_dbg("[combat] %s applied %s to %s." % [ability.display_name, bid, tgt.unit_name])
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
	_nephilic_shape_entry(caster, entry)
	CombatBuffs.apply(caster.body, entry)
	caster.refresh_bar()      # a max-HP / max-Spirit buff can move the ceilings
	caster.refresh_buffs()
	_note_buff("+%s (self)" % bid)
	_dbg("[combat] %s buffs %s with %s." % [ability.display_name, caster.unit_name, bid])
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
func _apply_spirit_effects(caster: BattleCharacter, ability: Ability, tgt: BattleCharacter, rank: int, include_caster_gain: bool = true) -> void:
	if ability == null or not ability.has_spirit_effect(rank):
		return
	# THE CASTER'S OWN GAIN IS PER CAST, NOT PER TARGET (COMBAT C4.2). An AoE calls
	# this once per affected unit — the STEAL and the GRANT are genuinely per target
	# — so only the first of them carries the gain. Without this a four-target Wail
	# would refund its caster four times over.
	var gain := ability.spirit_gain_at(rank) if include_caster_gain else 0
	# LEAD riders: Growth's +spirit, and Stand Firm's one-shot "+25 on your next Lead".
	if include_caster_gain and caster != null and String(ability.id) == LEAD_ID:
		gain += int(CombatPerks.value(caster.body, "lead_spirit", "amount"))
		for e in CombatBuffs.entries_with(caster.body, "lead_spirit_bonus"):
			gain += int(e["lead_spirit_bonus"])
			CombatBuffs.remove_entry(caster.body, e)
			caster.refresh_buffs()
	if gain != 0 and caster != null:
		var got := caster.change_spirit(gain)
		_dbg("[combat] %s gains %d spirit from %s." % [caster.unit_name, got, ability.display_name])
	var steal := ability.spirit_steal_at(rank)
	if steal != 0 and tgt != null:
		var lost := tgt.change_spirit(-steal)
		_dbg("[combat] %s loses %d spirit to %s." % [tgt.unit_name, -lost, ability.display_name])
	# GRANT — spirit given TO the target. Applied AFTER the caster's own gain, for the
	# same reason the gain precedes the steal: a caster running an overflow_shield
	# converts its own over-cap remainder first, before it starts handing spirit out.
	var grant := ability.spirit_grant_at(rank)
	if grant != 0 and tgt != null:
		var given := tgt.change_spirit(grant)
		_dbg("[combat] %s grants %s %d spirit." % [ability.display_name, tgt.unit_name, given])

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
func _apply_bonus_damage(caster: BattleCharacter, ability: Ability, tgt: BattleCharacter, rank: int, damage_scale: float = 1.0) -> void:
	if ability == null or not ability.has_bonus_damage():
		return
	if tgt == null or tgt.body == null or not tgt.is_alive():
		return
	var caster_body: CharacterBase = caster.body if caster else null
	if caster_body == null:
		return
	var elem := String(ability.bonus_damage_element)
	# damage_scale is the multi-hit split — the second element is part of the
	# ability's own output, so a split multi-hit divides it like the main hit.
	var raw := ability.compute_bonus_damage(caster_body.effective_stats(), rank) * damage_scale
	if raw <= 0.0:
		return
	var dmg := CombatMath.resolve_flat(caster_body, tgt.body, raw, elem, 0.0, true, CombatMath.ability_amp(caster_body, ability))
	if dmg <= 0:
		return
	tgt.take_damage(dmg, elem, false)
	caster.damage_dealt += float(dmg)
	_dbg("[combat] %s also deals %d %s damage to %s (second element)." % [
		ability.display_name, dmg, elem, tgt.unit_name])


## %-OF-MAX-HP DAMAGE: an extra hit worth a fraction of the TARGET's max health,
## dealt after the attack's own damage. The same shape as Shatter's bonus hit, but
## with no consume-a-debuff gate in front of it — an ability that simply scales off
## how big the target is (Disembowel) needs no setup to do it.
##
## Routed through CombatMath.resolve_flat, so the target's resistance to the hit's
## element, the caster's pierce and amp for it, damage_dealt_mult and
## damage_taken_mult all apply. Dealt with NO source, so it triggers no on-struck
## reaction and cannot recurse, and it is never a crit — the same contract as the
## second element and Shatter's bonus.
##
## NB IT DOES NOT TAKE THE HOARFROST AMP. Shatter samples and consumes the amp
## itself because its own gate can eat the entry carrying it; this hit has no gate,
## so an ICE %-max-HP term riding on a sourced ice attack would double-dip against an
## amp take_damage has already spent. If an ice one is ever authored, fix it here
## rather than in take_damage.
func _apply_pct_max_hp_damage(caster: BattleCharacter, ability: Ability, tgt: BattleCharacter, rank: int, damage_scale: float = 1.0) -> void:
	if ability == null or not ability.has_pct_max_hp_damage():
		return
	if tgt == null or tgt.body == null or not tgt.is_alive():
		return
	var pct := ability.pct_max_hp_damage_at(rank)
	if pct <= 0.0:
		return
	var caster_body: CharacterBase = caster.body if caster else null
	var elem := ability.pct_max_hp_element_key()
	# damage_scale: the multi-hit split, exactly as for the second element.
	var raw := maxf(0.0, float(tgt.get_max_hp()) * pct) * damage_scale
	var dmg := CombatMath.resolve_flat(caster_body, tgt.body, raw, elem, 0.0, true, CombatMath.ability_amp(caster_body, ability))
	if dmg <= 0:
		return
	tgt.take_damage(dmg, elem, false)
	if caster:
		caster.damage_dealt += float(dmg)
	_dbg("[combat] %s also deals %d %s damage to %s (%.0f%% of max HP)." % [
		ability.display_name, dmg, elem, tgt.unit_name, pct * 100.0])


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
		var bonus := CombatMath.resolve_flat(caster_body, tgt.body, raw, s_elem, 0.0, true, CombatMath.ability_amp(caster_body, ability))
		# Hoarfrost is applied HERE rather than inside take_damage: this hit is dealt with
		# no source, and take_damage only amps a SOURCED ice hit. `ice_amp` was sampled
		# above the gate, so the boost lands even when the gate ate the hoarfrost entry
		# itself; consume whatever ice-amp debuffs are still on the target either way.
		if bonus > 0 and ice_amp > 0.0:
			bonus = int(round(maxf(0.0, float(bonus) * (1.0 + ice_amp))))
			CombatBuffs.consume_ice_amp(tgt.body)
		if bonus > 0:
			tgt.take_damage(bonus, s_elem, false)
			if caster:
				caster.damage_dealt += float(bonus)
	tgt.refresh_bar()
	tgt.refresh_buffs()
	_dbg("[combat] %s shatters a %s debuff on %s." % [ability.display_name, elem, tgt.unit_name])

# ============================================================================
# THE NEPHILIC KIT (2026-09-24) — perks, costs and hooks
# ============================================================================
## The spirit a cast costs, after overrides (Apotheosis makes Crash free).
func _spirit_cost(caster: BattleCharacter, ability: Ability, rank: int) -> int:
	var c := ability.spirit_cost_at(rank)
	if c > 0 and caster != null and caster.body != null and String(ability.id) == CRASH_ID \
			and not CombatBuffs.entries_with(caster.body, "crash_free").is_empty():
		return 0
	return c

## The HP a cast costs its caster (a fraction of max HP and/or of current HP).
func _hp_cost(caster: BattleCharacter, ability: Ability, rank: int) -> int:
	if caster == null or ability == null or not ability.has_hp_cost():
		return 0
	var c := ability.hp_cost_pct_max_at(rank) * float(caster.get_max_hp()) \
		+ ability.hp_cost_pct_current * float(caster.get_hp())
	return maxi(0, int(round(c)))

func _uses_this_combat(caster: BattleCharacter, ability: Ability) -> int:
	return int(caster.fight_flags.get("uses_%s" % String(ability.id), 0))

## Fold the player's perks into the body meta, then grant the fight-start ones
## (Grit's shield, Hone's level-scaled amp).
func _setup_player_perks() -> void:
	if _player == null or _player.body == null:
		return
	var ch := get_node_or_null("/root/Character")
	if ch == null:
		return
	var perks := {}
	if ch.has_method("get_equipped"):
		for id in ch.get_equipped():
			var ab := _get_ability(str(id))
			if ab == null or String(ab.perk) == "" or ab.is_always_active():
				continue
			CombatPerks.merge(perks, String(ab.perk), ab.perk_at(_ability_rank(_player, ab)))
	# Always-active nodes (Growth) carry perks from the INVESTED node, never the wheel.
	if "allocations" in ch:
		for nid in ch.allocations.keys():
			var pts := int(ch.allocations[nid])
			if pts <= 0:
				continue
			var ab2 := _get_ability(str(ch.node_abilities.get(nid, nid)))
			if ab2 == null or String(ab2.perk) == "" or not ab2.is_always_active():
				continue
			CombatPerks.merge(perks, String(ab2.perk), ab2.perk_at(pts))
	CombatPerks.set_all(_player.body, perks)
	if perks.is_empty():
		return
	_dbg("[combat] player perks: %s" % str(perks.keys()))
	var body := _player.body
	# GRIT: a fight-start shield, and less damage taken while it holds.
	if perks.has("grit"):
		var amt := CombatPerks.value(body, "grit", "shield") * float(body.max_hp())
		if amt > 0.0:
			var recv := 1.0 + maxf(0.0, body.get_effective("shield_power")) / 100.0
			CombatShields.apply(body, {"id": "grit", "source": "Grit", "element": "",
				"amount": int(round(amt * recv)), "decay": {}})
		if CombatPerks.value(body, "grit", "dr") > 0.0:
			var ward := BuffLibrary.build("grit_ward", body, body)
			if not ward.is_empty():
				ward["mods"] = {"damage_taken_mult": -CombatPerks.value(body, "grit", "dr")}
				ward["per_stack"]["mods"] = ward["mods"].duplicate()
				CombatBuffs.apply(body, ward)
	# HONE: +rate amp to every element per level (1 amp = 0.01 in the engine).
	if perks.has("hone"):
		var per := CombatPerks.value(body, "hone", "rate") * float(maxi(1, body.level))
		var mods := {}
		for e in Stats.REAL_ELEMENTS:
			mods[Stats.amp_key(e)] = per
		CombatBuffs.apply(body, Buff.make({"id": "hone", "source": "Hone",
			"desc": "Hone: +%d amp to every element." % int(round(per * 100.0)),
			"kind": Buff.KIND_BUFF, "duration": -1, "stackable": false, "visible": false,
			"mods": mods}))
		# CRASH "instead" runs at crash_rate: a real PER-ABILITY amp (CombatMath.ability_amp)
		# of (crash_rate - rate) x level stacked on the every-element amp above, so Crash's
		# Hone total is exactly crash_rate x level (+50 at L50) on every term of the hit.
		var lvl := float(maxi(1, body.level))
		var extra := (CombatPerks.value(body, "hone", "crash_rate") - CombatPerks.value(body, "hone", "rate")) * lvl
		var aa: Dictionary = body.get_meta("ability_amp", {})
		aa[CRASH_ID] = extra      # SET, not added: a re-run perk setup must not stack it
		body.set_meta("ability_amp", aa)

## Shape an entry the player is about to apply: Constellation (+turns, +potency on
## buffs Sonny gives), Nimbus (+1 turn of Apotheosis), Intercede's guardian stamp.
func _nephilic_shape_entry(caster: BattleCharacter, entry: Dictionary) -> void:
	if caster == null or caster.body == null or entry.is_empty():
		return
	var cb := caster.body
	if Buff.is_buff(entry) and CombatPerks.has(cb, "constellation"):
		var d := int(entry.get("duration", -1))
		if d > 0:
			entry["duration"] = d + int(CombatPerks.value(cb, "constellation", "turns"))
		var pot := CombatPerks.value(cb, "constellation", "potency")
		if pot > 0.0:
			Buff.scale_potency(entry, 1.0 + pot)
	if str(entry.get("id", "")) == "apotheosis" and CombatPerks.has(cb, "nimbus"):
		entry["duration"] = int(entry.get("duration", 3)) + 1
	if float(entry.get("redirect_pct", 0.0)) > 0.0:
		entry["guardian_uid"] = caster.get_instance_id()

## Riders a BUFF/DEBUFF cast carries besides its buff. True if any did something.
func _apply_nephilic_riders(caster: BattleCharacter, ability: Ability, u: BattleCharacter, rank: int) -> bool:
	var did := false
	# CATALYZE: every poison already on the target gains N turns.
	if String(ability.extend_debuff_id) != "":
		var n := CombatBuffs.extend_debuffs_of_id(u.body, String(ability.extend_debuff_id), ability.extend_turns_at(rank))
		_note_buff("%d %s extended" % [n, String(ability.extend_debuff_id)])
		u.refresh_buffs()
		did = true
	# ABLUTION: cleanse N debuffs (oldest first; self-paid costs are exempt).
	var cn := ability.cleanse_count_at(rank)
	if cn > 0:
		var gone := CombatBuffs.cleanse(u.body, cn)
		_note_buff("cleansed %d" % gone.size())
		u.refresh_buffs()
		u.refresh_bar()
		did = true
	# TITHE: a shield worth a fraction of the CASTER's max HP.
	var sp := ability.shield_pct_caster_max_hp_at(rank)
	if sp > 0.0:
		var amt := int(round(sp * float(caster.get_max_hp()) * _shield_power_dealt(caster.body)))
		if amt > 0:
			u.gain_shield({"id": String(ability.id), "source": ability.display_name,
				"element": "", "amount": amt, "decay": {}})
		did = true
	return did

## Extra crit-chance points for this one hit (Hew; Heavy Hand's Crash crit).
func _extra_crit(caster: BattleCharacter, ability: Ability, tgt: BattleCharacter) -> float:
	var c := 0.0
	if ability.crit_chance_per_debuff != 0.0 and String(ability.bonus_per_debuff_id) != "":
		c += ability.crit_chance_per_debuff * float(CombatBuffs.count_debuffs_of_id(tgt.body, String(ability.bonus_per_debuff_id)))
	if String(ability.id) == CRASH_ID:
		c += CombatPerks.value(caster.body, "heavy_hand", "crash_crit")
	return c

## The caster-side damage multiplier for one hit of `ability` on `tgt`.
func _outgoing_mult(caster: BattleCharacter, ability: Ability, tgt: BattleCharacter) -> float:
	if caster == null or caster.body == null:
		return 1.0
	var b := caster.body
	var m := 1.0
	# BRIMMING: any ability cast while the bar was above 99.
	if CombatPerks.has(b, "brimming") and int(_cast_ctx.get("spirit_at_cast", 0)) > 99:
		m *= 1.0 + CombatPerks.value(b, "brimming", "dmg")
	# IRE: below half health.
	if CombatPerks.has(b, "ire") and caster.get_hp() * 2 < caster.get_max_hp():
		m *= 1.0 + CombatPerks.value(b, "ire", "dmg")
	# EPIPHANY: per buff it froze.
	for e in CombatBuffs.entries_with(b, "epiphany_per_buff"):
		m *= 1.0 + float(e["epiphany_per_buff"]) * float(CombatBuffs.count_visible_buffs(b, "freeze_buffs"))
	# STOKER: per instance of a debuff on the target.
	if ability.damage_bonus_per_debuff != 0.0 and String(ability.bonus_per_debuff_id) != "" and tgt != null:
		m *= 1.0 + ability.damage_bonus_per_debuff * float(CombatBuffs.count_debuffs_of_id(tgt.body, String(ability.bonus_per_debuff_id)))
	if String(ability.id) == CRASH_ID:
		# APOTHEOSIS: free Crashes hit for less.
		for e in CombatBuffs.entries_with(b, "crash_damage_mult"):
			m *= float(e["crash_damage_mult"])
			break
		# REBUKE: every stack gathered since the last Crash.
		m *= 1.0 + CombatPerks.value(b, "rebuke", "per") * float(_cast_ctx.get("rebuke", 0))
		# (HONE's Crash rate is no longer a ratio here — it is a real per-ability amp,
		# CombatMath.ability_amp, written in _setup_player_perks.)
	return m

## INTERCEDE: route redirect_pct of `dmg` to the guardian named on the target's entry.
func _apply_intercede(tgt: BattleCharacter, dmg: int, element: String) -> int:
	if dmg <= 0 or tgt == null or tgt.body == null:
		return dmg
	for e in CombatBuffs.entries_with(tgt.body, "redirect_pct"):
		var gid := int(e.get("guardian_uid", 0))
		for other in _units:
			var g: BattleCharacter = other
			if g == null or g == tgt or not g.is_alive() or g.get_instance_id() != gid:
				continue
			var part := int(round(float(dmg) * float(e["redirect_pct"])))
			if part > 0:
				g.take_damage(part, element, false, null, false, false)
				dmg -= part
			break
		break
	return maxi(0, dmg)

## After a LANDED hit: Excise's burst, and Crash's Turning Sword + Fall of the Watchers.
func _apply_nephilic_hit_riders(caster: BattleCharacter, ability: Ability, tgt: BattleCharacter, rank: int, dmg: int, element: String, out_mult: float) -> void:
	var atk := caster.body
	# EXCISE: pull instances of the debuff and deal their remaining ticks now.
	if String(ability.excise_debuff_id) != "" and tgt.is_alive():
		var total := 0
		var vuln := maxf(0.0, tgt.body.get_effective("vulnerability"))
		var pulled := CombatBuffs.take_debuffs_of_id(tgt.body, String(ability.excise_debuff_id), ability.excise_count_at(rank))
		for e in pulled:
			var ticks := maxi(0, int(e.get("duration", 0)))
			var raw := float(Buff.dot_damage(e)) * float(ticks) * vuln
			total += CombatMath.resolve_flat(null, tgt.body, raw, str(e.get("dot_element", "toxic")), Buff.dot_pierce(e))
		if total > 0:
			tgt.take_damage(total, str(ability.element_key() if pulled.is_empty() else pulled[0].get("dot_element", "toxic")), false)
			caster.damage_dealt += float(total)
		if not pulled.is_empty():
			_note_buff("excised %d" % pulled.size())
			tgt.refresh_buffs()
	if String(ability.id) != CRASH_ID:
		return
	# THE TURNING SWORD: Crash is enflamed.
	var ts := CombatPerks.value(atk, "turning_sword", "mult")
	if ts > 0.0 and tgt.is_alive():
		var fire := CombatMath.resolve_flat(atk, tgt.body, ts * atk.get_effective("vigor") * out_mult, "fire", 0.0, true, CombatMath.ability_amp(atk, ability))
		if fire > 0:
			tgt.take_damage(fire, "fire", false)
			caster.damage_dealt += float(fire)
		var burn := BuffLibrary.build("on_fire", atk, tgt.body)
		if not burn.is_empty() and tgt.is_alive():
			burn["duration"] = 5
			if not bool(CombatBuffs.try_apply(tgt.body, burn, atk)["resisted"]):
				tgt.refresh_buffs()
	# FALL OF THE WATCHERS: splash onto the units above, below and behind.
	var sp := CombatPerks.value(atk, "fall_of_the_watchers", "splash")
	if sp > 0.0 and dmg > 0:
		for n in _grid_neighbours(tgt):
			var nb: BattleCharacter = n
			var splash := maxi(1, int(round(float(dmg) * sp)))
			nb.take_damage(splash, element, false)
			caster.damage_dealt += float(splash)   # splash is CREDITED (dev call 2026-09-25)

## The living units directly above, below and behind `u` on its own side.
func _grid_neighbours(u: BattleCharacter) -> Array:
	var out: Array = []
	if u == null or u.grid_col < 0:
		return out
	for other in _units:
		var o: BattleCharacter = other
		if o == null or o == u or not o.is_alive() or o.team == TEAM_ENEMY and u.team != TEAM_ENEMY \
				or o.team != TEAM_ENEMY and u.team == TEAM_ENEMY:
			continue
		if o.grid_col == u.grid_col and absi(o.grid_row - u.grid_row) == 1:
			out.append(o)
		elif o.grid_row == u.grid_row and o.grid_col == u.grid_col - 1:
			out.append(o)
	return out

## Once per Crash cast, after its cost is paid: Follow Through's refund and Nimbus's
## echo strike.
func _after_crash(caster: BattleCharacter, ability: Ability, targets: Array, rank: int, scale_bonus: Dictionary, sp_cost: int) -> void:
	var b := caster.body
	if bool(_cast_ctx.get("killed", false)) and sp_cost > 0:
		var ft := CombatPerks.value(b, "follow_through", "pct")
		if ft > 0.0:
			caster.change_spirit(int(round(float(sp_cost) * ft)))
	if CombatPerks.has(b, "nimbus"):
		var during_apo := not CombatBuffs.entries_with(b, "crash_free").is_empty()
		if during_apo or int(caster.fight_flags.get("crash_count", 0)) % 3 == 0:
			for t in targets:
				var tu: BattleCharacter = t
				if tu != null and tu.is_alive() and caster.is_alive() and not _battle_over:
					_resolve_attack_on(caster, ability, tu, rank, scale_bonus, false, 0.5)
			_log_note("%s's Crash strikes again (Nimbus)" % caster.unit_name)

## HP LOST, any cause: Stigmata (the bearer) and Pharmaceutical (the player, off
## toxic damage an enemy takes).
func _on_unit_hp_lost(u: BattleCharacter, amount: int, element: String) -> void:
	if u == null or u.body == null or amount <= 0:
		return
	# A loaded unit that just died blanks its top-panel slot (FUTURE_PLANS §7).
	# A DOWNED one keeps it — it is getting back up.
	if not u.is_alive() and not u.downed:
		_unload_unit(u)
	var step := CombatPerks.value(u.body, "stigmata", "pct")
	if step > 0.0 and u.is_alive():
		var acc := float(u.fight_flags.get("stigmata_acc", 0.0)) + 100.0 * float(amount) / float(maxi(1, u.get_max_hp()))
		var gain := int(floor(acc / step))
		u.fight_flags["stigmata_acc"] = acc - float(gain) * step
		if gain > 0:
			u.change_spirit(gain)
	if element == "toxic" and _player != null and _player.is_alive() and _is_hostile(_player, u):
		var ph := CombatPerks.value(_player.body, "pharmaceutical", "pct")
		if ph > 0.0:
			var acc2 := float(_player.fight_flags.get("pharma_acc", 0.0)) + float(amount) * ph
			var h := int(floor(acc2))
			_player.fight_flags["pharma_acc"] = acc2 - float(h)
			if h > 0:
				_player.heal(h)

## HP PAID as a cost: Mortification feeds every ally but the payer.
func _on_unit_hp_paid(u: BattleCharacter, amount: int) -> void:
	if u == null or u.body == null:
		return
	var per := CombatPerks.value(u.body, "mortification", "per_pct")
	if per <= 0.0:
		return
	var acc := float(u.fight_flags.get("mortify_acc", 0.0)) + per * 100.0 * float(amount) / float(maxi(1, u.get_max_hp()))
	var sp := int(floor(acc))
	u.fight_flags["mortify_acc"] = acc - float(sp)
	if sp <= 0:
		return
	for other in _units:
		var o: BattleCharacter = other
		if o != null and o != u and o.is_alive() and not _is_hostile(u, o):
			o.change_spirit(sp)

## STRUCK by a sourced hit: Rebuke banks a stack for every enemy ATTACK (max 5).
func _on_unit_struck(u: BattleCharacter, source, from_attack: bool) -> void:
	if u == null or u.body == null or not from_attack or not (source is BattleCharacter):
		return
	if not _is_hostile(u, source) or not CombatPerks.has(u.body, "rebuke"):
		return
	var cap := int(CombatPerks.value(u.body, "rebuke", "max", 5.0))
	u.fight_flags["rebuke"] = mini(cap, int(u.fight_flags.get("rebuke", 0)) + 1)

## DEATH GUARD: Reprieve (the player, once per fight) and Caput Mortuum (each ally
## of the player, once per fight, paid for with twice the saved HP).
## NB Reprieve is built as "survive at 1 HP" — the spec's "revive at the start of his
## turn" would need a downed state the engine does not have yet.
func _death_guard(u: BattleCharacter) -> int:
	if u == null or u.body == null or _battle_over:
		return 0
	# REPRIEVE: once per fight the player goes DOWN instead of dying, and stands up at
	# 1 HP at the start of his next turn (_revive_downed). Replaces "survive at 1 HP".
	if u == _player and CombatPerks.has(u.body, "reprieve") and not u.fight_flags.get("reprieve_used", false):
		u.fight_flags["reprieve_used"] = true
		u.float_status("REPRIEVE", Color(0.95, 0.85, 0.45))
		_log_note("%s falls — Reprieve will raise him on his turn" % u.unit_name)
		return BattleCharacter.DOWNED
	if u.team == TEAM_ALLY and _player != null and _player.is_alive() \
			and CombatPerks.has(_player.body, "caput_mortuum") and not u.fight_flags.get("caput_used", false):
		u.fight_flags["caput_used"] = true
		var keep := maxi(1, int(round(CombatPerks.value(_player.body, "caput_mortuum", "survive") * float(u.get_max_hp()))))
		_player.pay_hp(keep * 2)
		u.float_status("CAPUT MORTUUM", Color(0.6, 0.5, 0.7))
		_log_note("%s pays for %s's life (Caput Mortuum)" % [_player.unit_name, u.unit_name])
		return keep
	return 0

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
		_wheel.set_use_state(_player.body if _player else null, _player.cooldowns if _player else {}, _wheel_spent)
	if _wheel:
		_wheel.queue_redraw()

## The wheel's once-per-combat gate: true when the player has spent `ability`'s
## uses_per_combat this fight (Apotheosis, First Sun). Same test as _use_blocked.
func _wheel_spent(ability: Ability) -> bool:
	return _player != null and ability.uses_per_combat > 0 \
		and _uses_this_combat(_player, ability) >= ability.uses_per_combat

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
	if not _player.is_alive() and not _player.downed:
		_battle_over = true
		if _wheel:
			_wheel.close()
		_log_note("DEFEAT — %s has fallen." % _player.unit_name)
		_dbg("[combat] defeat — %s has fallen." % _player.unit_name)
		_record_damage_history()
		_leave_after_defeat()

## DEFEAT EXIT, DEFERRED (bugfix 2026-09-25). _check_defeat is reached from INSIDE
## ability resolution — _use_ability, while _perform_action / the AI turn are still
## mid-coroutine. Leaving right there changed scene synchronously, pulled combat out
## of the tree, and the very next line of _perform_action (its camera-hold timer)
## crashed on a null get_tree(). Exactly like _win: the battle is already locked
## (_battle_over), let the killing blow read for a beat, then leave. Not awaited by
## the caller, so resolution unwinds normally first.
func _leave_after_defeat() -> void:
	await get_tree().create_timer(2.0).timeout
	if is_inside_tree():
		_leave_combat()

func _win() -> void:
	_battle_over = true
	if _wheel:
		_wheel.close()
	_record_damage_history()
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
	# PER-ENEMY BOUNTIES (§1.19). If ANY enemy in this fight declares what it is
	# worth, the fight's money and xp become the SUM over its enemies rather than the
	# fight-level roll — which is the only way a mixed composition can pay out
	# honestly. If none declares one, the rolled table above stands untouched, so
	# every fight authored before this is unchanged. Items come from the table either
	# way; they were never per-enemy.
	#
	# Counted from _units, so it is what the fight ACTUALLY fielded, and a bounty is
	# earned whether that enemy died or merely lost.
	var bounty_money := 0
	var bounty_xp := 0
	for u in _units:
		if u != null and u.team == TEAM_ENEMY and u.body != null:
			bounty_money += int(u.body.bounty_money)
			bounty_xp += int(u.body.bounty_xp)
	if bounty_money > 0 or bounty_xp > 0:
		BattleState.result_money = bounty_money
		BattleState.result_xp = bounty_xp
	BattleState.result_items = loot.get("items", [])
	BattleState.result_party = party
	_log_note("VICTORY — +%d money, +%d xp, %d item(s)." % [BattleState.result_money, BattleState.result_xp, BattleState.result_items.size()])
	if _dialogue and not _dialogue.is_empty():
		await _play_lines(_dialogue.take("victory"))
		if not is_inside_tree():
			return
	_dbg("[combat] victory! +%d money, +%d xp, %d items" % [BattleState.result_money, BattleState.result_xp, BattleState.result_items.size()])
	# Let the final blow / death animation read for a beat before the results screen
	# takes over. The battle is already locked (_battle_over = true), so nothing can
	# act during the wait.
	if typeof(GameManager) != TYPE_NIL and GameManager.has_method("go_to_victory"):
		await get_tree().create_timer(2.0).timeout
		if is_inside_tree():
			GameManager.go_to_victory()

# ---- persisted damage history (AI_PRIMER §6.8, tier 1) -----------------
## File this fight's damage for the player and every COMPANION into
## Character.damage_history (newest first, last DAMAGE_HISTORY_FIGHTS fights).
##
## WHO: the player, plus allies whose body is a `companion` — the long-term party.
## One-fight helpers (c1's hunters) are not companions and are left out; so are
## enemies, which are rebuilt from their module every fight and have no history.
## WHEN: a WIN or a DEFEAT. Walking out of a fight (the Leave button / Escape) files
## nothing, and neither does the practice dummy.
func _record_damage_history() -> void:
	if _history_recorded or _dummy_fight:
		return
	_history_recorded = true
	var ch := get_node_or_null("/root/Character")
	if ch == null or not ch.has_method("record_fight_damage"):
		return
	var per_unit := {}
	for unit in _units:
		var u: BattleCharacter = unit
		if u == null or u.team == TEAM_ENEMY:
			continue
		if u != _player and (u.body == null or not u.body.companion):
			continue
		per_unit[u.history_key()] = int(round(u.damage_dealt))
	ch.record_fight_damage(per_unit)

# ---- cooldown holds (GODTHAAB §1.16) -----------------------------------
## The key a cooldown-holding cast stamps on what it applies: WHICH unit, WHICH
## ability. A string on the entry, never a unit reference.
func _hold_key(caster: BattleCharacter, ability: Ability) -> String:
	return "%d:%s" % [caster.get_instance_id(), String(ability.id)]

## THE EVENT. Every held slot whose key no longer appears on any LIVING unit is
## released: its cooldown restarts at the ability's full value. Swept rather than
## hooked, so it catches every way an entry can end — natural expiry, a break sweep,
## a cleanse, an escape, displacement at the stack cap, or its bearer dying — with
## nothing added to any of those paths. Called after every resolved action and after
## every turn-start; a handful of units and baskets, so it costs nothing.
func _sweep_cooldown_holds() -> void:
	for unit in _units:
		var u: BattleCharacter = unit
		if u == null or u.cooldown_holds.is_empty():
			continue
		for slot in u.cooldown_holds.keys():
			var key := str(u.cooldown_holds[slot])
			if _hold_still_standing(key):
				continue
			var ab: Ability = _ability_for_slot(u, int(slot))
			var turns := ab.cooldown_at(_ability_rank(u, ab)) if ab != null else 0
			u.release_cooldown_hold(int(slot), turns)
			if u == _player:
				_sync_wheel_state()
			_dbg("[combat] %s: %s is off hold — %d turn(s) of cooldown from now." % [
				u.unit_name, ab.display_name if ab else "slot %d" % int(slot), turns])

func _hold_still_standing(key: String) -> bool:
	for unit in _units:
		var o: BattleCharacter = unit
		if o == null or o.body == null or not o.is_alive():
			continue
		for basket in ["buffs", "debuffs"]:
			for e in o.body.baskets.get(basket, []):
				if typeof(e) == TYPE_DICTIONARY and str(e.get("cooldown_hold", "")) == key:
					return true
	return false

func _ability_for_slot(u: BattleCharacter, slot: int) -> Ability:
	var id := u.ability_at(slot)
	if id == "":
		return null
	return _get_ability(id)

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
	_log_note("—— battle start · %d units ——" % _units.size())
	_dbg("[combat] battle start — %d units on the timeline." % _units.size())
	# AI PRIMITIVE SELF-TEST — debug builds only, and quiet when healthy (one PASS
	# line). It checks AIGain's curve and AIPick's roulette against the numbers
	# AI_PRIMER quotes, with no units and no fight involved, so a silently wrong
	# exponent or an off-by-one in the cumulative walk is caught here rather than
	# read as "the enemies feel random" weeks later. Turn it off by setting
	# AIDebug.SELF_TEST_ON_BATTLE_START to false.
	if AIDebug.SELF_TEST_ON_BATTLE_START and AITurn.is_debug():
		AIDebug.self_test_once()
	_run_turn_loop()

## THE TURN LOOP. Pick the living unit scheduled soonest, scroll the clock to it,
## give it a turn, repeat. This is the whole cycle — there is no round, no player
## phase and no enemy phase. It is a coroutine: it suspends on the scroll animation
## and, on the player's turn, on the `_turn_finished` signal, so nothing spins.
func _run_turn_loop() -> void:
	if _loop_running:
		return
	_loop_running = true
	# OPENING DIALOGUE — before anyone acts.
	if _dialogue and not _dialogue.is_empty():
		await _play_lines(_dialogue.take("start"))
		if not is_inside_tree():
			return
	while not _battle_over:
		_sync_intervals()
		var nxt := _next_actor()
		if nxt == null:
			_dbg("[combat] nobody left to act — turn loop stopping.")
			break
		await _scroll_clock_to(nxt.next_turn_at)
		if _battle_over:
			break
		# A SAFE POINT: between one turn and the next. Mid-fight dialogue plays here.
		await _dialogue_checkpoint(nxt)
		if _battle_over or not is_inside_tree():
			break
		await _begin_unit_turn(nxt)
	_loop_running = false

# ---- combat dialogue (rev33) -------------------------------------------
## Check every mid-fight trigger that can fire before `next_unit` acts, and play what
## fired, in order. See CombatDialogue for the spec shape. ALWAYS a coroutine.
func _dialogue_checkpoint(next_unit: BattleCharacter) -> void:
	if _dialogue == null or _dialogue.is_empty():
		await get_tree().process_frame
		return
	var lines: Array = []
	var any_defeat := false
	for t in _dialogue.pending("unit_defeated"):
		if _trigger_unit_defeated(t):
			any_defeat = true
	if any_defeat:
		lines.append_array(_dialogue.take("unit_defeated", _trigger_unit_defeated))
	var any_low := false
	for t in _dialogue.pending("enemy_hp_below"):
		if _trigger_enemy_hp_below(t):
			any_low = true
	if any_low:
		lines.append_array(_dialogue.take("enemy_hp_below", _trigger_enemy_hp_below))
	if next_unit == _player and _player != null:
		lines.append_array(_dialogue.take("player_turn", _trigger_player_turn))
	await _play_lines(lines)

func _trigger_player_turn(t: Dictionary) -> bool:
	return _player != null and int(t.get("turn", 1)) == _player.turns_taken + 1

func _trigger_unit_defeated(t: Dictionary) -> bool:
	var key := str(t.get("character", ""))
	for unit in _units:
		var u: BattleCharacter = unit
		if u.is_alive() or u.downed:
			continue
		if key == "" and u.team == TEAM_ENEMY:
			return true
		if key != "" and _unit_matches(u, key):
			return true
	return false

func _trigger_enemy_hp_below(t: Dictionary) -> bool:
	var key := str(t.get("character", ""))
	var pct := float(t.get("pct", 0.5))
	for unit in _units:
		var u: BattleCharacter = unit
		if u.team != TEAM_ENEMY or not u.is_alive():
			continue
		if key != "" and not _unit_matches(u, key):
			continue
		if float(u.get_hp()) < pct * float(maxi(1, u.get_max_hp())):
			return true
	return false

func _unit_matches(u: BattleCharacter, key: String) -> bool:
	return u.spec_id == key or u.unit_name.to_lower() == key.to_lower()

func _find_unit(key: String) -> BattleCharacter:
	for unit in _units:
		var u: BattleCharacter = unit
		if _unit_matches(u, key):
			return u
	return null

## Play a list of LINES through the bottom panel's dialogue boxes, one at a time,
## each waiting for the player to advance. Nothing else can act meanwhile.
## ALWAYS a coroutine.
func _play_lines(lines: Array) -> void:
	await get_tree().process_frame
	if lines.is_empty() or _dialogue_left == null:
		return
	_dialogue_busy = true
	if _wheel:
		_wheel.close()
	_refresh_turn_ui()
	for raw in lines:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var line := _resolve_line(raw)
		var right := str(line.get("side", "left")) == "right"
		var box: DialogueBox = _dialogue_right if right else _dialogue_left
		var other: DialogueBox = _dialogue_left if right else _dialogue_right
		other.hide_box()
		box.show_line(line)
		await box.advanced
		if not is_inside_tree():
			return
	_dialogue_left.hide_box()
	_dialogue_right.hide_box()
	_dialogue_busy = false
	_refresh_turn_ui()

## Fill a line's speaker / colour / portrait / side from the unit it names.
func _resolve_line(raw: Dictionary) -> Dictionary:
	var line := raw.duplicate()
	var unit: BattleCharacter = null
	var cid := str(line.get("character", ""))
	if cid != "":
		unit = _find_unit(cid)
	var spk := str(line.get("speaker", ""))
	if spk == "$player" and _player != null:
		unit = _player
		spk = _player.unit_name
	elif unit == null and spk != "":
		unit = _find_unit(spk)
	if spk == "" and unit != null:
		spk = unit.unit_name
	line["speaker"] = spk
	if unit != null and unit.body != null:
		if not line.has("color"):
			line["color"] = unit.body.model_color()
		if not line.has("portrait") and unit.body.portrait != null:
			line["portrait"] = unit.body.portrait
	if not line.has("side"):
		line["side"] = "right" if (unit != null and unit.team == TEAM_ENEMY) else "left"
	return line

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
		# A DOWNED unit keeps its place on the timeline — its turn is when it stands up.
		if not u.is_alive() and not u.downed:
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
	if u.downed:
		_revive_downed(u)
	_active = u
	_turn_should_end = false
	u.turns_taken += 1
	_log_turn(u)
	if _timeline:
		_timeline.set_active(u)

	_process_turn_start(u)
	u.tick_cooldowns()
	# After the tick, so a hold released by this turn-start (an entry that expired,
	# a bearer killed by its DoT) restarts at its FULL cooldown rather than one less.
	_sweep_cooldown_holds()
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
		_dbg("[combat] %s is stunned and loses its turn." % u.unit_name)
		_finish_turn(u)
		return

	_refresh_turn_ui()
	_sync_wheel_state()

	if u == _player:
		_phase = Phase.PLAYER
		_dbg("[combat] %s's turn (turn %d for them, clock %.0f)." % [u.unit_name, u.turns_taken, _clock])
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
	# 0) ESCAPES — the unit broke out of an escapable debuff (Netted). The roll ran
	#    inside collect_turn_start, which is BEFORE _begin_unit_turn's stun check,
	#    so a unit that breaks out of a stunning net acts this very turn.
	for e in report.get("escaped", []):
		u.float_escaped()
		_log_note("%s broke free of %s" % [u.unit_name, str(e.get("source", e.get("id", "?")))])
		_dbg("[combat] %s breaks free of %s." % [u.unit_name, str(e.get("source", e.get("id", "?")))])
	# 1) DoT damage (routed through take_damage so it animates + handles death)
	for d in report["dots"]:
		if u.is_alive():
			u.take_damage(int(d["amount"]), str(d["element"]), false)
			_credit_dot(u, d)
	# 1b) heal-over-turn (Scaled Skin, ...): restore HP via heal() so it
	# animates and respects the healing-received multiplier.
	for h in report["heals"]:
		if u.is_alive():
			u.heal(int(h["amount"]))
	# 1c) HP COSTS paid per turn (Putrefaction) — pay_hp floors at 1 HP.
	var hp_pct := float(report.get("hp_cost_pct", 0.0))
	if hp_pct > 0.0 and u.is_alive():
		u.pay_hp(int(round(float(u.get_max_hp()) * hp_pct)))
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
	var had_shield := CombatShields.has_shield(u.body)
	CombatShields.tick_decay(u.body)
	# A shield that DECAYS to nothing has broken exactly as one chewed through by a
	# hit has, so whatever was riding on it ends here too. take_damage owns the other
	# half of this test; these are the only two ways a pool can empty.
	if had_shield and not CombatShields.has_shield(u.body):
		for e in CombatBuffs.break_on_shield_break(u.body):
			_log_note("%s loses %s — shield gone" % [u.unit_name, str(e.get("source", e.get("id", "?")))])
			_dbg("[combat] %s loses %s — its shield decayed away." % [u.unit_name, str(e.get("id", "?"))])
	u.refresh_bar()
	u.refresh_buffs()

## DoT CREDIT (FUTURE_PLANS §2e / COMBAT C4 #19): a tick counts toward the damage_dealt
## of whoever applied it (stamped `applier_uid` = the caster BODY's instance id), so a
## poison build shows in the damage history and the AI's reputation signal. Credited
## even if the applier has since died. Only a HOSTILE applier is credited — a self-paid
## DoT (electrostimulated) or friendly fire never inflates anyone's tally.
func _credit_dot(bearer: BattleCharacter, d: Dictionary) -> void:
	var uid := int(d.get("applier_uid", 0))
	if uid == 0:
		return
	for unit in _units:
		var a: BattleCharacter = unit
		if a != null and a.body != null and a.body.get_instance_id() == uid:
			if _is_hostile(a, bearer):
				a.damage_dealt += float(d.get("amount", 0))
			return

## REPRIEVE's second half: at the start of a DOWNED unit's turn it stands up at 1 HP
## with every debuff CLEANSED (dev call — otherwise one DoT tick kills it again; the
## `uncleansable` self-costs stay), keeps its buffs, and then takes its turn normally.
func _revive_downed(u: BattleCharacter) -> void:
	var cleared := CombatBuffs.cleanse(u.body, 1 << 30)
	u.stand_up(1)
	u.float_status("RISES", Color(0.95, 0.85, 0.45))
	_log_note("%s rises (Reprieve)%s" % [u.unit_name, (" — %d debuff(s) cleansed" % cleared.size()) if not cleared.is_empty() else ""])
	_dbg("[combat] %s rises at 1 HP (Reprieve), %d debuff(s) cleansed." % [u.unit_name, cleared.size()])
	u.refresh_buffs()
	if u.team != TEAM_ENEMY and _loaded_ally == null:
		_load_unit(u)

## The player ends their turn — from the End Turn button, or from the wheel handler
## once the action-point budget is spent. Wakes _run_turn_loop, which is parked on
## _turn_finished.
func end_player_turn() -> void:
	if _battle_over or _phase != Phase.PLAYER or _active != _player or _action_busy or _dialogue_busy:
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
		_dbg("[combat] %s does nothing." % u.unit_name)
		return
	await AITurn.run(self, u)

## May this unit take ANOTHER action inside its current turn? The loop condition for
## any multi-action AI routine.
func _ai_can_continue(u: BattleCharacter) -> bool:
	return not _battle_over and not _turn_should_end \
		and u != null and u == _active and u.is_alive() and u.ap > AP_EPSILON

func _refresh_turn_ui() -> void:
	if _end_turn_btn:
		_end_turn_btn.disabled = _battle_over or _phase != Phase.PLAYER or _active != _player \
			or _action_busy or _dialogue_busy
	if _leave_btn:
		_leave_btn.disabled = _battle_over
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
		_dbg("[combat] no GameManager.go_to_overworld() — staying put.")
