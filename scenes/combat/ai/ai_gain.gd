extends RefCounted
class_name AIGain

## ============================================================================
## AI GAIN  —  the ONE bias primitive every AI layer uses  (AI_PRIMER §4)
## ============================================================================
## Every bias in the unit AI is `value * pow(gain, signal)`. Nothing else. That
## single shape is what lets one authored number produce a 15x or 40x swing while
## staying gentle at low signal, and it is why no layer needs an "invert" flag:
##
##   gain == 1.0   the term does NOTHING, at any signal.        pow(1, s) == 1
##   gain  >  1.0  ATTRACTION, rising to exactly `gain` at s = 1.
##   gain  <  1.0  REPULSION,  falling to exactly `gain` at s = 1.
##   signal == 0   the term does NOTHING, at any gain.          pow(g, 0) == 1
##
## So a gain stat reads in plain language: `ai_bloodlust = 40` means "up to 40x
## more attractive at full signal", and `ai_caution = 0.15` means "down to 0.15x
## against the scariest thing on the board". Never negative, never zero, always
## composable — a layer's multiplier is just the PRODUCT of its terms, and because
## products of exponentials are exponentials the order never matters.
##
## >> THE FOOTGUN. Every OTHER coefficient in this codebase is neutral at 0 (a
##    buff's `mods`, a `damage_taken_mult`). A GAIN IS NEUTRAL AT 1.0, and a gain
##    left at 0.0 clamps to MIN_GAIN and becomes a 50x REPULSION — silent, and
##    extremely confusing to debug. Three mitigations, all live:
##      1. every gain stat defaults to 1.0 in Stats unless deliberately biased;
##      2. AIRules.validate() warns under is_debug() on any gain sitting at 0.0;
##      3. the naming keeps them apart — everything ADDITIVE in the AI vocabulary
##         is an `ai_intent_*` weight, everything else is a gain.
##
## >> TERMS MULTIPLY. Three 4x preferences is 64x, not 12x — an obsession you did
##    not mean to write. When something feels over-tuned, COUNT THE TERMS before
##    shrinking any single gain. And the pick's exponent (AIPick) rides on top of
##    the whole product, so gains and the exponent compound in log space: tune one
##    at a time.
##
## WHAT A GAIN BUYS (keep this table open while tuning):
##   gain  | s=0.25   s=0.50   s=0.75   s=1.00   reads as
##   ------+----------------------------------------------------------------
##   0.10  |  0.56     0.32     0.18     0.10    near-total avoidance
##   0.15  |  0.62     0.39     0.24     0.15    strong avoidance
##   0.25  |  0.71     0.50     0.35     0.25    clear avoidance  (tidiness default)
##   0.50  |  0.84     0.71     0.59     0.50    mild avoidance
##   0.60  |  0.88     0.77     0.68     0.60    a nudge away     (shield default)
##   1.00  |  1.00     1.00     1.00     1.00    OFF
##   1.50  |  1.11     1.22     1.36     1.50    a nudge toward
##   2.00  |  1.19     1.41     1.68     2.00    mild preference
##   4.00  |  1.41     2.00     2.83     4.00    clear preference
##   8.00  |  1.68     2.83     4.76     8.00    strong preference
##   12.0  |  1.86     3.46     6.45    12.00    dominant         (mercy default)
##   15.0  |  1.97     3.87     7.62    15.00    dominant         (finisher default)
##   25.0  |  2.24     5.00    11.18    25.00    near-decisive
##   40.0  |  2.51     6.32    15.91    40.00    obsessive        (the assassin)
##   100   |  3.16    10.00    31.62   100.00    single-minded
##
## class_name global — RESTART Godot once after adding this script.
## ----------------------------------------------------------------------------

## Clamps on an authored gain. The floor is deliberately NOT 0: a gain of exactly
## zero would annihilate a weight rather than repel from it, and "impossible" is a
## VIABILITY decision (AIIntent) or an authored `magnetism` of 0 — never a gain.
const MIN_GAIN := 0.02
const MAX_GAIN := 200.0

## The whole primitive. `sig` is the 0..1 signal (NB it cannot be called `signal`
## — that is a GDScript keyword).
static func apply(value: float, gain: float, sig: float) -> float:
	return value * factor(gain, sig)

## The multiplier alone, for a caller that wants to log the term before applying
## it (the gain ledger prints `bloodlust^0.75 = 15.91`, which is this).
static func factor(gain: float, sig: float) -> float:
	var g := clampf(gain, MIN_GAIN, MAX_GAIN)
	var s := clampf(sig, 0.0, 1.0)
	if is_equal_approx(g, 1.0) or s <= 0.0:
		return 1.0
	return pow(g, s)

## True when this gain would do nothing at ANY signal — the cheap test that lets a
## layer skip computing an expensive signal no gain on this unit actually reads.
## (AI_PRIMER §11.3: "skip any signal whose every consuming gain is 1.0" is the
## single biggest saving in the estimator, because most creatures leave most gains
## off.)
static func is_off(gain: float) -> bool:
	return is_equal_approx(clampf(gain, MIN_GAIN, MAX_GAIN), 1.0)

## Soft saturation, x >= 0 -> [0, 1). The codebase's standard squash — the same
## curve CombatMitigation and CombatDodge already use — kept here so every AI file
## normalises an unbounded quantity the same way. `ref` is the value that reads as
## 0.5: squash(ref, ref) == 0.5.
static func squash(x: float, ref: float = 1.0) -> float:
	var r := maxf(0.0001, ref)
	var v := maxf(0.0, x) / r
	return v / (1.0 + v)
