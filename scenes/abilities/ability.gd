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
## OPTIONAL second caster-stat scaling term, added on top of scaling_stat. Lets one
## ability scale off TWO stats at once (e.g. Claw: 50% vigor + 50% instinct). Leave
## scaling_stat2 blank to use only the primary term — every existing .tres inherits
## the blank default, so nothing needs re-saving. Has its own per-rank override
## array (scaling_mult2_ranks), mirroring scaling_mult / scaling_mult_ranks.
@export var scaling_stat2: StringName = &""
@export var scaling_mult2: float = 0.0
@export var requires: Array[StringName] = []
@export var required_level: int = 1

# --- PER-RANK OVERRIDES  (the ability RANK system) --------------------------
## An ability can hold a DIFFERENT value per skill-tree rank. Each array below,
## when NON-EMPTY, OVERRIDES the matching scalar field for a given rank R (1-based):
## the value used is  array[clamp(R-1, 0, size-1)]  — so a 3-entry array covers
## ranks 1/2/3 and any higher rank clamps to the last entry. Leave an array EMPTY
## to keep the plain scalar behaviour (every existing .tres inherits empty arrays,
## so nothing needs re-saving). Ranks need NOT be linear or consistent — e.g. Hod
## costs 20/15/15 spirit and scales Instinct 300/325/350% (scaling_mult 3.0/3.25/3.5).
## Only fields that CHANGE per rank need an array; the rest keep their single value.
##   description_ranks  : per-rank tooltip body (String)
##   cost_amount_ranks  : per-rank cost_amount (int)
##   base_power_ranks   : per-rank base_power (float) — overrides the
##                        base_power + power_per_point*(R-1) curve when set
##   scaling_mult_ranks : per-rank caster-stat scaling multiplier (float)
##   cooldown_ranks     : per-rank cooldown in turns (int)
@export var description_ranks: Array[String] = []
@export var cost_amount_ranks: Array[int] = []
@export var base_power_ranks: Array[float] = []
@export var scaling_mult_ranks: Array[float] = []
@export var scaling_mult2_ranks: Array[float] = []
@export var cooldown_ranks: Array[int] = []

# --- UPGRADE node (a skill-tree node that buffs OTHER abilities) -------------
## Some skill-tree nodes are not castable abilities of their own — investing points
## in them strengthens the player's OTHER abilities. Such a node's ability .tres
## carries this `upgrades` map instead of combat stats:
##     { "<target_ability_id>": { "<stat_key>": per_point_scaling_add, ... }, ... }
## For every point invested in the granting node, each listed target ability gains
## `per_point_scaling_add * caster[stat]` extra output (applied at damage time via
## Character.ability_scaling_bonus -> compute_damage's scaling_bonus argument).
## Example — Sinewed (the Malkuth node), per point:
##     { "claw":  { "vigor": 0.25, "instinct": 0.25 },
##       "scour": { "vigor": 0.25 } }
## An ability with a non-empty `upgrades` map is treated as UPGRADE-ONLY: it never
## enters the ability pool / combat wheel (see Character.unlock_ability). Blank for
## every normal ability, so existing .tres are unaffected.
@export var upgrades: Dictionary = {}

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

# --- per-rank value access --------------------------------------------------
## Clamp a 1-based rank `points` to a valid index into a per-rank array of `n`
## entries: below rank 1 -> 0, above the last entry -> the last entry.
func _rank_index(points: int, n: int) -> int:
	var r := points - 1
	if r < 0:
		r = 0
	elif r > n - 1:
		r = n - 1
	return r

## The tooltip body for a given rank (description_ranks override, else the scalar).
func description_at(points: int) -> String:
	if not description_ranks.is_empty():
		return description_ranks[_rank_index(points, description_ranks.size())]
	return description

## A stat key as a display label ("vigor" -> "Vigor", "some_stat" -> "Some Stat").
func _stat_label(stat_key: String) -> String:
	return stat_key.capitalize()

## Human phrase for this ability's EFFECTIVE caster-stat scaling at `points`, e.g.
## "50% of Vigor + 50% of Instinct". `scaling_bonus` (stat_key -> extra multiplier,
## from Character.ability_scaling_bonus) is folded in so an upgraded ability shows
## its upgraded percentages — e.g. Sinewed pushes Claw to "75% of Vigor + 75% of
## Instinct". Native stats come first (in scaling_stat, scaling_stat2 order), then
## any bonus-only stats the ability doesn't natively scale off. Empty when the
## ability has no scaling at all.
func scaling_phrase(points: int = 1, scaling_bonus: Dictionary = {}) -> String:
	var parts := PackedStringArray()
	var used := {}
	var s1 := String(scaling_stat)
	if s1 != "":
		used[s1] = true
		var m1 := scaling_mult_at(points) + float(scaling_bonus.get(s1, 0.0))
		parts.append("%d%% of %s" % [int(round(m1 * 100.0)), _stat_label(s1)])
	var s2 := String(scaling_stat2)
	if s2 != "":
		used[s2] = true
		var m2 := scaling_mult2_at(points) + float(scaling_bonus.get(s2, 0.0))
		parts.append("%d%% of %s" % [int(round(m2 * 100.0)), _stat_label(s2)])
	if typeof(scaling_bonus) == TYPE_DICTIONARY:
		for k in scaling_bonus.keys():
			var ks := String(k)
			if used.has(ks):
				continue
			var mv := float(scaling_bonus[k])
			if mv == 0.0:
				continue
			parts.append("%d%% of %s" % [int(round(mv * 100.0)), _stat_label(ks)])
	return " + ".join(parts)

## The description for `points`, with dynamic tokens substituted. Supports the
## "{scaling}" token, which is replaced by scaling_phrase(points, scaling_bonus) so a
## description like "Deal Physical damage equal to {scaling}." shows the ability's
## LIVE effective scaling (including any upgrade-node bonus). Tokens are only touched
## when present, so plain authored descriptions are returned unchanged.
func description_resolved(points: int = 1, scaling_bonus: Dictionary = {}) -> String:
	var s := description_at(points)
	if s.find("{scaling}") != -1:
		s = s.replace("{scaling}", scaling_phrase(points, scaling_bonus))
	return s

## The raw cost_amount for a given rank (cost_amount_ranks override, else scalar).
func cost_amount_at(points: int) -> int:
	if not cost_amount_ranks.is_empty():
		return int(cost_amount_ranks[_rank_index(points, cost_amount_ranks.size())])
	return cost_amount

## The caster-stat scaling multiplier for a given rank.
func scaling_mult_at(points: int) -> float:
	if not scaling_mult_ranks.is_empty():
		return float(scaling_mult_ranks[_rank_index(points, scaling_mult_ranks.size())])
	return scaling_mult

## The SECOND caster-stat scaling multiplier for a given rank (scaling_mult2_ranks
## override, else the scalar). Mirrors scaling_mult_at for the optional second stat.
func scaling_mult2_at(points: int) -> float:
	if not scaling_mult2_ranks.is_empty():
		return float(scaling_mult2_ranks[_rank_index(points, scaling_mult2_ranks.size())])
	return scaling_mult2

## True when this ability is an UPGRADE-ONLY node (it carries an `upgrades` map and
## exists only to strengthen other abilities — never cast, never equipped).
func is_upgrade_only() -> bool:
	return typeof(upgrades) == TYPE_DICTIONARY and not upgrades.is_empty()

## The cooldown (turns) for a given rank.
func cooldown_at(points: int) -> int:
	if not cooldown_ranks.is_empty():
		return int(cooldown_ranks[_rank_index(points, cooldown_ranks.size())])
	return cooldown

## Spirit actually spent at a given rank (only SPIRIT costs are deducted today).
func spirit_cost_at(points: int) -> int:
	return cost_amount_at(points) if cost_type == CostType.SPIRIT else 0

## True when this ability is a PASSIVE that carries a constant stat bonus.
func is_passive() -> bool:
	return kind == Kind.PASSIVE

## True when this passive actually contributes something to the passives basket.
func has_passive_bonus() -> bool:
	return is_passive() and ((typeof(passive_mods) == TYPE_DICTIONARY and not passive_mods.is_empty()) \
		or (typeof(passive_mult) == TYPE_DICTIONARY and not passive_mult.is_empty()))

## The cost as a human phrase WITHOUT the "Cost:" prefix, for a given rank (e.g.
## "20 spirit", "10% of maximum health", "nothing"). Add new cases as CostType grows.
func cost_phrase_at(points: int) -> String:
	match cost_type:
		CostType.NONE:           return "nothing"
		CostType.SPIRIT:         return "%d spirit" % cost_amount_at(points)
		CostType.PCT_MAX_HP:     return "%d%% of maximum health" % cost_amount_at(points)
		CostType.PCT_CUR_HP:     return "%d%% of current health" % cost_amount_at(points)
		CostType.PCT_CUR_SPIRIT: return "%d%% of current spirit" % cost_amount_at(points)
		CostType.PCT_MAX_SPIRIT: return "%d%% of maximum spirit" % cost_amount_at(points)
		_:                       return "nothing"

## The full text for the tooltip cost panel at a given rank: "Cost: <phrase>",
## plus a "CD: <n>" line when the ability has a cooldown. A PASSIVE shows "Passive".
func cost_text_at(points: int) -> String:
	if is_passive():
		return "Passive"
	var t := "Cost: " + cost_phrase_at(points)
	var cd := cooldown_at(points)
	if cd > 0:
		t += "\nCD: %d" % cd
	return t

## Rank-1 convenience wrappers (kept so existing callers are unchanged).
func cost_phrase() -> String:
	return cost_phrase_at(1)

func cost_text() -> String:
	return cost_text_at(1)

## Spirit actually spent in combat. Only SPIRIT costs are deducted for now; the
## PCT_* (health/spirit percentage) kinds are described in the tooltip but not
## yet applied — hook their deduction into combat when you wire them up.
func spirit_cost() -> int:
	return spirit_cost_at(1)

## Base effect value for a given number of invested points (0 if none). When
## base_power_ranks is set it drives the value directly (arbitrary per-rank curve);
## otherwise the legacy linear base_power + power_per_point*(R-1) applies.
func power_at(points: int) -> float:
	if points <= 0:
		return 0.0
	if not base_power_ranks.is_empty():
		return float(base_power_ranks[_rank_index(points, base_power_ranks.size())])
	return base_power + power_per_point * float(points - 1)

## Pre-mitigation damage/effect value including caster-stat scaling, at a rank.
##   e.g. Strike: power_at(1)=100  +  1.0 * caster["vigor"].
## Mitigation (pierce vs defence, amplification) is applied later in CombatMath.
func compute_damage(caster_stats: Dictionary, points: int = 1, scaling_bonus: Dictionary = {}) -> float:
	var dmg := power_at(points)
	var stat := String(scaling_stat)
	if stat != "":
		dmg += scaling_mult_at(points) * float(caster_stats.get(stat, 0))
	# Optional second scaling stat (e.g. Claw's instinct term).
	var stat2 := String(scaling_stat2)
	if stat2 != "":
		dmg += scaling_mult2_at(points) * float(caster_stats.get(stat2, 0))
	# Extra per-stat scaling granted by invested UPGRADE nodes (e.g. Sinewed adds
	# vigor/instinct scaling to Claw & Scour). scaling_bonus maps stat_key -> extra
	# multiplier; combat fills it from Character.ability_scaling_bonus(id).
	if typeof(scaling_bonus) == TYPE_DICTIONARY and not scaling_bonus.is_empty():
		for k in scaling_bonus.keys():
			dmg += float(scaling_bonus[k]) * float(caster_stats.get(String(k), 0))
	return dmg

## Healing an HEAL ability restores (before the target's healing-received
## multiplier). Same power_at + caster-stat scaling as compute_damage, named
## separately so the intent reads clearly at the call site.
##   e.g. Alef: power_at(1)=0  +  3.0 * caster["instinct"]  =  300% of instinct.
func compute_heal(caster_stats: Dictionary, points: int = 1) -> float:
	return maxf(0.0, compute_damage(caster_stats, points))
