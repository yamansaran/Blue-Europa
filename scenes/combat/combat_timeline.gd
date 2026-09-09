class_name CombatTimeline
extends RefCounted

## ============================================================================
## COMBAT TIMELINE  —  the turn-interval math (rev30)
## ============================================================================
## Pure static math, no state. The ONE place speed is tuned. Sibling of
## CombatMath / CombatCrit / CombatMitigation.
##
## Blue Europa's turn order is a continuously scrolling timeline, not a round
## queue. A single float clock (units: TICKS) advances; every unit is scheduled
## at a clock value (BattleCharacter.next_turn_at) and takes its turn when the
## clock reaches it. A unit's INTERVAL is how many ticks pass between its turns,
## and it is the LENGTH OF ITS BAR on the TurnTimeline widget: a shorter bar is
## a faster character, and it is short in exactly the proportion that it is fast.
##
##      interval = TICKS_PER_TURN
##               * (ALACRITY_REF + ALACRITY_BASE) / (ALACRITY_REF + alacrity)
##               / turn_rate
##
## The curve is hyperbolic, so speed has automatic diminishing returns and can
## never reach a zero interval however much alacrity is stacked. Sanity points
## with the constants below:
##      alacrity   0 -> 110.0     (10% slower than default)
##      alacrity  10 -> 100.0     (the default character: one turn per 100 ticks)
##      alacrity  45 ->  75.9
##      alacrity 120 ->  50.0     (twice as many turns as default)
##      alacrity 320 ->  26.2
##
## `turn_rate` is a separate hidden stat (Stats.TURN_RATE_DEFAULT = 1.0) that
## DIVIDES the interval. It is the "extra multiplier" knob: turn_rate 2.0 on an
## enemy spec is literally "this thing acts twice as often", independent of
## alacrity (which also drives crit and dodge). Being a real base stat it is
## spec-overridable AND buffable — mods:{"turn_rate": +0.5} is a haste effect.
##
## NB the OTHER way to give a unit more actions is action_points (COMBAT_PRIMER
## C7): more actions inside ONE turn, rather than more turns. The two are
## deliberately distinct and both default to 1.0.
## ----------------------------------------------------------------------------

## Ticks between turns for a DEFAULT character (alacrity 10, turn_rate 1.0).
## Everything else in the game is measured against this: "one turn" = 100 ticks.
const TICKS_PER_TURN := 100.0
## Alacrity above ALACRITY_BASE that halves the interval. Raise it to make
## alacrity a weaker speed stat, lower it to make it a stronger one.
const ALACRITY_REF := 100.0
## Stats.MAJOR_DEFAULTS["alacrity"]. Kept as its own constant so a default
## character lands on exactly TICKS_PER_TURN rather than near it.
const ALACRITY_BASE := 10.0
## Hard floor on an interval. A runaway alacrity + turn_rate + haste stack can
## otherwise approach zero and starve every other unit off the timeline.
const MIN_INTERVAL := 10.0
## Floor on the turn_rate divisor, so a debuff that drives turn_rate to 0 (or a
## legacy body that has no such stat and reads 0.0) slows a unit down hard
## instead of dividing by zero.
const MIN_TURN_RATE := 0.05

## The interval, in ticks, for a given alacrity + turn_rate pair.
static func interval(alacrity: float, turn_rate: float) -> float:
	var rate := maxf(MIN_TURN_RATE, turn_rate)
	var alac := maxf(0.0, alacrity)
	var iv := TICKS_PER_TURN * (ALACRITY_REF + ALACRITY_BASE) / (ALACRITY_REF + alac) / rate
	return maxf(MIN_INTERVAL, iv)

## The interval for a body, read from its LIVE effective stats — so a haste buff
## shortens the bar the moment it lands.
static func interval_for(body: CharacterBase) -> float:
	if body == null:
		return TICKS_PER_TURN
	return interval(body.get_effective("alacrity"), rate_of(body))

## This body's effective turn_rate. Self-heals a body built before turn_rate
## existed (get_base returns 0.0 for a missing key, which would otherwise read as
## "infinitely slow"): the default is written into base_stats on first read, so
## the stat is then buffable and spec-overridable exactly like any other.
static func rate_of(body: CharacterBase) -> float:
	if body == null:
		return 1.0
	if not body.base_stats.has("turn_rate"):
		body.base_stats["turn_rate"] = Stats.TURN_RATE_DEFAULT
	return body.get_effective("turn_rate")

## Ticks -> "turns" as a human-readable figure, for logs and tooltips.
static func turns_of(ticks: float) -> float:
	return ticks / TICKS_PER_TURN
