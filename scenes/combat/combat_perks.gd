extends RefCounted
class_name CombatPerks

## ============================================================================
## COMBAT PERKS  —  passives whose effect is a HOOK, not a stat (Nephilic, 2026-09-24)
## ============================================================================
## A perk is named by an Ability's `perk` field; its numbers are Ability.perk_at(rank).
## At combat start combat.gd folds every perk the player brings (equipped passives,
## plus invested always-active nodes such as Growth) into ONE map and stores it on the
## player's BODY as metadata:
##     body.get_meta("perks") == { "brimming": {"dmg": 0.2}, "stigmata": {"pct": 3.0}, ... }
## A second equipped copy of the same perk ADDS its numbers (every value x copies).
## Stored on the body (not the BattleCharacter) so static systems that only ever see
## bodies — CombatBuffs.try_apply (Poise) — can read it too.
## Combat-only: the meta lives on the battle clone and dies with the fight.
##
## class_name global — RESTART Godot once after adding this script.
## ----------------------------------------------------------------------------

const META_KEY := "perks"

static func set_all(body: CharacterBase, perks: Dictionary) -> void:
	if body != null:
		body.set_meta(META_KEY, perks)

static func all(body: CharacterBase) -> Dictionary:
	if body == null or not body.has_meta(META_KEY):
		return {}
	var d = body.get_meta(META_KEY)
	return d if typeof(d) == TYPE_DICTIONARY else {}

static func has(body: CharacterBase, perk_id: String) -> bool:
	return all(body).has(perk_id)

static func params(body: CharacterBase, perk_id: String) -> Dictionary:
	var d = all(body).get(perk_id, {})
	return d if typeof(d) == TYPE_DICTIONARY else {}

## One number off a perk, `fallback` when the perk (or the key) is absent.
static func value(body: CharacterBase, perk_id: String, key: String, fallback: float = 0.0) -> float:
	var p := params(body, perk_id)
	if p.is_empty() or not p.has(key):
		return fallback
	return float(p[key])

## Fold one ability's perk params into `into` (numeric values add up across copies;
## the first copy's non-numeric values win).
static func merge(into: Dictionary, perk_id: String, p: Dictionary) -> void:
	if perk_id == "":
		return
	if not into.has(perk_id):
		into[perk_id] = p.duplicate(true)
		return
	var cur: Dictionary = into[perk_id]
	for k in p.keys():
		var v = p[k]
		if (typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT) and cur.has(k):
			cur[k] = float(cur[k]) + float(v)
		elif not cur.has(k):
			cur[k] = v
