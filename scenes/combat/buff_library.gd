extends RefCounted
class_name BuffLibrary

## ============================================================================
## BUFF LIBRARY  —  the named buff / debuff catalogue (class_name global)
## ============================================================================
## The concrete buffs live here, in readable code, keyed by a string id. An
## Ability .tres names one of these ids in its `applies_buff` field; combat calls
## BuffLibrary.build(id, caster, target) when that ability resolves and applies
## the returned entry with CombatBuffs.apply().
##
## Each builder returns a FRESH entry dict (via Buff.make), so callers never share
## state. `caster` / `target` are passed for future scaling (e.g. a DoT that
## scales off the caster's stats); the current catalogue uses fixed numbers.
##
## To add a buff: add a case to build() (or call Buff.make directly). To retune
## the existing ones, edit the numbers here — this is the single tuning spot.
##
## class_name global — RESTART Godot once after adding this script.
## ----------------------------------------------------------------------------

## Thorns tuning: per stack, reflect this much flat damage + this fraction of the
## damage taken back at the attacker. The single tuning spot for thorns.
const THORNS_FLAT := 20.0
const THORNS_PCT := 0.15

## Every real element's defense (resist) stat key, for "all resists" effects.
static func _all_resist_mods(delta: float) -> Dictionary:
	var mods := {}
	for e in Stats.REAL_ELEMENTS:
		mods[Stats.defense_key(e)] = delta
	return mods

## Build a buff entry by id. Returns {} (empty) for an unknown / blank id.
static func build(id: String, _caster: CharacterBase = null, _target: CharacterBase = null) -> Dictionary:
	match id:
		# --- Bet: +100% to ALL resists, 5 turns, stacks infinitely -----------
		# A true MULTIPLICATIVE resist bonus (see CombatMath): resist_mult 1.0 per
		# stack => x2 resists at one stack, x3 at two, ... max_stacks 0 = unlimited.
		"resist_up_100":
			return Buff.make({
				"id": "resist_up_100",
				"source": "Bet — Resist Up",
				"desc": "Increases all resistances by 100% (multiplicative). Stacks without limit.",
				"kind": Buff.KIND_BUFF,
				"visible": true,
				"duration": 5,
				"stackable": true,
				"max_stacks": 0,             # 0 => unlimited
				"weight": 1.0,
				"resistible": false,
				"resist_mult": 1.0,          # per stack: +100% of resists
			})

		# --- Gimel: +25 spirit per turn, 8 turns -----------------------------
		"spirit_regen_25":
			return Buff.make({
				"id": "spirit_regen_25",
				"source": "Gimel — Spirit Font",
				"desc": "Restores 25 spirit at the start of each of your turns for 8 turns.",
				"kind": Buff.KIND_BUFF,
				"visible": true,
				"duration": 8,
				"stackable": false,
				"weight": 1.0,
				"resistible": false,
				"spirit_per_turn": 25.0,
			})

		# --- Dalet: -15 flat to all resists AND drain 20 spirit/turn, 5 turns -
		"resist_down_drain":
			return Buff.make({
				"id": "resist_down_drain",
				"source": "Dalet — Sap",
				"desc": "Lowers all resistances by 15 (flat) and drains 20 spirit at the start of each turn for 5 turns.",
				"kind": Buff.KIND_DEBUFF,
				"visible": true,
				"duration": 5,
				"stackable": false,
				"weight": 1.0,
				"resistible": true,
				"mods": _all_resist_mods(-15.0),   # flat resist reduction (additive)
				"spirit_per_turn": -20.0,          # drain
			})

		# --- Thorns: when struck, deal damage back to the attacker ------------
		# The first user of the generic "when struck do X" system (see
		# CombatBuffs.fire_on_struck). Each stack reflects THORNS_FLAT flat damage
		# PLUS THORNS_PCT of the damage taken back at the attacker. Stacks up to 5.
		"thorns":
			return Buff.make({
				"id": "thorns",
				"source": "Thorns",
				"desc": "When struck, reflects %d (+%d%% of the damage taken) back to the attacker. Stacks up to 5." % [int(THORNS_FLAT), int(round(THORNS_PCT * 100.0))],
				"kind": Buff.KIND_BUFF,
				"visible": true,
				"duration": 5,
				"stackable": true,
				"max_stacks": 5,
				"weight": 1.0,
				"resistible": false,
				"on_struck": [
					{"effect": "reflect", "amount": THORNS_FLAT, "percent": THORNS_PCT, "element": "physical"},
				],
			})

		_:
			return {}

## True when `id` names a buff this library knows how to build.
static func has(id: String) -> bool:
	return not build(id).is_empty()

# ---------------------------------------------------------------------------
# Generic constructors — handy for building common effects from code without a
# catalogue entry (bleed/poison, a temporary max-HP / max-Spirit change, etc.).
# ---------------------------------------------------------------------------

## A bleed/poison DoT. `element` tints the ticking numbers and is stored as the
## DoT element; `dot_mult` is the flat per-DoT multiplier (default 1.0).
static func make_dot(id: String, source: String, amount: float, element: String, turns: int, dot_mult: float = 1.0, is_debuff: bool = true) -> Dictionary:
	return Buff.make({
		"id": id, "source": source, "desc": "%s: %d %s damage per turn." % [source, int(round(amount)), element],
		"kind": Buff.KIND_DEBUFF if is_debuff else Buff.KIND_BUFF,
		"visible": true, "duration": turns, "element": element, "resistible": true,
		"dot": amount, "dot_element": element, "dot_mult": dot_mult,
	})

## A temporary max-HP change (via hp_base, which max_hp() reads). Positive raises
## the ceiling; when it expires CombatBuffs re-clamps current HP down.
static func make_max_hp(id: String, source: String, delta: float, turns: int) -> Dictionary:
	return Buff.make({
		"id": id, "source": source, "desc": "%s: %+d maximum health." % [source, int(round(delta))],
		"kind": Buff.KIND_BUFF if delta >= 0.0 else Buff.KIND_DEBUFF,
		"visible": true, "duration": turns,
		"mods": {"hp_base": delta},
	})

## A temporary max-Spirit change (via the spirit base stat that max_spirit reads).
static func make_max_spirit(id: String, source: String, delta: float, turns: int) -> Dictionary:
	return Buff.make({
		"id": id, "source": source, "desc": "%s: %+d maximum spirit." % [source, int(round(delta))],
		"kind": Buff.KIND_BUFF if delta >= 0.0 else Buff.KIND_DEBUFF,
		"visible": true, "duration": turns,
		"mods": {"spirit": delta},
	})
