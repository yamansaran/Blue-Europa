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
## >> PHASE 0 — THE SPINE. `decide()` currently picks a UNIFORM RANDOM legal
##    (ability, target) pair. That is deliberate and temporary: it proves the seam
##    end to end (context -> choice -> `_use_ability`) with zero scoring, and the
##    moment it lands every on-struck / on-hit rider in the game is exercised in
##    BOTH directions for the first time. Expect real bugs here — they will be in
##    the riders, not in this file. The three scoring layers (AIIntent / AITarget /
##    AIAbility) replace `decide()` and nothing else in this file moves.
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

		combat._use_ability(u, decision["ability"], decision["target"], int(decision["slot"]))
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
	var options := ctx.options()
	if options.is_empty():
		return {}
	var i := AIPick.uniform(options.size())
	if i < 0:
		return {}
	var chosen: Dictionary = options[i]
	return chosen

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
		if not ctx.combat._valid_target(ctx.actor, ability, tgt):
			continue
		var pr := AIContext.priority_of(ability)
		if pr <= 0.0:
			continue
		if pr > best_priority:
			best_priority = pr
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
		"yes" if u.body.get_effective("ai_smart") >= 0.5 else "no"])
	var usable := []
	for p in ctx.pairs:
		usable.append("%s(%d)[%s]" % [p["id"], int(p["slot"]), ",".join(p["intents"])])
	print("     usable  %s" % " ".join(usable))
	print("     -> %s (slot %d) on %s   [uniform over %d option(s)]" % [
		ability.display_name, int(decision["slot"]), tgt.unit_name, ctx.options().size()])

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
