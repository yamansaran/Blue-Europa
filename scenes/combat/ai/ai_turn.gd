extends RefCounted
class_name AITurn

## ============================================================================
## AI TURN  —  THE RUNNER: one unit's whole turn  (AI_PRIMER §16)
## ============================================================================
## The action loop, the guards, the pacing, the fallback ladder and the debug
## ledger. Combat calls exactly one thing — `await AITurn.run(self, unit)` — and
## this owns everything from there until the unit has nothing left to do. It does
## NOT close the turn: `_begin_unit_turn` calls `_finish_turn(u)` after this
## returns, which is what schedules the unit's next slot on the timeline.
##
## >> rev33 — THE THREE LAYERS ARE LIVE. `decide()` runs INTENT (AIIntent) -> TARGET
##    (AITarget) -> ABILITY (AIAbility), each a weighted roulette over the
##    exponential gain terms of AI_PRIMER §4-§10, with the archetype read from
##    AIRules. The §16.5 fallback ladder wraps them: a layer that fails ZEROES that
##    intent and re-rolls from what is left; all four exhausted -> the best usable
##    attack on the most magnetic hostile; nothing -> pass. The Phase-0 uniform
##    picker is gone (`erratic` reproduces it with decisiveness/focus 0).
##
## WHY THE LOOP REBUILDS ITS CONTEXT EVERY ACTION: see AIContext.
##
## THE GUARDS, each of which exists because something in this codebase can
## actually cause it:
##   MAX_ACTIONS_PER_TURN  ZAP! is `action_cost 0.0, cooldown 0`. A loop that only
##                         stops when the action-point budget runs out will never
##                         stop on a unit holding a free, cooldown-free ability.
##   _ai_can_continue      combat's own predicate. It covers, in one call: the
##                         battle ending mid-turn (`_use_ability` runs
##                         `_check_victory` / `_check_defeat` internally), the
##                         actor dying to its own action (a thorns / High Voltage
##                         reflect can kill the attacker), the turn being flagged
##                         over, the actor losing the active seat, and the budget
##                         being spent. Checked before EVERY action, never once.
##   the real slot index   `_use_ability(..., slot)` starts the cooldown on THAT
##                         slot; a slot of -1 silently never cools down. Every
##                         option carries the index AIContext read it at.
##
## class_name global — RESTART Godot once after adding this script.
## ----------------------------------------------------------------------------

## Hard ceiling on actions in one turn, whatever the action-point budget says.
const MAX_ACTIONS_PER_TURN := 8

## Beat between one action and the NEXT within a single unit's turn, so a
## two-action boss reads as two decisions rather than one blur. There is no delay
## before the FIRST action: combat already waits ENEMY_THINK_DELAY before handing
## the turn over, and paying both makes an ordinary one-action enemy feel sluggish.
const AI_ACTION_DELAY := 0.45

## Mirror of combat's AP_EPSILON. Duplicated rather than read off the combat node
## so this file has no dependency on a constant it does not own; if combat's ever
## changes, this is only used to WORD a log line, never to gate an action (that is
## `_ai_can_continue`'s job, which reads the real one).
const AP_EPSILON := 0.0001

# ----------------------------------------------------------------------------
## One unit's turn. ALWAYS a coroutine, so the caller can `await` it
## unconditionally.
static func run(combat, u: BattleCharacter) -> void:
	if combat == null or u == null or u.body == null or not u.is_alive():
		return
	await combat.get_tree().process_frame

	var log_on := is_debug()
	if log_on and u.turns_taken <= 1:
		AIRules.validate(u.body, u.ai, u.unit_name)
	var actions := 0
	var stop_reason := "budget spent"

	while true:
		if not combat._ai_can_continue(u):
			stop_reason = _why_stopped(combat, u)
			break
		if actions >= MAX_ACTIONS_PER_TURN:
			stop_reason = "action cap (%d) reached" % MAX_ACTIONS_PER_TURN
			push_warning("[ai] %s hit the %d-action cap in one turn — check for a free, cooldown-free ability." % [u.unit_name, MAX_ACTIONS_PER_TURN])
			break

		# The pacing beat goes BEFORE the context is built, so the snapshot the
		# decision is made from is the state as it is at the moment of acting.
		if actions > 0:
			await combat.get_tree().create_timer(AI_ACTION_DELAY).timeout
			if not combat._ai_can_continue(u):
				stop_reason = _why_stopped(combat, u)
				break

		var ctx := AIContext.build(combat, u)
		if ctx.pairs.is_empty():
			stop_reason = "nothing usable"
			if log_on:
				_log_nothing_usable(combat, u)
			break
		var decision := decide(ctx)
		if decision.is_empty():
			stop_reason = "no legal (ability, target) pair"
			if log_on:
				print("[ai] %s found no legal target for anything it can use." % u.unit_name)
			break

		if log_on:
			_log_decision(ctx, decision, actions + 1)

		await combat._perform_action(u, decision["ability"], decision["target"], int(decision["slot"]))
		actions += 1

		if combat._battle_over:
			stop_reason = "battle over"
			break

	if log_on:
		if actions == 0:
			print("[ai] %s acted 0 times — %s." % [u.unit_name, stop_reason])
		else:
			print("[ai] %s ends its turn after %d action(s) — %s." % [u.unit_name, actions, stop_reason])

## Which of `_ai_can_continue`'s five conditions actually stopped us. Only ever
## used for the log line, but "the enemy stopped and I don't know why" is exactly
## the class of bug this whole file's logging exists to prevent.
static func _why_stopped(combat, u: BattleCharacter) -> String:
	if combat._battle_over:
		return "the battle ended"
	if u == null or not u.is_alive():
		return "it died during its own turn"
	if CombatBuffs.is_stunned(u.body):
		return "it was stunned mid-turn"
	if u.ap <= AP_EPSILON:
		return "action points spent"
	return "the turn was closed out from elsewhere"

# ----------------------------------------------------------------------------
## THE DECISION.  { "ability": Ability, "slot": int, "target": BattleCharacter },
## or {} when nothing legal exists.
##
## PHASE 0: uniform over every legal (ability, target) combination. Uniform rather
## than "always attack" on purpose — a random walk through the whole option space
## is what shakes out the plumbing bugs, where a fixed choice would exercise one
## code path forever.
##
## PHASE 1+: this becomes
##     intent  = AIIntent.pick(ctx)          -> zero it and re-roll on failure
##     target  = AITarget.pick(ctx, intent)  -> DEFENSE short-circuits to the actor
##     ability = AIAbility.pick(ctx, intent, target)
## with the §16.5 ladder around it, ending at `fallback(ctx)` and then a pass.
static func decide(ctx: AIContext) -> Dictionary:
	if ctx.options().is_empty():
		return {}
	# A SCRIPTED FOLLOW-UP OUTRANKS THE WHOLE PIPELINE. It is a commitment, not a
	# preference, so it cannot be a gain term — no amount of appetite should talk a
	# unit out of the second beat of its own pattern.
	var fu := _follow_up(ctx)
	if not fu.is_empty():
		return fu
	var layer1 := AIIntent.score_all(ctx)
	var scores: Dictionary = layer1["scores"]
	var notes: Array = []
	for intent in AIIntent.INTENTS:
		notes.append("%s %s" % [intent.substr(0, 3), str(layer1["ledger"][intent])])
	var tries := 0
	while tries < AIIntent.INTENTS.size():
		tries += 1
		var arr: Array = []
		for intent in AIIntent.INTENTS:
			arr.append(float(scores[intent]))
		var ii := AIPick.weighted(arr, maxf(0.0, ctx.stat("ai_decisiveness")))
		if ii < 0:
			break
		var intent: String = AIIntent.INTENTS[ii]
		var t := AITarget.pick(ctx, intent)
		var tgt: BattleCharacter = t["target"]
		if tgt == null:
			notes.append("-> %s FAILED at target (%s); re-rolling" % [intent.to_upper(), ", ".join(t["ledger"])])
			scores[intent] = 0.0
			continue
		var a := AIAbility.pick(ctx, intent, tgt)
		if a["pair"] == null:
			notes.append("-> %s on %s FAILED at ability; re-rolling" % [intent.to_upper(), tgt.unit_name])
			scores[intent] = 0.0
			continue
		var pair: Dictionary = a["pair"]
		notes.append("-> %s" % intent.to_upper())
		notes.append("target   " + " | ".join(t["ledger"]))
		notes.append("ability  " + " | ".join(a["ledger"]))
		return {"ability": pair["ability"], "slot": int(pair["slot"]), "target": tgt, "intent": intent, "notes": notes}
	# every intent exhausted — the bottom rungs of the ladder
	var fb := fallback(ctx)
	if not fb.is_empty():
		notes.append("-> FALLBACK: best attack on the most magnetic hostile")
		fb["intent"] = "fallback"
		fb["notes"] = notes
	return fb

## THE SCRIPTED FOLLOW-UP (Ability.ai_follow_up). If the ability this unit last
## resolved names a follow-up, and that follow-up is usable and has a legal target,
## take it — before the three layers get a say. "After Riot Shield, always Shield
## Bash": a two-beat pattern the player can learn to read, and the cheapest telegraph
## available.
##
## EVERY GATE STILL APPLIES. The follow-up has to be in ctx.pairs, which means it
## already passed combat._can_use (cooldown, spirit, silence, action points), and it
## has to have a legal target under its own intent. Fail either and this returns {}
## and the normal decision runs — a follow-up is never allowed to make a unit stall.
##
## SELF-LIMITING BY CONSTRUCTION: taking the follow-up overwrites last_ability_id
## with the follow-up's own id, so unless that ability ALSO names one, the pattern
## stops after its second beat. Two abilities naming each other would loop forever
## by design, which is a thing an author can want and the action cap still bounds.
static func _follow_up(ctx: AIContext) -> Dictionary:
	if ctx.actor == null:
		return {}
	var last := str(ctx.actor.last_ability_id)
	if last == "":
		return {}
	var prev: Ability = ctx.combat._get_ability(last)
	if prev == null:
		return {}
	var want := String(prev.ai_follow_up)
	if want == "":
		return {}
	for p in ctx.pairs:
		var ab: Ability = p["ability"]
		if String(ab.id) != want:
			continue
		var intents := AIContext.intents_of(ab)
		var intent: String = str(intents[0]) if not intents.is_empty() else Ability.AI_OFFENSE
		var legal := ctx.intent_targets(intent, ab)
		if legal.is_empty():
			return {}
		# Still ask Layer 2 WHO — the pattern fixes the ability, not the victim.
		var picked := AITarget.pick(ctx, intent)
		var tgt: BattleCharacter = picked["target"]
		if tgt == null or not legal.has(tgt):
			tgt = legal[0]
		return {
			"ability": ab, "slot": int(p["slot"]), "target": tgt, "intent": intent,
			"notes": ["-> FOLLOW-UP: %s commits to %s" % [prev.display_name, ab.display_name]],
		}
	return {}

## THE BOTTOM RUNG of the fallback ladder (§16.5): the best usable OFFENSE-tagged
## ability against the most magnetic legal hostile. Deterministic, no roulette —
## "the default answer is simple offense". Already written so the ladder in Phase 1
## has somewhere to land; nothing calls it while `decide()` is uniform.
static func fallback(ctx: AIContext) -> Dictionary:
	var tgt := ctx.most_magnetic_hostile()
	if tgt == null:
		return {}
	var best := {}
	var best_priority := -1.0
	for p in ctx.by_intent.get(Ability.AI_OFFENSE, []):
		var ability: Ability = p["ability"]
		if not ctx.intent_targets(Ability.AI_OFFENSE, ability).has(tgt):
			continue
		var pr := AIContext.priority_of(ability)
		if pr <= 0.0:
			continue
		# best = highest priority, ties broken by expected damage
		var score := pr * 1000.0 + AIEstimate.expected_damage(ctx, ctx.actor, tgt, ability)
		if score > best_priority:
			best_priority = score
			best = {"ability": ability, "slot": int(p["slot"]), "target": tgt}
	return best

# ----------------------------------------------------------------------------
# Debug ledger  (CORE §5B — every debug-only feature obeys the master flag)
# ----------------------------------------------------------------------------
static func is_debug() -> bool:
	if typeof(GameManager) == TYPE_NIL or not GameManager.has_method("is_debug"):
		return false
	return GameManager.is_debug()

## One block per decision. Phase 1+ grows this into the full GAIN LEDGER — every
## term, its signal, its gain and its product — because with exponential terms
## "why is that number 63" is otherwise unanswerable, and tuning an exponential
## system without a ledger is guesswork. The `intent` line is deliberately shaped
## so it can later become an on-screen telegraph ("the Ice Spirit is preparing to
## defend"), which Layer 1 produces one beat before the action happens.
static func _log_decision(ctx: AIContext, decision: Dictionary, action_no: int) -> void:
	var u := ctx.actor
	var ability: Ability = decision["ability"]
	var tgt: BattleCharacter = decision["target"]
	print("[ai] %s (%s) · turn %d · action %d · ap %.2f · smart:%s" % [
		u.unit_name, u.ai, u.turns_taken, action_no, u.ap,
		"yes" if ctx.stat("ai_smart") >= 0.5 else "no"])
	var usable := []
	for p in ctx.pairs:
		usable.append("%s(%d)[%s]" % [p["id"], int(p["slot"]), ",".join(p["intents"])])
	print("     usable  %s" % " ".join(usable))
	for line in decision.get("notes", []):
		print("     %s" % str(line))
	print("     => %s (slot %d) on %s" % [ability.display_name, int(decision["slot"]), tgt.unit_name])

## Why nothing was usable, slot by slot, straight from combat's own gate. A unit
## that silently does nothing is the hardest AI bug to find, and today's `"none"`
## behaviour is exactly that — this exists so the new AI never reproduces it.
static func _log_nothing_usable(combat, u: BattleCharacter) -> void:
	if u.loadout.is_empty():
		print("[ai] %s has an EMPTY loadout — it can never act. Give its module or fight spec an `abilities` list." % u.unit_name)
		return
	var lines := []
	for slot in u.loadout.size():
		var aid := str(u.loadout[slot])
		if aid == "":
			continue
		var ability: Ability = combat._get_ability(aid)
		if ability == null:
			lines.append("%d:%s = unknown ability id" % [slot, aid])
			continue
		if ability.is_passive() or ability.is_always_active():
			lines.append("%d:%s = passive, never castable" % [slot, aid])
			continue
		# Explicitly typed, not inferred: `combat` is untyped (combat.gd has no
		# class_name), so every call through it returns Variant and `:=` has
		# nothing to infer from.
		var why: String = combat._use_blocked(u, ability, slot)
		lines.append("%d:%s = %s" % [slot, aid, why if why != "" else "usable but no legal target"])
	print("[ai] %s has nothing usable — %s" % [u.unit_name, " | ".join(lines)])
