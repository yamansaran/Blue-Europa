extends RefCounted
class_name CombatDodge

## ============================================================================
## COMBAT DODGE  —  the accuracy / evasion roll
## ============================================================================
## Its own script (alongside CombatMitigation / CombatCrit / CombatResist) so the
## dodge curve can be tuned in one place. CombatMath.resolve() asks it, as STAGE 0,
## whether the hit lands at all; a dodged hit short-circuits the whole pipeline and
## returns damage 0 with "dodged": true.
##
## THE FORMULA (dev-specified):
##   d      = defender.alacrity - attacker.alacrity
##   raw    = BASE + SPREAD * squash(STIFFNESS * d)
##            + the defender's dodge_chance_bonus  (buffs)
##            - the attacker's accuracy_bonus      (buffs)
##            - ability.accuracy_mod               (per-ability override)
##   dodge% = clampf(raw, MIN_PCT, MAX_PCT) * delivery_multiplier(ability)
##
## squash(y) = y / (1 + |y|) — the same shape CombatMitigation uses, so everything
## in the game bends the same way. STIFFNESS is deliberately GENTLE: dodging an
## attack outright is meant to be an occasional swing, never a strategy that turns
## a fight off. At EQUAL alacrity the chance is exactly BASE (10%).
##
## Worked (attack delivery, no buffs):
##   d = -50 -> 1.0% (floor) ; -25 -> 2.6% ; 0 -> 10.0% ; +25 -> 17.4% ;
##   +50 -> 22.0% ; +100 -> 27.5% ; +200 -> 32.6% ; asymptote 42%, capped 35%.
##
## THE DELIVERY MULTIPLIER is the accuracy tier system. It falls out of the
## ability's KIND plus its hidden delivery class (Ability.is_attack_delivery), so
## no authoring field is needed:
##   kind ATTACK + attack delivery  -> 1.0  (full dodge; Claw, Scour, Shatter)
##   kind ATTACK + spell  delivery  -> 0.5  (+50% accuracy; Mind Freeze, ZAP!)
##   any non-damaging kind          -> 0.0  (never dodged — a pure BUFF/DEBUFF/HEAL/
##                                           SHIELD use is gated by CombatResist's
##                                           magnificence roll instead, not by this)
## So a damaging spell baselines at 5% and tops out at 17.5%, and a debuff-only
## ability always connects (its debuff can still be RESISTED — a separate axis).
##
## ANTI-FRUSTRATION (rev33). The more a unit dodges the PLAYER SIDE's attacks in a
## row, the less likely its next dodge — reset the moment it is hit:
##
##   streak  = consecutive dodges since this unit was last hit (combat tracks it and
##             mirrors it onto the body as metadata STREAK_META)
##   adv     = maxf(0, defender.alacrity - attacker.alacrity)
##   relief  = 1 / (1 + adv / AF_ALACRITY_REF)          # 1.0 at parity, falls with adv
##   mult    = maxf(AF_FLOOR, 1 - AF_PER_DODGE * streak * relief)
##   dodge%  = normal dodge% * mult
##
## WEAK AND LOW-KEY ON PURPOSE: one dodge costs 7% of the next chance at equal
## alacrity (10% -> 9.3%), three in a row 21%, and it can never cut more than
## (1 - AF_FLOOR). It SCALES INVERSELY WITH THE ALACRITY GAP: a unit that is meant to
## be evasive (+50 alacrity over the attacker) keeps a third of the relief — its
## dodges are the design, not bad luck. Only attackers that are NOT enemies feed or
## read it (an ENEMY body never gets the discount), so it never helps the AI.
##
## class_name global — RESTART Godot once after adding this script.
## ----------------------------------------------------------------------------

# --- tuning knobs -----------------------------------------------------------
const BASE      := 10.0    # dodge % when attacker and defender have equal alacrity
const SPREAD     := 70.0   # how far the curve can travel from BASE (before clamps)
const STIFFNESS := 0.021   # scales the alacrity gap before the squash; smaller = gentler
const MIN_PCT   := 1.0     # a hit is never truly guaranteed
const MAX_PCT   := 75.0    # ...and evasion never becomes a wall

# --- anti-frustration ---------------------------------------------------------
## Object metadata key on a DEFENDER body: its current dodge streak (int).
const STREAK_META := &"af_dodge_streak"
## Fraction of the dodge chance removed per consecutive dodge, at equal alacrity.
const AF_PER_DODGE := 0.07
## Alacrity advantage at which the relief is halved (bigger = gentler scaling).
const AF_ALACRITY_REF := 25.0
## The dodge chance is never cut below this fraction of itself.
const AF_FLOOR := 0.55

# --- delivery multipliers (the accuracy tiers) ------------------------------
const MULT_ATTACK_DELIVERY := 1.0   # a physical strike: full dodge chance
const MULT_SPELL_DELIVERY  := 0.5   # a damaging spell: +50% accuracy
const MULT_NON_DAMAGING    := 0.0   # a pure buff/debuff/heal/shield: never dodged

# --- basket stat keys (read from buffs + debuffs) ---------------------------
## Flat percentage points ADDED to the DEFENDER's dodge chance (an evasion buff).
const DODGE_CHANCE_BONUS_KEY := "dodge_chance_bonus"
## Flat percentage points SUBTRACTED from the dodge chance by the ATTACKER (a
## true-strike buff). Both are plain `mods` keys, so a buff sets them for free.
const ACCURACY_BONUS_KEY := "accuracy_bonus"

## Sum a stat across ONLY the buffs and debuffs baskets.
static func _buff_debuff_bonus(body: CharacterBase, key: String) -> float:
	if body == null:
		return 0.0
	return body.get_basket_bonus("buffs", key) + body.get_basket_bonus("debuffs", key)

# ----------------------------------------------------------------------------
## The accuracy tier for an ability: 1.0 for a physical strike, 0.5 for a damaging
## spell, 0.0 for anything that deals no damage of its own. A null ability is
## treated as a plain attack.
static func delivery_multiplier(ability: Ability) -> float:
	if ability == null:
		return MULT_ATTACK_DELIVERY
	# Only a kind-ATTACK use deals damage; every other kind is undodgeable.
	if ability.kind != Ability.Kind.ATTACK:
		return MULT_NON_DAMAGING
	return MULT_ATTACK_DELIVERY if ability.is_attack_delivery() else MULT_SPELL_DELIVERY

## Dodge chance as a number in 0..100 for this attacker/defender/ability triple.
static func chance(attacker: CharacterBase, defender: CharacterBase, ability: Ability) -> float:
	var mult := delivery_multiplier(ability)
	if mult <= 0.0 or defender == null:
		return 0.0

	var d := defender.get_effective("alacrity")
	if attacker != null:
		d -= attacker.get_effective("alacrity")

	var y := STIFFNESS * d
	var raw := BASE + SPREAD * (y / (1.0 + absf(y)))
	raw += _buff_debuff_bonus(defender, DODGE_CHANCE_BONUS_KEY)
	raw -= _buff_debuff_bonus(attacker, ACCURACY_BONUS_KEY)
	raw -= _ability_accuracy_mod(ability)

	return clampf(raw, MIN_PCT, MAX_PCT) * mult * anti_frustration_mult(attacker, defender)

## The anti-frustration multiplier (see the header). 1.0 = no effect.
static func anti_frustration_mult(attacker: CharacterBase, defender: CharacterBase) -> float:
	if defender == null or not defender.has_meta(STREAK_META):
		return 1.0
	if attacker != null and attacker.char_type == Stats.CharType.ENEMY:
		return 1.0
	var streak := int(defender.get_meta(STREAK_META, 0))
	if streak <= 0:
		return 1.0
	var adv := defender.get_effective("alacrity")
	if attacker != null:
		adv -= attacker.get_effective("alacrity")
	var relief := 1.0 / (1.0 + maxf(0.0, adv) / AF_ALACRITY_REF)
	return maxf(AF_FLOOR, 1.0 - AF_PER_DODGE * float(streak) * relief)

## Roll against a chance. Pass floor >= 0 to inject a specific 0..99 roll (tests);
## otherwise a fresh random 0..99 is drawn. Mirrors CombatCrit.rolls_crit.
static func rolls_dodge(chance_pct: float, floor: int = -1) -> bool:
	if chance_pct <= 0.0:
		return false
	var roll := floor if floor >= 0 else (randi() % 100)
	return float(roll) < chance_pct

# ----------------------------------------------------------------------------
## Per-ability accuracy override, in percentage points subtracted from the dodge
## chance (100 = effectively unmissable). Tolerant of abilities authored before the
## field existed.
static func _ability_accuracy_mod(ability: Ability) -> float:
	if ability != null and "accuracy_mod" in ability:
		return float(ability.accuracy_mod)
	return 0.0
