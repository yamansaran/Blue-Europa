class_name UnitRig
extends Node2D

## ============================================================================
## UNIT RIG  —  a posable, dressable, animated body  (class_name global)
## ============================================================================
## The ROOT SCRIPT of every rig scene (humanoid_rig.tscn today). A rig scene is:
##   UnitRig (this)
##   ├─ Skeleton2D ── Bone2D tree (names = part ids), each bone with a
##   │                RemoteTransform2D "rt" pushing its transform onto its part
##   ├─ Parts ─────── RigPart nodes, FLAT, in draw order (back -> front)
##   └─ AnimationPlayer
## RIG SPACE: feet at y = 0, facing +x, `rig_height` units tall. The owner scales it
## (fit_to) and mirrors it (set_facing). RIG_SPEC §2-§5.
##
## WHAT IT DOES: dress(body) — skin + gear from a CharacterBase; play(clip) with
## fallbacks; `cued(name)` when a clip's method track calls cue(); wait_cue() for
## combat to sync on (Stage 2). Presentation only — it never touches stats.
##
## CLIPS: anything keyframed in the scene's own AnimationPlayer (default library)
## wins; RigAnimations fills every clip the scene lacks into the "auto" library.
##
## class_name global — RESTART Godot once after adding this file.
## ----------------------------------------------------------------------------

signal cued(cue_name: StringName)
## A NON-looping clip ended (the rig then returns to idle by itself).
signal clip_finished(clip: StringName)

const AUTO_LIB := &"auto"
const IDLE := &"idle"
## Clips that END IN A POSE: when they finish the rig stays in the last frame instead
## of returning to idle (death, a downed slump). play() anything to leave it.
const HOLD_CLIPS := [&"death", &"down", &"victory"]

## Height of the figure in rig units (feet to crown, weapons excluded).
@export var rig_height: float = 190.0

var plan: StringName = &""
var facing: float = 1.0
var _parts: Dictionary = {}          # part_id -> RigPart
var _bones: Dictionary = {}          # part_id -> Bone2D
var _rest: Dictionary = {}           # Bone2D -> Transform2D (captured at _ready)
var _draw_order: Array = []          # default child order of Parts
var _anim: AnimationPlayer = null
var _current: StringName = &""
## The resting loop: IDLE normally, &"stun" while stunned (set_idle).
var idle_clip: StringName = IDLE
var _flash: Tween = null

## Instance the rig scene for a body plan. null = unknown plan / broken scene (the
## caller keeps its rectangle).
static func create(plan_id: StringName) -> UnitRig:
	var path := RigPlans.scene_path(plan_id)
	if path == "":
		push_warning("UnitRig: unknown body plan '%s'." % plan_id)
		return null
	var ps = load(path)
	if not (ps is PackedScene):
		push_warning("UnitRig: cannot load %s." % path)
		return null
	var r = (ps as PackedScene).instantiate()
	if not (r is UnitRig):
		push_warning("UnitRig: %s's root is not a UnitRig." % path)
		if r:
			r.free()
		return null
	(r as UnitRig).plan = plan_id
	return r

func _ready() -> void:
	var parts_node := get_node_or_null("Parts")
	if parts_node:
		for p in parts_node.get_children():
			if p is RigPart:
				_parts[(p as RigPart).part_id] = p
				_draw_order.append(p)
	var skel := get_node_or_null("Skeleton2D")
	if skel:
		_collect_bones(skel)
	_anim = get_node_or_null("AnimationPlayer")
	if _anim:
		RigAnimations.install(_anim, self)
		_anim.animation_finished.connect(_on_animation_finished)
	play(IDLE)
	queue_redraw()

func _collect_bones(n: Node) -> void:
	for c in n.get_children():
		if c is Bone2D:
			_bones[StringName(c.name)] = c
			_rest[c] = (c as Bone2D).transform
			_collect_bones(c)

# ---- queries --------------------------------------------------------------------
func part(part_id: StringName) -> RigPart:
	return _parts.get(part_id, null)

func bone(part_id: StringName) -> Bone2D:
	return _bones.get(part_id, null)

func part_ids() -> Array:
	return _parts.keys()

## The rest transform captured when the rig was built (what clips are relative to).
func rest_of(b: Bone2D) -> Transform2D:
	return _rest.get(b, b.transform)

## A socket's GLOBAL position (Stage 2: where a projectile leaves).
func socket_global_position(socket: StringName = &"weapon_main") -> Vector2:
	var p := part(socket)
	return p.global_position if p else global_position

# ---- placement -------------------------------------------------------------------
## +1 = face right (the party), -1 = face left (the foes).
func set_facing(dir: float) -> void:
	facing = -1.0 if dir < 0.0 else 1.0
	scale.x = absf(scale.x) * facing

## Scale to a `box` of this height and stand the feet on its bottom-centre.
func fit_to(box: Vector2) -> void:
	var s := box.y / maxf(rig_height, 1.0)
	scale = Vector2(s * facing, s)
	position = Vector2(box.x * 0.5, box.y)

# ---- dressing --------------------------------------------------------------------
## Paint the body: its skin (or the placeholder in its model colour), then every
## piece of gear in body.rig_gear {slot_key: item_id}. Safe to call again.
func dress(body: CharacterBase) -> void:
	for p in _parts.values():
		(p as RigPart).clear_layers()
	var base := body.model_color() if body else Color(0.6, 0.6, 0.6)
	var skin: RigSkin = body.skin if body else null
	for id in _parts.keys():
		var p: RigPart = _parts[id]
		if p.shape == RigPart.Shape.SOCKET:
			continue
		p.set_base_color(_placeholder_color(id, base))
		var sp: RigPiece = skin.piece(id) if skin else null
		if sp:
			if sp.color.a > 0.0:
				p.set_base_color(sp.color)
			if sp.texture:
				p.add_image(sp.texture, sp.offset, sp.scale, deg_to_rad(sp.rotation_degrees), sp.tint)
				p.base_hidden = true
				p.queue_redraw()
	if body:
		for slot_key in body.rig_gear.keys():
			_wear(str(slot_key), StringName(str(body.rig_gear[slot_key])))

## Near-side parts in the model colour; far-side ones a shade darker (depth); head
## and hands lighter (reads as skin against clothes).
func _placeholder_color(id: StringName, base: Color) -> Color:
	var s := String(id)
	var c := base
	if s == "head" or s.begins_with("hand"):
		c = base.lightened(0.45)
	if s.ends_with("_far"):
		c = c.darkened(0.22)
	return c

func _wear(slot_key: String, item_id: StringName) -> void:
	if item_id == &"":
		return
	var item = _item(item_id)
	var look: ItemLook = null
	if item != null and item.get("look") is ItemLook:
		look = item.get("look")
	var covered: Array = RigPlans.covers(plan, slot_key)
	# Weapon sockets.
	if slot_key == "weapon_main" or slot_key == "weapon_off":
		for sid in covered:
			var sock := part(sid)
			if sock == null:
				continue
			var cls := RigPlans.weapon_class_of(item)
			var accent: Color = item.rarity_color() if item != null and item.has_method("rarity_color") else Color(0.9, 0.75, 0.3)
			var textured := look != null and look.texture != null
			var L := look.length if look != null and look.length > 0.0 else RigPlans.weapon_length(cls)
			sock.set_socket(cls, L, accent, textured)
			if textured:
				var ang := float(RigPart.CLASS_ANGLE.get(cls, 0.0)) + deg_to_rad(look.angle_degrees)
				sock.add_image(look.texture, Vector2.ZERO, Vector2.ONE, ang, look.tint, look.grip)
		return
	# Armour: the look's own pieces first; any covered part it does not dress gets
	# the placeholder tint (so a look with a helmet image and nothing else still
	# reads as a helmet on a mannequin).
	var gear_col := Stats.name_to_color(String(item_id))
	var dressed := {}
	if look:
		for k in look.pieces.keys():
			var pid := StringName(str(k))
			var pc: RigPiece = look.piece(pid)
			var p := part(pid)
			if p == null or pc == null:
				continue
			dressed[pid] = true
			if pc.texture:
				p.add_image(pc.texture, pc.offset, pc.scale, deg_to_rad(pc.rotation_degrees), pc.tint)
				if pc.hides_base:
					p.base_hidden = true
					p.queue_redraw()
			else:
				_tint_part(p, pc.color if pc.color.a > 0.0 else gear_col, pc.hides_base)
	for pid in covered:
		if dressed.has(pid):
			continue
		var p2 := part(pid)
		if p2:
			_tint_part(p2, gear_col if not String(pid).ends_with("_far") else gear_col.darkened(0.22), false)

func _tint_part(p: RigPart, col: Color, hide_base: bool) -> void:
	var g := p.gear_colors.duplicate()
	g.append(col)
	p.set_gear(g, hide_base or p.base_hidden)

func _item(item_id: StringName):
	var db := get_node_or_null("/root/ItemDB")
	if db and db.has_method("get_item"):
		return db.get_item(item_id)
	return null

# ---- draw order --------------------------------------------------------------------
## Reorder the Parts list: `ids` are moved, in the order given, to the FRONT (or the
## back when to_front is false). Clips call this from a method track; play() puts
## the default order back.
func set_draw_order(ids: Array, to_front: bool = true) -> void:
	var parts_node := get_node_or_null("Parts")
	if parts_node == null:
		return
	for id in ids:
		var p := part(StringName(str(id)))
		if p:
			parts_node.move_child(p, parts_node.get_child_count() - 1 if to_front else 0)

func reset_draw_order() -> void:
	var parts_node := get_node_or_null("Parts")
	if parts_node == null:
		return
	for i in _draw_order.size():
		parts_node.move_child(_draw_order[i], i)

# ---- clips -----------------------------------------------------------------------
## The clip name that will actually play for `clip`: the scene's own clip, else the
## auto one, else the same with the "_suffix" stripped (attack_blade -> attack).
## &"" = nothing to play.
func resolve_clip(clip: StringName) -> StringName:
	if _anim == null:
		return &""
	var tries: Array = [String(clip)]
	var s := String(clip)
	var cut := s.find("_")
	if cut > 0:
		tries.append(s.substr(0, cut))
	for t in tries:
		if _anim.has_animation(t):
			return StringName(t)
		var auto := "%s/%s" % [AUTO_LIB, t]
		if _anim.has_animation(auto):
			return StringName(auto)
	return &""

func has_clip(clip: StringName) -> bool:
	return resolve_clip(clip) != &""

## Play a clip from its start (the pose snaps back to rest first, so a clip cut off
## halfway never leaves a limb bent). Non-looping clips fall back to idle when they
## end. Returns false when there is nothing to play.
func play(clip: StringName) -> bool:
	var real := resolve_clip(clip)
	if real == &"":
		return false
	reset_pose()
	reset_draw_order()
	_current = real
	_anim.play(real)
	_anim.seek(0.0, true)
	return true

func play_idle() -> void:
	play(idle_clip)

## Change the resting loop (stun <-> idle). Switches at once only when the rig is
## currently resting — an attack or a flinch finishes first and then lands on it.
func set_idle(clip: StringName) -> void:
	if clip == idle_clip:
		return
	var was_resting := _current == resolve_clip(idle_clip)
	idle_clip = clip if has_clip(clip) else IDLE
	if was_resting:
		play_idle()

## Freeze in the current pose (dead / downed). play() starts it moving again.
func hold_still() -> void:
	if _anim:
		_anim.pause()

func current_clip() -> StringName:
	return _current

func clip_length(clip: StringName) -> float:
	var real := resolve_clip(clip)
	return _anim.get_animation(real).length if real != &"" else 0.0

## Put every bone back at its rest transform.
func reset_pose() -> void:
	for b in _rest.keys():
		if is_instance_valid(b):
			(b as Bone2D).transform = _rest[b]

func _on_animation_finished(anim_name: StringName) -> void:
	var a: Animation = _anim.get_animation(anim_name) if _anim else null
	if a and a.loop_mode != Animation.LOOP_NONE:
		return
	clip_finished.emit(anim_name)
	# "auto/death" -> "death"; a scene clip "death_fire" -> "death" too.
	var base := String(anim_name).get_file()
	var cut := base.find("_")
	if cut > 0:
		base = base.substr(0, cut)
	if StringName(base) in HOLD_CLIPS:
		return
	if resolve_clip(idle_clip) != anim_name:
		play_idle()

## Wait for the current NON-looping clip to end, at most `timeout` seconds. Returns
## at once when nothing (or a loop) is playing.
func wait_finish(timeout: float = 1.2) -> void:
	if _anim == null or not _anim.is_playing():
		return
	var a: Animation = _anim.get_animation(_anim.current_animation)
	if a == null or a.loop_mode != Animation.LOOP_NONE:
		return
	var done := [false]
	var cb := func(_n: StringName) -> void:
		done[0] = true
	clip_finished.connect(cb)
	var t := 0.0
	while not done[0] and t < timeout and is_inside_tree():
		await get_tree().process_frame
		t += get_process_delta_time()
	if clip_finished.is_connected(cb):
		clip_finished.disconnect(cb)

# ---- cues ------------------------------------------------------------------------
## Called by a clip's METHOD TRACK at its moment (impact, release, step). Combat
## listens for these; it never times itself off clip lengths. RIG_SPEC §5.
func cue(cue_name: StringName) -> void:
	cued.emit(cue_name)

## Wait for a cue, at most `timeout` seconds. true = the cue fired; false = timed out
## (a clip without that cue) — the caller carries on either way, so a missing cue
## can never hang a turn.
func wait_cue(cue_name: StringName, timeout: float = 1.2) -> bool:
	var got := [false]
	var cb := func(n: StringName) -> void:
		if n == cue_name:
			got[0] = true
	cued.connect(cb)
	var t := 0.0
	while not got[0] and t < timeout and is_inside_tree():
		await get_tree().process_frame
		t += get_process_delta_time()
	if cued.is_connected(cb):
		cued.disconnect(cb)
	return got[0]

# ---- feedback --------------------------------------------------------------------
## A quick white flash (a landed hit), on each PART's modulate — so image layers
## flash too, and the owner's own modulate (dead / downed greying) still applies.
func flash(color: Color = Color(2.2, 2.2, 2.2), time: float = 0.25) -> void:
	if _parts.is_empty():
		return
	if _flash and _flash.is_valid():
		_flash.kill()
	_flash = create_tween().set_parallel(true)
	for p in _parts.values():
		(p as CanvasItem).modulate = color
		_flash.tween_property(p, "modulate", Color.WHITE, time)

# ---- debug -----------------------------------------------------------------------
## DEBUG (GameManager.is_debug): a small cross on the FEET point — the rig's origin,
## where fit_to stands it.
func _draw() -> void:
	var gm := get_node_or_null("/root/GameManager")
	if gm == null or not gm.has_method("is_debug") or not gm.is_debug():
		return
	var k := 6.0 / maxf(absf(scale.y), 0.01)
	draw_line(Vector2(-k, 0), Vector2(k, 0), Color(1, 0, 1), 1.5 / maxf(absf(scale.y), 0.01))
	draw_line(Vector2(0, -k), Vector2(0, k), Color(1, 0, 1), 1.5 / maxf(absf(scale.y), 0.01))
