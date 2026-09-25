extends RefCounted
class_name AIAbility

## ============================================================================
## AI ABILITY  —  LAYER 3: which ability, against that target?  (AI_PRIMER §9)
## ============================================================================
## The set = usable pairs tagged with the intent that can legally hit the target.
## Scores land near 1.0 for "an ordinary use":
##   OFFENSE  min(expected / ehp, 1) (+ LETHAL_BONUS)  x cooldown + spirit discounts
##   DEBUFF   entry_value x (1 - resist_chance [smart only]) x novelty
##   BUFF     need_fit x entry_value
##   DEFENSE  need_fit against SELF (self_danger in place of incoming pressure)
## x ai_priority (the per-ABILITY knob), x the ai_thirst rider for Spirit refills.
## An ALL_ENEMIES / ALL_ALLIES ability is scored as the SUM over every unit it
## sweeps, not against the one unit Layer 2 nominated (AI_PRIMER §19.5).
## Picked by roulette with exponent ai_decisiveness.
##
## class_name global — RESTART Godot once after adding this script.
## ----------------------------------------------------------------------------

const LETHAL_BONUS := 1.5
const COOLDOWN_REF := 6.0
const REPEAT_NOVELTY := 0.15

## { "pair": Dictionary|null, "ledger": Array[String] }
static func pick(ctx: AIContext, intent: String, tgt: BattleCharacter) -> Dictionary:
	var pairs: Array = []
	var scores: Array = []
	var ledger: Array = []
	for p in ctx.by_intent.get(intent, []):
		var ab: Ability = p["ability"]
		if not ctx.intent_targets(intent, ab).has(tgt):
			continue
		var sc := score(ctx, intent, ab, tgt)
		pairs.append(p)
		scores.append(sc)
		ledger.append("%s %.2f" % [ab.display_name, sc])
	var i := AIPick.weighted(scores, maxf(0.0, ctx.stat("ai_decisiveness")))
	return {"pair": pairs[i] if i >= 0 else null, "ledger": ledger}

## True when this ability's value is SPREAD over a side rather than aimed at one
## unit: an ALL_ENEMIES / ALL_ALLIES ability (it hits everyone), or a random-target
## multi-hit like Spray (it hits whoever the dice pick). Either way the unit Layer 2
## nominated is not where the damage goes, so the ability is scored as the SUM over
## its legal targets — and for Spray, AIEstimate.expected_damage divides each target's
## share by the pool size, so that sum is the attack's honest total.
static func is_area(ab: Ability) -> bool:
	return ab != null and (ab.is_area_target() or ab.retargets_each_hit())

## The ability's score for this intent against the target Layer 2 picked.
##
## AN AoE IS WORTH THE SUM OF WHAT IT DOES TO EVERYONE IT HITS (AI_PRIMER §19.5).
## Layer 2 still picks a nominal unit, but an area ability ignores it and sweeps the
## whole side, so scoring it against that ONE unit undervalues it by roughly the
## number of units it would have hit — which is exactly how an AI ends up never
## reaching for the abilities it should. `intent_targets` layers the intent's own
## side rules on top of the ability's, so a BUFF-intent AoE does not count the actor
## when ai_self_buff is 0.
##
## The per-CAST multipliers — ai_priority and the ai_thirst rider — ride on the
## summed score, not on each unit's share.
static func score(ctx: AIContext, intent: String, ab: Ability, tgt: BattleCharacter) -> float:
	var sc := 0.0
	if is_area(ab):
		for u in ctx.intent_targets(intent, ab):
			sc += _score_against(ctx, intent, ab, u)
	else:
		sc = _score_against(ctx, intent, ab, tgt)
	sc *= AIContext.priority_of(ab)
	# THE UNIVERSAL RIDER: reach for Spirit when the tank is low (§9.2).
	var relief := AISignals.spirit_relief(ctx, ctx.actor, ab)
	if relief > 0.0:
		sc *= AIGain.factor(ctx.stat("ai_thirst"), AISignals.spirit_need(ctx.actor) * relief)
	return maxf(0.0, sc)

## This ability's score against ONE unit, before the per-cast multipliers above.
static func _score_against(ctx: AIContext, intent: String, ab: Ability, tgt: BattleCharacter) -> float:
	var actor := ctx.actor
	var rank: int = ctx.combat._ability_rank(actor, ab)
	var sc := 0.0
	match intent:
		Ability.AI_OFFENSE:
			var expd := AIEstimate.expected_damage(ctx, actor, tgt, ab)
			var ehp := AIEstimate.effective_hp(tgt, ab.element_key())
			sc = minf(expd / ehp, 1.0)
			if expd >= ehp:
				sc += LETHAL_BONUS
			# a damaging ability that also drops a debuff is worth a little more
			if String(ab.applies_buff) != "":
				sc += 0.25 * AIEstimate.entry_value(ctx, actor, ab, tgt)
			sc *= pow(0.5, float(ab.cooldown_at(rank)) / COOLDOWN_REF)
			sc *= pow(0.7, float(ab.spirit_cost_at(rank)) / maxf(1.0, float(actor.get_max_spirit())))
			# a Snap-shaped attack with nothing to snap still reads as a (weak) option
			sc = maxf(sc, 0.01)
		Ability.AI_DEBUFF:
			var value := AIEstimate.entry_value(ctx, actor, ab, tgt)
			if ab.kind == Ability.Kind.ATTACK:
				value += minf(AIEstimate.expected_damage(ctx, actor, tgt, ab) / AIEstimate.effective_hp(tgt, ab.element_key()), 1.0)
			var resist := AISignals.resist_chance(ctx, actor, tgt)
			sc = value * (1.0 - resist) * _novelty(ctx, actor, ab, tgt)
		Ability.AI_BUFF:
			sc = _need_fit(ctx, ab, tgt, false) * maxf(0.05, AIEstimate.entry_value(ctx, actor, ab, tgt))
		Ability.AI_DEFENSE:
			sc = _need_fit(ctx, ab, actor, true) * maxf(0.05, AIEstimate.entry_value(ctx, actor, ab, actor))
	return maxf(0.0, sc)

## How much `tgt` needs what this ability does (§9.2).
static func _need_fit(ctx: AIContext, ab: Ability, tgt: BattleCharacter, defensive: bool) -> float:
	match ab.kind:
		Ability.Kind.HEAL:
			return AISignals.missing_hp(tgt)
		Ability.Kind.SHIELD:
			var pressure := AISignals.self_danger(ctx, tgt) if defensive else AISignals.incoming_pressure(ctx, tgt)
			return maxf(0.05, pressure) * (1.0 - AISignals.shield_frac(tgt))
	if String(ab.applies_buff) == "" and ab.has_spirit_effect(1):
		return 1.0 - AISignals.spirit_frac(tgt) if tgt.get_max_spirit() > 0 else 0.0
	var fit := 1.0 - AISignals.buff_severity(tgt)
	if defensive:
		fit *= maxf(0.25, AISignals.self_danger(ctx, tgt))
	return fit

## 0.15 when the target already carries this exact non-stackable entry, else 1.0.
static func _novelty(ctx: AIContext, actor: BattleCharacter, ab: Ability, tgt: BattleCharacter) -> float:
	var e := AIEstimate.built_entry(ctx, actor, ab, tgt)
	if e.is_empty() or bool(e.get("stackable", false)):
		return 1.0
	var id := str(e.get("id", ""))
	var basket := Buff.basket_for(e)
	if tgt.body.has_entry(basket, id):
		return REPEAT_NOVELTY
	return 1.0
