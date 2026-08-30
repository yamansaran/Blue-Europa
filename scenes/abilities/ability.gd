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

enum Kind { ATTACK, BUFF, DEBUFF, HEAL, PASSIVE, SHIELD }
enum Target { ENEMY, ALLY, SELF, ALL_ENEMIES, ALL_ALLIES }
## DELIVERY CLASS — a HIDDEN tag (never shown in a tooltip) saying HOW the ability
## reaches its target: SPELL = cast at range, ATTACK = a physical strike, PASSIVE =
## it is never used at all. This is what "attacks-only" reactions key off: an
## on-struck reaction like thorns (reflect) or Rime Skin fires when the incoming hit
## was an ATTACK and stays silent for a SPELL. Nothing else reads it today.
## Defaults to SPELL, so an existing .tres needs no re-save; the six real attacks
## (claw, scour, qoph, netzach, vav, chesed) set `delivery = 1` explicitly.
## PASSIVE is DERIVED, not authored — see delivery_class(): any PASSIVE-kind or
## always-active ability reports PASSIVE whatever the exported value.
enum Delivery { SPELL, ATTACK, PASSIVE }
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
## Skill-tree ranks. The ceiling is 99 so a "grind" node (Severity: +3 Vigor / +1
## Vitality / -1 max Spirit per point, 99 ranks) can be authored. A node that deep
## should express its per-rank values with passive_mods_per_point (below) rather
## than a 99-entry passive_mods_ranks array.
@export_range(1, 99) var max_points: int = 1

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
## Hidden melee-vs-ranged tag (see the Delivery enum). Read it through
## delivery_class() / is_attack_delivery(), never raw — the raw value is meaningless
## on a passive.
@export var delivery: Delivery = Delivery.SPELL
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

# --- SHIELD (kind == SHIELD) ------------------------------------------------
## A SHIELD ability grants the target an ABSORBING shield (temporary HP that soaks
## incoming damage before health, with no overflow to health — see CombatShields).
## The shield AMOUNT uses the same power_at + scaling as an attack/heal
## (base_power + scaling_stat + scaling_stat2), so author it with base_power /
## scaling_stat(2) / scaling_mult(2)[_ranks] exactly like a HEAL. Below are the
## DECAY knobs: each turn the shield loses flat + %-of-current + %-of-value-at-apply.
## Leave all three at 0 for a shield that never decays (lasts until spent). Only read
## when kind == SHIELD; existing .tres inherit the zero defaults with no re-save.
@export var shield_decay_flat: float = 0.0          # flat points lost per turn
@export var shield_decay_pct_current: float = 0.0   # fraction of CURRENT lost per turn (0.2 = 20%)
@export var shield_decay_pct_max: float = 0.0       # fraction of the AT-APPLY value lost per turn

# --- buff / debuff application ----------------------------------------------
## Id of the buff/debuff this ability applies to its target, resolved through
## BuffLibrary.build(). Used by BUFF / DEBUFF abilities (and any other kind that
## should also drop a buff on hit). Blank => this ability applies no buff.
@export var applies_buff: StringName = &""
## Id of a SECOND buff this ability drops on the CASTER (never the target) the moment
## it resolves, resolved through the same BuffLibrary.build() + rank-clone mapping as
## applies_buff. Lets one ability both debuff its victim and buff its user — Pass
## Current sears the target with Arc Burn (applies_buff) AND gives the caster +5
## Alacrity for 3 turns (applies_buff_self). Blank => no self buff, so every existing
## .tres is unaffected with no re-save. Applied for EVERY kind, after the kind's own
## effect resolved successfully (see combat._maybe_apply_self_buff).
@export var applies_buff_self: StringName = &""

# --- one-time spirit effects (on cast) --------------------------------------
## Instant, one-shot spirit adjustments applied the moment this ability resolves
## (NOT a per-turn buff — that is spirit_per_turn on a buff entry). Two independent
## effects: the CASTER gains `spirit_gain`, and the TARGET loses `spirit_steal`
## (both flat spirit points, clamped to each unit's [0, max] by change_spirit).
## Combat's ATTACK path applies them after the hit lands (see combat.gd
## _apply_spirit_effects); other kinds could call the same helper if wired. Each
## has an optional per-rank override array mirroring cost_amount_ranks — leave the
## arrays empty to use the scalar, and leave both scalars 0 for no spirit effect,
## so every existing .tres is unaffected with no re-save.
@export var spirit_gain: int = 0
@export var spirit_gain_ranks: Array[int] = []
@export var spirit_steal: int = 0
@export var spirit_steal_ranks: Array[int] = []

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
## OPTIONAL per-rank overrides for a PASSIVE's stat bonus, mirroring the attack/heal
## _ranks arrays: when NON-EMPTY, entry[clamp(R-1,...)] replaces passive_mods /
## passive_mult for the invested rank R. Each element is a { stat_key: amount } dict
## (an empty {} means "no bonus at that rank"). Lets one passive scale per rank —
## e.g. Beautiful Form grows +5/15/30/30/30 flat and +0/0/0/10/25% across 5 ranks.
## Leave empty to keep the single passive_mods / passive_mult at every rank; existing
## passives inherit the empty defaults with no re-save. Read via passive_mods_at /
## passive_mult_at (Character rebuilds the passives basket at the invested rank).
@export var passive_mods_ranks: Array[Dictionary] = []
@export var passive_mult_ranks: Array[Dictionary] = []
## PER-POINT passive bonus — the LINEAR alternative to the _ranks arrays, for a passive
## with too many ranks to enumerate. Every entry here is multiplied by the invested rank
## R and ADDED on top of whatever passive_mods / passive_mods_ranks resolved to, e.g.
##   passive_mods_per_point = {"vigor": 3.0, "vitality": 1.0, "spirit": -1.0}
## gives Severity +3 Vigor, +1 Vitality and -1 maximum Spirit for each of its 99 points.
## passive_mult_per_point is the same idea for the multiplier layer. Empty => nothing is
## added, so every existing passive is unaffected with no re-save.
@export var passive_mods_per_point: Dictionary = {}
@export var passive_mult_per_point: Dictionary = {}
## Id of an ability this node UNLOCKS as a side effect of being invested in. The moment
## any point sits in the granting node, the named ability is added to the player's pool
## exactly as if its own node had been unlocked (Character.unlock_ability cascades into
## it, and the respec resync keeps it alive only while the granting node still holds a
## point). The granted ability needs no node of its own — with no node mapping its rank
## falls back to 1, so author it as a single-rank ability. Severity uses this to hand the
## player Vicious Strike. Blank => grants nothing.
@export var unlocks_ability: StringName = &""

# --- STAT-DERIVED passive bonus (Galvanism) ---------------------------------
## A PASSIVE whose flat bonus is a FRACTION OF ANOTHER STAT rather than a fixed
## number. Shape: { target_stat: { source_stat: fraction } }, e.g.
##   {"alacrity": {"instinct": 0.30}}   =>  +Alacrity equal to 30% of Instinct.
## Unlike passive_mods (a static dict) this is recomputed live by Character into a
## dedicated "derived" basket, so it tracks the source stat as gear / levels / other
## passives move it. The derived basket is cleared before it is rebuilt, so a passive
## can never scale off its own output. Multiple passives naming the same target stat
## simply sum. Per-rank override: passive_scale_ranks (same clamp rule as the other
## _ranks arrays). Empty => no derived bonus (every existing passive).
@export var passive_scale: Dictionary = {}
@export var passive_scale_ranks: Array[Dictionary] = []
## A PASSIVE may also grant a per-turn / persistent BUFF while it sits in a wheel
## slot. This names a BuffLibrary id; at combat start, combat._apply_passive_buffs
## builds "<passive_buff>_<invested rank>" and applies it to the player as a permanent
## buff (re-granted every fight, like a character's permanent_buffs). Use this for a
## passive whose effect is NOT a plain stat mod (e.g. Gliogenesis' per-turn regen).
## Blank => the passive contributes only its passive_mods / passive_mult. Only read
## when kind == PASSIVE.
@export var passive_buff: StringName = &""
## CAPSTONE passive buff: a SECOND BuffLibrary id applied (as a permanent, fight-long
## buff, like passive_buff) only once the invested rank reaches passive_buff_capstone_rank.
## Unlike passive_buff the id is used VERBATIM — no "_<rank>" suffix is appended, since a
## capstone has exactly one form. Lightning Shell uses it to grant High Voltage at rank 10.
## Blank / rank 0 => no capstone. Only read when kind == PASSIVE.
@export var passive_buff_capstone: StringName = &""
@export var passive_buff_capstone_rank: int = 0

# --- ALWAYS ACTIVE (a passive granted from the node, never equipped) ---------
## Marks a PASSIVE whose stat bonus is live from the moment ANY point sits in its
## skill-tree node — it is NEVER equipped in the combat wheel and NEVER enters the
## ability pool (Character.unlock_ability skips it). Character rebuilds its passive
## bonus straight from the invested node at its rank (Character._rebuild_passive_basket),
## exactly like a slotted passive but sourced from the tree instead of the wheel. Use it
## for a passive that should simply be ON once unlocked (nothing sets it today — Beautiful
## Form is a normal EQUIPPABLE passive). The upgrade-only (Sinewed), wheel-slot (Overmind)
## and bonus-scaling (Crown) nodes are
## ALSO always-active by nature — is_always_active() treats all of them as one category,
## so they all read "Always Active" and stay out of the pool. Blank/false for every
## normal ability, so existing .tres are unaffected.
@export var always_active: bool = false

# --- WHEEL-SLOT passive (Overmind) ------------------------------------------
## An always-on passive whose invested points ADD combat-wheel slots. UNLIKE a normal
## passive it does NOT need to be equipped: Character reads the invested rank straight
## from the skill tree (Character.extra_wheel_slots) and grows the wheel, so the effect
## is live while ANY point sits in the granting node. Each invested point grants this
## many extra wheel slots (Overmind = 1 => +1/2/3 across its ranks). Because it is
## never cast or equipped, Character.unlock_ability keeps it out of the ability pool
## (like an upgrade-only node). 0 => not a wheel-slot passive (every other ability).
@export var wheel_slots_per_point: int = 0

# --- CROWN: always-on per-character-level scaling of the player's BONUS stats -
## Like Overmind / Sinewed, this is an always-on skill-tree node: its effect is live
## the moment ANY point sits in the granting node — it is NEVER cast or equipped, and
## Character.unlock_ability keeps it out of the ability pool (see is_bonus_scaling).
## For each stat key in `bonus_per_level_stats`, the player gains `bonus_per_level` of
## that stat's current BONUS (the summed flat mods — NOT the base) per CHARACTER LEVEL
## per invested point. Character rebuilds a "crown" basket from a snapshot of the other
## baskets' bonuses (so it never scales off itself). Crown sets bonus_per_level 0.01
## across vigor/vitality/instinct/magnificence/disdain and every real element's
## pierce/defense/amp. 0.0 => not a bonus-scaling node (every other ability).
@export var bonus_per_level: float = 0.0
@export var bonus_per_level_stats: Array[String] = []

# --- SHATTER: consume a debuff of an element for a bonus on-hit effect -------
## When an ATTACK sets consume_debuff_element (e.g. &"ice") and the struck target
## carries at least one debuff tagged with that element, combat._apply_shatter
## removes the OLDEST such debuff and then applies the extras below. Blank => the
## attack has no shatter behaviour, so existing .tres are unaffected.
@export var consume_debuff_element: StringName = &""
## Buff/debuff id applied to the target when a shatter triggers (e.g. &"stunned").
@export var shatter_apply_buff: StringName = &""
## Bonus damage dealt on a shatter, as a FRACTION of the target's max HP (0.15 = 15%).
## Has a per-rank override array mirroring the other _ranks fields.
@export var shatter_pct_max_hp: float = 0.0
@export var shatter_pct_max_hp_ranks: Array[float] = []
## Element the shatter bonus damage is dealt as (a string key for take_damage).
@export var shatter_damage_element: StringName = &"ice"

# --- HOARFROST: this attack's own ice damage bypasses the hoarfrost amp ------
## When true, this ATTACK's own ice damage does NOT benefit from or consume the
## target's hoarfrost stacks (so casting Hoarfrost neither eats nor is boosted by
## other Hoarfrost applications). Set only on Hoarfrost; every other attack leaves
## it false, so their ice hits amplify + consume hoarfrost normally.
@export var skip_ice_amp: bool = false

# --- SNAP: damage multiplied by a debuff count on the target -----------------
## When an ATTACK sets this (e.g. &"ice"), its computed damage is MULTIPLIED by the
## number of debuffs of that element currently on the target — i.e. the per-hit value
## (base + scaling) is dealt once per matching debuff. 0 matching debuffs => 0 damage.
## Blank => normal single-instance damage, so existing .tres are unaffected.
@export var damage_per_debuff_element: StringName = &""

# --- CRYONECROSIS: bonus PIERCE per debuff of an element on the target --------
## When an ATTACK sets pierce_per_debuff_element (e.g. &"ice"), the attack gains
## `pierce_per_debuff` extra pierce of its OWN element for EACH debuff of the named
## element currently on the target. Combat counts the matching debuffs
## (CombatBuffs.count_debuffs_of_element) and adds pierce_per_debuff_at(rank) × count
## to the attacker's pierce for this one hit (threaded into CombatMath.resolve's
## extra_pierce). 0 matching debuffs => no bonus. Has a per-rank override array
## mirroring the other _ranks fields; blank element / zero value => no effect, so
## existing .tres are unaffected.
@export var pierce_per_debuff_element: StringName = &""
@export var pierce_per_debuff: float = 0.0
@export var pierce_per_debuff_ranks: Array[float] = []

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

## The shatter bonus-damage fraction of the target's max HP for a given rank
## (shatter_pct_max_hp_ranks override, else the scalar). 0.0 => no bonus damage.
func shatter_pct_max_hp_at(points: int) -> float:
	if not shatter_pct_max_hp_ranks.is_empty():
		return float(shatter_pct_max_hp_ranks[_rank_index(points, shatter_pct_max_hp_ranks.size())])
	return shatter_pct_max_hp

## True when this ATTACK has shatter behaviour (it consumes a debuff element).
func has_shatter() -> bool:
	return String(consume_debuff_element) != ""

## The bonus pierce granted PER matching debuff for a given rank (pierce_per_debuff_ranks
## override, else the scalar). Combat multiplies this by the count of debuffs of
## pierce_per_debuff_element on the target. 0.0 => no bonus.
func pierce_per_debuff_at(points: int) -> float:
	if not pierce_per_debuff_ranks.is_empty():
		return float(pierce_per_debuff_ranks[_rank_index(points, pierce_per_debuff_ranks.size())])
	return pierce_per_debuff

## True when this ability is an UPGRADE-ONLY node (it carries an `upgrades` map and
## exists only to strengthen other abilities — never cast, never equipped).
func is_upgrade_only() -> bool:
	return typeof(upgrades) == TYPE_DICTIONARY and not upgrades.is_empty()

## The cooldown (turns) for a given rank.
func cooldown_at(points: int) -> int:
	if not cooldown_ranks.is_empty():
		return int(cooldown_ranks[_rank_index(points, cooldown_ranks.size())])
	return cooldown

## Flat spirit the CASTER gains when this ability resolves, at a given rank
## (spirit_gain_ranks override, else the scalar). 0 = no gain.
func spirit_gain_at(points: int) -> int:
	if not spirit_gain_ranks.is_empty():
		return int(spirit_gain_ranks[_rank_index(points, spirit_gain_ranks.size())])
	return spirit_gain

## Flat spirit the TARGET loses when this ability resolves, at a given rank
## (spirit_steal_ranks override, else the scalar). 0 = no drain.
func spirit_steal_at(points: int) -> int:
	if not spirit_steal_ranks.is_empty():
		return int(spirit_steal_ranks[_rank_index(points, spirit_steal_ranks.size())])
	return spirit_steal

## True when this ability carries any one-time spirit effect (gain or steal) at
## the given rank — lets combat skip the work when there is nothing to do.
func has_spirit_effect(points: int) -> bool:
	return spirit_gain_at(points) != 0 or spirit_steal_at(points) != 0

## Spirit actually spent at a given rank (only SPIRIT costs are deducted today).
func spirit_cost_at(points: int) -> int:
	return cost_amount_at(points) if cost_type == CostType.SPIRIT else 0

## True when this ability is a PASSIVE that carries a constant stat bonus.
func is_passive() -> bool:
	return kind == Kind.PASSIVE

## True when this passive actually contributes something to the passives basket —
## either the flat/multiplier scalars OR the per-rank override arrays (Beautiful Form
## sets only the rank arrays, so those must count too).
func has_passive_bonus() -> bool:
	if not is_passive():
		return false
	if (typeof(passive_mods) == TYPE_DICTIONARY and not passive_mods.is_empty()) \
		or (typeof(passive_mult) == TYPE_DICTIONARY and not passive_mult.is_empty()):
		return true
	if not passive_mods_ranks.is_empty() or not passive_mult_ranks.is_empty():
		return true
	# A purely PER-POINT passive (Severity) has no static dict and no rank arrays — its
	# whole bonus is rank x per_point, so it must count as contributing too.
	if (typeof(passive_mods_per_point) == TYPE_DICTIONARY and not passive_mods_per_point.is_empty()) \
		or (typeof(passive_mult_per_point) == TYPE_DICTIONARY and not passive_mult_per_point.is_empty()):
		return true
	# A purely stat-DERIVED passive (Galvanism) has no static mods, but it must still
	# count as "contributing" so the passive-basket scan doesn't skip it.
	if typeof(passive_scale) == TYPE_DICTIONARY and not passive_scale.is_empty():
		return true
	return not passive_scale_ranks.is_empty()

## Add `per_point` x `points` onto a copy of `base`, key by key. Shared by
## passive_mods_at / passive_mult_at so the per-point layer behaves identically for the
## flat and multiplier dicts. Returns `base` untouched (but duplicated) when there is
## no per-point layer, so nothing that doesn't use it pays for it.
func _fold_per_point(base: Dictionary, per_point: Dictionary, points: int) -> Dictionary:
	if typeof(per_point) != TYPE_DICTIONARY or per_point.is_empty():
		return base
	var r := float(maxi(points, 0))
	var out := base.duplicate(true)
	for k in per_point.keys():
		out[k] = float(out.get(k, 0.0)) + float(per_point[k]) * r
	return out

## The FLAT passive stat bonus for a given rank: the passive_mods_ranks override (else the
## passive_mods scalar), plus passive_mods_per_point x rank. Always returns a Dictionary.
func passive_mods_at(points: int) -> Dictionary:
	var base := {}
	if not passive_mods_ranks.is_empty():
		var d = passive_mods_ranks[_rank_index(points, passive_mods_ranks.size())]
		base = d if typeof(d) == TYPE_DICTIONARY else {}
	elif typeof(passive_mods) == TYPE_DICTIONARY:
		base = passive_mods
	return _fold_per_point(base, passive_mods_per_point, points)

## The MULTIPLIER passive stat bonus for a given rank: the passive_mult_ranks override
## (else the passive_mult scalar), plus passive_mult_per_point x rank.
func passive_mult_at(points: int) -> Dictionary:
	var base := {}
	if not passive_mult_ranks.is_empty():
		var d = passive_mult_ranks[_rank_index(points, passive_mult_ranks.size())]
		base = d if typeof(d) == TYPE_DICTIONARY else {}
	elif typeof(passive_mult) == TYPE_DICTIONARY:
		base = passive_mult
	return _fold_per_point(base, passive_mult_per_point, points)

## True when this PASSIVE should also hand the player a capstone buff at `points`.
func has_capstone_at(points: int) -> bool:
	return String(passive_buff_capstone) != "" \
		and passive_buff_capstone_rank > 0 \
		and points >= passive_buff_capstone_rank

## The STAT-DERIVED passive bonus for a given rank (passive_scale_ranks override, else
## the passive_scale scalar). Shape { target_stat: { source_stat: fraction } }.
func passive_scale_at(points: int) -> Dictionary:
	if not passive_scale_ranks.is_empty():
		var d = passive_scale_ranks[_rank_index(points, passive_scale_ranks.size())]
		return d if typeof(d) == TYPE_DICTIONARY else {}
	return passive_scale if typeof(passive_scale) == TYPE_DICTIONARY else {}

## True when this PASSIVE carries a stat-derived bonus (Character rebuilds the
## "derived" basket from it — see Character._rebuild_derived_basket).
func has_passive_scale() -> bool:
	if not is_passive():
		return false
	if typeof(passive_scale) == TYPE_DICTIONARY and not passive_scale.is_empty():
		return true
	return not passive_scale_ranks.is_empty()

## True when this ability is an always-on WHEEL-SLOT passive (Overmind): its invested
## points add combat-wheel slots and it is never equipped (see wheel_slots_per_point
## and Character.extra_wheel_slots / unlock_ability).
func is_wheel_slot_passive() -> bool:
	return wheel_slots_per_point != 0

## True when this ability is an always-on CROWN bonus-scaling node (its invested points
## scale the player's bonus stats per character level and it is never cast or equipped —
## see bonus_per_level and Character._rebuild_crown_basket / unlock_ability).
func is_bonus_scaling() -> bool:
	return bonus_per_level != 0.0 and not bonus_per_level_stats.is_empty()

## True when this ability is an ALWAYS-ACTIVE node ability: its effect is live while any
## point sits in its skill-tree node, and it is never cast, equipped, or shown in the
## ability pool. This unifies FOUR shapes into one category: the explicit `always_active`
## passive (unused today), the upgrade-only node (Sinewed), the wheel-slot passive
## (Overmind), and the bonus-scaling node (Crown). The hover panel shows "Always Active"
## for all of them, and Character.unlock_ability keeps every one out of the pool.
func is_always_active() -> bool:
	return always_active or is_upgrade_only() or is_wheel_slot_passive() or is_bonus_scaling()

## The RESOLVED delivery class (the hidden attack/spell/passive tag). Anything that is
## never cast — a PASSIVE-kind ability or one of the always-active node shapes — reports
## PASSIVE regardless of what the .tres set, so a passive can never be mistaken for a
## spell. Everything else reports its exported `delivery` (SPELL unless authored ATTACK).
func delivery_class() -> Delivery:
	if is_passive() or is_always_active():
		return Delivery.PASSIVE
	return delivery

## True when this ability lands as a physical ATTACK. This is the gate for attacks-only
## reactions: thorns-style reflects and Rime Skin proc on true here and stay silent for
## a spell. A passive is never an attack.
func is_attack_delivery() -> bool:
	return delivery_class() == Delivery.ATTACK

## True when this ability lands as a SPELL (cast, not struck). Passives are neither.
func is_spell_delivery() -> bool:
	return delivery_class() == Delivery.SPELL

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
## plus a "CD: <n>" line when the ability has a cooldown. An ALWAYS-ACTIVE node
## ability (Crown / Sinewed / Overmind) shows "Always Active"; any
## other PASSIVE shows "Passive" (e.g. the equippable Beautiful Form).
func cost_text_at(points: int) -> String:
	if is_always_active():
		return "Always Active"
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

## The absorbing-shield amount a SHIELD ability grants (before any target modifiers).
## Same power_at + caster-stat scaling as compute_damage/compute_heal — named
## separately so the intent reads clearly at the call site.
##   e.g. Vanguard: 0 base + 4.0*vitality + (0.75..2.0)*instinct.
func compute_shield(caster_stats: Dictionary, points: int = 1) -> float:
	return maxf(0.0, compute_damage(caster_stats, points))

## The decay spec for this SHIELD ability's shield, as CombatShields expects it:
## { "flat":.., "pct_current":.., "pct_max":.. } with only the non-zero terms
## present. An all-zero spec returns {} (a shield that never decays).
func shield_decay_spec() -> Dictionary:
	var d := {}
	if shield_decay_flat != 0.0:
		d["flat"] = shield_decay_flat
	if shield_decay_pct_current != 0.0:
		d["pct_current"] = shield_decay_pct_current
	if shield_decay_pct_max != 0.0:
		d["pct_max"] = shield_decay_pct_max
	return d
