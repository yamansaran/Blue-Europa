extends RefCounted
class_name CombatMitigation

## ============================================================================
## COMBAT MITIGATION  —  turns pre-mitigation damage into post-mitigation damage
## ============================================================================
## Its own script so the mitigation curve can be fine-tuned in one place without
## touching CombatMath / combat.gd. CombatMath.resolve() calls apply() with the
## element's resistance/pierce/amplification, all already summed on the bodies:
##   R = defender.get_effective(Stats.defense_key(element))   # resistance
##   P = attacker.get_effective(Stats.pierce_key(element))    # pierce
##   A = attacker.get_effective(Stats.amp_key(element))       # amplification
##
## THE FORMULA (dev-specified, rev "damage system"):
##   post = pre * ( (A + 1) * ( 1 - (m(R - P)) / (1 + |m(R - P)|) ) )
##   m = the DEFENDER's per-character mitigation stiffness (base 0.025).
##
## squash(y) = y / (1 + |y|) maps y into (-1, +1). Here y = m*(R - P), so m scales
## the resistance-vs-pierce gap BEFORE the squash — a small m keeps typical gaps in
## the near-linear middle of the curve, so the first few points of net pierce /
## resist aren't oppressively strong and later points keep mattering (the curve
## saturates slowly). The term (1 - squash) is:
##   - resistance beats pierce  -> squash -> +1 -> term shrinks toward 0   (mitigated)
##   - pierce beats resistance  -> squash -> -1 -> term grows  toward 2   (amplified)
##   - equal (R = P)            -> squash = 0  -> term = 1
## The (A + 1) coefficient (not bare A) keeps resistance/pierce meaningful when
## amplification A = 0; with bare A a non-amplified hit (the default) would deal 0.
## At A = 0 the multiplier is just the term, so it is 1.0 at R = P (like TRUE),
## <1 when out-resisted, up to ~2 when fully pierced. The hidden TRUE element
## bypasses this entirely (CombatMath returns pre unchanged for it).
##
## Worked (m = 0.025, A = 0): R=45,P=15 -> x0.571 ; R=P -> x1.000 ; R=15,P=45 ->
## x1.429 ; a single point of net resist (d=1) -> x0.976 (gentle).
## ----------------------------------------------------------------------------

## Used only when a body somehow has no mitigation_stiffness (0 or missing).
const STIFFNESS_FALLBACK := 0.025

## The signed, squashed resistance response in (-1, +1), stiffness-scaled. Positive
## => the target's resistance is winning; negative => pierce is winning.
static func net_response(resistance: float, pierce: float, stiffness: float) -> float:
	var d := stiffness * (resistance - pierce)
	return d / (1.0 + absf(d))

## The final damage multiplier applied to pre-mitigation damage.
static func multiplier(resistance: float, pierce: float, amp: float, stiffness: float) -> float:
	return (amp + 1.0) * (1.0 - net_response(resistance, pierce, stiffness))

## post = pre * multiplier(...). Never returns below 0.
static func apply(pre: float, resistance: float, pierce: float, amp: float, stiffness: float) -> float:
	return maxf(0.0, pre * multiplier(resistance, pierce, amp, stiffness))
