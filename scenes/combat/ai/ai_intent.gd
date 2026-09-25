extends RefCounted
class_name AIIntent

## ============================================================================
## AI INTENT  —  LAYER 1: which of four things do I want to do?  (AI_PRIMER §7)
## ============================================================================
##   score[i] = 100 * ai_intent_<i>  x  a product of gain terms (§7.2)
##   non-viable intents are ZEROED (a gate, never a discount)
##   OFFENSE, when viable, never drops below OFFENSE_FLOOR — it is the default answer
## The pick is AIPick.weighted over the scores with exponent ai_decisiveness.
##
## class_name global — RESTART Godot once after adding this script.
## ----------------------------------------------------------------------------

const INTENTS := [Ability.AI_OFFENSE, Ability.AI_DEFENSE, Ability.AI_BUFF, Ability.AI_DEBUFF]
const OFFENSE_FLOOR := 12.0

## { intent: score } plus a "ledger" { intent: String } explaining each number.
static func score_all(ctx: AIContext) -> Dictionary:
	var scores := {}
	var ledger := {}
	for intent in INTENTS:
		var base := 100.0 * maxf(0.0, ctx.stat("ai_intent_" + intent))
		if not ctx.is_viable(intent):
			scores[intent] = 0.0
			ledger[intent] = "NOT VIABLE"
			continue
		var terms: Array = []
		var m := 1.0
		match intent:
			Ability.AI_OFFENSE:
				m *= _term(terms, "finisher", ctx.stat("ai_finisher"), _best_kill_fraction(ctx))
				m *= _term(terms, "shield", ctx.stat("ai_shield_aversion"), _mean_shield(ctx))
				m *= _term(terms, "bloodrage", ctx.stat("ai_bloodrage"), AISignals.missing_hp(ctx.actor))
			Ability.AI_DEBUFF:
				m *= _term(terms, "tidiness", ctx.stat("ai_tidiness"), AISignals.party_debuff_pressure(ctx.hostiles))
				m *= _term(terms, "offer", ctx.stat("ai_offer_drive"), AISignals.offer_strength(ctx, intent))
				m *= _term(terms, "resist", ctx.stat("ai_resist_awareness"), _best_resist(ctx))
			Ability.AI_BUFF:
				m *= _term(terms, "tidiness", ctx.stat("ai_tidiness"), AISignals.party_buff_pressure(ctx.allies))
				m *= _term(terms, "offer", ctx.stat("ai_offer_drive"), AISignals.offer_strength(ctx, intent))
				m *= _term(terms, "altruism", ctx.stat("ai_altruism"), _best_buff_need(ctx))
				m *= _term(terms, "retinue", ctx.stat("ai_retinue_drive"), AISignals.party_depletion(ctx))
			Ability.AI_DEFENSE:
				m *= _term(terms, "panic", ctx.stat("ai_panic"), AISignals.self_danger(ctx, ctx.actor))
				m *= _term(terms, "offer", ctx.stat("ai_offer_drive"), AISignals.offer_strength(ctx, intent))
				m *= _term(terms, "sat", ctx.stat("ai_defense_sat"),
					maxf(AISignals.shield_frac(ctx.actor), AISignals.buff_severity(ctx.actor)))
		var sc := maxf(0.0, base * m)
		if intent == Ability.AI_OFFENSE:
			sc = maxf(sc, OFFENSE_FLOOR)
		scores[intent] = sc
		ledger[intent] = "%.1f = %.1f%s" % [sc, base, "" if terms.is_empty() else " x " + " x ".join(terms)]
	return {"scores": scores, "ledger": ledger}

## One gain term: returns its factor and appends a ledger fragment when it fired.
static func _term(terms: Array, name: String, gain: float, sig: float) -> float:
	var f := AIGain.factor(gain, sig)
	if not is_equal_approx(f, 1.0):
		terms.append("%s^%.2f(%.2f)" % [name, clampf(sig, 0.0, 1.0), f])
	return f

static func _best_kill_fraction(ctx: AIContext) -> float:
	if AIGain.is_off(ctx.stat("ai_finisher")):
		return 0.0
	var best := 0.0
	for t in ctx.intent_candidates(Ability.AI_OFFENSE):
		best = maxf(best, AISignals.kill_fraction(ctx, ctx.actor, t))
	return best

static func _mean_shield(ctx: AIContext) -> float:
	var c := ctx.intent_candidates(Ability.AI_OFFENSE)
	if c.is_empty():
		return 0.0
	var t := 0.0
	for u in c:
		t += AISignals.shield_frac(u)
	return t / float(c.size())

static func _best_resist(ctx: AIContext) -> float:
	if not AISignals.is_smart(ctx):
		return 0.0
	var best := 1.0
	var any := false
	for t in ctx.intent_candidates(Ability.AI_DEBUFF):
		any = true
		best = minf(best, AISignals.resist_chance(ctx, ctx.actor, t))
	return best if any else 0.0

static func _best_buff_need(ctx: AIContext) -> float:
	var best := 0.0
	for t in ctx.intent_candidates(Ability.AI_BUFF):
		var need := 0.50 * AISignals.missing_hp(t) + 0.30 * AISignals.debuff_severity(t) \
			+ 0.20 * (1.0 - AISignals.buff_severity(t))
		best = maxf(best, clampf(need, 0.0, 1.0))
	return best
