extends RefCounted
class_name CombatShields

## ============================================================================
## COMBAT SHIELDS  —  absorbing-shield engine (class_name global)
## ============================================================================
## A shield is temporary HP that sits ON TOP of a unit's health: incoming damage
## is dealt to the shield FIRST, and only a unit with NO shield takes damage to
## its health. Shields are the one thing here that is NOT a stat mod, so — unlike
## buffs — they live in their own list (`body.shields`), not in a stat basket.
##
## KEY RULES (per design):
##  - MULTIPLE INSTANCES. Every source that shields the unit appends its OWN
##    instance. Two 200 shields are stored as two 200s (the bar shows 400). They
##    are independent: each can decay on its own schedule.
##  - NEWEST FIRST. A hit eats the most-recently-applied shield first, cascading to
##    older instances only if it exhausts the newer one.
##  - NO OVERFLOW TO HEALTH. If the unit has ANY shield when a hit lands, that hit
##    deals ZERO to health — even a hit larger than the whole shield pool. (500
##    shield vs a 1000 hit -> shields gone, 0 health lost.) BattleCharacter enforces
##    the "0 to health" part; absorb() just drains the instances.
##  - DECAY. Each instance may decay at the turn boundary (see tick_decay). A shield
##    with no decay spec lasts until it is spent.
##
## Combat-only: `body.shields` lives on the battle clone and is never saved. Purely
## static, like CombatBuffs / CombatMath.
##
## class_name global — RESTART Godot once after adding this script.
## ----------------------------------------------------------------------------
## A shield instance Dictionary:
##   { "id": String, "source": String, "element": String,
##     "amount": float,       # current shield remaining
##     "max_amount": float,   # the value when first applied (for %-of-max decay)
##     "decay": Dictionary }  # {} = never decays; else any of:
##         { "flat": float,          # lose this many points per turn
##           "pct_current": float,   # lose this fraction of the CURRENT amount
##           "pct_max": float }      # lose this fraction of the value at apply
##       Total loss per turn = flat + pct_current*current + pct_max*max_amount.
## ----------------------------------------------------------------------------

## An instance is dropped once its amount falls to/under this (avoids 0.4-hp ghosts).
const PRUNE_EPSILON := 0.5

## The live shield list on `body` (always an Array; safe on a body without the field).
static func _list(body) -> Array:
	if body == null or not ("shields" in body):
		return []
	return body.shields

## Total shield across every instance, rounded — the number shown on the bar.
static func total(body) -> int:
	var t := 0.0
	for s in _list(body):
		t += float(s.get("amount", 0.0))
	return int(round(t))

## True when the unit currently has any shield.
static func has_shield(body) -> bool:
	return total(body) > 0

## Apply a new shield instance from `config` (keys: id, source, element, amount,
## and optional decay). A non-positive amount is a no-op. The instance is appended
## as the NEWEST, so it absorbs before any existing shield.
static func apply(body, config: Dictionary) -> void:
	if body == null or not ("shields" in body):
		return
	var amt := float(config.get("amount", 0.0))
	if amt <= 0.0:
		return
	var decay = config.get("decay", {})
	if typeof(decay) != TYPE_DICTIONARY:
		decay = {}
	body.shields.append({
		"id": str(config.get("id", "shield")),
		"source": str(config.get("source", "Shield")),
		"element": str(config.get("element", "")),
		"amount": amt,
		"max_amount": float(config.get("max_amount", amt)),
		"decay": (decay as Dictionary).duplicate(true),
	})

## Absorb `amount` of incoming damage across the instances, NEWEST FIRST. Depleted
## instances are removed. Returns the amount actually absorbed (<= amount, and <=
## the shield pool that existed). There is deliberately NO overflow to health — the
## caller (BattleCharacter.take_damage) deals 0 to HP whenever a shield was present.
static func absorb(body, amount: int) -> int:
	var list := _list(body)
	if list.is_empty() or amount <= 0:
		return 0
	var remaining := float(amount)
	var absorbed := 0.0
	# newest = highest index, so walk from the end toward the front.
	for i in range(list.size() - 1, -1, -1):
		if remaining <= 0.0:
			break
		var cur := float(list[i].get("amount", 0.0))
		var take := minf(cur, remaining)
		list[i]["amount"] = cur - take
		remaining -= take
		absorbed += take
	_prune(body)
	return int(round(absorbed))

## Turn-boundary decay: every instance with a decay spec loses its per-turn amount
## (flat + %-of-current + %-of-value-at-apply); non-decaying instances are left
## alone. Depleted instances are removed. Returns the total amount decayed away.
static func tick_decay(body) -> int:
	var list := _list(body)
	if list.is_empty():
		return 0
	var lost_total := 0.0
	for s in list:
		var d = s.get("decay", {})
		if typeof(d) != TYPE_DICTIONARY or d.is_empty():
			continue
		var cur := float(s.get("amount", 0.0))
		var loss := float(d.get("flat", 0.0)) \
			+ float(d.get("pct_current", 0.0)) * cur \
			+ float(d.get("pct_max", 0.0)) * float(s.get("max_amount", cur))
		if loss <= 0.0:
			continue
		var applied := minf(cur, loss)
		s["amount"] = cur - applied
		lost_total += applied
	_prune(body)
	return int(round(lost_total))

## Remove every shield instance (e.g. a hard cleanse). Returns true if any existed.
static func clear(body) -> bool:
	var list := _list(body)
	if list.is_empty():
		return false
	list.clear()
	return true

## Drop instances whose amount has fallen to/under PRUNE_EPSILON.
static func _prune(body) -> void:
	var list := _list(body)
	for i in range(list.size() - 1, -1, -1):
		if float(list[i].get("amount", 0.0)) <= PRUNE_EPSILON:
			list.remove_at(i)
