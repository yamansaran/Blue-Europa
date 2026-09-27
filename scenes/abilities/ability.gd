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
## ALLY_OTHER / ALL_OTHER_ALLIES (Nephilic, 2026-09-24): the ally-but-NOT-the-caster
## classes — every Nigredo ability buffs allies and never Sonny. Appended at the END so
## the ints already written in .tres files (0..4) keep their meaning: 5 ALLY_OTHER,
## 6 ALL_OTHER_ALLIES.
enum Target { ENEMY, ALLY, SELF, ALL_ENEMIES, ALL_ALLIES, ALLY_OTHER, ALL_OTHER_ALLIES }
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
## Where each hit of a MULTI-HIT attack lands (see hit_count below).
##   SAME   every hit strikes the unit the attack was aimed at (Flurry, Flail)
##   RANDOM each hit picks a fresh random LEGAL hostile (Spray) — legal meaning
##          _valid_target, so back-row protection still applies per shot.
## Written as an INT in a .tres, like every other enum here: 0 SAME, 1 RANDOM.
enum HitRetarget { SAME, RANDOM }
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
## COOLDOWN HELD BY WHAT THIS CAST APPLIED (GODTHAAB §1.16). When true, the slot's
## cooldown is FROZEN for as long as any entry this cast put on a unit survives on a
## living unit — it cannot tick, so the ability stays unusable. The moment the last
## such entry is gone (it expired, it broke, it was removed, its bearer died) the
## cooldown restarts at its full value and ticks normally from there.
## Covering: cooldown 5 + this => "only one ally Protected at a time, and five turns
## after the protection is lost". The hold is swept by combat (_sweep_cooldown_holds),
## so it catches every way an entry can end without any buff needing a hook.
## A cast whose buff never lands (resisted, failed proc) is released at once.
@export var cooldown_while_applied: bool = false
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
## GRANT: flat spirit given TO THE TARGET — the exact mirror of spirit_steal with the
## sign flipped, and the third and last member of this family. `spirit_gain` feeds the
## caster and `spirit_steal` drains the victim; before this there was no way to GIVE
## spirit to somebody else, which is all a support ability like Haunted Choir does.
## Applied in the same pass (combat._apply_spirit_effects), AFTER the caster's own gain,
## and clamped by change_spirit like the other two. When target = ALLY the caster can be
## its own target, in which case the gain and the grant both land on it.
@export var spirit_grant: int = 0
@export var spirit_grant_ranks: Array[int] = []

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

# --- SECOND ELEMENT: one attack, two damage types ----------------------------
## An ATTACK has exactly one `element`, which is wrong for a strike that is two
## things at once — a claw AND a cold. These three generalise the shatter shape
## above into a plain SECOND HIT that rides on the first: after the main damage
## lands, an extra hit of `bonus_damage_element` worth
## `bonus_scaling_mult × caster[bonus_scaling_stat]` is dealt to the same target.
##
## It is a REAL hit of that element, resolved through CombatMath.resolve_flat, so
## the target's resistance for the SECOND element, the caster's pierce/amp for it,
## damage_dealt_mult and damage_taken_mult all apply — which is the entire point:
## authoring a two-element attack as a single-element one loses the half of it that
## a lopsided resistance profile is supposed to answer. Dealt with NO source, so it
## fires no on-struck reaction and cannot recurse, and it is never a crit.
##
## Blank element (the default) => no second hit, so every existing .tres is
## unaffected with no re-save. A dodged attack skips this exactly as it skips
## everything else the attack carries.
@export var bonus_damage_element: StringName = &""
@export var bonus_scaling_stat: StringName = &""
@export var bonus_scaling_mult: float = 0.0
@export var bonus_scaling_mult_ranks: Array[float] = []

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

# --- FLAT PIERCE on an ability ----------------------------------------------
## Flat pierce of the ability's OWN element, added to the attacker's pierce for this
## one hit. The Cryonecrosis term above is CONDITIONAL on what the target already
## carries; this one is unconditional and belongs to the ability itself — a shriek
## that goes through armour does so whether or not you are already hexed. Combat SUMS
## the two rather than choosing between them, so an ability may carry both.
## 0.0 => no bonus, so every existing .tres is unaffected. Ignored for a TRUE-element
## attack, which skips the whole mitigation stage anyway.
@export var pierce_flat: float = 0.0
@export var pierce_flat_ranks: Array[float] = []

# --- %-OF-MAX-HP DAMAGE as an ordinary term ---------------------------------
## An extra hit worth a FRACTION of the TARGET's max HP (0.08 = 8%), dealt after the
## attack's own damage. This is the shatter_pct_max_hp shape above lifted out from
## behind its consume-a-debuff gate, so an ability can simply scale off how big the
## target is with no setup at all — which is what a titan-slayer scaler needs.
##
## Resolved through CombatMath.resolve_flat exactly as the second element is, so the
## target's resistance to pct_max_hp_element, the caster's pierce and amp for it,
## damage_dealt_mult and damage_taken_mult all apply. Dealt with NO source (it fires
## no on-struck reaction and cannot recurse) and never a crit.
##
## pct_max_hp_element blank (the default) => the ability's OWN element is used.
## 0.0 damage => no extra hit, so every existing .tres is unaffected.
@export var pct_max_hp_damage: float = 0.0
@export var pct_max_hp_damage_ranks: Array[float] = []
@export var pct_max_hp_element: StringName = &""

# --- APPLY CHANCE: a proc chance on this ability's buff/debuff ---------------
## The probability (0..1) that this ability's `applies_buff` is even ATTEMPTED.
## Rolled in combat._maybe_apply_buff BEFORE CombatResist, so 0.25 means one cast in
## four reaches the Magnificence-vs-Disdain roll and three in four never roll at all.
##
## THE TWO MULTIPLY. A 25% rider aimed at a target with real Magnificence lands far
## less often than either number reads, which is exactly why apply_chance and the
## resist stats have to be authored in the same pass rather than separately.
##
## A failed roll still CONSUMES THE CAST — spirit, action point and cooldown are all
## spent, precisely as a resisted debuff is. 1.0 (the default) = always attempted, so
## every existing .tres is unaffected.
##
## NB `applies_buff_self` is deliberately NOT gated by this. "The rider on the target
## is unreliable, the buff on me is certain" is a common and useful shape, and one
## field cannot express two different chances.
@export var apply_chance: float = 1.0
@export var apply_chance_ranks: Array[float] = []

# --- MULTI-HIT: one attack, several strikes ---------------------------------
## How many separate strikes this ATTACK makes. Each strike is its OWN
## CombatMath.resolve, so DODGE AND CRIT ROLL PER HIT — which is the entire
## mechanical point of a multi-hit against a single hit of the same total damage:
## the variance is different, and a shield has to absorb every strike separately.
## 1 (the default) = an ordinary single hit, so every existing .tres is unaffected.
@export var hit_count: int = 1
@export var hit_count_ranks: Array[int] = []
## Whether the ability's damage is DIVIDED across its hits or dealt PER hit.
##   true  the authored damage is the TOTAL, split evenly (Flurry: "same total damage
##         as the standard attack")
##   false the authored damage is dealt by EVERY hit (Flail)
## What gets divided is the ABILITY'S OWN damage output — its main hit, its second
## element and its %-of-max-HP term. Everything else fires once PER HIT at full
## value: the applies_buff rider (so Flail is 0-3 On Fire per use, and that variance
## is the threat), spirit steal/grant, Shatter, and the ATTACKER's on-hit riders.
## Irrelevant at hit_count 1, which is why it can safely default to true.
@export var hit_split: bool = true
## Where each hit lands — see HitRetarget above. Ignored for an ALL_ENEMIES /
## ALL_ALLIES ability, which already strikes everyone: a fan-out resolves
## "hit_count hits on EACH affected unit", never a random scatter across them.
@export var hit_retarget: HitRetarget = HitRetarget.SAME

# --- accuracy (see CombatDodge) ---------------------------------------------
## Flat percentage points SUBTRACTED from the target's dodge chance for this ability.
## The baseline accuracy tier is already decided by kind + delivery (a physical strike
## is fully dodgeable, a damaging spell is half as dodgeable, a non-damaging ability is
## never dodged), so this is only for per-ability exceptions: a large positive value
## (100) makes an ability effectively unmissable, a negative value makes it wild.
## 0.0 = use the tier as-is, so every existing .tres is unaffected.
@export var accuracy_mod: float = 0.0

# --- crit (see CombatCrit) --------------------------------------------------
## Multiplies the base crit CHANCE for this ability (base 1.0 = no change).
@export var crit_chance_mult: float = 1.0
## Flat percentage points ADDED to this ability's crit chance after the multiply.
@export var crit_chance_add: float = 0.0
## Multiplies crit DAMAGE for this ability (base 1.0). Combined with the
## character's base crit-damage multiplier and any buff/debuff crit-damage bonus.
@export var crit_damage_mult: float = 1.0

# --- NEPHILIC KIT (2026-09-24) — every field below defaults to "off" -----------
## PERK: a passive whose effect is a combat HOOK rather than a stat mod. At combat
## start the player's equipped passives (and invested always-active nodes) that name a
## perk are folded into one {perk_id: params} map on the body (CombatPerks); combat's
## hooks read it. perk_ranks[r-1] is the params dict at rank r (numbers only).
@export var perk: StringName = &""
@export var perk_ranks: Array[Dictionary] = []
## Per-application DURATION for applies_buff (0 = the entry's own). One unified poison /
## On Fire entry serves every ability at its own length (FUTURE_PLANS §3).
@export var applies_buff_duration: int = 0
@export var applies_buff_duration_ranks: Array[int] = []
## How many INSTANCES of applies_buff one cast lands (Pestilence 1..4). Default 1.
@export var applies_buff_count_ranks: Array[int] = []
## A SECOND debuff/buff dropped on the same target (Wormwood's toxic shred beside its
## poison). Rank-suffixed like applies_buff ("<id>_<rank>" when that exists).
@export var applies_buff_extra: StringName = &""
## HP COSTS. A fraction of the CASTER's max HP (per rank) or current HP, paid on use.
## An HP cost can never kill: an ability whose cost would be lethal is unusable, and
## any payment is floored so the caster keeps at least 1 HP.
@export var hp_cost_pct_max_ranks: Array[float] = []
@export var hp_cost_pct_current: float = 0.0
## HEAL riders. heal_missing_hp_bonus: heal x (1 + b * clamp((1 - HP%) / 0.7, 0, 1))
## (Second Wind). heal_from_hp_paid: the heal is this multiple of the HP the caster just
## paid (Bloodletting).
@export var heal_missing_hp_bonus_ranks: Array[float] = []
@export var heal_from_hp_paid_ranks: Array[float] = []
## A shield on each target worth this fraction of the CASTER's max HP (Tithe).
@export var shield_pct_caster_max_hp_ranks: Array[float] = []
## Cleanse N debuffs from the target (oldest first). 0 = none (Ablution 1/3).
@export var cleanse_count_ranks: Array[int] = []
## Catalyze: every instance of this debuff id on the target gains N turns, instantly.
## Nothing is left behind, so back-to-back casts each extend again.
@export var extend_debuff_id: StringName = &""
@export var extend_turns_ranks: Array[int] = []
## Excise: remove N instances of this debuff id (0 = ALL) and deal their remaining
## ticks now.
@export var excise_debuff_id: StringName = &""
@export var excise_count_ranks: Array[int] = []
## Per-instance payoffs off a debuff id on the target (Stoker: +10% damage per On Fire;
## Hew: +10 crit-chance points per On Fire).
@export var bonus_per_debuff_id: StringName = &""
@export var damage_bonus_per_debuff: float = 0.0
@export var crit_chance_per_debuff: float = 0.0
## Uses allowed per combat (0 = unlimited). Apotheosis and First Sun are 1.
@export var uses_per_combat: int = 0

# --- unit AI (see AI_PRIMER §9.4) -------------------------------------------
## The four INTENTS the AI decides between, as the strings every AI file keys by.
## They live here, on the one class both sides already depend on, so the ability
## layer and the AI layer can never drift on a spelling.
const AI_OFFENSE := "offense"
const AI_DEFENSE := "defense"
const AI_BUFF := "buff"
const AI_DEBUFF := "debuff"

## Which intents this ability serves. EMPTY = derive from kind + target
## (ai_intents_default below), which is correct for every ability shipped today —
## so this is an OVERRIDE, not something an author has to fill in. Use it to
## NARROW ("this attack exists to land its debuff: ["debuff"], stop competing for
## offense") or to WIDEN. For "the AI never picks this", use ai_priority = 0.0.
@export var ai_intents: Array[String] = []

## Flat multiplier on this ability's score in the AI's ability layer. THE ONLY
## PER-ABILITY AI KNOB, and it matters more than it looks: an archetype's stat
## block cannot say "prefer the stun", because the stun is an ability, not a stat.
## So a disabler's stun .tres carries ai_priority = 3.0 and the archetype simply
## raises its debuff appetite. 0.0 means "the AI never picks this", which is how a
## player-only ability can live on a .tres a creature also carries.
@export var ai_priority: float = 1.0

## TURN GATE: the earliest of ITS OWN turns on which a unit may use this ability.
## 0 / 1 (the default) = no gate. 2 = "never on the opening turn", which is the
## whole reason it exists — a tutorial enemy that opens by tripling its own damage
## teaches the wrong lesson in the wrong order, and a boss the player never gets to
## see before its ultimate lands is a worse boss.
##
## Read by AIContext when it builds the usable (ability, slot) set, so it works at
## every AI phase: it narrows the legal set the choice is drawn from rather than
## competing inside the scoring. It is an AI-ONLY gate — the player's wheel is not
## filtered by it, because a skill-tree ability with a turn gate isn't a thing that
## exists and pretending otherwise would put a rule in the UI with nothing behind it.
@export var ai_not_before_turn: int = 0

# --- A SCRIPTED FOLLOW-UP ----------------------------------------------------
## The id of an ability this unit should take NEXT, whenever it next decides,
## before the three AI layers get a say: "after Riot Shield, always Shield Bash".
##
## It is a COMMITMENT, not a preference, which is why it cannot be expressed as a
## gain — the AI re-decides from scratch every action and has no notion of a plan.
## It still passes the usual gates: the follow-up must be usable (_can_use, so
## cooldown / spirit / silence / action points all apply) and must have a legal
## target, or it is quietly dropped and the normal decision runs.
##
## Also the cheapest telegraph in the game: a two-beat pattern the player can learn
## to read. Blank (the default) = no follow-up, so every existing .tres is unaffected.
@export var ai_follow_up: StringName = &""

# --- presentation: how a RIGGED caster performs it (claude/RIG_SPEC.md §6) ----
## MELEE runs to the target and strikes; RANGED winds up in place and sends a
## projectile; STAY casts in place. AUTO derives it (CombatChoreo.motion_for): a
## buff / heal / shield or anything friendly STAYs; an area or scattered ability is
## RANGED; an ATTACK-delivery attack is MELEE unless the caster holds a gun, bow or
## staff; everything else hostile is RANGED. Presentation only — never read by the
## damage path or the AI. Every existing .tres inherits AUTO.
enum Motion { AUTO, MELEE, RANGED, STAY }
@export var motion: Motion = Motion.AUTO
## Clip override (blank = attack_<weapon> / windup_<weapon> / cast_self by motion).
@export var anim: StringName = &""
## RANGED only: what flies to the target. null = an orb in the element's colour.
@export var projectile: ProjectileLook = null

## The intents this ability serves when it declares none of its own, derived from
## kind + target. Deriving rather than authoring is what lets every existing .tres
## work with no re-save.
##
## NB an ATTACK aimed at a FRIENDLY (ZAP! is kind ATTACK, target ALLY) derives to
## NOTHING. It deals damage to your own side, and no intent in the model wants
## that; an ability that genuinely should be cast on an ally — to steal their
## spirit, say — must say so explicitly with `ai_intents`.
func ai_intents_default() -> Array:
	# Never castable: a PASSIVE, or any of the always-active node shapes.
	if is_passive() or is_always_active():
		return []
	match kind:
		Kind.ATTACK:
			if target == Target.ENEMY or target == Target.ALL_ENEMIES:
				# An attack that also drops a debuff competes for BOTH intents.
				if String(applies_buff) != "":
					return [AI_OFFENSE, AI_DEBUFF]
				return [AI_OFFENSE]
			return []
		Kind.DEBUFF:
			return [AI_DEBUFF]
		Kind.BUFF:
			# A self-buff is how a unit DEFENDS itself; it is also a legitimate
			# thing to do for its own sake, so it serves both.
			if target == Target.SELF:
				return [AI_DEFENSE, AI_BUFF]
			return [AI_BUFF]
		Kind.HEAL:
			if target == Target.SELF:
				return [AI_DEFENSE]
			return [AI_BUFF, AI_DEFENSE]
		Kind.SHIELD:
			if target == Target.SELF:
				return [AI_DEFENSE]
			return [AI_BUFF, AI_DEFENSE]
	return []

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

## Flat spirit the TARGET gains when this ability resolves, at a given rank
## (spirit_grant_ranks override, else the scalar). 0 = no grant.
func spirit_grant_at(points: int) -> int:
	if not spirit_grant_ranks.is_empty():
		return int(spirit_grant_ranks[_rank_index(points, spirit_grant_ranks.size())])
	return spirit_grant

## True when this ability carries any one-time spirit effect (gain, steal or grant)
## at the given rank — lets combat skip the work when there is nothing to do.
func has_spirit_effect(points: int) -> bool:
	return spirit_gain_at(points) != 0 or spirit_steal_at(points) != 0 \
		or spirit_grant_at(points) != 0

## The second element's scaling multiplier at a given rank (bonus_scaling_mult_ranks
## override, else the scalar). 0.0 => the bonus hit computes to nothing.
func bonus_scaling_mult_at(points: int) -> float:
	if not bonus_scaling_mult_ranks.is_empty():
		return float(bonus_scaling_mult_ranks[_rank_index(points, bonus_scaling_mult_ranks.size())])
	return bonus_scaling_mult

## True when this ATTACK carries a second hit of a DIFFERENT element. Both the
## element and a stat to scale it off are required — a bonus element with no
## scaling would compute to 0 and float a pointless "0" over the target.
func has_bonus_damage() -> bool:
	return String(bonus_damage_element) != "" and String(bonus_scaling_stat) != ""

## The raw (pre-mitigation) second-element damage this attack deals at `points`,
## off the given caster stat snapshot. 0.0 when it carries no second element.
func compute_bonus_damage(caster_stats: Dictionary, points: int = 1) -> float:
	if not has_bonus_damage():
		return 0.0
	var stat := float(caster_stats.get(String(bonus_scaling_stat), 0.0))
	return maxf(0.0, bonus_scaling_mult_at(points) * stat)

## The FLAT pierce this ability carries at a given rank (pierce_flat_ranks override,
## else the scalar). Combat sums it with the per-debuff term.
func pierce_flat_at(points: int) -> float:
	if not pierce_flat_ranks.is_empty():
		return float(pierce_flat_ranks[_rank_index(points, pierce_flat_ranks.size())])
	return pierce_flat

## The %-of-max-HP extra hit at a given rank, as a fraction. 0.0 => none.
func pct_max_hp_damage_at(points: int) -> float:
	if not pct_max_hp_damage_ranks.is_empty():
		return float(pct_max_hp_damage_ranks[_rank_index(points, pct_max_hp_damage_ranks.size())])
	return pct_max_hp_damage

## True when this ATTACK carries a %-of-max-HP hit at ANY rank. Tests the array as
## well as the scalar, so an ability whose rank-1 value is 0 but whose rank-3 value is
## not is never mistaken for one that has no such hit at all.
func has_pct_max_hp_damage() -> bool:
	if pct_max_hp_damage > 0.0:
		return true
	for v in pct_max_hp_damage_ranks:
		if float(v) > 0.0:
			return true
	return false

## The element the %-of-max-HP hit is dealt as: pct_max_hp_element when set, else the
## ability's own element.
func pct_max_hp_element_key() -> String:
	var e := String(pct_max_hp_element)
	return e if e != "" else element_key()

## The chance (0..1) that this ability's applies_buff is ATTEMPTED at a given rank.
## Clamped, so a mis-authored value (a percentage typed as 25 instead of 0.25) can
## never make a rider impossible, and a negative one can never make it certain.
func apply_chance_at(points: int) -> float:
	if not apply_chance_ranks.is_empty():
		return clampf(float(apply_chance_ranks[_rank_index(points, apply_chance_ranks.size())]), 0.0, 1.0)
	return clampf(apply_chance, 0.0, 1.0)

## Number of strikes at a given rank (hit_count_ranks override, else the scalar).
## Floored at 1 — a zero typed into a .tres can never make an attack do nothing.
func hit_count_at(points: int) -> int:
	var n := hit_count
	if not hit_count_ranks.is_empty():
		n = int(hit_count_ranks[_rank_index(points, hit_count_ranks.size())])
	return maxi(1, n)

## True when this attack strikes more than once at the given rank.
func is_multi_hit(points: int = 1) -> bool:
	return hit_count_at(points) > 1

## The factor applied to EACH hit's damage terms: 1/N for a split multi-hit, 1.0
## otherwise. So hits x scale is 1.0 for a split ability (same total as one hit) and
## N for an unsplit one — the identity combat and the AI estimator both rely on.
func hit_damage_scale(points: int) -> float:
	var n := hit_count_at(points)
	return (1.0 / float(n)) if hit_split and n > 1 else 1.0

## True when each hit picks a fresh random legal target. Always false for an area
## ability (see hit_retarget).
func retargets_each_hit() -> bool:
	return hit_retarget == HitRetarget.RANDOM and not is_area_target()

## True when this ability resolves against every unit on a side (ALL_ENEMIES /
## ALL_ALLIES) rather than one. The single definition combat, the camera and the AI
## all read.
func is_area_target() -> bool:
	return target == Target.ALL_ENEMIES or target == Target.ALL_ALLIES or target == Target.ALL_OTHER_ALLIES

## The earliest of a unit's OWN turns on which the AI may use this ability. Floors
## at 1 so 0 (the default) and 1 both mean "no gate", and `turns_taken >= this` is
## the whole test.
func not_before_turn() -> int:
	return maxi(1, ai_not_before_turn)

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

# --- NEPHILIC KIT accessors (see the field block above) ------------------------
func _rank_f(arr: Array, points: int, fallback: float = 0.0) -> float:
	if arr.is_empty():
		return fallback
	return float(arr[_rank_index(points, arr.size())])

func _rank_i(arr: Array, points: int, fallback: int = 0) -> int:
	if arr.is_empty():
		return fallback
	return int(arr[_rank_index(points, arr.size())])

func perk_at(points: int) -> Dictionary:
	if perk_ranks.is_empty():
		return {}
	var d = perk_ranks[_rank_index(points, perk_ranks.size())]
	return (d as Dictionary).duplicate(true) if typeof(d) == TYPE_DICTIONARY else {}

func applies_buff_duration_at(points: int) -> int:
	return _rank_i(applies_buff_duration_ranks, points, applies_buff_duration)

func applies_buff_count_at(points: int) -> int:
	return maxi(1, _rank_i(applies_buff_count_ranks, points, 1))

func hp_cost_pct_max_at(points: int) -> float:
	return _rank_f(hp_cost_pct_max_ranks, points)

func has_hp_cost() -> bool:
	return not hp_cost_pct_max_ranks.is_empty() or hp_cost_pct_current > 0.0

func heal_missing_hp_bonus_at(points: int) -> float:
	return _rank_f(heal_missing_hp_bonus_ranks, points)

func heal_from_hp_paid_at(points: int) -> float:
	return _rank_f(heal_from_hp_paid_ranks, points)

func shield_pct_caster_max_hp_at(points: int) -> float:
	return _rank_f(shield_pct_caster_max_hp_ranks, points)

func cleanse_count_at(points: int) -> int:
	return _rank_i(cleanse_count_ranks, points)

func extend_turns_at(points: int) -> int:
	return _rank_i(extend_turns_ranks, points)

func excise_count_at(points: int) -> int:
	return _rank_i(excise_count_ranks, points)

## Targets a friendly unit other than the caster.
func is_other_ally_target() -> bool:
	return target == Target.ALLY_OTHER or target == Target.ALL_OTHER_ALLIES
