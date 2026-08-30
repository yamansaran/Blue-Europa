class_name BattleCharacter
extends Control
## Combat model, rev6: driven by a CharacterBase `body`. The placeholder model is
## a rectangle tinted by the name-hash colour (or the character's portrait if one
## is assigned). HP and Spirit are read from / written to the body.

signal hovered(unit: BattleCharacter)
signal unhovered(unit: BattleCharacter)
signal clicked(unit: BattleCharacter)

var body: CharacterBase = null
var team: int = 0
var ai: String = "none"
var unit_name: String = "Unit"
var health_bar: BattleHealthBar = null
## The visible buff/debuff strip beside this unit's health bar (set by combat).
var buff_bar: BuffBar = null
## Visual size multiplier for the model (e.g. bosses are drawn bigger). The
## combat engine reads an enemy spec's "size_scale" and applies it in layout.
var size_scale: float = 1.0

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

	# Name + level, floating just ABOVE the model. Hidden until hovered.
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
	_label.offset_top = -28.0
	_label.offset_bottom = -4.0
	# white text with a black outline so it reads over any model colour
	_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_label.add_theme_constant_override("outline_size", 5)
	_label.add_theme_font_size_override("font_size", 13)
	_label.visible = false
	add_child(_label)

	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)


func _on_mouse_entered() -> void:
	if _label:
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

func refresh_bar() -> void:
	if health_bar:
		health_bar.set_hp(get_hp(), get_max_hp())
		health_bar.set_spirit(get_spirit(), get_max_spirit())
		health_bar.set_shield(get_shield())

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
		refresh_bar()
		_spawn_number(absorbed, "shield", false, false)
		if source != null:
			CombatBuffs.fire_on_struck(self, source, amount, element, from_attack)
		return
	body.current_hp = clampi(body.current_hp - amount, 0, body.max_hp())
	refresh_bar()
	_spawn_number(amount, element, is_crit, false)
	if _rect:
		var base := _model_color()
		_rect.color = Color(1, 1, 1)
		var t := create_tween()
		t.tween_property(_rect, "color", base, 0.25)
	if not is_alive():
		modulate = Color(0.45, 0.45, 0.45, 0.7)
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
	var point := position + Vector2(size.x * 0.5, size.y * 0.30)   # our upper-centre
	DamageNumber.spawn(host, point, amount, element, is_crit, is_heal)

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
