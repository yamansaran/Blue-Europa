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
## additive stat model already sums, so a buff's "mods" apply to effective stats
## for free — this engine only handles the parts that AREN'T a plain additive
## stat.
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

# ============================================================================
# The start-of-turn tick
# ============================================================================
## Collect this unit's start-of-turn effects and advance every buff/debuff by one
## turn. DoT and spirit_per_turn are gathered for the FULL current stack of each
## entry (including an entry that expires this turn — it still ticks once more),
## THEN durations are decremented and any that hit 0 are removed.
##
## Returns a report for combat to apply the VISIBLE parts of:
##   {
##     "dots":        [ {amount:int, element:String}, ... ],  # one per DoT entry
##     "dot_total":   int,                                    # summed DoT damage
##     "spirit_delta": float,   # sum of every entry's spirit_per_turn (+/-)
##     "expired":     [ entry, ... ],  # entries removed this tick (for expiry FX)
##   }
## NOTE: this does NOT apply DoT to HP or change spirit itself — combat does that
## through BattleCharacter.take_damage() (so the number animates + death is
## handled) and by adjusting spirit alongside the default per-turn regen.
static func collect_turn_start(body: CharacterBase) -> Dictionary:
	var report := {"dots": [], "dot_total": 0, "spirit_delta": 0.0, "expired": []}
	if body == null:
		return report

	for basket in ["buffs", "debuffs"]:
		if not body.baskets.has(basket):
			continue
		var kept := []
		for e in body.baskets[basket]:
			if typeof(e) != TYPE_DICTIONARY:
				continue
			# --- effects for this turn (full current stack) ---
			var dmg := Buff.dot_damage(e)
			if dmg > 0:
				report["dots"].append({"amount": dmg, "element": str(e.get("dot_element", "physical"))})
				report["dot_total"] = int(report["dot_total"]) + dmg
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
