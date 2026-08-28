extends RefCounted
class_name CombatBuffs

## ============================================================================
## COMBAT BUFFS  —  the buff / debuff engine (class_name global)
## ============================================================================
## Applies buffs to a CharacterBase, stacks / refreshes them, ticks their
## per-turn effects, answers gameplay queries (silence / stun / resist multiplier
## / healing multiplier), and fires on-expire events. It is the one place that
## MUTATES the "buffs" / "debuffs" baskets; combat.gd drives it once per turn and
## the visible parts (damage numbers, bar refreshes) are applied by combat from
## the report this returns.
##
## Everything is static (like CombatMath / CombatCrit). A buff is the rich entry
## dict built by Buff.make (see buff.gd); it lives in the same baskets the
## additive stat model already sums, so a buff's "mods"/"mult" apply to effective
## stats for free — this engine only handles the parts that AREN'T a plain stat.
##
## class_name global — RESTART Godot once after adding this script.
## ----------------------------------------------------------------------------

# Basket-read stat keys that combat consumes from buffs+debuffs (kept here so the
# key strings live in one place; CombatMath / the heal path read the same names).
const RESIST_MULT_KEY := "resist_mult"                 # global multiplicative resist bonus
const HEALING_RECEIVED_MULT_KEY := "healing_received_mult"  # additive around 0, in mods

# ============================================================================
# Applying
# ============================================================================
## Apply a buff/debuff entry to `body`. Handles stacking (same id already present
## + stackable => bump stacks up to max_stacks and refresh duration) and refresh
## (same id, not stackable => refresh to the longer duration). Returns the entry
## that now lives in the basket. Re-clamps vitals in case a max-HP / max-Spirit
## mod changed the ceilings.
static func apply(body: CharacterBase, entry: Dictionary) -> Dictionary:
	if body == null or entry.is_empty():
		return {}
	var basket := Buff.basket_for(entry)
	if not body.baskets.has(basket):
		body.baskets[basket] = []

	var incoming: Dictionary = entry.duplicate(true)
	# _find returns a Dictionary OR null, so it must stay untyped (no := inference).
	var existing = _find(body, basket, str(incoming.get("id", "")))

	var result: Dictionary
	if existing != null:
		if bool(existing.get("stackable", false)):
			var add_stacks := maxi(1, int(incoming.get("stacks", 1)))
			var cap := int(existing.get("max_stacks", 1))
			var new_stacks := int(existing.get("stacks", 1)) + add_stacks
			if cap > 0:
				new_stacks = mini(new_stacks, cap)
			existing["stacks"] = new_stacks
			Buff.recompute_scaled(existing)
		existing["duration"] = _combine_duration(int(existing.get("duration", -1)), int(incoming.get("duration", -1)))
		result = existing
	else:
		body.baskets[basket].append(incoming)
		result = incoming

	body.clamp_vitals()
	return result

## Remove a buff/debuff by id from BOTH baskets (no expiry event fired). Returns
## true if something was removed. Use for a dispel / cleanse.
static func remove(body: CharacterBase, id: String) -> bool:
	if body == null:
		return false
	var removed := false
	for basket in ["buffs", "debuffs"]:
		if body.baskets.has(basket):
			var kept := []
			for e in body.baskets[basket]:
				if str(e.get("id", "")) == id:
					removed = true
				else:
					kept.append(e)
			body.baskets[basket] = kept
	if removed:
		body.clamp_vitals()
	return removed

## Remove the OLDEST debuff whose element tag matches `element` (e.g. "ice"), from
## the debuffs basket. "Oldest" = lowest index, since entries are appended in the
## order they were applied. Returns true iff one was found and removed. Used by the
## Shatter ability to consume a single ice debuff and gate its bonus effect on the
## target actually carrying one. No expiry event is fired (this is a consume, not a
## natural expiry).
static func consume_oldest_debuff_of_element(body: CharacterBase, element: String) -> bool:
	if body == null or element == "" or not body.baskets.has("debuffs"):
		return false
	var arr: Array = body.baskets["debuffs"]
	for i in arr.size():
		var e = arr[i]
		if typeof(e) == TYPE_DICTIONARY and str(e.get("element", "")) == element:
			arr.remove_at(i)
			body.clamp_vitals()
			return true
	return false

## Hoarfrost consume: if `body` carries any ice-amp debuff (ice_amp_per_stack > 0),
## amplify `amount` by (1 + sum of ice_amp_per_stack * stacks across those entries)
## and REMOVE them (a one-shot consume). Returns the amplified amount; returns it
## unchanged when no such debuff is present. Called by BattleCharacter.take_damage
## for a sourced ice hit, so hoarfrost boosts the next ice attack and is then spent.
static func apply_incoming_ice_amp(body: CharacterBase, amount: int) -> int:
	if body == null or not body.baskets.has("debuffs"):
		return amount
	var total_amp := 0.0
	var kept := []
	var consumed := false
	for e in body.baskets["debuffs"]:
		if typeof(e) == TYPE_DICTIONARY and float(e.get("ice_amp_per_stack", 0.0)) > 0.0:
			total_amp += float(e.get("ice_amp_per_stack", 0.0)) * float(Buff.stacks(e))
			consumed = true          # drop it (consumed by this ice instance)
		else:
			kept.append(e)
	if not consumed:
		return amount
	body.baskets["debuffs"] = kept
	body.clamp_vitals()
	return int(round(maxf(0.0, float(amount) * (1.0 + total_amp))))

## Count the debuffs on `body` tagged with `element` (e.g. "ice"). Used by Snap to
## scale its damage by the number of ice debuffs the target carries. 0 when none.
static func count_debuffs_of_element(body: CharacterBase, element: String) -> int:
	if body == null or element == "" or not body.baskets.has("debuffs"):
		return 0
	var n := 0
	for e in body.baskets["debuffs"]:
		if typeof(e) == TYPE_DICTIONARY and str(e.get("element", "")) == element:
			n += 1
	return n

# ============================================================================
# The start-of-turn tick
# ============================================================================
## Collect this unit's start-of-turn effects and advance every buff/debuff by one
## turn. DoT and spirit_per_turn are gathered for the FULL current stack of each
## entry (including an entry that expires this turn — it still ticks once more),
## THEN durations are decremented and any that hit 0 are removed.
##
## VULNERABILITY: each DoT's damage is multiplied by the BEARER's effective
## `vulnerability` stat (default 1.0) as it is collected — i.e. when the buff
## computes how much damage it will deal, BEFORE that number is handed off to be
## applied. A debuff can raise vulnerability (more DoT taken); a buff can lower it.
##
## Returns a report for combat to apply the VISIBLE parts of:
##   {
##     "dots":        [ {amount:int, element:String}, ... ],  # one per DoT entry
##     "dot_total":   int,                                    # summed DoT damage
##     "heals":       [ {amount:int}, ... ],                  # one per heal-over-turn entry
##     "heal_total":  int,                                    # summed heal amount
##     "spirit_delta": float,   # sum of every entry's spirit_per_turn (+/-)
##     "expired":     [ entry, ... ],  # entries removed this tick (for expiry FX)
##   }
## NOTE: this does NOT apply DoT to HP or change spirit itself — combat does that
## through BattleCharacter.take_damage() (so the number animates + death is
## handled) and by adjusting spirit alongside the default per-turn regen.
static func collect_turn_start(body: CharacterBase) -> Dictionary:
	var report := {"dots": [], "dot_total": 0, "heals": [], "heal_total": 0, "spirit_delta": 0.0, "expired": []}
	if body == null:
		return report

	# The bearer's DoT vulnerability multiplier (clamped >= 0). Applied to every
	# DoT this turn as it is computed, before the damage is dealt.
	var vuln := maxf(0.0, body.get_effective("vulnerability"))

	for basket in ["buffs", "debuffs"]:
		if not body.baskets.has(basket):
			continue
		var kept := []
		for e in body.baskets[basket]:
			if typeof(e) != TYPE_DICTIONARY:
				continue
			# --- effects for this turn (full current stack) ---
			var raw_dmg := Buff.dot_damage(e)
			if raw_dmg > 0:
				var dmg := int(round(float(raw_dmg) * vuln))   # vulnerability applied here
				if dmg > 0:
					report["dots"].append({"amount": dmg, "element": str(e.get("dot_element", "physical"))})
					report["dot_total"] = int(report["dot_total"]) + dmg
			# --- heal-over-turn (Scaled Skin, Gliogenesis, ...) : restore HP this turn ---
			# FLAT snapshot (heal_per_turn) + LIVE % of max HP (heal_pct_per_turn); collected
			# OUTSIDE the DoT branch so a pure heal buff (no dot) still heals.
			var heal := Buff.heal_amount(e)
			var heal_pct := float(e.get("heal_pct_per_turn", 0.0))
			if heal_pct > 0.0:
				heal += int(round(maxf(0.0, float(body.max_hp()) * heal_pct)))
			if heal > 0:
				report["heals"].append({"amount": heal})
				report["heal_total"] = int(report["heal_total"]) + heal
			report["spirit_delta"] = float(report["spirit_delta"]) + float(e.get("spirit_per_turn", 0.0))

			# --- advance duration ---
			var dur := int(e.get("duration", -1))
			if dur < 0:
				kept.append(e)          # permanent: never counts down
				continue
			dur -= 1
			if dur <= 0:
				report["expired"].append(e)   # dropped from the basket
			else:
				e["duration"] = dur
				kept.append(e)
		body.baskets[basket] = kept

	body.clamp_vitals()
	return report

## Fire the on-expire event for an entry (called by combat for each expired entry
## the tick reported). Most buffs set no expire_effect and this is a no-op; add
## cases as you build expire events. `unit` is the BattleCharacter it was on.
static func fire_expiry(unit, entry: Dictionary) -> void:
	var effect := str(entry.get("expire_effect", ""))
	if effect == "":
		return
	match effect:
		# Example hook — add your own expire events here. Each case gets the unit
		# (a BattleCharacter, so it can take_damage / heal / apply another buff)
		# and the entry that just expired.
		#   "detonate":
		#       if unit and unit.has_method("take_damage"):
		#           unit.take_damage(50, str(entry.get("element", "true")))
		_:
			pass

# ============================================================================
# "When struck" reactions  (thorns, and future on-struck effects)
# ============================================================================
## Fire every ON-STRUCK reaction the STRUCK unit carries, in response to being hit
## by `attacker_unit` for `damage_taken` of `element`. This is the generic
## "when struck do X" hook: a buff/debuff entry may carry an "on_struck" list of
## reaction dicts, each dispatched here by its "effect" id. Called by
## BattleCharacter.take_damage() when a hit has a source.
##
## `struck_unit` / `attacker_unit` are BattleCharacters (kept untyped to avoid a
## class dependency, mirroring fire_expiry). Reactions that deal damage back call
## attacker_unit.take_damage() WITHOUT a source, so thorns can't recurse.
##
## Reaction schema (all keys optional unless noted):
##   { "effect": "reflect", "amount": float, "percent": float, "element": String }
##     -> deals amount*stacks + percent*damage_taken back to the attacker.
##        percent is a fraction (0.25 = 25% of the damage taken). element defaults
##        to the reaction's, then the entry's, then "physical".
## Add new "effect" cases below as you build more on-struck effects.
static func fire_on_struck(struck_unit, attacker_unit, damage_taken: int, element: String) -> void:
	if struck_unit == null or struck_unit.body == null:
		return
	var body: CharacterBase = struck_unit.body
	for basket in ["buffs", "debuffs"]:
		if not body.baskets.has(basket):
			continue
		for e in body.baskets[basket]:
			if typeof(e) != TYPE_DICTIONARY:
				continue
			var reactions := Buff.on_struck(e)
			if reactions.is_empty():
				continue
			var stacks := Buff.stacks(e)
			for r in reactions:
				if typeof(r) != TYPE_DICTIONARY:
					continue
				match str(r.get("effect", "")):
					"reflect":
						_react_reflect(r, e, stacks, attacker_unit, damage_taken)
					"self_pct_max_hp":
						_react_self_pct_max_hp(r, e, struck_unit)
					_:
						pass

## Reflect (thorns): deal amount*stacks + percent*damage_taken back to the
## attacker as its own element. No source is passed, so it never re-triggers.
static func _react_reflect(reaction: Dictionary, entry: Dictionary, stacks: int, attacker_unit, damage_taken: int) -> void:
	if attacker_unit == null or not attacker_unit.has_method("is_alive") or not attacker_unit.is_alive():
		return
	var flat := float(reaction.get("amount", 0.0)) * float(stacks)
	var pct := float(reaction.get("percent", 0.0)) * float(maxi(damage_taken, 0))
	var total := int(round(maxf(0.0, flat + pct)))
	if total <= 0:
		return
	var rel := str(reaction.get("element", str(entry.get("element", ""))))
	if rel == "":
		rel = "physical"
	attacker_unit.take_damage(total, rel, false)

## Self-damage on struck (Rime Skin): the STRUCK bearer takes `percent` of its OWN
## max HP as damage of the reaction element (default ice) whenever it is hit by a
## sourced attack. Dealt with NO source, so it triggers no further on-struck and no
## hoarfrost amp. `percent` is a fraction (0.05 = 5%); not stack-scaled.
static func _react_self_pct_max_hp(reaction: Dictionary, entry: Dictionary, struck_unit) -> void:
	if struck_unit == null or not struck_unit.has_method("is_alive") or not struck_unit.is_alive():
		return
	var pct := float(reaction.get("percent", 0.0))
	if pct <= 0.0:
		return
	var dmg := int(round(maxf(0.0, float(struck_unit.get_max_hp()) * pct)))
	if dmg <= 0:
		return
	var rel := str(reaction.get("element", str(entry.get("element", "ice"))))
	if rel == "":
		rel = "ice"
	struck_unit.take_damage(dmg, rel, false)

# ============================================================================
# "On hit" application  (Wraith Form: coat every struck target in a buff)
# ============================================================================
## Fire every ON-HIT-APPLY effect the ATTACKER carries against the target it just hit.
## An attacker buff/debuff entry may carry an "on_hit_apply" list of specs
## { "buff": "<id>", (opt) "duration": int }; for each, the named BuffLibrary entry is
## built and applied to `struck_unit`, with its duration overridden when the spec sets
## one. Called by combat's ATTACK branch after the hit lands. `struck_unit` is a
## BattleCharacter (kept untyped like fire_on_struck). Wraith Form uses this to drop a
## 1-turn Rime Skin on whatever the wraith attacks.
static func fire_on_hit(attacker_body: CharacterBase, struck_unit) -> void:
	if attacker_body == null or struck_unit == null or struck_unit.body == null:
		return
	var applied_any := false
	for basket in ["buffs", "debuffs"]:
		if not attacker_body.baskets.has(basket):
			continue
		for e in attacker_body.baskets[basket]:
			if typeof(e) != TYPE_DICTIONARY:
				continue
			for spec in Buff.on_hit_apply(e):
				if typeof(spec) != TYPE_DICTIONARY:
					continue
				var bid := str(spec.get("buff", ""))
				if bid == "":
					continue
				var entry := BuffLibrary.build(bid, attacker_body, struck_unit.body)
				if entry.is_empty():
					continue
				if spec.has("duration"):
					entry["duration"] = int(spec["duration"])
				apply(struck_unit.body, entry)
				applied_any = true
	if applied_any and struck_unit.has_method("refresh_buffs"):
		struck_unit.refresh_buffs()


# ============================================================================
# Queries
# ============================================================================
## True if any active buff/debuff silences this body (blocks spirit-cost abilities).
static func is_silenced(body: CharacterBase) -> bool:
	return _any_flag(body, "silence")

## True if any active buff/debuff stuns this body (blocks acting entirely).
static func is_stunned(body: CharacterBase) -> bool:
	return _any_flag(body, "stun")

## The multiplicative resist bonus for `element`: sum of every buff/debuff's
## global resist_mult plus its per-element resist_mult_by_element[element]. Read
## by CombatMath, which turns effective resist into base_resist * (1 + this).
static func resist_mult_bonus(body: CharacterBase, element: String) -> float:
	if body == null:
		return 0.0
	var total := 0.0
	for basket in ["buffs", "debuffs"]:
		if not body.baskets.has(basket):
			continue
		for e in body.baskets[basket]:
			if typeof(e) != TYPE_DICTIONARY:
				continue
			total += float(e.get(RESIST_MULT_KEY, 0.0))
			var rme = e.get("resist_mult_by_element", {})
			if typeof(rme) == TYPE_DICTIONARY and rme.has(element):
				total += float(rme[element])
	return total

## Multiplier applied to healing this body RECEIVES: 1.0 + sum of
## healing_received_mult across its buffs+debuffs (stored in each entry's "mods",
## so it also shows up in effective stats). Never returns below 0.
static func healing_received_mult(body: CharacterBase) -> float:
	if body == null:
		return 1.0
	var bonus := body.get_basket_bonus("buffs", HEALING_RECEIVED_MULT_KEY) \
		+ body.get_basket_bonus("debuffs", HEALING_RECEIVED_MULT_KEY)
	return maxf(0.0, 1.0 + bonus)

## Every VISIBLE buff/debuff entry (buffs first, then debuffs) for the UI.
static func visible_entries(body: CharacterBase) -> Array:
	var out := []
	if body == null:
		return out
	for basket in ["buffs", "debuffs"]:
		if not body.baskets.has(basket):
			continue
		for e in body.baskets[basket]:
			if typeof(e) == TYPE_DICTIONARY and bool(e.get("visible", true)):
				out.append(e)
	return out

# ============================================================================
# Internals
# ============================================================================
static func _find(body: CharacterBase, basket: String, id: String):
	if id == "" or not body.baskets.has(basket):
		return null
	for e in body.baskets[basket]:
		if typeof(e) == TYPE_DICTIONARY and str(e.get("id", "")) == id:
			return e
	return null

## Combine two durations: a permanent (-1) side wins; otherwise keep the longer.
static func _combine_duration(a: int, b: int) -> int:
	if a < 0 or b < 0:
		return -1
	return maxi(a, b)

static func _any_flag(body: CharacterBase, flag: String) -> bool:
	if body == null:
		return false
	for basket in ["buffs", "debuffs"]:
		if not body.baskets.has(basket):
			continue
		for e in body.baskets[basket]:
			if typeof(e) == TYPE_DICTIONARY and bool(e.get(flag, false)):
				return true
	return false
