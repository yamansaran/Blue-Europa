extends RefCounted
class_name AIContext

## ============================================================================
## AI CONTEXT  —  one unit's snapshot of the battlefield, for ONE decision
## ============================================================================
## AI_PRIMER §2. Built ONCE per ACTION and thrown away after. **It is never
## reused across actions of the same turn**, and that is not an optimisation
## detail — after one action the HP moved, a debuff landed, a cooldown started and
## the action-point budget dropped. A second action decided from stale state is the
## classic bug in a multi-action routine, and rebuilding is how it is made
## impossible rather than merely avoided.
##
## What it holds:
##   actor      the deciding unit
##   allies     LIVING units on the actor's side, the actor INCLUDED
##   hostiles   LIVING units on the other side
##   pairs      every (ability, slot) the actor may legally use RIGHT NOW, each
##              tagged with the intents it serves
## Everything is filtered with combat's OWN predicates — `_can_use` (which is
## `_use_blocked` returning "") and `_valid_target`. The AI does not own a second
## copy of those rules; if it ever disagrees with the wheel's click handler, that
## is a bug in the gate, not in the AI.
##
## COOLDOWNS COME FOR FREE. `_use_blocked` already refuses a cooling slot, so a
## cooling ability is simply absent from `pairs` — which means it is absent from
## the intents it would have served, absent from the offer-strength that drives
## appetite for those intents, and absent from the ability layer's choices. One
## gate, three consequences, no cooldown-specific code anywhere in the AI.
##
## class_name global — RESTART Godot once after adding this script.
## ----------------------------------------------------------------------------

## The combat node (scenes/combat/combat.gd). Untyped on purpose: combat.gd is a
## plain `extends Control` with no class_name, so there is no type to annotate
## with, and typing it as Control would lose the method calls.
var combat = null
var actor: BattleCharacter = null

## LIVING units, split by side relative to the actor. `allies` includes the actor.
var allies: Array = []
var hostiles: Array = []

## Every legally usable (ability, slot) this instant. Each entry:
##   { "ability": Ability, "slot": int, "id": String, "intents": Array[String] }
## The SLOT IS CARRIED, never re-derived: `_use_ability(..., slot)` starts the
## cooldown on THAT slot, and passing -1 means the ability silently never cools
## down. Two copies of the same ability in two slots are two independent pairs.
var pairs: Array = []

## intent name -> Array of pair dictionaries. Built once here so the layers never
## re-scan; an intent absent from this dictionary has NO usable ability and is
## therefore not viable.
var by_intent: Dictionary = {}

## The actor's archetype id (CharacterBase.ai) — AIRules reads its preset through it.
var ai_id: String = "standard"

## Per-DECISION memo for every estimate, built buff entry and signal (AIEstimate /
## AISignals key into it). Thrown away with the context, so it can never go stale.
var cache: Dictionary = {}

## The actor's EFFECTIVE AI stat, with its archetype preset standing in for defaults.
func stat(key: String) -> float:
	return AIRules.stat(actor.body if actor else null, ai_id, key)

# ----------------------------------------------------------------------------
static func build(combat_node, unit: BattleCharacter) -> AIContext:
	var ctx := AIContext.new()
	ctx.combat = combat_node
	ctx.actor = unit
	ctx.ai_id = unit.ai if unit != null else "standard"
	if combat_node == null or unit == null or unit.body == null:
		return ctx

	for other in combat_node._units:
		var u: BattleCharacter = other
		if u == null or not u.is_alive():
			continue
		if combat_node._is_hostile(unit, u):
			ctx.hostiles.append(u)
		else:
			ctx.allies.append(u)

	ctx._build_pairs()
	return ctx

## Walk the actor's loadout IN SLOT ORDER and keep what it may legally use now.
func _build_pairs() -> void:
	var warned_passive := false
	for slot in actor.loadout.size():
		var aid := str(actor.loadout[slot])
		if aid == "":
			continue                      # the wheel's slot array is padded
		var ability: Ability = combat._get_ability(aid)
		if ability == null:
			continue
		# A PASSIVE MUST NEVER REACH THE AI. `_loadout_for` returns body.abilities
		# verbatim, so a module that lists a passive there hands us an uncastable
		# slot. Warn ONCE per decision — an authoring error worth surfacing, not
		# swallowing — and drop it.
		if ability.is_passive() or ability.is_always_active():
			if not warned_passive:
				warned_passive = true
				push_warning("[ai] %s carries the passive '%s' in its castable loadout (slot %d) — passives are not castable and are being ignored." % [actor.unit_name, aid, slot])
			continue
		# A BUFF/DEBUFF-kind ability that names NO buff cannot resolve at all:
		# `_use_ability` prints "no buff to apply", leaves `acted` false, and
		# returns WITHOUT spending an action point. An AI that chose it would come
		# back round the loop with the same budget and the same option and choose
		# it again, all the way to the action cap. `_use_blocked` does not catch
		# this — it is an authoring error, not a gameplay gate — so it is caught
		# here, where the alternative is a unit that visibly stalls its own turn.
		# EXCEPT when its whole payload is a one-time SPIRIT effect (gain / steal /
		# grant): combat's BUFF branch resolves that shape too, so it is a real
		# ability with no buff rather than an unfinished one. Haunted Choir is it.
		if (ability.kind == Ability.Kind.BUFF or ability.kind == Ability.Kind.DEBUFF) \
		and String(ability.applies_buff) == "" \
		and not ability.has_spirit_effect(1):
			push_warning("[ai] %s carries '%s', a buff/debuff-kind ability that names no applies_buff and carries no spirit effect — it can never resolve, and the AI is ignoring it." % [actor.unit_name, aid])
			continue
		# THE TURN GATE. `ai_not_before_turn` holds an ability back until the actor's
		# Nth OWN turn — "shambling corpses never open with Frenzy". It is filtered
		# here, in the usable set, rather than scored in a layer, so it is a hard rule
		# at every AI phase (including today's uniform-random Phase 0) and no amount
		# of appetite can talk a unit into breaking it. `turns_taken` is bumped at the
		# top of _begin_unit_turn, so it is already 1 during the actor's FIRST turn.
		if actor.turns_taken < ability.not_before_turn():
			continue
		if not combat._can_use(actor, ability, slot):
			continue
		var intents := AIContext.intents_of(ability)
		if intents.is_empty():
			continue                      # declared ai_intents = [] -> never chosen
		var pair := {"ability": ability, "slot": slot, "id": aid, "intents": intents}
		pairs.append(pair)
		for intent_name in intents:
			if not by_intent.has(intent_name):
				by_intent[intent_name] = []
			by_intent[intent_name].append(pair)

# ----------------------------------------------------------------------------
## The intents an ability serves: its authored `ai_intents` override when it sets
## one, else the derivation from kind + target. Tolerant of an Ability built
## before the fields existed, so nothing needs re-saving.
static func intents_of(ability: Ability) -> Array:
	if ability == null:
		return []
	if "ai_intents" in ability and not ability.ai_intents.is_empty():
		var out: Array = []
		for v in ability.ai_intents:
			out.append(str(v))
		return out
	if ability.has_method("ai_intents_default"):
		return ability.ai_intents_default()
	return []

## The per-ability AI weight (`ai_priority`), 1.0 for anything that predates it.
## 0.0 means "the AI never picks this", which is how a player-only ability can
## live on a .tres a creature also carries.
static func priority_of(ability: Ability) -> float:
	if ability != null and "ai_priority" in ability:
		return maxf(0.0, float(ability.ai_priority))
	return 1.0

# ----------------------------------------------------------------------------
## The LIVING units `ability` may legally be aimed at, from THIS actor's seat.
##
## Resolved with combat's `_valid_target`, plus one correction the AI has to make
## for itself: for ALL_ENEMIES / ALL_ALLIES that predicate returns true for ANY
## unit (it is written for the player's click path, where the clicked unit is
## already the right side), so an ALL_ENEMIES ability would otherwise read the
## actor's own allies as legal.
##
## FAN-OUT NOW EXISTS (COMBAT C4.2): combat._affected_targets sweeps the whole side
## at resolve time, so the list this returns for an area ability is the set that will
## ACTUALLY be hit, not a menu to choose one from. Layer 2 still nominates a single
## unit — an area ability simply ignores it — and Layer 3 scores the ability as the
## SUM over this list (AIAbility.is_area).
func targets_for(ability: Ability) -> Array:
	if ability == null:
		return []
	match ability.target:
		Ability.Target.SELF:
			return [actor] if actor.is_alive() else []
		Ability.Target.ALL_ENEMIES, Ability.Target.ALL_ALLIES:
			# ONE SOURCE OF TRUTH: ask combat for the exact set it will sweep at
			# resolve time. Today that is every living unit on the right side — an
			# AoE deliberately ignores back-row protection — but if that ever
			# changes, it changes in one place and the AI follows for free.
			return combat._affected_targets(actor, ability, null)
	var out: Array = []
	for u in allies + hostiles:
		if combat._valid_target(actor, ability, u):
			out.append(u)
	return out

## Does this ability have at least one legal target? Cheaper than building the
## list when all the caller wants is viability.
func has_target_for(ability: Ability) -> bool:
	return not targets_for(ability).is_empty()

## Every legal (pair, target) combination, as
## { "ability":.., "slot":.., "target":.. }. `intent` restricts to the pairs
## serving that intent; "" means every usable pair. This is the flat option space
## the Phase-0 spine picks uniformly from, and the same list the fallback ladder
## searches.
func options(intent: String = "") -> Array:
	var source: Array = pairs
	if intent != "":
		source = by_intent.get(intent, [])
	var out: Array = []
	for p in source:
		for t in targets_for(p["ability"]):
			out.append({"ability": p["ability"], "slot": int(p["slot"]), "target": t})
	return out

## The legal targets of `ability` FOR `intent` (AI_PRIMER §7.1):
##   OFFENSE / DEBUFF  hostiles only
##   BUFF              friendlies — the actor itself only when ai_self_buff > 0 or it is
##                     the last friendly standing
##   DEFENSE           the actor itself, and only if the ability can target it
func intent_targets(intent: String, ability: Ability) -> Array:
	var raw := targets_for(ability)
	var out: Array = []
	match intent:
		Ability.AI_OFFENSE, Ability.AI_DEBUFF:
			for u in raw:
				if combat._is_hostile(actor, u):
					out.append(u)
		Ability.AI_BUFF:
			var self_ok := stat("ai_self_buff") > 0.0 or allies.size() <= 1
			for u in raw:
				if combat._is_hostile(actor, u):
					continue
				if u == actor and not self_ok:
					continue
				out.append(u)
		Ability.AI_DEFENSE:
			if raw.has(actor):
				out.append(actor)
	return out

## Every distinct unit that is a legal target for at least one of `intent`'s usable abilities.
func intent_candidates(intent: String) -> Array:
	var out: Array = []
	for p in by_intent.get(intent, []):
		for u in intent_targets(intent, p["ability"]):
			if not out.has(u):
				out.append(u)
	return out

## True when the actor holds at least one usable ability serving `intent` AND a
## legal target for it under that intent's rules. The viability gate, in one call.
func is_viable(intent: String) -> bool:
	for p in by_intent.get(intent, []):
		if not intent_targets(intent, p["ability"]).is_empty():
			return true
	return false

## The most magnetic LIVING hostile — the deterministic bottom rung of the
## fallback ladder, and the proxy "who is the party's centre of gravity" that a
## couple of signals read. Null when there are no hostiles left.
func most_magnetic_hostile() -> BattleCharacter:
	var best: BattleCharacter = null
	var best_m := -1.0
	for u in hostiles:
		var m: float = AIRules.stat(u.body, u.ai, "magnetism") if u.body else 0.0
		if m > best_m:
			best = u
			best_m = m
	return best
