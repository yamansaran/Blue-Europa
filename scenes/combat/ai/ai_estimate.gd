extends RefCounted
class_name AIEstimate

## ============================================================================
## AI ESTIMATE  —  dry-run damage, effective HP and offer value  (AI_PRIMER §10-11)
## ============================================================================
## Everything goes THROUGH THE REAL PIPELINE: expected_damage calls
## CombatMath.preview, the non-rolling twin of resolve(), so the AI's idea of a hit
## can never drift from the real hit. Every result is cached on the AIContext for the
## one decision it was built for.
##
## class_name global — RESTART Godot once after adding this script.
## ----------------------------------------------------------------------------

const HEAL_VALUE_SCALE := 3.0
const SHIELD_VALUE_SCALE := 2.5
const SPIRIT_VALUE_SCALE := 2.0

## Expected damage of `ability` cast by `caster` on `tgt`, folding in the cheap,
## deterministic riders (Snap's per-debuff multiplier, Cryonecrosis' pierce, the flat
## pierce term, Shatter's %-max-HP bonus, the unconditional %-max-HP term, a second
## element). 0 for anything that is not an ATTACK.
static func expected_damage(ctx: AIContext, caster: BattleCharacter, tgt: BattleCharacter, ability: Ability) -> float:
	if ctx == null or caster == null or tgt == null or ability == null or caster.body == null or tgt.body == null:
		return 0.0
	if ability.kind != Ability.Kind.ATTACK:
		return 0.0
	var key := "exp|%d|%d|%s" % [caster.get_instance_id(), tgt.get_instance_id(), String(ability.id)]
	if ctx.cache.has(key):
		return float(ctx.cache[key])
	var combat = ctx.combat
	var rank: int = combat._ability_rank(caster, ability)
	var bonus: Dictionary = {}
	if caster == combat._player:
		var ch: Node = combat.get_node_or_null("/root/Character")
		if ch and ch.has_method("ability_scaling_bonus"):
			bonus = ch.ability_scaling_bonus(String(ability.id))
	var extra_pierce := 0.0
	var pp_elem := String(ability.pierce_per_debuff_element)
	if pp_elem != "":
		extra_pierce = ability.pierce_per_debuff_at(rank) * float(CombatBuffs.count_debuffs_of_element(tgt.body, pp_elem))
	# Flat pierce, summed with the per-debuff term exactly as combat does it.
	extra_pierce += ability.pierce_flat_at(rank)
	var pv := CombatMath.preview(caster.body, tgt.body, ability, rank, bonus, extra_pierce)
	var dmg := float(pv["expected"])
	var per_elem := String(ability.damage_per_debuff_element)
	if per_elem != "":
		# Snap deals NOTHING without a matching debuff — the AI must know that.
		dmg *= float(CombatBuffs.count_debuffs_of_element(tgt.body, per_elem))
	var hit_chance := 1.0 - clampf(float(pv["dodge_chance"]) / 100.0, 0.0, 1.0)
	if ability.has_bonus_damage():
		var raw := ability.compute_bonus_damage(caster.body.effective_stats(), rank)
		if raw > 0.0:
			dmg += float(CombatMath.resolve_flat(caster.body, tgt.body, raw, String(ability.bonus_damage_element))) * hit_chance
	# The UNCONDITIONAL %-of-max-HP term. Unlike Shatter's, it has no gate, so it is
	# always part of what this attack is worth — and against a big target it can be
	# most of it, which is the whole reason a titan-slayer archetype exists.
	if ability.has_pct_max_hp_damage():
		var pct_mh := ability.pct_max_hp_damage_at(rank)
		if pct_mh > 0.0:
			var raw_mh := float(tgt.get_max_hp()) * pct_mh
			dmg += float(CombatMath.resolve_flat(caster.body, tgt.body, raw_mh, ability.pct_max_hp_element_key())) * hit_chance
	if ability.has_shatter():
		var elem := String(ability.consume_debuff_element)
		if CombatBuffs.count_debuffs_of_element(tgt.body, elem) > 0:
			var pct := ability.shatter_pct_max_hp_at(rank)
			if pct > 0.0:
				var raw2 := float(tgt.get_max_hp()) * pct
				dmg += float(CombatMath.resolve_flat(caster.body, tgt.body, raw2, String(ability.shatter_damage_element))) * hit_chance
	# MULTI-HIT. Everything above is ONE strike at full value. Dodge and crit are
	# already folded in as expectations, and both are linear, so N strikes are worth
	# N x one — times the split scale. hits x scale is 1.0 for a split ability (the
	# same total as one hit: Flurry) and N for an unsplit one (Flail).
	# NB Shatter's term above scales the same way here, while in combat it fires at
	# full value on every hit that finds a debuff to consume. Nothing ships with a
	# multi-hit Shatter; if one is ever authored, this is where the estimate drifts.
	var hits := ability.hit_count_at(rank)
	if hits > 1:
		dmg *= float(hits) * ability.hit_damage_scale(rank)
	# RANDOM-TARGET (Spray): the strikes scatter over every legal hostile, so THIS
	# target's expected share is the total divided by the pool. Layer 3 sums the
	# share over the pool (AIAbility.is_area), which gives back the honest total —
	# and a scatter-shot correctly almost never reads as LETHAL on one unit.
	if ability.retargets_each_hit():
		var pool := 0
		for u in combat._units:
			if u != null and u.is_alive() and combat._valid_target(caster, ability, u):
				pool += 1
		dmg /= float(maxi(1, pool))
	dmg = maxf(0.0, dmg)
	ctx.cache[key] = dmg
	return dmg

## Health a hit of `element` must chew through. TRUE damage ignores shields.
static func effective_hp(u: BattleCharacter, element: String = "") -> float:
	if u == null or u.body == null:
		return 1.0
	var hp := float(u.get_hp())
	if element != "true":
		hp += float(CombatShields.total(u.body))
	return maxf(1.0, hp)

## Abilities `u` could cast AT ALL right now, ignoring action points (used for units
## that are not the actor — threat, ally_power). Cooldown + spirit + silence respected.
static func castable_attacks(ctx: AIContext, u: BattleCharacter) -> Array:
	var key := "atk|%d" % u.get_instance_id()
	if ctx.cache.has(key):
		return ctx.cache[key]
	var out: Array = []
	if u != null and u.body != null and u.is_alive() and not CombatBuffs.is_stunned(u.body):
		for slot in u.loadout.size():
			var aid := str(u.loadout[slot])
			if aid == "":
				continue
			var ab: Ability = ctx.combat._get_ability(aid)
			if ab == null or ab.kind != Ability.Kind.ATTACK or ab.is_passive() or ab.is_always_active():
				continue
			if u.on_cooldown(slot):
				continue
			var cost := ab.spirit_cost_at(ctx.combat._ability_rank(u, ab))
			if cost > 0 and (CombatBuffs.is_silenced(u.body) or u.get_spirit() < cost):
				continue
			out.append(ab)
	ctx.cache[key] = out
	return out

## The attack list for `caster`: the actor's USABLE offense pairs, anyone else's
## castable attacks.
static func attacks_of(ctx: AIContext, caster: BattleCharacter) -> Array:
	if caster == ctx.actor:
		var out: Array = []
		for p in ctx.pairs:
			var ab: Ability = p["ability"]
			if ab.kind == Ability.Kind.ATTACK:
				out.append(ab)
		return out
	return castable_attacks(ctx, caster)

## { "ability": Ability|null, "expected": float, "element": String } — the best single
## hit `caster` has on `tgt`.
static func best_attack(ctx: AIContext, caster: BattleCharacter, tgt: BattleCharacter) -> Dictionary:
	var key := "best|%d|%d" % [caster.get_instance_id(), tgt.get_instance_id()]
	if ctx.cache.has(key):
		return ctx.cache[key]
	var best := {"ability": null, "expected": 0.0, "element": "physical"}
	for ab in attacks_of(ctx, caster):
		var a: Ability = ab
		if not _legal_against(ctx, caster, a, tgt):
			continue
		var e := expected_damage(ctx, caster, tgt, a)
		if e > float(best["expected"]):
			best = {"ability": a, "expected": e, "element": a.element_key()}
	ctx.cache[key] = best
	return best

## The MEAN expected damage over `caster`'s damaging options against `tgt` (softness).
static func mean_attack(ctx: AIContext, caster: BattleCharacter, tgt: BattleCharacter) -> float:
	var total := 0.0
	var n := 0
	for ab in attacks_of(ctx, caster):
		var a: Ability = ab
		if not _legal_against(ctx, caster, a, tgt):
			continue
		total += expected_damage(ctx, caster, tgt, a)
		n += 1
	return total / float(n) if n > 0 else 0.0

static func _legal_against(ctx: AIContext, caster: BattleCharacter, a: Ability, tgt: BattleCharacter) -> bool:
	match a.target:
		Ability.Target.ALL_ENEMIES:
			return ctx.combat._is_hostile(caster, tgt)
		Ability.Target.ALL_ALLIES:
			return not ctx.combat._is_hostile(caster, tgt)
	return ctx.combat._valid_target(caster, a, tgt)

# ----------------------------------------------------------------------------
## How GOOD a castable effect is, in "about 1.0 is ordinary" units (§10.2).
static func entry_value(ctx: AIContext, caster: BattleCharacter, ability: Ability, tgt: BattleCharacter) -> float:
	if ability == null or caster == null or caster.body == null:
		return 0.0
	var key := "val|%d|%s|%d" % [caster.get_instance_id(), String(ability.id), tgt.get_instance_id() if tgt else 0]
	if ctx.cache.has(key):
		return float(ctx.cache[key])
	var combat = ctx.combat
	var rank: int = combat._ability_rank(caster, ability)
	var value := 0.0
	var bid := String(ability.applies_buff)
	if bid != "" and tgt != null and tgt.body != null:
		var entry := built_entry(ctx, caster, ability, tgt)
		if not entry.is_empty():
			# APPLY CHANCE discounts the BUFF half and nothing else: a 25% rider is
			# worth a quarter of its severity to the AI, while the heal / shield /
			# spirit terms below are certain and stay whole. This single line also
			# reaches offer_strength, which gauges an intent's appetite off the same
			# function — so a creature holding only an unreliable debuff correctly
			# wants DEBUFF less, with no second edit anywhere.
			value += ability.apply_chance_at(rank) * AISignals.entry_severity(entry)
	var max_hp := float(maxi(1, tgt.get_max_hp())) if tgt else 1.0
	match ability.kind:
		Ability.Kind.HEAL:
			value += ability.compute_heal(caster.body.effective_stats(), rank) * combat._heal_power_dealt(caster.body) / max_hp * HEAL_VALUE_SCALE
		Ability.Kind.SHIELD:
			value += ability.compute_shield(caster.body.effective_stats(), rank) * combat._shield_power_dealt(caster.body) / max_hp * SHIELD_VALUE_SCALE
	if ability.has_spirit_effect(rank):
		var sp := float(ability.spirit_gain_at(rank) + ability.spirit_grant_at(rank) + ability.spirit_steal_at(rank))
		value += sp / maxf(1.0, float(caster.get_max_spirit())) * SPIRIT_VALUE_SCALE
	ctx.cache[key] = value
	return value

## The buff entry `ability` would drop on `tgt`, BUILT BUT NEVER APPLIED (cached).
static func built_entry(ctx: AIContext, caster: BattleCharacter, ability: Ability, tgt: BattleCharacter) -> Dictionary:
	var bid := String(ability.applies_buff)
	if bid == "" or tgt == null:
		return {}
	var rank: int = ctx.combat._ability_rank(caster, ability)
	var key := "entry|%d|%s|%d" % [caster.get_instance_id(), String(ability.id), tgt.get_instance_id()]
	if ctx.cache.has(key):
		return ctx.cache[key]
	var entry := BuffLibrary.build(ctx.combat._rank_clone_id(bid, rank), caster.body, tgt.body)
	ctx.cache[key] = entry
	return entry
