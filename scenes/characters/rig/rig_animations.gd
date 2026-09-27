class_name RigAnimations
extends RefCounted

## ============================================================================
## RIG ANIMATIONS  —  the code-built default clips  (class_name global, static)
## ============================================================================
## So the rig moves before any clip has been keyframed. install() adds these as the
## "auto" library on a rig's AnimationPlayer; UnitRig.resolve_clip prefers a clip of
## the same name in the scene's OWN library, so the moment the dev keyframes "idle"
## (or "attack_blade") in humanoid_rig.tscn, that one plays instead. RIG_SPEC §5.
##
## Every value here is a DELTA from the bone's rest pose (read off the rig), so the
## clips survive the rest pose being re-posed in the editor. Built once per rig scene
## and shared by every instance of it.
##
## THE CLIPS (humanoid): idle (loop), run (loop), attack (cue impact), windup (cue
## release), cast_self (cue release), hit, dodge, down + death + victory (HELD — the
## rig stays in the last frame, UnitRig.HOLD_CLIPS), rise (down -> standing), stun
## (loop; the idle while stunned).
## WEAPON-CLASS SETS (Stage 3, after Sonny 2's Attack / Attack_Upper / Attack_Stab /
## attack2 / cast labels — claude/SONNY2_INTERNALS.md): attack_blade = "attack" (the
## slash), attack_blunt (overhead smash), attack_polearm (lunge + stab),
## attack_unarmed (punch), attack2 (the quick follow-up strike of a MULTI-HIT melee),
## windup_gun (aim + recoil), windup_bow (draw + loose), windup_staff (raise + point),
## fire (a quick re-shot: every ranged hit after the first). Any class without its
## own clip falls back to attack / windup (UnitRig.resolve_clip). Bones a clip does
## not name are left at rest — UnitRig.play() snaps to rest before every clip.
##
## class_name global — RESTART Godot once after adding this file.
## ----------------------------------------------------------------------------

static var _cache: Dictionary = {}   # rig scene path -> AnimationLibrary

static func install(anim: AnimationPlayer, rig: UnitRig) -> void:
	if anim.has_animation_library(UnitRig.AUTO_LIB):
		return
	var key := rig.scene_file_path
	var lib: AnimationLibrary = _cache.get(key, null)
	if lib == null:
		lib = build(rig)
		if key != "":
			_cache[key] = lib
	anim.add_animation_library(UnitRig.AUTO_LIB, lib)

static func build(rig: UnitRig) -> AnimationLibrary:
	var lib := AnimationLibrary.new()
	if rig.plan == RigPlans.HUMANOID or rig.plan == &"":
		_humanoid(lib, rig)
	return lib

# ---- the humanoid set ------------------------------------------------------------
static func _humanoid(lib: AnimationLibrary, rig: UnitRig) -> void:
	# IDLE — breathing: the torso rises a touch, the arms drift.
	var c := _Clip.new(rig, 1.6, true)
	c.pos(&"torso", [[0.0, Vector2.ZERO], [0.8, Vector2(0, 1.6)], [1.6, Vector2.ZERO]])
	c.rot(&"torso", [[0.0, 0.0], [0.8, -0.02], [1.6, 0.0]])
	c.rot(&"head", [[0.0, 0.0], [0.8, 0.04], [1.6, 0.0]])
	c.rot(&"upper_arm_near", [[0.0, 0.0], [0.8, -0.06], [1.6, 0.0]])
	c.rot(&"forearm_near", [[0.0, 0.0], [0.8, -0.05], [1.6, 0.0]])
	c.rot(&"upper_arm_far", [[0.0, 0.0], [0.8, 0.05], [1.6, 0.0]])
	lib.add_animation(&"idle", c.anim)

	# RUN — a loop for the dash to a melee target (Stage 2).
	c = _Clip.new(rig, 0.5, true)
	c.rot(&"torso", [[0.0, 0.15], [0.5, 0.15]])
	c.pos(&"hip", [[0.0, Vector2.ZERO], [0.125, Vector2(0, -3)], [0.25, Vector2.ZERO], [0.375, Vector2(0, -3)], [0.5, Vector2.ZERO]])
	c.rot(&"thigh_near", [[0.0, -0.6], [0.25, 0.5], [0.5, -0.6]])
	c.rot(&"thigh_far", [[0.0, 0.5], [0.25, -0.6], [0.5, 0.5]])
	c.rot(&"calf_near", [[0.0, 0.2], [0.125, 0.9], [0.25, 0.15], [0.5, 0.2]])
	c.rot(&"calf_far", [[0.0, 0.15], [0.25, 0.2], [0.375, 0.9], [0.5, 0.15]])
	c.rot(&"upper_arm_near", [[0.0, 0.6], [0.25, -0.6], [0.5, 0.6]])
	c.rot(&"upper_arm_far", [[0.0, -0.6], [0.25, 0.6], [0.5, -0.6]])
	c.rot(&"forearm_near", [[0.0, -0.6], [0.5, -0.6]])
	c.rot(&"forearm_far", [[0.0, -0.6], [0.5, -0.6]])
	lib.add_animation(&"run", c.anim)

	# ATTACK — raise, strike, recover. IMPACT on the strike.
	c = _Clip.new(rig, 0.6, false)
	c.rot(&"upper_arm_near", [[0.0, 0.0], [0.18, 2.0], [0.3, -1.2], [0.42, -1.1], [0.6, 0.0]])
	c.rot(&"forearm_near", [[0.0, 0.0], [0.18, -0.6], [0.3, 0.3], [0.6, 0.0]])
	c.rot(&"weapon_main", [[0.0, 0.0], [0.18, -0.3], [0.3, 0.6], [0.6, 0.0]])
	c.rot(&"torso", [[0.0, 0.0], [0.18, -0.12], [0.3, 0.18], [0.6, 0.0]])
	c.rot(&"head", [[0.0, 0.0], [0.3, -0.1], [0.6, 0.0]])
	c.rot(&"upper_arm_far", [[0.0, 0.0], [0.18, -0.4], [0.3, 0.5], [0.6, 0.0]])
	c.rot(&"thigh_near", [[0.0, 0.0], [0.3, -0.25], [0.6, 0.0]])
	c.rot(&"calf_near", [[0.0, 0.0], [0.3, 0.2], [0.6, 0.0]])
	c.cue(0.3, &"impact")
	lib.add_animation(&"attack", c.anim)

	# WINDUP — the ranged / spell gesture: draw back, thrust the arm at the target.
	# RELEASE when the effect or projectile should leave.
	c = _Clip.new(rig, 0.7, false)
	c.rot(&"upper_arm_near", [[0.0, 0.0], [0.22, 0.5], [0.4, -1.45], [0.55, -1.35], [0.7, 0.0]])
	c.rot(&"forearm_near", [[0.0, 0.0], [0.22, -0.5], [0.4, 0.35], [0.7, 0.0]])
	c.rot(&"torso", [[0.0, 0.0], [0.22, -0.1], [0.4, 0.08], [0.7, 0.0]])
	c.rot(&"upper_arm_far", [[0.0, 0.0], [0.4, 0.5], [0.7, 0.0]])
	c.cue(0.4, &"release")
	lib.add_animation(&"windup", c.anim)

	# CAST_SELF — both arms up (a buff, heal or shield). RELEASE at the top.
	c = _Clip.new(rig, 0.6, false)
	c.rot(&"upper_arm_near", [[0.0, 0.0], [0.25, -2.2], [0.45, -2.2], [0.6, 0.0]])
	c.rot(&"upper_arm_far", [[0.0, 0.0], [0.25, -2.3], [0.45, -2.3], [0.6, 0.0]])
	c.rot(&"forearm_near", [[0.0, 0.0], [0.25, 0.3], [0.6, 0.0]])
	c.rot(&"forearm_far", [[0.0, 0.0], [0.25, 0.3], [0.6, 0.0]])
	c.rot(&"head", [[0.0, 0.0], [0.25, -0.15], [0.6, 0.0]])
	c.pos(&"torso", [[0.0, Vector2.ZERO], [0.25, Vector2(0, -2)], [0.6, Vector2.ZERO]])
	c.cue(0.25, &"release")
	lib.add_animation(&"cast_self", c.anim)

	# HIT — a flinch back.
	c = _Clip.new(rig, 0.35, false)
	c.rot(&"torso", [[0.0, 0.0], [0.08, -0.22], [0.35, 0.0]])
	c.pos(&"torso", [[0.0, Vector2.ZERO], [0.08, Vector2(-3, 0)], [0.35, Vector2.ZERO]])
	c.rot(&"head", [[0.0, 0.0], [0.08, -0.25], [0.35, 0.0]])
	c.rot(&"upper_arm_near", [[0.0, 0.0], [0.08, 0.4], [0.35, 0.0]])
	c.rot(&"upper_arm_far", [[0.0, 0.0], [0.08, 0.4], [0.35, 0.0]])
	lib.add_animation(&"hit", c.anim)

	# DODGE — a hop back and a lean away.
	c = _Clip.new(rig, 0.4, false)
	c.pos(&"hip", [[0.0, Vector2.ZERO], [0.12, Vector2(-16, -6)], [0.4, Vector2.ZERO]])
	c.rot(&"torso", [[0.0, 0.0], [0.12, -0.25], [0.4, 0.0]])
	c.rot(&"head", [[0.0, 0.0], [0.12, -0.15], [0.4, 0.0]])
	c.rot(&"upper_arm_near", [[0.0, 0.0], [0.12, 0.5], [0.4, 0.0]])
	c.rot(&"upper_arm_far", [[0.0, 0.0], [0.12, 0.6], [0.4, 0.0]])
	c.rot(&"thigh_near", [[0.0, 0.0], [0.12, -0.3], [0.4, 0.0]])
	lib.add_animation(&"dodge", c.anim)

	# DEATH — falls on its back and STAYS there (held).
	c = _Clip.new(rig, 0.7, false)
	c.pos(&"hip", [[0.0, Vector2.ZERO], [0.25, Vector2(-8, 30)], [0.7, Vector2(-22, 84)]])
	c.rot(&"hip", [[0.0, 0.0], [0.25, -0.4], [0.7, -1.5]])
	c.rot(&"head", [[0.0, 0.0], [0.7, -0.3]])
	c.rot(&"upper_arm_near", [[0.0, 0.0], [0.7, 0.8]])
	c.rot(&"upper_arm_far", [[0.0, 0.0], [0.7, 0.9]])
	c.rot(&"thigh_near", [[0.0, 0.0], [0.7, -0.2]])
	c.rot(&"calf_near", [[0.0, 0.0], [0.7, 0.15]])
	lib.add_animation(&"death", c.anim)

	# DOWN (held) and RISE (its reverse) — a slumped kneel, for a DOWNED unit.
	var down := {
		&"hip": Vector2(-4, 44), &"thigh_near": -1.1, &"calf_near": 2.0,
		&"thigh_far": -0.9, &"calf_far": 1.8, &"torso": 0.35, &"head": 0.35,
		&"upper_arm_near": -0.2, &"upper_arm_far": -0.15,
	}
	c = _Clip.new(rig, 0.5, false)
	for k in down:
		if down[k] is Vector2:
			c.pos(k, [[0.0, Vector2.ZERO], [0.5, down[k]]])
		else:
			c.rot(k, [[0.0, 0.0], [0.5, down[k]]])
	lib.add_animation(&"down", c.anim)
	c = _Clip.new(rig, 0.45, false)
	for k in down:
		if down[k] is Vector2:
			c.pos(k, [[0.0, down[k]], [0.45, Vector2.ZERO]])
		else:
			c.rot(k, [[0.0, down[k]], [0.45, 0.0]])
	lib.add_animation(&"rise", c.anim)

	# ---- weapon-class sets (Stage 3) ----------------------------------------------
	# NB a weapon rotates WITH the hand, so a clip that swings the arm forward
	# counter-rotates weapon_main to keep a gun / polearm pointing at the target.

	# ATTACK_BLUNT — Sonny's Attack_Upper: a slow overhead smash, crouching into it.
	c = _Clip.new(rig, 0.75, false)
	c.rot(&"upper_arm_near", [[0.0, 0.0], [0.3, 2.6], [0.42, -1.0], [0.55, -0.9], [0.75, 0.0]])
	c.rot(&"forearm_near", [[0.0, 0.0], [0.3, -0.2], [0.42, 0.35], [0.75, 0.0]])
	c.rot(&"weapon_main", [[0.0, 0.0], [0.3, -0.4], [0.42, 0.9], [0.75, 0.0]])
	c.rot(&"torso", [[0.0, 0.0], [0.3, -0.18], [0.42, 0.28], [0.75, 0.0]])
	c.pos(&"hip", [[0.0, Vector2.ZERO], [0.42, Vector2(0, 4)], [0.75, Vector2.ZERO]])
	c.rot(&"thigh_near", [[0.0, 0.0], [0.42, -0.3], [0.75, 0.0]])
	c.rot(&"calf_near", [[0.0, 0.0], [0.42, 0.35], [0.75, 0.0]])
	c.rot(&"upper_arm_far", [[0.0, 0.0], [0.3, -0.3], [0.42, 0.5], [0.75, 0.0]])
	c.cue(0.42, &"impact")
	lib.add_animation(&"attack_blunt", c.anim)

	# ATTACK_POLEARM — Sonny's Attack_Stab: draw back, lunge, thrust level.
	c = _Clip.new(rig, 0.55, false)
	c.rot(&"upper_arm_near", [[0.0, 0.0], [0.14, 0.5], [0.26, -1.3], [0.4, -1.25], [0.55, 0.0]])
	c.rot(&"forearm_near", [[0.0, 0.0], [0.14, -0.8], [0.26, 0.35], [0.55, 0.0]])
	c.rot(&"weapon_main", [[0.0, 0.0], [0.14, 1.5], [0.26, 2.2], [0.4, 2.2], [0.55, 0.0]])
	c.rot(&"torso", [[0.0, 0.0], [0.14, -0.08], [0.26, 0.22], [0.55, 0.0]])
	c.pos(&"hip", [[0.0, Vector2.ZERO], [0.26, Vector2(8, 0)], [0.55, Vector2.ZERO]])
	c.rot(&"thigh_near", [[0.0, 0.0], [0.26, -0.45], [0.55, 0.0]])
	c.rot(&"calf_near", [[0.0, 0.0], [0.26, 0.3], [0.55, 0.0]])
	c.cue(0.26, &"impact")
	lib.add_animation(&"attack_polearm", c.anim)

	# ATTACK_UNARMED — a quick jab.
	c = _Clip.new(rig, 0.42, false)
	c.rot(&"upper_arm_near", [[0.0, 0.0], [0.08, 0.4], [0.18, -1.35], [0.3, -1.3], [0.42, 0.0]])
	c.rot(&"forearm_near", [[0.0, 0.0], [0.08, -1.2], [0.18, 0.35], [0.42, 0.0]])
	c.rot(&"upper_arm_far", [[0.0, 0.0], [0.18, -0.6], [0.42, 0.0]])
	c.rot(&"forearm_far", [[0.0, 0.0], [0.18, -1.0], [0.42, 0.0]])
	c.rot(&"torso", [[0.0, 0.0], [0.18, 0.15], [0.42, 0.0]])
	c.pos(&"hip", [[0.0, Vector2.ZERO], [0.18, Vector2(6, 0)], [0.42, Vector2.ZERO]])
	c.cue(0.18, &"impact")
	lib.add_animation(&"attack_unarmed", c.anim)

	# ATTACK2 — Sonny's attack2: the quick backhand every melee hit after the first.
	c = _Clip.new(rig, 0.38, false)
	c.rot(&"upper_arm_near", [[0.0, 0.0], [0.06, -1.6], [0.14, 0.6], [0.38, 0.0]])
	c.rot(&"forearm_near", [[0.0, 0.0], [0.06, 0.2], [0.14, -0.4], [0.38, 0.0]])
	c.rot(&"weapon_main", [[0.0, 0.0], [0.14, -0.5], [0.38, 0.0]])
	c.rot(&"torso", [[0.0, 0.0], [0.06, 0.1], [0.14, -0.08], [0.38, 0.0]])
	c.cue(0.14, &"impact")
	lib.add_animation(&"attack2", c.anim)

	# WINDUP_GUN — raise and aim level, fire with a kick of recoil.
	c = _Clip.new(rig, 0.55, false)
	c.rot(&"upper_arm_near", [[0.0, 0.0], [0.16, -1.35], [0.28, -1.35], [0.32, -1.55], [0.42, -1.35], [0.55, 0.0]])
	c.rot(&"forearm_near", [[0.0, 0.0], [0.16, 0.35], [0.42, 0.35], [0.55, 0.0]])
	c.rot(&"weapon_main", [[0.0, 0.0], [0.16, 1.0], [0.28, 1.0], [0.32, 0.75], [0.42, 1.0], [0.55, 0.0]])
	c.rot(&"torso", [[0.0, 0.0], [0.28, 0.0], [0.32, -0.06], [0.55, 0.0]])
	c.rot(&"head", [[0.0, 0.0], [0.16, -0.05], [0.55, 0.0]])
	c.cue(0.28, &"release")
	lib.add_animation(&"windup_gun", c.anim)

	# WINDUP_BOW — bow arm out, the far hand draws to the chest and snaps free.
	c = _Clip.new(rig, 0.8, false)
	c.rot(&"upper_arm_near", [[0.0, 0.0], [0.25, -1.35], [0.6, -1.35], [0.8, 0.0]])
	c.rot(&"forearm_near", [[0.0, 0.0], [0.25, 0.35], [0.6, 0.35], [0.8, 0.0]])
	c.rot(&"weapon_main", [[0.0, 0.0], [0.25, 1.0], [0.6, 1.0], [0.8, 0.0]])
	c.rot(&"upper_arm_far", [[0.0, 0.0], [0.25, -1.3], [0.45, -1.1], [0.5, -1.2], [0.8, 0.0]])
	c.rot(&"forearm_far", [[0.0, 0.0], [0.25, 0.2], [0.45, -1.6], [0.5, 0.2], [0.8, 0.0]])
	c.rot(&"torso", [[0.0, 0.0], [0.45, -0.06], [0.8, 0.0]])
	c.cue(0.5, &"release")
	lib.add_animation(&"windup_bow", c.anim)

	# WINDUP_STAFF — Sonny's cast: raise it high, then point it at the target.
	c = _Clip.new(rig, 0.75, false)
	c.rot(&"upper_arm_near", [[0.0, 0.0], [0.25, 2.3], [0.45, -1.3], [0.6, -1.3], [0.75, 0.0]])
	c.rot(&"forearm_near", [[0.0, 0.0], [0.25, -0.2], [0.45, 0.35], [0.75, 0.0]])
	c.rot(&"weapon_main", [[0.0, 0.0], [0.45, 0.6], [0.75, 0.0]])
	c.rot(&"torso", [[0.0, 0.0], [0.25, -0.12], [0.45, 0.1], [0.75, 0.0]])
	c.rot(&"head", [[0.0, 0.0], [0.25, -0.12], [0.75, 0.0]])
	c.cue(0.45, &"release")
	lib.add_animation(&"windup_staff", c.anim)

	# FIRE — a quick re-shot from the aimed pose (ranged hits 2..N).
	c = _Clip.new(rig, 0.3, false)
	c.rot(&"upper_arm_near", [[0.0, -1.35], [0.06, -1.55], [0.18, -1.35], [0.3, 0.0]])
	c.rot(&"forearm_near", [[0.0, 0.35], [0.18, 0.35], [0.3, 0.0]])
	c.rot(&"weapon_main", [[0.0, 1.0], [0.06, 0.75], [0.18, 1.0], [0.3, 0.0]])
	c.cue(0.06, &"release")
	lib.add_animation(&"fire", c.anim)

	# STUN — Sonny's stun: slumped, the head lolling. The idle while stunned (loop).
	c = _Clip.new(rig, 1.2, true)
	c.pos(&"hip", [[0.0, Vector2(0, 3)], [1.2, Vector2(0, 3)]])
	c.rot(&"torso", [[0.0, 0.2], [0.6, 0.28], [1.2, 0.2]])
	c.rot(&"head", [[0.0, 0.3], [0.3, 0.45], [0.6, 0.3], [0.9, 0.15], [1.2, 0.3]])
	c.rot(&"upper_arm_near", [[0.0, 0.1], [0.6, 0.15], [1.2, 0.1]])
	c.rot(&"upper_arm_far", [[0.0, 0.1], [0.6, 0.05], [1.2, 0.1]])
	lib.add_animation(&"stun", c.anim)

	# VICTORY (held) — a hop and the weapon raised high.
	c = _Clip.new(rig, 0.6, false)
	c.pos(&"hip", [[0.0, Vector2.ZERO], [0.15, Vector2(0, -8)], [0.3, Vector2.ZERO]])
	c.rot(&"upper_arm_near", [[0.0, 0.0], [0.25, -2.6], [0.6, -2.6]])
	c.rot(&"forearm_near", [[0.0, 0.0], [0.25, 0.3], [0.6, 0.3]])
	c.rot(&"weapon_main", [[0.0, 0.0], [0.25, 0.3], [0.6, 0.3]])
	c.rot(&"head", [[0.0, 0.0], [0.25, -0.15], [0.6, -0.15]])
	lib.add_animation(&"victory", c.anim)

# ---- clip builder ----------------------------------------------------------------
## Keys are [time, delta] pairs; a delta is added to the bone's REST value. A bone the
## rig does not have is skipped silently (a clip written for one plan degrades on
## another instead of erroring).
class _Clip:
	var anim: Animation
	var rig: UnitRig

	func _init(p_rig: UnitRig, length: float, loop: bool) -> void:
		rig = p_rig
		anim = Animation.new()
		anim.length = length
		anim.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE

	func rot(bone_id: StringName, keys: Array) -> void:
		var b := rig.bone(bone_id)
		if b == null:
			return
		var base := rig.rest_of(b).get_rotation()
		var t := _track(b, "rotation")
		for k in keys:
			anim.track_insert_key(t, float(k[0]), base + float(k[1]))

	func pos(bone_id: StringName, keys: Array) -> void:
		var b := rig.bone(bone_id)
		if b == null:
			return
		var base := rig.rest_of(b).origin
		var t := _track(b, "position")
		for k in keys:
			anim.track_insert_key(t, float(k[0]), base + (k[1] as Vector2))

	## A METHOD key calling UnitRig.cue(name) at `time`.
	func cue(time: float, cue_name: StringName) -> void:
		var t := anim.add_track(Animation.TYPE_METHOD)
		anim.track_set_path(t, NodePath("."))
		anim.track_insert_key(t, time, {"method": &"cue", "args": [cue_name]})

	func _track(b: Bone2D, prop: String) -> int:
		var t := anim.add_track(Animation.TYPE_VALUE)
		anim.track_set_path(t, NodePath("%s:%s" % [String(rig.get_path_to(b)), prop]))
		anim.track_set_interpolation_type(t, Animation.INTERPOLATION_CUBIC)
		return t
