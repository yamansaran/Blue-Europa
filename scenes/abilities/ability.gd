class_name Ability
extends Resource

## ============================================================================
## ABILITY  —  data template for one skill-tree / combat ability
## ============================================================================
## One .tres per ability in scenes/abilities/ability_data/. Describes what an
## ability IS; invested points live in Character, wheel slots live in
## Character.equipped_abilities. Rev6: `damage_type` is now `element`, drawn from
## the full element list (physical … mental, plus hidden TRUE). The actual
## pierce/defence/amp math lives in CombatMath.resolve_damage().
## ----------------------------------------------------------------------------

enum Kind { ATTACK, BUFF, DEBUFF, HEAL, PASSIVE }
enum Target { ENEMY, ALLY, SELF, ALL_ENEMIES, ALL_ALLIES }
## What resource an ability costs to use. Extend this list as new cost kinds are
## needed; cost_text() and combat's cost handling switch on it.
enum CostType {
	NONE,             # costs nothing
	SPIRIT,           # cost_amount spirit
	PCT_MAX_HP,       # cost_amount % of maximum health
	PCT_CUR_HP,       # cost_amount % of current health
	PCT_CUR_SPIRIT,   # cost_amount % of current spirit
	PCT_MAX_SPIRIT,   # cost_amount % of maximum spirit
}

# --- identity / presentation ------------------------------------------------
@export var id: StringName = &"do_thing"
@export var display_name: String = "Do Thing"
@export_multiline var description: String = "do a thing"
@export var icon: Texture2D

# --- skill-tree economy -----------------------------------------------------
@export_range(1, 20) var max_points: int = 1

# --- combat wheel -----------------------------------------------------------
## How many wheel slots a single copy of this ability may occupy at once.
@export_range(1, 10) var max_equipped: int = 2

# --- action-point economy ---------------------------------------------------
## Action points this ability spends from the caster's per-turn budget (default
## 1.0). A character starts each turn with its `action_points` stat (default 1.0),
## so by default one ability ends the turn; set this to 0.0 for a free action, or
## higher for an ability that eats more of the budget. Existing .tres pick up the
## default automatically (no need to re-save them).
@export var action_cost: float = 1.0

# --- Sonny-style combat stats ----------------------------------------------
@export var kind: Kind = Kind.ATTACK
@export var target: Target = Target.ENEMY
## Damage element. Drives which pierce/defence/amp stats apply (see CombatMath).
## TRUE ignores all mitigation.
@export var element: Stats.Element = Stats.Element.PHYSICAL
## Cost model: cost_type picks what is spent, cost_amount is the number
## (flat for SPIRIT, a percentage for the PCT_* kinds). NONE => free.
@export var cost_type: CostType = CostType.NONE
@export var cost_amount: int = 0
@export var cooldown: int = 0
## value at rank R = base_power + power_per_point * (R - 1)
@export var base_power: float = 0.0
@export var power_per_point: float = 0.0
## Optional caster-stat scaling: adds scaling_mult * caster[scaling_stat]. For a
## HEAL ability this is the healing scaling (e.g. Alef: instinct * 3.0).
@export var scaling_stat: StringName = &""
@export var scaling_mult: float = 0.0
@export var requires: Array[StringName] = []
@export var required_level: int = 1

# --- buff / debuff application ----------------------------------------------
## Id of the buff/debuff this ability applies to its target, resolved through
## BuffLibrary.build(). Used by BUFF / DEBUFF abilities (and any other kind that
## should also drop a buff on hit). Blank => this ability applies no buff.
@export var applies_buff: StringName = &""

# --- PASSIVE stat bonus (kind == PASSIVE) -----------------------------------
## A PASSIVE ability grants a CONSTANT stat bonus while it sits in a combat-wheel
## slot — no activation, no cost, no cooldown. Character rebuilds a "passives"
## basket from every PASSIVE ability currently in the wheel (exactly like the
## items basket is rebuilt from equipped gear), so the bonus applies in AND out of
## combat and is removed the moment the ability leaves the wheel. Because it lives
## in a PERSISTENT basket it is NOT cleared at the end of combat.
##   passive_mods : FLAT stat mods,      { stat_key: amount }   e.g. {"vigor": 5}
##   passive_mult : MULTIPLIER stat mods, { stat_key: fraction } e.g. {"vigor": 0.2}
##                  (0.2 = +20%; multipliers from all sources are additive)
## Keys come from the Stats vocabulary. Only read when kind == PASSIVE; existing
## .tres inherit the empty defaults with no re-save.
@export var passive_mods: Dictionary = {}
@export var passive_mult: Dictionary = {}

# --- crit (see CombatCrit) --------------------------------------------------
## Multiplies the base crit CHANCE for this ability (base 1.0 = no change).
@export var crit_chance_mult: float = 1.0
## Flat percentage points ADDED to this ability's crit chance after the multiply.
@export var crit_chance_add: float = 0.0
## Multiplies crit DAMAGE for this ability (base 1.0). Combined with the
## character's base crit-damage multiplier and any buff/debuff crit-damage bonus.
@export var crit_damage_mult: float = 1.0

## Element as its string prefix ("fire", "true", ...) for stat lookups.
func element_key() -> String:
	return Stats.element_key(element)

## True when this ability is a PASSIVE that carries a constant stat bonus.
func is_passive() -> bool:
	return kind == Kind.PASSIVE

## True when this passive actually contributes something to the passives basket.
func has_passive_bonus() -> bool:
	return is_passive() and ((typeof(passive_mods) == TYPE_DICTIONARY and not passive_mods.is_empty()) \
		or (typeof(passive_mult) == TYPE_DICTIONARY and not passive_mult.is_empty()))

## The cost as a human phrase WITHOUT the "Cost:" prefix (e.g. "20 spirit",
## "10% of maximum health", "nothing"). Add new cases here as CostType grows.
func cost_phrase() -> String:
	match cost_type:
		CostType.NONE:           return "nothing"
		CostType.SPIRIT:         return "%d spirit" % cost_amount
		CostType.PCT_MAX_HP:     return "%d%% of maximum health" % cost_amount
		CostType.PCT_CUR_HP:     return "%d%% of current health" % cost_amount
		CostType.PCT_CUR_SPIRIT: return "%d%% of current spirit" % cost_amount
		CostType.PCT_MAX_SPIRIT: return "%d%% of maximum spirit" % cost_amount
		_:                       return "nothing"

## The full text for the tooltip cost panel: "Cost: <phrase>", plus a second
## line "CD: <n>" when the ability has a cooldown. A PASSIVE shows "Passive".
func cost_text() -> String:
	if is_passive():
		return "Passive"
	var t := "Cost: " + cost_phrase()
	if cooldown > 0:
		t += "\nCD: %d" % cooldown
	return t

## Spirit actually spent in combat. Only SPIRIT costs are deducted for now; the
## PCT_* (health/spirit percentage) kinds are described in the tooltip but not
## yet applied — hook their deduction into combat when you wire them up.
func spirit_cost() -> int:
	return cost_amount if cost_type == CostType.SPIRIT else 0

## Base effect value for a given number of invested points (0 if none).
func power_at(points: int) -> float:
	if points <= 0:
		return 0.0
	return base_power + power_per_point * float(points - 1)

## Pre-mitigation damage/effect value including caster-stat scaling.
##   e.g. Strike: power_at(1)=100  +  1.0 * caster["vigor"].
## Mitigation (pierce vs defence, amplification) is applied later in CombatMath.
func compute_damage(caster_stats: Dictionary, points: int = 1) -> float:
	var dmg := power_at(points)
	var stat := String(scaling_stat)
	if stat != "":
		dmg += scaling_mult * float(caster_stats.get(stat, 0))
	return dmg

## Healing an HEAL ability restores (before the target's healing-received
## multiplier). Same power_at + caster-stat scaling as compute_damage, named
## separately so the intent reads clearly at the call site.
##   e.g. Alef: power_at(1)=0  +  3.0 * caster["instinct"]  =  300% of instinct.
func compute_heal(caster_stats: Dictionary, points: int = 1) -> float:
	return maxf(0.0, compute_damage(caster_stats, points))
