extends RefCounted
class_name AIDebug

## ============================================================================
## AI DEBUG  —  the self-test harness for the AI's primitives
## ============================================================================
## Everything the unit AI does rests on two pure functions — AIGain.factor and
## AIPick.weighted — and both are the kind of code that is silently, subtly wrong:
## an exponent applied to the wrong side, a cumulative walk that is off by one, a
## zero that stops being zero. Neither shows up as a crash. Both show up as "the
## enemies feel random", weeks later, with no way to tell whether the bug is in the
## maths or in the tuning.
##
## So they get checked directly, against the numbers AI_PRIMER quotes, with no
## combat, no units and no fight needed. QUIET WHEN HEALTHY: one PASS line. When
## something fails it prints the full comparison and pushes a warning.
##
## HOW IT RUNS: combat calls self_test_once() at battle start (first fight per session) under
## GameManager.is_debug(). Set SELF_TEST_ON_BATTLE_START false below to silence it
## once you trust it — or call AIDebug.self_test() by hand from anywhere.
##
## class_name global — RESTART Godot once after adding this script.
## ----------------------------------------------------------------------------

## Set false to stop combat running the self-test at the start of every fight.
const SELF_TEST_ON_BATTLE_START := true

## Draws used for the roulette distribution check. 20k keeps the whole test around
## a millisecond while holding the sampling error well inside TOLERANCE.
const ROULETTE_DRAWS := 20000
const TOLERANCE := 0.02

# ----------------------------------------------------------------------------
## Once per SESSION, not once per fight (perf, 2026-09-25): ~30k roulette draws are
## tens of milliseconds of debug GDScript, and they drained AIPick's shared RNG, which
## broke AIPick.set_seed reproducibility whenever debug was on. The self-test now draws
## from its OWN RNG (AIPick.weighted's `gen` argument), so the AI's stream is untouched.
static var _ran := false

static var _test_rng: RandomNumberGenerator = null

static func _trng() -> RandomNumberGenerator:
	if _test_rng == null:
		_test_rng = RandomNumberGenerator.new()
		_test_rng.randomize()
	return _test_rng

static func self_test_once() -> void:
	if _ran:
		return
	_ran = true
	self_test()

static func self_test() -> bool:
	var fails: Array = []
	fails += _test_gain_curve()
	fails += _test_roulette()
	fails += _test_zero_stays_zero()
	if fails.is_empty():
		print("[ai-debug] self-test PASSED — gain curve, roulette distribution (%d draws), zero-stays-zero." % ROULETTE_DRAWS)
		return true
	print("[ai-debug] self-test FAILED — %d problem(s):" % fails.size())
	for line in fails:
		print("           %s" % line)
	push_warning("[ai-debug] AI primitive self-test failed — see the Output log. The AI's tuning numbers will not mean what AI_PRIMER says they mean.")
	return false

# ----------------------------------------------------------------------------
## THE GAIN CURVE against the table in AI_PRIMER §4.3. The assassin's two numbers
## are the ones that matter most: the whole design brief ("a half-health target is
## 6-8x more magnetic, a quarter-health one about 15x") is met by ONE authored
## number, ai_bloodlust = 40, and only if this curve is right.
static func _test_gain_curve() -> Array:
	var out: Array = []
	var cases := [
		# [gain, signal, expected, what it is]
		[40.0, 0.50,  6.3246, "ai_bloodlust 40 at half health"],
		[40.0, 0.75, 15.9054, "ai_bloodlust 40 at quarter health"],
		[15.0, 1.00, 15.0,    "ai_finisher 15 on an available kill"],
		[12.0, 0.50,  3.4641, "ai_mercy 12 on a half-dead ally"],
		[0.25, 0.50,  0.5,    "ai_tidiness 0.25 on a half-saturated party"],
		[0.60, 1.00,  0.6,    "ai_shield_aversion 0.60 into a full shield wall"],
		[1.00, 1.00,  1.0,    "a gain of 1.0 is OFF at full signal"],
		[40.0, 0.00,  1.0,    "any gain is OFF at zero signal"],
	]
	for c in cases:
		var got := AIGain.factor(float(c[0]), float(c[1]))
		if absf(got - float(c[2])) > 0.001:
			out.append("gain curve: %s -> expected %.4f, got %.4f" % [str(c[3]), float(c[2]), got])
	# THE FOOTGUN, checked rather than trusted: a gain left at 0.0 must clamp to
	# MIN_GAIN and become a strong repulsion, not annihilate the weight outright.
	var zero_gain := AIGain.factor(0.0, 1.0)
	if absf(zero_gain - AIGain.MIN_GAIN) > 0.0001:
		out.append("gain curve: a gain of 0.0 should clamp to MIN_GAIN (%.3f), got %.4f" % [AIGain.MIN_GAIN, zero_gain])
	# Signals are clamped, so an out-of-range one can never blow a weight up.
	if not is_equal_approx(AIGain.factor(40.0, 3.0), 40.0):
		out.append("gain curve: a signal above 1.0 is not being clamped")
	if not is_equal_approx(AIGain.factor(40.0, -2.0), 1.0):
		out.append("gain curve: a negative signal is not being clamped to 0")
	# The shared squash: its reference value is the point that reads as one half.
	if absf(AIGain.squash(4.0, 4.0) - 0.5) > 0.0001:
		out.append("squash: squash(ref, ref) should be exactly 0.5")
	return out

## THE ROULETTE against AI_PRIMER §15.1's worked example. Scores 25 / 60 / 100 /
## 400 total 585, so the buckets are 25, 25..85, 85..185, 185..585 and the
## probabilities are 4.27% / 10.26% / 17.09% / 68.38%. Sampled rather than
## reasoned about, because the failure mode this catches — a cumulative walk that
## is off by one bucket — passes every eyeball test.
static func _test_roulette() -> Array:
	var out: Array = []
	var scores := [25.0, 60.0, 100.0, 400.0]
	var expected := [25.0 / 585.0, 60.0 / 585.0, 100.0 / 585.0, 400.0 / 585.0]
	var counts := [0, 0, 0, 0]
	for _i in ROULETTE_DRAWS:
		var pick := AIPick.weighted(scores, 1.0, _trng())
		if pick < 0 or pick >= 4:
			out.append("roulette: returned an out-of-range index %d for four positive scores" % pick)
			return out
		counts[pick] += 1
	for i in 4:
		var got := float(counts[i]) / float(ROULETTE_DRAWS)
		if absf(got - float(expected[i])) > TOLERANCE:
			out.append("roulette: option %d expected %.1f%% of draws, got %.1f%%" % [i, float(expected[i]) * 100.0, got * 100.0])
	# The exponent must SHARPEN, not reorder. At 4.0 the 400-weight option should
	# take essentially everything (400^4 is ~4000x the 100^4 runner-up).
	var sharp := 0
	for _i in 2000:
		if AIPick.weighted(scores, 4.0, _trng()) == 3:
			sharp += 1
	if float(sharp) / 2000.0 < 0.98:
		out.append("roulette: at exponent 4.0 the dominant option won only %.1f%% of the time (expected >98%%)" % [float(sharp) / 20.0])
	# An empty or all-zero score set must FAIL, so the caller drops to its
	# fallback ladder rather than silently acting on option zero.
	if AIPick.weighted([], 1.5, _trng()) != -1:
		out.append("roulette: an empty score array must return -1")
	if AIPick.weighted([0.0, 0.0, 0.0], 1.5, _trng()) != -1:
		out.append("roulette: an all-zero score array must return -1")
	return out

## ZERO STAYS ZERO, at every exponent. This is the entire reason the pick raises
## scores to a power instead of using a softmax: a non-viable option must be
## IMPOSSIBLE, not merely unlikely. The dangerous case is exponent 0 (`erratic`),
## where pow(0, 0) is 1 in IEEE arithmetic and would quietly resurrect every
## option the viability gate had ruled out.
static func _test_zero_stays_zero() -> Array:
	var out: Array = []
	for exponent in [0.0, 1.0, 1.5, 8.0]:
		for _i in 500:
			if AIPick.weighted([0.0, 5.0], float(exponent), _trng()) != 1:
				out.append("zero-stays-zero: a score of 0.0 was chosen at exponent %.1f" % float(exponent))
				break
	# ...and at exponent 0 the NON-zero options must be uniform among themselves.
	var counts := [0, 0, 0]
	for _i in 6000:
		var pick := AIPick.weighted([0.0, 5.0, 500.0], 0.0, _trng())
		if pick >= 0:
			counts[pick] += 1
	if counts[0] != 0:
		out.append("zero-stays-zero: the zero option was picked %d times at exponent 0" % counts[0])
	elif absf(float(counts[1]) - float(counts[2])) / 6000.0 > TOLERANCE:
		out.append("erratic: at exponent 0 the two live options should be equally likely, got %d vs %d" % [counts[1], counts[2]])
	return out

# ----------------------------------------------------------------------------
## Print one unit's whole decision space right now: what it may use, what each of
## those may be aimed at, and which intents are viable. Call it by hand from a
## breakpoint or a temporary line when a unit is doing something you did not
## expect — it answers "what were its options" without needing to read the loop.
static func dump_context(combat, u: BattleCharacter) -> void:
	if combat == null or u == null:
		print("[ai-debug] dump_context: nothing to dump.")
		return
	var ctx := AIContext.build(combat, u)
	print("[ai-debug] %s (%s) · ap %.2f/%.2f · hp %d/%d · spirit %d/%d" % [
		u.unit_name, u.ai, u.ap, u.max_ap(),
		u.get_hp(), u.get_max_hp(), u.get_spirit(), u.get_max_spirit()])
	print("           allies   %s" % _names(ctx.allies))
	print("           hostiles %s" % _names(ctx.hostiles))
	for intent in [Ability.AI_OFFENSE, Ability.AI_DEFENSE, Ability.AI_BUFF, Ability.AI_DEBUFF]:
		print("           %-8s viable:%s  options:%d" % [
			intent, "yes" if ctx.is_viable(intent) else "NO ", ctx.options(intent).size()])
	if ctx.pairs.is_empty():
		print("           (nothing usable this instant)")
		return
	for p in ctx.pairs:
		var ability: Ability = p["ability"]
		# `combat` is untyped, so its return is Variant — cast before it is handed
		# to a typed parameter.
		var rank := int(combat._ability_rank(u, ability))
		print("           slot %d  %-16s [%s]  cd %d  spirit %d  ap %.2f  -> %s" % [
			int(p["slot"]), str(p["id"]), ",".join(p["intents"]),
			ability.cooldown_at(rank), ability.spirit_cost_at(rank),
			ability.action_cost, _names(ctx.targets_for(ability))])

static func _names(units: Array) -> String:
	if units.is_empty():
		return "(none)"
	var out: Array = []
	for x in units:
		var u: BattleCharacter = x
		out.append("%s(%d/%d)" % [u.unit_name, u.get_hp(), u.get_max_hp()])
	return ", ".join(out)
