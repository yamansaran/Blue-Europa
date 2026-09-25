class_name BattleCharacter
extends Control
## Combat model, rev6: driven by a CharacterBase `body`. The placeholder model is
## a rectangle tinted by the name-hash colour (or the character's portrait if one
## is assigned). HP and Spirit are read from / written to the body.

signal hovered(unit: BattleCharacter)
signal unhovered(unit: BattleCharacter)
signal clicked(unit: BattleCharacter)
## This unit just lost ACTUAL HEALTH — not shield, and not a zero-damage hit.
## combat.gd listens and runs the break sweeps: effects that cannot survive their
## bearer being hurt, and effects elsewhere anchored to this unit as their caster
## (Protected, when the officer shielding its bearer is struck). A signal rather
## than a direct call because only combat knows the other units.
signal health_damaged(unit: BattleCharacter)
## NEPHILIC HOOKS (2026-09-24). hp_lost: ACTUAL health went down, by any cause
## (a hit, a DoT tick, an HP cost) — Stigmata, Pharmaceutical. hp_paid: the unit paid
## an HP COST (Mortification). struck: a SOURCED hit reached this unit, whether a
## shield ate it or not (Rebuke counts enemy ATTACK hits).
signal hp_lost(unit: BattleCharacter, amount: int, element: String)
signal hp_paid(unit: BattleCharacter, amount: int)
signal struck(unit: BattleCharacter, source, from_attack: bool)

var body: CharacterBase = null
## Per-fight bookkeeping for the Nephilic hooks: uses-per-combat counters, Crash
## counters, Rebuke stacks, once-per-fight flags (Reprieve, Caput Mortuum).
var fight_flags: Dictionary = {}
## DEATH GUARD: set by combat. Called with (self, overkill_hp_before) when a hit would
## drop this unit to 0 HP; returns the HP to survive at (0 = the unit dies).
var death_guard: Callable = Callable()
## DOWNED (Reprieve — FUTURE_PLANS §9, COMBAT C4 #11). A death guard returning DOWNED
## leaves the unit at 0 HP but NOT dead: is_alive() is false, so nothing can target,
## heal or AoE it and it takes no turn-start tick — but the turn loop still schedules
## it (combat._next_actor), defeat does not fire (combat._check_defeat), and at the
## start of its next turn combat stands it up (stand_up).
const DOWNED := -1
var downed: bool = false
var team: int = 0
var ai: String = "none"
var unit_name: String = "Unit"
## The BIG bar in the top panel. NULL for most units: since the overhead rework only
## IMPORTANT units (player, companions, minibosses, bosses) get one — combat decides.
var health_bar: BattleHealthBar = null
## The visible buff/debuff strip beside the top-panel bar (null with health_bar).
var buff_bar: BuffBar = null
## The compact bars + buff icons floating above THIS model. Every unit has one.
var overhead: UnitOverhead = null
## The CharacterRegistry id this unit was built from ("" for an inline spec / the
## player). Combat dialogue triggers name units by it.
var spec_id: String = ""

## The id this unit's damage is filed under in Character.damage_history: "player"
## for the player (whose spec_id is "player"), a companion's CharacterRegistry id,
## else its display name.
func history_key() -> String:
	return spec_id if spec_id != "" else unit_name

## --- ANTI-FRUSTRATION (CombatDodge) -------------------------------------------
## Consecutive attacks from the PLAYER'S SIDE this unit has dodged since it was last
## hit. Each one shaves a little off its next dodge chance; any landed hit resets it.
var dodge_streak: int = 0

## TOTAL damage this unit has dealt this fight: its attacks' main hits, the second
## element, %-max-HP terms, Shatter's bonus, on-hit damage riders and on-struck
## reflects (thorns). DoT is NOT counted — an instance is disconnected from its caster
## by design, so a tick has nobody to credit. The AI's `reputation` signal reads it as
## tier 2 (AI_PRIMER §6.8), and at fight end combat files it for the player and every
## COMPANION into Character.damage_history, which is tier 1.
var damage_dealt: float = 0.0

## The id of the last ability this unit actually RESOLVED, written by
## combat._use_ability. The AI's entire memory between decisions: AITurn reads it to
## honour that ability's `ai_follow_up`, which is how a scripted two-beat pattern
## ("Riot Shield, then Shield Bash") exists at all in a system that otherwise
## re-decides from scratch every action. Combat-local, never saved.
var last_ability_id: String = ""

## --- damage-number bursts ----------------------------------------------------
## Numbers spawned within this many ms of the previous one join the same BURST and
## fan out in different directions (DamageNumber.set_spread).
const BURST_WINDOW_MS := 160
var _burst: Array = []
var _burst_last_ms: int = -100000
## Visual size multiplier for the model (e.g. bosses are drawn bigger). The
## combat engine reads an enemy spec's "size_scale" and applies it in layout.
var size_scale: float = 1.0

# ---- formation slot (rev32) -------------------------------------------------
## Where this unit stands in ITS SIDE'S BattleGrid: `grid_col` is 0 = BACK /
## 1 = FRONT, `grid_row` is 0 (top) .. 4 (bottom). -1 = not seated yet, which is
## the signal combat._place_units uses to deal this unit a slot; set both BEFORE
## placement to pin a unit to a specific slot instead. The grid owns occupancy —
## always seat a unit through BattleGrid.place/assign rather than by writing these
## two directly, or the slot it left will still think it is there.
## NOTHING reads these to make a decision yet (rev32 is slots and data only); they
## drive position, draw order and the debug overlay.
var grid_col: int = -1
var grid_row: int = -1

# ---- per-turn action state (EVERY unit has these, not just the player) ----
## This unit's ability ids in SLOT order, snapshotted by combat at battle start.
## For the PLAYER these are the wheel's equipped_abilities; for everyone else they
## are body.abilities. Slot indices must stay stable for the whole fight — that is
## what lets `cooldowns` key by them.
var loadout: Array = []
## Action points left THIS turn. Refilled to the body's (buffable) `action_points`
## stat at the start of THIS UNIT'S OWN turn. An ability spends its action_cost
## from here; the acting unit's turn auto-ends when the budget is gone.
var ap: float = 0.0
## Action points this unit has ACTUALLY SPENT during the current turn. rev30: the
## timeline advance at the end of a turn is `interval * (ap_spent / max_ap)`, so
## a unit that only spent half its budget before ending its turn waits only half
## an interval for its next one. Reset alongside `ap`.
var ap_spent: float = 0.0
## Ability cooldowns for THIS unit: SLOT INDEX (int) -> turns remaining. Keyed by
## slot rather than by ability id so two copies of the same ability cool down
## independently. For the player this dict is handed to the ActionWheel BY
## REFERENCE, so the wheel greys the exact slot that is cooling down.
## rev30: a "turn" here is THIS UNIT'S OWN turn — cooldowns tick when this unit
## acts, not on a global round boundary.
var cooldowns: Dictionary = {}

## COOLDOWN HOLDS (GODTHAAB §1.16): SLOT INDEX -> the hold key stamped on every entry
## that slot's cast applied (Ability.cooldown_while_applied). A held slot's cooldown
## is FROZEN — tick_cooldowns skips it — until combat's _sweep_cooldown_holds finds
## no living unit still carrying an entry with that key and calls
## release_cooldown_hold. Combat-local, like `cooldowns`; never saved.
var cooldown_holds: Dictionary = {}

# ---- timeline state (rev30) -------------------------------------------------
## The combat CLOCK VALUE at which this unit next acts. combat.gd advances its
## clock to the smallest next_turn_at among the living and gives that unit a
## turn; TurnTimeline draws this unit's bars starting here and repeating every
## turn_interval() ticks. See CombatTimeline.
var next_turn_at: float = 0.0
## How many turns this unit has taken this fight. Bookkeeping / logs only.
var turns_taken: int = 0
## The interval this unit was last seen to have, so combat.gd can spot a change
## (a haste buff landing, alacrity being drained) and rescale the REMAINING wait
## proportionally instead of leaving the already-scheduled turn where it was.
## 0.0 means "not sampled yet".
var cached_interval: float = 0.0

var _rect: ColorRect
var _portrait: TextureRect
var _label: Label

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	if body != null:
		unit_name = body.char_name

	if body != null and body.portrait != null:
		_portrait = TextureRect.new()
		_portrait.texture = body.portrait
		_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(_portrait)
	else:
		_rect = ColorRect.new()
		_rect.color = _model_color()
		_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(_rect)

	# Compact bars + buff icons floating over the model (every unit).
	overhead = UnitOverhead.new()
	add_child(overhead)
	overhead.setup(self)
	resized.connect(_on_resized)

	# Name + level, floating ABOVE the overhead bars. Hidden until hovered.
	var lvl := body.level if body != null else 1
	_label = Label.new()
	_label.text = "%s  Lv %d" % [unit_name, lvl]
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.anchor_left = 0.0
	_label.anchor_right = 1.0
	_label.anchor_top = 0.0
	_label.anchor_bottom = 0.0
	_label.offset_left = -24.0
	_label.offset_right = 24.0
	_label.offset_top = -28.0 - overhead.stack_height()
	_label.offset_bottom = -4.0 - overhead.stack_height()
	# white text with a black outline so it reads over any model colour
	_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_label.add_theme_constant_override("outline_size", 5)
	_label.add_theme_font_size_override("font_size", 13)
	_label.visible = false
	add_child(_label)

	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)


func _on_resized() -> void:
	if overhead:
		overhead.relayout()
		if _label:
			_label.offset_top = -28.0 - overhead.stack_height()
			_label.offset_bottom = -4.0 - overhead.stack_height()

func _on_mouse_entered() -> void:
	if _label:
		var lvl := body.level if body != null else 1
		_label.text = "%s  Lv %d   %d/%d" % [unit_name, lvl, get_hp(), get_max_hp()]
		_label.visible = true
	hovered.emit(self)


func _on_mouse_exited() -> void:
	if _label:
		_label.visible = false
	unhovered.emit(self)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit(self)
		accept_event()

func _model_color() -> Color:
	if body != null:
		return body.model_color()
	return Color.GRAY

# ---- vitals (read from the body) --------------------------------------
func get_max_hp() -> int:
	return body.max_hp() if body else 1

func get_hp() -> int:
	return body.current_hp if body else 0

func get_max_spirit() -> int:
	return body.max_spirit() if body else 0

func get_spirit() -> int:
	return body.current_spirit if body else 0

func is_alive() -> bool:
	return get_hp() > 0

## Stand a DOWNED unit back up at `hp` (Reprieve). No-op on a unit that isn't downed.
func stand_up(hp: int) -> void:
	if body == null or not downed:
		return
	downed = false
	body.current_hp = clampi(hp, 1, body.max_hp())
	modulate = Color(1, 1, 1, 1)
	refresh_bar()

# ---- per-turn action state --------------------------------------------
## Refill this unit's action-point budget to its EFFECTIVE action_points stat, so a
## buff that grants an extra action just works. Called at the start of THIS UNIT'S
## OWN turn; a dead unit refills to 0 and can't act. Also clears the spend counter
## the timeline advance is computed from.
func reset_ap() -> void:
	ap_spent = 0.0
	if body == null or not is_alive():
		ap = 0.0
		return
	ap = maxf(0.0, body.get_effective("action_points"))

## This unit's FULL action-point budget for a turn (as opposed to `ap`, what is
## left of it). The denominator of the timeline-advance fraction.
func max_ap() -> float:
	if body == null:
		return 1.0
	return maxf(0.0, body.get_effective("action_points"))

# ---- timeline ---------------------------------------------------------
## How many clock TICKS pass between this unit's turns, from its LIVE effective
## alacrity and turn_rate — so a haste buff shortens it (and visibly shortens the
## unit's bars on the TurnTimeline) the moment it lands. See CombatTimeline.
func turn_interval() -> float:
	return CombatTimeline.interval_for(body)

## The ability id in `slot` of this unit's loadout ("" when the slot is empty or out
## of range — the wheel's slot array is padded, so empty slots are normal).
func ability_at(slot: int) -> String:
	if slot < 0 or slot >= loadout.size():
		return ""
	return str(loadout[slot])

func cooldown_left(slot: int) -> int:
	return int(cooldowns.get(slot, 0))

func on_cooldown(slot: int) -> bool:
	return cooldown_left(slot) > 0

## Start `turns` of cooldown on `slot`. A slot of -1 (an ability used from no slot)
## simply doesn't cool down.
func start_cooldown(slot: int, turns: int) -> void:
	if slot < 0 or turns <= 0:
		return
	cooldowns[slot] = turns

## SET a slot's cooldown outright — raise it, lower it, or clear it with 0. Unlike
## start_cooldown this can SHORTEN a cooldown, which is what an event that changes a
## cooldown needs. Leaves any hold on the slot alone.
func set_cooldown(slot: int, turns: int) -> void:
	if slot < 0:
		return
	if turns <= 0:
		cooldowns.erase(slot)
	else:
		cooldowns[slot] = turns

## Freeze `slot`'s cooldown until nothing carrying `key` survives (§1.16).
func hold_cooldown(slot: int, key: String) -> void:
	if slot < 0 or key == "":
		return
	cooldown_holds[slot] = key

func is_cooldown_held(slot: int) -> bool:
	return cooldown_holds.has(slot)

## The event: whatever held `slot` is gone. The cooldown restarts at `turns` (the
## ability's full cooldown) and ticks normally from the unit's next turn.
func release_cooldown_hold(slot: int, turns: int) -> void:
	if not cooldown_holds.has(slot):
		return
	cooldown_holds.erase(slot)
	set_cooldown(slot, turns)

## Tick every cooling slot down one turn, dropping the ones that finished. A HELD
## slot (cooldown_holds) does not tick at all.
func tick_cooldowns() -> void:
	for slot in cooldowns.keys():
		if cooldown_holds.has(slot):
			continue
		var v := int(cooldowns[slot]) - 1
		if v <= 0:
			cooldowns.erase(slot)
		else:
			cooldowns[slot] = v

func refresh_bar() -> void:
	if health_bar:
		health_bar.set_hp(get_hp(), get_max_hp())
		health_bar.set_spirit(get_spirit(), get_max_spirit())
		health_bar.set_shield(get_shield())
	if overhead:
		overhead.set_values(get_hp(), get_max_hp(), get_spirit(), get_max_spirit(), get_shield())

## Total absorbing shield across every source (the number on the grey shield bar).
func get_shield() -> int:
	return CombatShields.total(body) if body else 0

## Grant an absorbing shield to this unit from a config dict (see CombatShields.apply:
## id / source / element / amount / decay). Floats a grey "+N" over the unit and
## refreshes the bar so the shield reads immediately.
func gain_shield(config: Dictionary) -> void:
	if body == null:
		return
	# RECEIVED shield_power: this unit's shield_power (%) increases every absorbing
	# shield it is granted, whatever the source. The DEALT side (the caster's own
	# shield_power) is applied where the shield is computed (combat.gd SHIELD branch).
	var recv_mult := 1.0 + maxf(0.0, body.get_effective("shield_power")) / 100.0
	var amt := int(round(float(config.get("amount", 0.0)) * recv_mult))
	if amt <= 0:
		return
	# Apply the boosted amount (duplicate the config so we don't mutate the caller's dict).
	var cfg := config.duplicate(true)
	cfg["amount"] = amt
	CombatShields.apply(body, cfg)
	refresh_bar()
	_spawn_number(amt, "shield", false, true)   # grey "+N"

## Rebuild the visible buff/debuff strip from the body's current buffs+debuffs.
func refresh_buffs() -> void:
	if buff_bar:
		buff_bar.refresh()
	if overhead:
		overhead.refresh_buffs()

# ---- mutations --------------------------------------------------------
## Apply damage and float a damage number over this unit. `element` tints the
## number (via ElementColors); `is_crit` enlarges + italicises it and appends "!".
## `source` is the attacking BattleCharacter, when there is one: it lets "when
## struck" reactions (thorns, ...) hit back. DoT / environmental damage passes no
## source and triggers no reaction. Reflected damage is dealt with no source too,
## so thorns can never recurse.
## `from_attack` is the hidden ATTACK-vs-SPELL delivery class of the incoming hit
## (Ability.is_attack_delivery()). Attacks-only on-struck reactions — thorns-style
## reflects and Rime Skin — fire ONLY when it is true, so a spell never procs them.
## It defaults to false, so any unsourced/incidental damage stays inert as before.
func take_damage(amount: int, element: String = "physical", is_crit: bool = false, source = null, amp_ice: bool = true, from_attack: bool = false) -> void:
	if body == null:
		return
	# Hoarfrost: a SOURCED ice hit (a player/ally attack) consumes the target's
	# hoarfrost stacks, amplifying this instance. amp_ice lets Hoarfrost's own ice
	# damage opt out so it neither eats nor is boosted by other Hoarfrost stacks.
	if amp_ice and element == "ice" and source != null:
		amount = CombatBuffs.apply_incoming_ice_amp(body, amount)
	# SILVER MIRROR: an enemy ATTACK that reaches a bearer with a struck-charge is
	# turned aside whole — no shield drain, no health loss, no on-struck reaction.
	if amount > 0 and from_attack and source != null and CombatBuffs.consume_struck_charge(body):
		float_status("DEFLECTED", Color(0.85, 0.88, 0.95))
		refresh_buffs()
		return
	if source != null:
		struck.emit(self, source, from_attack)
	# SHIELD absorption: damage is dealt to the shield FIRST (newest instance first),
	# and there is NO overflow to health — if the unit has ANY shield when the hit
	# lands, health takes ZERO this hit, whatever the leftover. Drain the shields,
	# float the absorbed amount in grey, still let "when struck" reactions fire.
	# TRUE DAMAGE IGNORES SHIELDS: the hidden "true" element already skips all
	# mitigation in CombatMath; it now also skips this absorption layer and goes
	# straight to health, leaving every shield instance untouched (it neither
	# spends nor is stopped by them). That makes "true" the one element a shield
	# is no answer to — the only clean way to threaten a shielded unit.
	if amount > 0 and element != "true" and CombatShields.has_shield(body):
		var absorbed := CombatShields.absorb(body, amount)
		# SHIELD BROKEN: the pool was standing when this hit landed and is gone now.
		# Tested HERE rather than inside CombatShields because absorb() is a pure
		# drain — the "was there, isn't now" edge only exists at a call site that saw
		# both sides of it. Anything riding on the shield ends with it.
		if not CombatShields.has_shield(body):
			if not CombatBuffs.break_on_shield_break(body).is_empty():
				refresh_buffs()
		refresh_bar()
		_spawn_number(absorbed, "shield", false, false)
		if source != null:
			CombatBuffs.fire_on_struck(self, source, amount, element, from_attack)
		return
	var hp_before := body.current_hp
	body.current_hp = clampi(body.current_hp - amount, 0, body.max_hp())
	# DEATH GUARD (Reprieve, Caput Mortuum): a lethal hit may be survived.
	if hp_before > 0 and body.current_hp <= 0 and death_guard.is_valid():
		var survive := int(death_guard.call(self))
		if survive > 0:
			body.current_hp = clampi(survive, 1, body.max_hp())
		elif survive == DOWNED:
			downed = true
	if body.current_hp < hp_before:
		hp_lost.emit(self, hp_before - body.current_hp, element)
	# ACTUAL HEALTH LOST. Announced only on this path — a hit the shield ate returned
	# above — and only for a hit that did something, so a 0-damage resolve (Snap with
	# nothing to snap) never breaks a Covering.
	if amount > 0:
		health_damaged.emit(self)
	refresh_bar()
	_spawn_number(amount, element, is_crit, false)
	if _rect:
		var base := _model_color()
		_rect.color = Color(1, 1, 1)
		var t := create_tween()
		t.tween_property(_rect, "color", base, 0.25)
	if not is_alive():
		# Downed reads lighter than dead: still greyed, but clearly not gone.
		modulate = Color(0.65, 0.65, 0.75, 0.85) if downed else Color(0.45, 0.45, 0.45, 0.7)
	# "When struck do X" — fire this unit's on-struck reactions against the source
	# of the hit (thorns reflect, etc.). Only for sourced hits, never DoT/reflect.
	if source != null:
		CombatBuffs.fire_on_struck(self, source, amount, element, from_attack)

## Restore HP, floating a green "+N" over this unit. The amount is scaled by the
## target's healing-received multiplier (from its buffs/debuffs) AND by its RECEIVED
## heal_power (%) — heal_power increases all healing this unit receives, whatever the
## source (direct heals and heal-over-turn alike). The DEALT side (the caster's own
## heal_power) is applied where the heal is computed (combat.gd HEAL branch).
## Returns the HP actually restored. Never revives a dead unit.
func heal(amount: int, _is_crit: bool = false) -> int:
	if body == null or not is_alive():
		return 0
	var recv_mult := 1.0 + maxf(0.0, body.get_effective("heal_power")) / 100.0
	var scaled := int(round(float(amount) * CombatBuffs.healing_received_mult(body) * recv_mult))
	if scaled <= 0:
		return 0
	var before := body.current_hp
	body.current_hp = clampi(body.current_hp + scaled, 0, body.max_hp())
	var restored := body.current_hp - before
	refresh_bar()
	if restored > 0:
		_spawn_number(restored, "physical", false, true)
	return restored

## Float a number up over this unit. It's added to our PARENT (not to us) so the
## grey-out modulate we apply on death doesn't dim it and it isn't clipped to our
## rect. `position`/`size` are our rect in the parent's local space.
func _spawn_number(amount: int, element: String, is_crit: bool, is_heal: bool) -> void:
	var host := get_parent()
	if host == null:
		return
	_join_burst(DamageNumber.spawn(host, _number_origin(), amount, element, is_crit, is_heal))

## Where floating numbers and status words start: the TOP-CENTRE of the model.
func _number_origin() -> Vector2:
	return position + Vector2(size.x * 0.5, 0.0)

## Add a freshly spawned number to the current burst (or start a new one) and re-fan
## every live member so each instance gets its own direction.
func _join_burst(dn: DamageNumber) -> void:
	if dn == null:
		return
	var now := Time.get_ticks_msec()
	if now - _burst_last_ms > BURST_WINDOW_MS:
		_burst.clear()
	_burst_last_ms = now
	var live: Array = []
	for n in _burst:
		if is_instance_valid(n):
			live.append(n)
	live.append(dn)
	_burst = live
	var count := _burst.size()
	if count < 2:
		return
	for i in count:
		var dir := lerpf(-1.0, 1.0, float(i) / float(count - 1))
		(_burst[i] as DamageNumber).set_spread(dir, count)

## Float a STATUS word over this unit — "DODGE" when it evades an attack, "RESIST"
## when it shrugs off a debuff. Same host/positioning rules as a damage number, so
## it is neither clipped to our rect nor dimmed by the death grey-out.
func float_status(label: String, color: Color, font_size: int = DamageNumber.STATUS_FONT_SIZE) -> void:
	var host := get_parent()
	if host == null:
		return
	_join_burst(DamageNumber.spawn_text(host, _number_origin(), label, color, font_size))

## Convenience wrappers so combat.gd never has to know the palette.
func float_dodge() -> void:
	float_status("DODGE", DamageNumber.DODGE_COLOR)

func float_resist() -> void:
	float_status("RESIST", DamageNumber.RESIST_COLOR)

## This unit is shielded by its own front row and cannot be targeted from the other
## side (BattleGrid.is_covered). Floated when a click is REFUSED, so the rule teaches
## itself the first time the player tries.
func float_covered() -> void:
	float_status("COVERED", DamageNumber.COVERED_COLOR)

## This unit rolled its way out of an escapable debuff (Netted) at the start of its
## turn. Without a float the player would never learn that rolling out is a thing
## that happens — the net would just silently vanish. Two words, so it uses the
## smaller face the empowerment float already needs for the same reason.
func float_escaped() -> void:
	float_status("BROKE FREE", DamageNumber.ESCAPE_COLOR, DamageNumber.EMPOWER_FONT_SIZE)

## A debuff landed AMPLIFIED by the caster's surplus Disdain. Reports what was
## actually gained: the potency multiplier when it grew, and "+NT" when the duration
## roll paid out. Called only when at least one of the two happened, so an unempowered
## cast floats nothing and the screen stays quiet at parity.
func float_empowered(potency: float, extra_turns: int) -> void:
	var parts := []
	if potency > 1.0:
		parts.append("x%.2f" % potency)
	if extra_turns > 0:
		parts.append("+%dT" % extra_turns)
	if parts.is_empty():
		return
	float_status(" ".join(parts), DamageNumber.EMPOWER_COLOR, DamageNumber.EMPOWER_FONT_SIZE)

## PAY AN HP COST (Nephilic, 2026-09-24). Straight off health: no mitigation, no
## shield, no on-struck reaction, and it can NEVER kill — the unit keeps at least 1 HP
## whatever is asked (combat also refuses a lethal cost up front). Emits hp_lost and
## hp_paid. Returns the HP actually paid.
func pay_hp(amount: int) -> int:
	if body == null or amount <= 0 or not is_alive():
		return 0
	var paid := mini(amount, body.current_hp - 1)
	if paid <= 0:
		return 0
	body.current_hp -= paid
	refresh_bar()
	_spawn_number(paid, "blood", false, false)
	hp_lost.emit(self, paid, "cost")
	hp_paid.emit(self, paid)
	return paid

## Spend spirit (the resource formerly called focus). Returns false if short.
func spend_spirit(amount: int) -> bool:
	if body == null:
		return amount <= 0
	if body.current_spirit < amount:
		return false
	body.current_spirit -= amount
	refresh_bar()
	return true

## Change spirit by a signed delta (per-turn regen/drain, or an ability's one-time
## gain/steal), clamped to [0, max]. Returns the actual change applied.
## OVERFILL: spirit a GAIN would have pushed past the cap is normally just wasted. A
## bearer of an overflow-shield effect (Lightning Shell) converts it instead — see
## _convert_spirit_overflow. This is deliberately in change_spirit rather than in the
## turn tick, so EVERY source of spirit counts: start-of-turn regen, a spirit_per_turn
## buff, Acceleration's +25, ZAP!'s +5.
func change_spirit(delta: int) -> int:
	if body == null:
		return 0
	var before := body.current_spirit
	body.current_spirit = clampi(body.current_spirit + delta, 0, body.max_spirit())
	var applied := body.current_spirit - before
	if delta > 0 and applied < delta:
		_convert_spirit_overflow(delta - applied)
	refresh_bar()
	return applied

## Turn `overflow` points of wasted (over-cap) spirit into absorbing shields, one grant
## per overflow-shield effect this unit carries. Each spec converts in WHOLE CHUNKS of
## `per_spirit` points — a remainder smaller than one chunk is simply lost, it does not
## carry to the next gain — and each chunk is worth sum(fraction * this unit's effective
## stat) across the spec's "scale" map, read LIVE so the shield tracks Vitality/Instinct.
## The grant goes through gain_shield(), so the bearer's shield_power applies and the
## grey "+N" floats like any other shield. A spec with no "decay" makes a shield that
## never decays (Lightning Shell's lasts until it is spent).
func _convert_spirit_overflow(overflow: int) -> void:
	if body == null or overflow <= 0:
		return
	for spec in CombatBuffs.overflow_shield_specs(body):
		var per := maxi(1, int(spec.get("per_spirit", 5)))
		var chunks := overflow / per          # integer division: whole chunks only
		if chunks <= 0:
			continue
		var scale = spec.get("scale", {})
		if typeof(scale) != TYPE_DICTIONARY:
			continue
		var per_chunk := 0.0
		for stat in scale.keys():
			per_chunk += float(scale[stat]) * maxf(0.0, body.get_effective(str(stat)))
		var amount := per_chunk * float(chunks)
		if amount <= 0.0:
			continue
		var decay = spec.get("decay", {})
		gain_shield({
			"id": str(spec.get("id", "overflow_shield")),
			"source": str(spec.get("source", "Shield")),
			"element": str(spec.get("element", "")),
			"amount": amount,
			"decay": decay if typeof(decay) == TYPE_DICTIONARY else {},
		})
