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
## Optional caster-stat scaling: adds scaling_mult * caster[scaling_stat].
@export var scaling_stat: StringName = &""
@export var scaling_mult: float = 0.0
@export var requires: Array[StringName] = []
@export var required_level: int = 1

## Element as its string prefix ("fire", "true", ...) for stat lookups.
func element_key() -> String:
	return Stats.element_key(element)

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
## line "CD: <n>" when the ability has a cooldown.
func cost_text() -> String:
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
