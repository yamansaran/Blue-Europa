extends RefCounted
class_name AITarget

## ============================================================================
## AI TARGET  —  LAYER 2: which unit?  (AI_PRIMER §8)
## ============================================================================
## Every candidate's MAGNETISM is COPIED (never written — a taunt must not be consumed
## by being read), bent by the intent's wiring through AIGain.apply, floored at
## MIN_MAGNETISM, and picked by roulette with exponent ai_focus.
## DEFENSE short-circuits: the target is the actor.
##
## AN AoE STILL COMES THROUGH HERE and still picks a unit. That is deliberate and
## harmless: combat._affected_targets ignores the nomination and sweeps the side, so
## the pick only decides which unit the log names first. The place an area ability is
## actually valued is Layer 3 (AIAbility.is_area), which sums over the whole set.
##
## A term whose GAIN is 1.0 is skipped before its signal is computed — most creatures
## leave most gains off, and that is the estimator's biggest saving (§11.3).
##
## class_name global — RESTART Godot once after adding this script.
## ----------------------------------------------------------------------------

const MIN_MAGNETISM := 1.0

## { "target": BattleCharacter|null, "ledger": Array[String] }
static func pick(ctx: AIContext, intent: String) -> Dictionary:
	if intent == Ability.AI_DEFENSE:
		return {"target": ctx.actor, "ledger": ["DEFENSE -> self"]}
	var cands := ctx.intent_candidates(intent)
	if cands.is_empty():
		return {"target": null, "ledger": ["no candidates"]}
	var wiring := AIRules.target_gains(ctx.ai_id, intent)
	var weights: Array = []
	var ledger: Array = []
	for u in cands:
		var cand: BattleCharacter = u
		var m := AIRules.stat(cand.body, cand.ai, "magnetism")
		var start := m
		var fired: Array = []
		for term in wiring:
			var sig_name := str(term[0])
			var gain := ctx.stat(str(term[1]))
			if AIGain.is_off(gain):
				continue
			var sig := AISignals.read(ctx, sig_name, ctx.actor, cand)
			if sig <= 0.0:
				continue
			var f := AIGain.factor(gain, sig)
			m *= f
			fired.append("%s^%.2f=%.2f" % [str(term[1]).trim_prefix("ai_"), sig, f])
		m = maxf(MIN_MAGNETISM, m)
		weights.append(m)
		ledger.append("%s %.0f -> %.0f  [%s]" % [cand.unit_name, start, m, ", ".join(fired) if not fired.is_empty() else "no terms fired"])
	var i := AIPick.weighted(weights, ctx.stat("ai_focus"))
	return {"target": cands[i] if i >= 0 else null, "ledger": ledger}
