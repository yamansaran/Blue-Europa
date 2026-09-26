extends RefCounted
class_name AIPick

## ============================================================================
## AI PICK  —  the weighted roulette, and the AI's own RNG  (AI_PRIMER §15)
## ============================================================================
## ALL THREE decision layers end here: intent, target and ability. One
## implementation, one RNG, one place to unit-test the off-by-ones, one place to
## add a "don't repeat last turn's choice" rule later. DO NOT WRITE THREE
## ROULETTES.
##
## THE EXPONENT is how a unit's CONVICTION is authored, separately from its
## PREFERENCES (which are the gains). It is applied as pow(score, k) rather than
## as a softmax for one specific reason: A ZERO STAYS ZERO. A non-viable option is
## impossible at every exponent, which a softmax would not guarantee.
##   0.0   every non-zero option equally likely   (a confused unit — `erratic`)
##   1.0   proportional to score                  (the plain model)
##   1.5   the default: real preference, real upsets
##   2-4   strongly favours the best while leaving genuine surprises (a boss)
##   8+    effectively argmax                     (a calculating machine)
##
## HOW BIG SHOULD A WEIGHT BE? To pick your preferred option with probability P
## against (n-1) alternatives all sitting at weight 1, its weight must be
##     W = P*(n-1) / (1-P)
##   targets |  50%   75%   90%   95%   99%
##   --------+---------------------------------
##      2    |    1     3     9    19    99
##      3    |    2     6    18    38   198
##      4    |    3     9    27    57   297
##      5    |    4    12    36    76   396
##      6    |    5    15    45    95   495
## Read it like this: in a four-unit party an assassin that should take the
## quarter-health target ~90% of the time needs an effective 27x. `ai_bloodlust
## 40` gives 15.9x at that health (~84%), and `ai_focus 1.5` raises it to
## 15.9^1.5 = 63x (~95%). THE GAIN SETS THE SHAPE, THE EXPONENT SETS THE
## CONVICTION.
##
## class_name global — RESTART Godot once after adding this script.
## ----------------------------------------------------------------------------

## The AI's own generator, separate from the global one the damage rolls use, so
## seeding it for a repeatable bug report never changes a crit roll. Lazily made
## and randomized on first use.
static var _rng: RandomNumberGenerator = null

static func rng() -> RandomNumberGenerator:
	if _rng == null:
		_rng = RandomNumberGenerator.new()
		_rng.randomize()
	return _rng

## Pin the AI's decisions for a reproducible fight. Worth having from day one and
## free: with the same seed and the same opening state, the same decisions come
## back. (Named set_seed, not seed — `seed` is a @GlobalScope function.)
static func set_seed(value: int) -> void:
	rng().seed = value

## WEIGHTED ROULETTE over `scores`, raised to `exponent`. Returns the chosen index,
## or -1 when every weight is zero (which the caller MUST treat as "this layer
## failed" and drop to its fallback — never as "pick the first one").
## Negative scores are floored at 0, so a term can never make an option cost
## probability from another one.
## `gen` (optional): draw from this RNG instead of the AI's shared one (AIDebug's self-test).
static func weighted(scores: Array, exponent: float = 1.0, gen: RandomNumberGenerator = null) -> int:
	var n := scores.size()
	if n <= 0:
		return -1
	var w := []
	w.resize(n)
	var total := 0.0
	for i in n:
		var s := maxf(0.0, float(scores[i]))
		# pow(0, 0) is 1 in IEEE, which would resurrect a non-viable option at
		# exponent 0 (`erratic`). Zero stays zero, at every exponent.
		var v := 0.0
		if s > 0.0:
			v = pow(s, maxf(0.0, exponent))
		w[i] = v
		total += v
	if total <= 0.0:
		return -1
	var roll := (gen if gen != null else rng()).randf() * total
	var acc := 0.0
	for i in n:
		acc += float(w[i])
		if roll < acc:
			return i
	return n - 1   # float-drift guard: the last positive bucket wins

## Uniform pick over `n` options. Used by the Phase-0 spine and by anything that
## genuinely wants a coin flip; `weighted(scores, 0.0)` is the same thing when you
## already have a score array with zeros in it that must stay impossible.
static func uniform(n: int) -> int:
	if n <= 0:
		return -1
	return rng().randi_range(0, n - 1)

## Pick a random element of `list`, or null when it is empty.
static func from(list: Array):
	var i := uniform(list.size())
	return null if i < 0 else list[i]
