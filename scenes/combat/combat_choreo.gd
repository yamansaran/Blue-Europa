class_name CombatChoreo
extends RefCounted

## ============================================================================
## COMBAT CHOREOGRAPHY  —  a RIGGED caster performs an action  (RIG_SPEC §6)
## ============================================================================
## Owned by combat.gd (_choreo). perform() is the rigged branch of _perform_action:
## it moves / animates the caster and calls `resolve` (a Callable wrapping
## _use_ability) AT THE MOMENT THE CLIP SAYS — the attack clip's `impact` cue, or a
## projectile's arrival after the windup's `release` cue. _use_ability itself is
## untouched and still synchronous; only WHEN it runs moved.
##
##   MELEE   run to the target's front · attack clip · impact -> resolve · recover ·
##           turn and run home · idle
##   RANGED  windup clip · release -> a projectile flies to the target · arrival ->
##           resolve · the clip finishes in the background
##   STAY    cast clip (cast_self on a friendly, windup on a hostile) · release ->
##           resolve
##
## ONLY THE RIG MOVES (dev call): the BattleCharacter Control — click box, overhead
## bars, grid seat, cover — never leaves its slot. Every wait is bounded (a clip with
## no cue, a missing clip), so no path can hang a turn; if the rig can't do something
## the action still resolves.
## ----------------------------------------------------------------------------

## Run speed in battle-panel px/s, and the clamp on one leg of the run.
const RUN_SPEED := 950.0
const RUN_MIN := 0.16
const RUN_MAX := 0.42
## How far in front of the target's centre the runner stops, as a fraction of the
## target's width (plus a flat margin, px).
const MELEE_GAP := 0.55
const MELEE_MARGIN := 10.0
## Wait for a cue at most the clip length plus this (s).
const CUE_SLACK := 0.25
## After a ranged / stay resolve, hold this long before handing back (s) — long
## enough for the numbers to read, short enough not to drag.
const AFTER_CAST := 0.3

const RANGED_CLASSES := [&"gun", &"bow", &"staff"]

var combat: Node = null        # combat.gd — for _battle_panel, _is_hostile, _sort_unit_depth
var panel: Control = null

func _init(p_combat: Node, p_panel: Control) -> void:
	combat = p_combat
	panel = p_panel

# ---- what kind of motion -----------------------------------------------------------
## How this caster performs this ability. Ability.motion wins when it isn't AUTO.
static func motion_for(caster: BattleCharacter, ability: Ability, hostile: bool) -> int:
	if ability.motion != Ability.Motion.AUTO:
		return ability.motion
	match ability.kind:
		Ability.Kind.BUFF, Ability.Kind.HEAL, Ability.Kind.SHIELD, Ability.Kind.PASSIVE:
			return Ability.Motion.STAY
	if not hostile:
		return Ability.Motion.STAY
	if ability.is_area_target() or ability.retargets_each_hit():
		return Ability.Motion.RANGED
	if ability.kind == Ability.Kind.ATTACK and ability.is_attack_delivery() \
			and not (caster.main_weapon_class() in RANGED_CLASSES):
		return Ability.Motion.MELEE
	return Ability.Motion.RANGED

## The clip a motion plays: the ability's own `anim`, else by motion + weapon class.
static func clip_for(caster: BattleCharacter, ability: Ability, motion: int, hostile: bool) -> StringName:
	if ability.anim != &"":
		return ability.anim
	var cls := caster.main_weapon_class()
	match motion:
		Ability.Motion.MELEE:
			return StringName("attack_%s" % cls)
		Ability.Motion.RANGED:
			return StringName("windup_%s" % cls)
	return &"windup" if hostile else &"cast_self"

# ---- the performance --------------------------------------------------------------
## Perform `ability` from `caster` at `tgt`, calling `resolve` exactly once (awaited —
## a multi-hit resolve suspends between hits on the HIT PACER). Awaitable.
func perform(caster: BattleCharacter, ability: Ability, tgt: BattleCharacter, resolve: Callable) -> void:
	var rig := caster.rig
	var hostile: bool = tgt != null and combat._is_hostile(caster, tgt)
	var motion := motion_for(caster, ability, hostile)
	if motion == Ability.Motion.MELEE and (tgt == null or tgt == caster):
		motion = Ability.Motion.STAY
	var clip := clip_for(caster, ability, motion, hostile)
	match motion:
		Ability.Motion.MELEE:
			await _melee(caster, rig, tgt, clip, resolve)
		Ability.Motion.RANGED:
			await _ranged(caster, rig, ability, tgt, clip, resolve)
		_:
			await _stay(caster, rig, ability, clip, hostile, resolve)

## Run `resolve` with combat's HIT PACER set for the duration (RIG_SPEC §12). The
## multi-hit loop (_resolve_hits_on) awaits pacer.call(i, target) before EVERY strike,
## so each hit of a flurry lands on its own swing or its own shot. Always cleared.
func _resolve_paced(resolve: Callable, pacer: Callable) -> void:
	combat.set("_hit_pacer", pacer)
	await resolve.call()
	combat.set("_hit_pacer", Callable())

func _melee(caster: BattleCharacter, rig: UnitRig, tgt: BattleCharacter, clip: StringName, resolve: Callable) -> void:
	var home := rig.position
	var spot := _melee_spot(caster, tgt)
	_raise(caster)
	# There
	rig.play(&"run")
	await _move_rig(rig, spot)
	if not _alive_scene(rig):
		await resolve.call()
		return
	# Strike. Hit 1 is the opening clip's impact; hits 2..N each get a quick attack2.
	if rig.play(clip):
		await rig.wait_cue(&"impact", rig.clip_length(clip) + CUE_SLACK)
	var pacer := func(i: int, _t: BattleCharacter) -> void:
		if i == 0 or not _alive_scene(rig):
			return
		if rig.play(&"attack2"):
			await rig.wait_cue(&"impact", rig.clip_length(&"attack2") + CUE_SLACK)
	await _resolve_paced(resolve, pacer)
	if not _alive_scene(rig):
		return
	await rig.wait_finish(maxf(rig.clip_length(clip), 0.2) + CUE_SLACK)
	if not _alive_scene(rig):
		return
	# Home — turned round and running, unless the swing got him killed (a reflect):
	# then the body slides back holding its death pose.
	if caster.is_alive():
		rig.set_facing(-caster.facing)
		rig.play(&"run")
	await _move_rig(rig, home)
	if not _alive_scene(rig):
		return
	rig.set_facing(caster.facing)
	if caster.is_alive():
		# The blow that won the fight: home, then the victory pose (_win already
		# posed everyone else; the run home overrode ours).
		if bool(combat.get("_won")):
			rig.play(&"victory")
		else:
			rig.play_idle()
	combat._sort_unit_depth()

func _ranged(caster: BattleCharacter, rig: UnitRig, ability: Ability, tgt: BattleCharacter, clip: StringName, resolve: Callable) -> void:
	if rig.play(clip):
		await rig.wait_cue(&"release", rig.clip_length(clip) + CUE_SLACK)
	if not _alive_scene(rig):
		await resolve.call()
		return
	var look := _projectile_look(caster, ability)
	var col := ElementColors.color_for_enum(int(ability.element))
	_muzzle(caster, rig, col)
	# AREA: no single place to fly to — resolve on release, with a burst on the target.
	if ability.is_area_target() or tgt == null or tgt == caster:
		await resolve.call()
	else:
		# SINGLE or SCATTERED (Spray): one projectile per hit, each to the unit that
		# hit will actually land on (the loop picks a scattered hit's target BEFORE
		# calling the pacer). Hit 1 leaves on the windup's release; hits 2..N each get
		# a quick `fire`.
		var pacer := func(i: int, t: BattleCharacter) -> void:
			if not _alive_scene(rig) or t == null:
				return
			if i > 0:
				if rig.play(&"fire"):
					await rig.wait_cue(&"release", rig.clip_length(&"fire") + CUE_SLACK)
				_muzzle(caster, rig, col)
			await _shoot(caster, rig, look, col, t)
		# _resolve_hits_on paces a SINGLE hit too (i = 0), so a one-shot flies as well.
		# A ranged DEBUFF never enters the hit loop: it lands on the release.
		await _resolve_paced(resolve, pacer)
	if _alive_scene(rig):
		await rig.get_tree().create_timer(AFTER_CAST).timeout

func _stay(caster: BattleCharacter, rig: UnitRig, ability: Ability, clip: StringName, hostile: bool, resolve: Callable) -> void:
	if rig.play(clip):
		await rig.wait_cue(&"release", rig.clip_length(clip) + CUE_SLACK)
	if _alive_scene(rig) and panel:
		var col := ElementColors.color_for_enum(int(ability.element)) if hostile else Color(0.75, 0.9, 1.0)
		ImpactBurst.spawn(panel, caster.position + Vector2(caster.size.x * 0.5, caster.size.y * 0.55), col, ImpactBurst.Kind.CAST)
	await resolve.call()
	if _alive_scene(rig):
		await rig.get_tree().create_timer(AFTER_CAST).timeout

## The projectile look for this shot: the ability's own, else the weapon preset for
## an ATTACK-delivery shot (bullet, arrow, bolt), else null (the element orb).
func _projectile_look(caster: BattleCharacter, ability: Ability) -> ProjectileLook:
	if ability.projectile != null:
		return ability.projectile
	if ability.is_attack_delivery():
		return ProjectileLook.for_weapon(caster.main_weapon_class())
	return null

## Fly one projectile from the caster's weapon (or hand) to `t`. Awaitable.
func _shoot(caster: BattleCharacter, rig: UnitRig, look: ProjectileLook, col: Color, t: BattleCharacter) -> void:
	if panel == null or not is_instance_valid(t):
		return
	var p := Projectile.new()
	p.setup(look, col)
	panel.add_child(p)
	await p.fly(_socket_in_panel(caster, rig), t.position + t.size * 0.5)

func _muzzle(caster: BattleCharacter, rig: UnitRig, col: Color) -> void:
	if panel and _alive_scene(rig):
		ImpactBurst.spawn(panel, _socket_in_panel(caster, rig), col, ImpactBurst.Kind.MUZZLE)

func _socket_in_panel(caster: BattleCharacter, rig: UnitRig) -> Vector2:
	var sock := &"weapon_main" if caster.main_weapon_class() != &"unarmed" else &"hand_near"
	return _to_panel(rig.socket_global_position(sock))

# ---- helpers ---------------------------------------------------------------------
## Where the runner's FEET stop, in the caster's local space: in front of the
## target (on the caster's side of it), level with the target's feet.
func _melee_spot(caster: BattleCharacter, tgt: BattleCharacter) -> Vector2:
	var toward := 1.0 if tgt.position.x >= caster.position.x else -1.0
	var feet := tgt.position + Vector2(tgt.size.x * 0.5, tgt.size.y)
	feet.x -= toward * (tgt.size.x * MELEE_GAP + MELEE_MARGIN)
	return feet - caster.position

func _move_rig(rig: UnitRig, to: Vector2) -> void:
	var t := clampf(rig.position.distance_to(to) / RUN_SPEED, RUN_MIN, RUN_MAX)
	var tw := rig.create_tween()
	tw.tween_property(rig, "position", to, t).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw.finished

## Draw the runner above every other unit for the trip (combat re-sorts on return).
func _raise(caster: BattleCharacter) -> void:
	var par := caster.get_parent()
	if par and par == panel:
		# above the other units, but keep anything added after the units (the wheel,
		# live numbers) where it is: sit just after the last unit.
		var last := 0
		for c in par.get_children():
			if c is BattleCharacter:
				last = maxi(last, c.get_index())
		par.move_child(caster, last)

func _to_panel(global_pt: Vector2) -> Vector2:
	return panel.get_global_transform().affine_inverse() * global_pt if panel else global_pt

func _alive_scene(rig: UnitRig) -> bool:
	return is_instance_valid(rig) and rig.is_inside_tree()
