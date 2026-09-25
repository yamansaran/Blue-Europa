class_name UnitOverhead
extends Control

## ============================================================================
## UNIT OVERHEAD  —  the small health / spirit / shield bars + buff strip that
## float ABOVE EVERY unit on the battlefield
## ============================================================================
## The top panel only carries the two LOADED units (FUTURE_PLANS §7 — combat._load_unit),
## so a fight with nine enemies never fills the band with nine bars. Every unit instead carries this: a
## compact HP bar, a thin spirit bar under it, a thin grey shield strip over it when
## shielded, and the unit's buffs/debuffs as small icons UNDER the bars — ONE ICON PER
## TYPE (grouped by id; several instances read "..." for turns).
##
## It is a CHILD of its BattleCharacter, anchored to the model's top-centre, so it
## follows the unit through placement, the camera zoom and the death grey-out with no
## per-frame bookkeeping. Pure display: combat pushes values through
## BattleCharacter.refresh_bar() / refresh_buffs(), exactly as it does to the big bar.
##
## Only the buff icons take the mouse (for their hover card); the bars ignore it, so a
## click on the unit behind still lands.
##
## class_name global — RESTART Godot once after adding this script.
## ----------------------------------------------------------------------------

const MIN_WIDTH := 84.0
const WIDTH_OF_MODEL := 1.05     # bar width as a multiple of the model's width
const HP_H := 8.0
const SPIRIT_H := 4.0
const SHIELD_H := 4.0
const BAR_GAP := 1.0
const ICON_GAP := 2.0
const GAP_ABOVE_MODEL := 5.0
const BAR_ANIM_TIME := 0.45

const HP_FILL := Color(0.22, 0.80, 0.34)
const HP_LOW_FILL := Color(0.90, 0.30, 0.22)     # under LOW_HP_FRAC the bar reddens
const LOW_HP_FRAC := 0.30
const SPIRIT_FILL := Color(0.26, 0.48, 0.90)
const SHIELD_FILL := Color(0.78, 0.78, 0.84)
const BACK := Color(0.06, 0.06, 0.08, 0.82)
const FRAME := Color(0, 0, 0, 0.9)

var unit: BattleCharacter = null
var buff_bar: BuffBar = null

var _hp := 0.0
var _hp_max := 1.0
var _sp := 0.0
var _sp_max := 0.0
var _shield := 0.0
var _hp_tween: Tween
var _sp_tween: Tween

func setup(p_unit: BattleCharacter) -> void:
	unit = p_unit
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.0
	anchor_bottom = 0.0
	buff_bar = BuffBar.new()
	buff_bar.group_by_id = true      # one icon per TYPE on the field (FUTURE_PLANS §6)
	add_child(buff_bar)
	buff_bar.setup(unit.body, BuffBar.SIDE_CENTER, true, 6)
	_hp = float(unit.get_hp())
	_hp_max = float(maxi(1, unit.get_max_hp()))
	_sp = float(unit.get_spirit())
	_sp_max = float(unit.get_max_spirit())
	_shield = float(unit.get_shield())
	relayout()

## Size and anchor above the model. Call after the unit's own size is final.
func relayout() -> void:
	if unit == null:
		return
	var w := maxf(MIN_WIDTH, unit.size.x * WIDTH_OF_MODEL)
	var icon_h := buff_bar.icon_size().y if buff_bar else 16.0
	var bars_h := _bars_height()
	var total := SHIELD_H + BAR_GAP + bars_h + ICON_GAP + icon_h
	offset_left = -w * 0.5
	offset_right = w * 0.5
	offset_bottom = -GAP_ABOVE_MODEL
	offset_top = -GAP_ABOVE_MODEL - total
	if buff_bar:
		buff_bar.position = Vector2(0.0, SHIELD_H + BAR_GAP + bars_h + ICON_GAP)
		buff_bar.size = Vector2(w, icon_h)
	queue_redraw()

func _bars_height() -> float:
	return HP_H + (BAR_GAP + SPIRIT_H if _sp_max > 0.0 else 0.0)

## Total height this widget occupies above the model (the hover label sits above it).
func stack_height() -> float:
	return -offset_top

func set_values(hp: int, hp_max: int, sp: int, sp_max: int, shield: int) -> void:
	var had_spirit := _sp_max > 0.0
	_hp_max = float(maxi(1, hp_max))
	_sp_max = float(maxi(0, sp_max))
	_shield = float(maxi(0, shield))
	if had_spirit != (_sp_max > 0.0):
		relayout()
	_hp_tween = _slide(_hp_tween, "_hp", float(hp))
	_sp_tween = _slide(_sp_tween, "_sp", float(sp))
	queue_redraw()

func refresh_buffs() -> void:
	if buff_bar:
		buff_bar.refresh()

func _slide(tw: Tween, prop: String, to: float) -> Tween:
	if tw and tw.is_valid():
		tw.kill()
	if not is_inside_tree():
		set(prop, to)
		return null
	var t := create_tween()
	t.tween_method(_apply_value.bind(prop), float(get(prop)), to, BAR_ANIM_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	return t

func _apply_value(v: float, prop: String) -> void:
	set(prop, v)
	queue_redraw()

func _draw() -> void:
	var w := size.x
	var y := SHIELD_H + BAR_GAP
	# shield strip (only while shielded)
	if _shield > 0.0:
		var sf := clampf(_shield / _hp_max, 0.0, 1.0)
		draw_rect(Rect2(0, 0, w, SHIELD_H), BACK)
		draw_rect(Rect2(0, 0, maxf(2.0, w * sf), SHIELD_H), SHIELD_FILL)
		draw_rect(Rect2(0, 0, w, SHIELD_H), FRAME, false, 1.0)
	# hp
	var hf := clampf(_hp / _hp_max, 0.0, 1.0)
	draw_rect(Rect2(0, y, w, HP_H), BACK)
	if hf > 0.0:
		draw_rect(Rect2(0, y, w * hf, HP_H), HP_LOW_FILL if hf < LOW_HP_FRAC else HP_FILL)
		draw_rect(Rect2(0, y, w * hf, HP_H * 0.35), Color(1, 1, 1, 0.18))   # a lit top edge
	draw_rect(Rect2(0, y, w, HP_H), FRAME, false, 1.0)
	y += HP_H + BAR_GAP
	# spirit
	if _sp_max > 0.0:
		var spf := clampf(_sp / _sp_max, 0.0, 1.0)
		draw_rect(Rect2(0, y, w, SPIRIT_H), BACK)
		if spf > 0.0:
			draw_rect(Rect2(0, y, w * spf, SPIRIT_H), SPIRIT_FILL)
		draw_rect(Rect2(0, y, w, SPIRIT_H), FRAME, false, 1.0)
