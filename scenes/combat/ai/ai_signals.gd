extends RefCounted
class_name AISignals

## ============================================================================
## AI SIGNALS  —  the normalised readings every gain rides  (AI_PRIMER §6)
## ============================================================================
## THE ONE RULE: every signal returns 0..1, and 0 ALWAYS means "this term does
## nothing" — so pow(gain, 0) == 1 makes "not applicable" free, and gating a signal
## (ai_smart) is just returning 0.
##
## A new signal = one function here + one line in `read()`.
##
## class_name global — RESTART Godot once after adding this script.
## ----------------------------------------------------------------------------

const SEVERITY_REFERENCE := 4.0
const OFFER_REFERENCE := 3.0
const DUR_REFERENCE := 4.0
const DUR_FLOOR := 0.25
const DUR_PERMANENT := 2.0
const SOFT_K := 3.0

## THE DISPATCHER. `actor` is the deciding unit, `u` the candidate being scored.
static func read(ctx: AIContext, sig: String, actor: BattleCharacter, u: BattleCharacter) -> float:
	match sig:
		"hp_frac": return hp_frac(u)
		"missing_hp": return missing_hp(u)
		"shield_frac": return shield_frac(u)
		"spirit_frac": return spirit_frac(u)
		"is_self": return 1.0 if u == actor else 0.0
		"buff_severity": return buff_severity(u)
		"debuff_severity": return debuff_severity(u)
		"lethal": return lethal(ctx, actor, u)
		"kill_fraction": return kill_fraction(ctx, actor, u)
		"threat": return threat(ctx, u, actor)
		"incoming_pressure": return incoming_pressure(ctx, u)
		"ally_power": return ally_power(ctx, u)
		"combo_ready": return combo_ready(ctx, actor, u)
		"resist_chance": return resist_chance(ctx, actor, u)
		"element_advantage": return element_advantage(ctx, actor, u)
		"softness": return softness(ctx, actor, u)
		"reputation": return reputation(ctx, u)
		"cooldown_load": return cooldown_load(u)
		"is_female": return 1.0 if u != null and u.body != null and u.body.figure == Stats.Figure.FEMALE else 0.0
		"is_child": return 1.0 if u != null and u.body != null and u.body.figure == Stats.Figure.CHILD else 0.0
	push_warning("[ai] unknown signal '%s'" % sig)
	return 0.0

# --- cheap signals -------------------------------------------------------------
static func hp_frac(u: BattleCharacter) -> float:
	if u == null:
		return 0.0
	return clampf(float(u.get_hp()) / maxf(1.0, float(u.get_max_hp())), 0.0, 1.0)

static func missing_hp(u: BattleCharacter) -> float:
	return 1.0 - hp_frac(u) if u != null else 0.0

static func shield_frac(u: BattleCharacter) -> float:
	if u == null or u.body == null:
		return 0.0
	return clampf(float(CombatShields.total(u.body)) / maxf(1.0, float(u.get_max_hp())), 0.0, 1.0)

static func spirit_frac(u: BattleCharacter) -> float:
	if u == null or u.get_max_spirit() <= 0:
		return 0.0
	return clampf(float(u.get_spirit()) / float(u.get_max_spirit()), 0.0, 1.0)

static func cooldown_load(u: BattleCharacter) -> float:
	if u == null or u.loadout.is_empty():
		return 0.0
	var cooling := 0
	var slots := 0
	for i in u.loadout.size():
		if str(u.loadout[i]) == "":
			continue
		slots += 1
		if u.on_cooldown(i):
			cooling += 1
	return float(cooling) / float(maxi(1, slots))

# --- severity (§10.1) ------------------------------------------------------------
static func duration_factor(e: Dictionary) -> float:
	var d := int(e.get("duration", -1))
	if d < 0:
		return DUR_PERMANENT
	return clampf(float(d) / DUR_REFERENCE, DUR_FLOOR, 1.0)

## magnitude x weight x stacks x potency x duration, for one entry.
static func entry_severity(e: Dictionary) -> float:
	return float(e.get("magnitude", 1.0)) * float(e.get("weight", 1.0)) * float(maxi(1, int(e.get("stacks", 1)))) \
		* float(e.get("potency_applied", 1.0)) * duration_factor(e)

static func severity_raw(body: CharacterBase, basket: String) -> float:
	if body == null or not body.baskets.has(basket):
		return 0.0
	var total := 0.0
	for e in body.baskets[basket]:
		if typeof(e) == TYPE_DICTIONARY and bool((e as Dictionary).get("visible", true)):
			total += entry_severity(e)
	return total

static func buff_severity(u: BattleCharacter) -> float:
	return AIGain.squash(severity_raw(u.body, "buffs"), SEVERITY_REFERENCE) if u and u.body else 0.0

static func debuff_severity(u: BattleCharacter) -> float:
	return AIGain.squash(severity_raw(u.body, "debuffs"), SEVERITY_REFERENCE) if u and u.body else 0.0

static func party_buff_pressure(units: Array) -> float:
	return _mean(units, "buff")

static func party_debuff_pressure(units: Array) -> float:
	return _mean(units, "debuff")

static func _mean(units: Array, which: String) -> float:
	if units.is_empty():
		return 0.0
	var t := 0.0
	for u in units:
		t += buff_severity(u) if which == "buff" else debuff_severity(u)
	return t / float(units.size())

# --- estimator signals (§6.5) ----------------------------------------------------
static func kill_fraction(ctx: AIContext, actor: BattleCharacter, t: BattleCharacter) -> float:
	var b := AIEstimate.best_attack(ctx, actor, t)
	return clampf(float(b["expected"]) / AIEstimate.effective_hp(t, str(b["element"])), 0.0, 1.0)

static func lethal(ctx: AIContext, actor: BattleCharacter, t: BattleCharacter) -> float:
	var b := AIEstimate.best_attack(ctx, actor, t)
	if b["ability"] == null:
		return 0.0
	return 1.0 if float(b["expected"]) >= AIEstimate.effective_hp(t, str(b["element"])) else 0.0

## "What fraction of `victim` can `u` remove in one hit" (squashed).
static func threat(ctx: AIContext, u: BattleCharacter, victim: BattleCharacter) -> float:
	if u == null or victim == null:
		return 0.0
	var b := AIEstimate.best_attack(ctx, u, victim)
	return AIGain.squash(float(b["expected"]) / AIEstimate.effective_hp(victim, ""))

static func incoming_pressure(ctx: AIContext, u: BattleCharacter) -> float:
	var key := "press|%d" % u.get_instance_id()
	if ctx.cache.has(key):
		return float(ctx.cache[key])
	var total := 0.0
	for other in ctx.combat._units:
		var h: BattleCharacter = other
		if h.is_alive() and ctx.combat._is_hostile(h, u):
			var b := AIEstimate.best_attack(ctx, h, u)
			total += float(b["expected"]) / AIEstimate.effective_hp(u, "")
	var v := AIGain.squash(total)
	ctx.cache[key] = v
	return v

static func ally_power(ctx: AIContext, u: BattleCharacter) -> float:
	var best_h: BattleCharacter = null
	var best_m := -1.0
	for other in ctx.combat._units:
		var h: BattleCharacter = other
		if h.is_alive() and ctx.combat._is_hostile(u, h):
			var m := AIRules.stat(h.body, h.ai, "magnetism")
			if m > best_m:
				best_m = m
				best_h = h
	if best_h == null:
		return 0.0
	var b := AIEstimate.best_attack(ctx, u, best_h)
	return AIGain.squash(float(b["expected"]) / AIEstimate.effective_hp(best_h, ""))

static func self_danger(ctx: AIContext, a: BattleCharacter) -> float:
	return clampf(0.50 * missing_hp(a) + 0.25 * debuff_severity(a) + 0.25 * incoming_pressure(ctx, a), 0.0, 1.0)

static func softness(ctx: AIContext, actor: BattleCharacter, t: BattleCharacter) -> float:
	var mean := AIEstimate.mean_attack(ctx, actor, t)
	if mean <= 0.0:
		return 0.0
	var hits := AIEstimate.effective_hp(t, "") / maxf(1.0, mean)
	return SOFT_K / (SOFT_K + hits)

## WHO HAS BEEN CARRYING THE PARTY, as a share of the leader (AI_PRIMER §6.8):
##   tier 1  PERSISTED — Character.damage_history, over the fights in the ACTOR's
##           window (ai_memory_from / ai_memory_span; the Enforcer reads the newest
##           fight only). Used only when the actor has a memory (span > 0) AND `u`
##           took part in a fight in that window — only the player and companions are
##           ever recorded, so an enemy candidate always drops through.
##   tier 2  this fight's damage_dealt, relative to its own side's leader;
##   tier 3  the live threat estimate against the actor (turn one of a fresh fight).
## Each tier normalises against ITS OWN leader, so a window with history is never
## compared against in-fight numbers.
static func reputation(ctx: AIContext, u: BattleCharacter) -> float:
	var span := int(round(ctx.stat("ai_memory_span")))
	if span > 0 and u != null:
		var from := maxi(0, int(round(ctx.stat("ai_memory_from"))))
		var mine := remembered_damage(ctx, u, from, span)
		if mine >= 0.0:
			var top := 0.0
			for other in ctx.combat._units:
				var o: BattleCharacter = other
				if (o.team == ctx.combat.TEAM_ENEMY) == (u.team == ctx.combat.TEAM_ENEMY):
					top = maxf(top, remembered_damage(ctx, o, from, span))
			return clampf(mine / top, 0.0, 1.0) if top > 0.0 else 0.0
	var best := 0.0
	for other in ctx.combat._units:
		var o: BattleCharacter = other
		if (o.team == ctx.combat.TEAM_ENEMY) == (u.team == ctx.combat.TEAM_ENEMY):
			best = maxf(best, o.damage_dealt)
	if best > 0.0:
		return clampf(u.damage_dealt / best, 0.0, 1.0)
	return threat(ctx, u, ctx.actor)

## Mean recorded damage for `u` over the window, or -1.0 with no record (not the
## player or a companion, or absent from every fight in the window). Memoised per
## decision in ctx.cache — the history is parsed once, not once per candidate.
static func remembered_damage(ctx: AIContext, u: BattleCharacter, from: int, span: int) -> float:
	if u == null or u.team == ctx.combat.TEAM_ENEMY:
		return -1.0
	if u != ctx.combat._player and (u.body == null or not u.body.companion):
		return -1.0
	var ck := "mem:%d:%d:%s" % [from, span, u.history_key()]
	if ctx.cache.has(ck):
		return float(ctx.cache[ck])
	var v := -1.0
	var ch = ctx.combat.get_node_or_null("/root/Character")
	if ch != null and ch.has_method("damage_in_window"):
		v = float(ch.damage_in_window(u.history_key(), from, span))
	ctx.cache[ck] = v
	return v

static func combo_ready(ctx: AIContext, actor: BattleCharacter, t: BattleCharacter) -> float:
	for p in ctx.pairs:
		var ab: Ability = p["ability"]
		for elem in [String(ab.consume_debuff_element), String(ab.damage_per_debuff_element), String(ab.pierce_per_debuff_element)]:
			if elem != "" and CombatBuffs.count_debuffs_of_element(t.body, elem) > 0:
				return 1.0
	return 0.0

# --- the ai_smart-gated signals (§12) ----------------------------------------------
static func is_smart(ctx: AIContext) -> bool:
	return ctx.stat("ai_smart") >= 0.5

static func resist_chance(ctx: AIContext, actor: BattleCharacter, t: BattleCharacter) -> float:
	if not is_smart(ctx):
		return 0.0
	var best := 1.0
	var found := false
	for p in ctx.by_intent.get(Ability.AI_DEBUFF, []):
		var ab: Ability = p["ability"]
		var e := AIEstimate.built_entry(ctx, actor, ab, t)
		if e.is_empty():
			continue
		found = true
		best = minf(best, CombatResist.resist_chance(actor.body, t.body, e) / 100.0)
	return clampf(best, 0.0, 1.0) if found else 0.0

static func element_advantage(ctx: AIContext, actor: BattleCharacter, t: BattleCharacter) -> float:
	if not is_smart(ctx):
		return 0.0
	var b := AIEstimate.best_attack(ctx, actor, t)
	var elem := str(b["element"])
	if b["ability"] == null:
		return 0.0
	if elem == "true":
		return 1.0
	var def := t.body.get_effective(Stats.defense_key(elem)) * (1.0 + CombatBuffs.resist_mult_bonus(t.body, elem))
	var pierce := actor.body.get_effective(Stats.pierce_key(elem))
	var y := 0.03 * (pierce - def)
	var fit := 0.5 + 0.5 * (y / (1.0 + absf(y)))
	return clampf(2.0 * (fit - 0.5), 0.0, 1.0)

# --- intent-level signals ------------------------------------------------------------
## squash(best castable entry_value for `intent` / OFFER_REFERENCE). Only USABLE pairs
## count, so a cooling ability contributes nothing (§10.2).
static func offer_strength(ctx: AIContext, intent: String) -> float:
	var best := 0.0
	for p in ctx.by_intent.get(intent, []):
		var ab: Ability = p["ability"]
		var targets := ctx.intent_targets(intent, ab)
		for t in targets:
			best = maxf(best, AIEstimate.entry_value(ctx, ctx.actor, ab, t))
	return AIGain.squash(best, OFFER_REFERENCE)

static func spirit_need(a: BattleCharacter) -> float:
	return 1.0 - spirit_frac(a) if a and a.get_max_spirit() > 0 else 0.0

static func spirit_relief(ctx: AIContext, a: BattleCharacter, ab: Ability) -> float:
	var rank: int = ctx.combat._ability_rank(a, ab)
	var gain := float(ab.spirit_gain_at(rank) + ab.spirit_steal_at(rank))
	var deficit := float(a.get_max_spirit() - a.get_spirit())
	if gain <= 0.0 or deficit <= 0.0:
		return 0.0
	return clampf(gain / deficit, 0.0, 1.0)

static func party_depletion(ctx: AIContext) -> float:
	var want := ctx.stat("ai_retinue")
	if want <= 0.0:
		return 0.0
	return clampf(1.0 - float(ctx.allies.size()) / maxf(1.0, want), 0.0, 1.0)
