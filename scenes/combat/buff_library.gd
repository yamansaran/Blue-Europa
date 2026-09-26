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
## THE SEVERITY PASS (AI_PRIMER §10.1 / §18 Phase 5). `magnitude` = HOW BIG an effect
## is; `weight` = how much the AI should care beyond its size. Keyed by the ENTRY id
## (the family — guard_1..4 all read "guard"). Applied by build() ONLY to an entry still
## at the Buff.make default of 1.0, so an entry that authors its own magnitude inline
## (frenzied, terrified, rejuvenating_salve, dark_blessing, gorged) keeps it.
## Anchors: 0.5 small single-stat buff · 1.0 ordinary debuff / modest DoT · 2.0 strong
## multi-turn package · 3.5 heavy resist / damage swing · 5.0 hard control.
const SEVERITY := {
	"resist_up_100":      {"magnitude": 3.5},
	"spirit_regen_25":    {"magnitude": 1.5},
	"resist_down_drain":  {"magnitude": 2.5},
	"thorns":             {"magnitude": 1.2},
	"thorns_permanent":   {"magnitude": 1.0},
	"frost_ward":         {"magnitude": 1.0},
	"frost_mantle":       {"magnitude": 1.0},
	"guard":              {"magnitude": 3.5},
	"scaled_skin":        {"magnitude": 2.0},
	"hematopoiesis":      {"magnitude": 1.5},
	"crystaline":         {"magnitude": 2.0},
	"gliogenesis":        {"magnitude": 1.0},
	"sclerosis":          {"magnitude": 1.0},
	"stunned":            {"magnitude": 5.0},
	"hypothermia":        {"magnitude": 1.5},
	"frost":              {"magnitude": 1.5},
	"arc_burn":           {"magnitude": 1.0},
	"electromyogenesis":  {"magnitude": 1.0},
	"energized_form":     {"magnitude": 3.0},
	"electrostimulated":  {"magnitude": 2.0},
	"pass_current":       {"magnitude": 0.5},
	"lightning_shell":    {"magnitude": 1.5},
	"high_voltage":       {"magnitude": 1.5},
	"rime_skin":          {"magnitude": 1.5},
	"hoarfrost":          {"magnitude": 0.6, "weight": 2.5},   # a combo ENABLER: small, but chase it
	"silenced":           {"magnitude": 5.0},
	"wraith_form":        {"magnitude": 3.5},
	"frostnip":           {"magnitude": 1.0},
	# --- c2b GODTHAAB -------------------------------------------------------
	"punished":           {"magnitude": 1.0},
	"bruised":            {"magnitude": 1.0},
	"on_fire":            {"magnitude": 2.0},
	"bleeding":           {"magnitude": 1.0},
	"hyperacusis":        {"magnitude": 1.0},
	"tinnitus":           {"magnitude": 1.0},
	"stripped":           {"magnitude": 1.0},
	"cauterized":         {"magnitude": 2.0},
	"netted":             {"magnitude": 5.0},
	"gut_stunned":        {"magnitude": 5.0},
	"neuromuscular":      {"magnitude": 2.0},
	"kneecapped":         {"magnitude": 1.0},
	"smokescreen":        {"magnitude": 2.0},
	"ordered":            {"magnitude": 2.0},
	"commended":          {"magnitude": 1.0},
	"oversight":          {"magnitude": 3.5},
	"on_guard":           {"magnitude": 1.0},
	"work_order":         {"magnitude": 2.0},
	"protected":          {"magnitude": 3.5},
	"braced":             {"magnitude": 3.5},
	"amphetamined":       {"magnitude": 2.0},
	"crash":              {"magnitude": 2.0},
	# --- THE NEPHILIC (2026-09-24) ----------------------------------------
	"poison":             {"magnitude": 1.0},
	"stand_firm":         {"magnitude": 3.0},
	"stand_firm_lead":    {"magnitude": 0.3},
	"tithe":              {"magnitude": 2.0},
	"inhale":             {"magnitude": 1.0},
	"wormwood":           {"magnitude": 1.5},
	"waxing_moon":        {"magnitude": 2.5},
	"silver_mirror":      {"magnitude": 3.0},
	"epiphany":           {"magnitude": 3.0},
	"ablution_ward":      {"magnitude": 1.5},
	"intercede":          {"magnitude": 3.0},
	"putrefaction":       {"magnitude": 2.0},
	"putrefaction_cost":  {"magnitude": 1.0},
	"first_sun":          {"magnitude": 3.5},
	"apotheosis":         {"magnitude": 3.0},
	"rejuvenation":       {"magnitude": 1.0},
	"heavy_hand":         {"magnitude": 0.5},
	"grit_ward":          {"magnitude": 1.5},
	"hone":               {"magnitude": 0.5},
}

## Build a buff entry by id WITHOUT applying it (the AI relies on that — keep build
## side-effect free). Every id resolves through _build_entry, then the severity pass.
static func build(id: String, caster: CharacterBase = null, target: CharacterBase = null) -> Dictionary:
	var entry := _build_entry(id, caster, target)
	if entry.is_empty():
		return entry
	var sev = SEVERITY.get(str(entry.get("id", "")), null)
	if typeof(sev) == TYPE_DICTIONARY and is_equal_approx(float(entry.get("magnitude", 1.0)), 1.0):
		entry["magnitude"] = float(sev.get("magnitude", 1.0))
		if sev.has("weight") and is_equal_approx(float(entry.get("weight", 1.0)), 1.0):
			entry["weight"] = float(sev["weight"])
	return entry

static func _build_entry(id: String, caster: CharacterBase = null, target: CharacterBase = null) -> Dictionary:
	var neph := _build_nephilic(id, caster)
	if not neph.is_empty():
		return neph
	match id:
		# ====================================================================
		# c2b · GODTHAAB
		# ====================================================================
		# >> EVERY MAGNITUDE IN THIS BLOCK IS A PLACEHOLDER (GODTHAAB_BUILD §2.7).
		#    Percentages, DURATIONS and CHANCES are authored — they carry identity
		#    and the ladder depends on them. Every stat figure, DoT value and health
		#    number is provisional and marked `# TUNE`, and is waiting on the two
		#    reference builds §2.7 asks for. Do not treat any `# TUNE` number as
		#    balanced; do not quote one as if it were.

		# --- THE WHARF ------------------------------------------------------
		# PUNISHED and BRUISED are the two halves of the damage formula stated as
		# debuffs, which is the whole reason the Stevedore that applies them is a
		# plaguebearer and not a hexer: they are only frightening stacked on ONE
		# victim, and a hexer spreading them would dilute the very lesson.
		"punished":
			return Buff.make({
				"id": "punished", "source": "Punished",
				"desc_template": "Punished: deals {modpctabs:damage_dealt_mult}% less damage ({turns} left).",
				"kind": Buff.KIND_DEBUFF, "duration": 3,
				"stackable": true,                    # INDEPENDENT INSTANCES, no cap
				"element": "physical",
				"potency_scale": 0.8, "duration_scale": 0.6,
				"mods": {"damage_dealt_mult": -0.12},   # TUNE
			})

		"bruised":
			return Buff.make({
				"id": "bruised", "source": "Bruised",
				"desc_template": "Bruised: takes {modpct:damage_taken_mult}% more damage ({turns} left).",
				"kind": Buff.KIND_DEBUFF, "duration": 3,
				"stackable": true,
				"element": "physical",
				"potency_scale": 0.8, "duration_scale": 0.6,
				"mods": {"damage_taken_mult": 0.12},    # TUNE
			})

		# The Wharfinger's order: the first enemy in the game that makes ANOTHER
		# enemy better. Not stacking — one order at a time is the point of it.
		"work_order":
			return Buff.make({
				"id": "work_order", "source": "Work Order",
				"desc_template": "Work Order: deals {modpct:damage_dealt_mult}% more damage ({turns} left).",
				"kind": Buff.KIND_BUFF, "duration": 3,
				"stackable": false,
				"mods": {"damage_dealt_mult": 0.25},    # TUNE
			})

		# --- THE REGISTRY ---------------------------------------------------
		# ACCURACY IS FLAT PERCENTAGE POINTS OFF THE DODGE ROLL, and the base dodge
		# at parity is 10 (CombatDodge.BASE). So +4 is a real edge and +10 would make
		# the bearer effectively unmissable — read that header before retuning these.
		"on_guard":
			return Buff.make({
				"id": "on_guard", "source": "On Guard",
				"desc_template": "On Guard: +{mod:accuracy_bonus} accuracy ({turns} left).",
				"kind": Buff.KIND_BUFF, "duration": 3,
				"stackable": false,
				"mods": {"accuracy_bonus": 4.0},        # TUNE
			})

		# The tanky guard's gift: it makes somebody ELSE unkillable.
		"oversight":
			return Buff.make({
				"id": "oversight", "source": "Oversight",
				"desc_template": "Oversight: takes {modpctabs:damage_taken_mult}% less damage ({turns} left).",
				"kind": Buff.KIND_BUFF, "duration": 2,
				"stackable": false,
				"mods": {"damage_taken_mult": -0.35},   # TUNE
			})

		# The Registrar's commendation. RENAMED from the dev's "Vigilant" (GODTHAAB
		# §0): the shield officer's pair needed that word, so the Registrar's became
		# Commend. Ability id `commend`, entry id `commended`.
		"commended":
			return Buff.make({
				"id": "commended", "source": "Commended",
				"desc_template": "Commended: +{mod:vigor} Vigor, +{mod:alacrity} Alacrity ({turns} left).",
				"kind": Buff.KIND_BUFF, "duration": 3,
				"stackable": false,
				"mods": {"vigor": 6.0, "alacrity": 4.0},   # TUNE
			})

		"kneecapped":
			return Buff.make({
				"id": "kneecapped", "source": "Kneecapped",
				"desc_template": "Kneecapped: {mod:alacrity} Alacrity ({turns} left).",
				"kind": Buff.KIND_DEBUFF, "duration": 3,
				"stackable": false,
				"element": "physical",
				"potency_scale": 0.6, "duration_scale": 0.5,
				"mods": {"alacrity": -12.0},            # TUNE
			})

		# --- THE CONSIGNMENT ------------------------------------------------
		"bleeding":
			return Buff.make({
				"id": "bleeding", "source": "Bleeding",
				"desc_template": "Bleeding: {dot} Physical damage at the start of each turn ({turns} left).",
				"kind": Buff.KIND_DEBUFF, "duration": 3,
				"stackable": true,
				"element": "physical",
				"potency_scale": 1.0, "duration_scale": 1.0,
				"dot": 9.0, "dot_element": "physical",  # TUNE
			})

		# HYPERACUSIS — the Screaming Corpse's spreading damage. Stacks.
		"hyperacusis":
			return Buff.make({
				"id": "hyperacusis", "source": "Hyperacusis",
				"desc_template": "Hyperacusis: {mod:alacrity} Alacrity, {mod:accuracy_bonus} accuracy ({turns} left).",
				"kind": Buff.KIND_DEBUFF, "duration": 3,
				"stackable": true,
				"element": "physical",
				"potency_scale": 0.8, "duration_scale": 0.6,
				"mods": {"alacrity": -5.0, "accuracy_bonus": -3.0},   # TUNE
			})

		# TINNITUS — a DoT that PIERCES, which is now an ordinary thing a buff can be
		# (§1.7). 15 physical pierce is the Screaming Corpse's whole identity: it is
		# the zone's answer to an armour build, and the pierce is on the EFFECT rather
		# than on the body so it only applies to what the scream leaves behind.
		#
		# EIGHT TURNS IS LONGER THAN MOST FIGHTS IN THE ZONE, deliberately — but buffs
		# die with the battle, so it cannot carry over. Confirm that is still wanted
		# before tuning the number (GODTHAAB §2.3 flags it as a decision).
		"tinnitus":
			return Buff.make({
				"id": "tinnitus", "source": "Tinnitus",
				"desc_template": "Tinnitus: {dot} piercing Physical damage at the start of each turn ({turns} left).",
				"kind": Buff.KIND_DEBUFF, "duration": 8,
				"stackable": true,
				"element": "physical",
				"potency_scale": 1.0, "duration_scale": 0.5,
				"dot": 7.0, "dot_element": "physical",  # TUNE
				"dot_pierce": 15.0,                     # AUTHORED — the creature's identity
			})

		# --- THE BURNING GROUND ---------------------------------------------
		# ON FIRE is NOT a damage debuff. It is a VULNERABILITY debuff with a burn
		# attached — the first time an enemy turns the player's own damage_taken lever
		# against them. Tune the multiplier before the DoT.
		"on_fire":
			return Buff.make({
				"id": "on_fire", "source": "On Fire",
				"desc_template": "On Fire: takes {modpct:damage_taken_mult}% more damage and burns for {dot} ({turns} left).",
				"kind": Buff.KIND_DEBUFF, "duration": 3,
				"stackable": true,
				"element": "fire",
				"potency_scale": 1.0, "duration_scale": 0.8,
				"mods": {"damage_taken_mult": 0.15},    # TUNE
				# UNIFIED ON FIRE (FUTURE_PLANS §1, built 2026-09-24): ONE entry for every
				# applier — the DoT is 20% of the APPLIER's Vigor, snapshotted at landing.
				# Replaces the flat 8. Duration comes from the application
				# (Ability.applies_buff_duration); 3 is the fallback.
				"dot": ON_FIRE_VIGOR * (maxf(0.0, caster.get_effective("vigor")) if caster != null else 0.0),   # TUNE
				"dot_element": "fire",
			})

		# CAUTERIZED — explicitly NOT stacking (GODTHAAB §1.1). One of the three lines
		# the burning trio squeezes: this is the healing one.
		"cauterized":
			return Buff.make({
				"id": "cauterized", "source": "Cauterized",
				"desc_template": "Cauterized: healing received cut by {modpctabs:healing_received_mult}% ({turns} left).",
				"kind": Buff.KIND_DEBUFF, "duration": 3,
				"stackable": false,
				"element": "fire",
				"potency_scale": 0.6, "duration_scale": 0.8,
				"mods": {"healing_received_mult": -0.50},   # TUNE
			})

		# SMOKESCREEN — the accuracy line of the same squeeze. Sits on the VICTIM and
		# cuts the accuracy of what it carries (see the note on on_guard above).
		"smokescreen":
			return Buff.make({
				"id": "smokescreen", "source": "Smokescreen",
				"desc_template": "Smokescreen: {mod:accuracy_bonus} accuracy ({turns} left).",
				"kind": Buff.KIND_DEBUFF, "duration": 2,
				"stackable": false,
				"element": "fire",
				"potency_scale": 0.6, "duration_scale": 0.6,
				"mods": {"accuracy_bonus": -5.0},       # TUNE
			})

		# --- THE CORPS AND THE GATE -----------------------------------------
		# GUT-STUNNED — Disembowel's stun, and NOT the shared `stunned` entry.
		#
		# WHY ITS OWN ID. `stunned` is Shatter's payoff and is deliberately
		# `resistible: false`: the player already paid an ice debuff to consume, and
		# whiffing after paying that would be miserable. Disembowel wants the exact
		# opposite — §1.9's "inherent -25 Disdain", a stun that is HARDER to land than
		# the caster's stat block says. Putting a resist_bias on the shared entry
		# would silently change the player's own Shatter, so the enemy gets its own.
		#
		# resist_bias is added straight onto the target's resist chance
		# (CombatResist.resist_chance), so +25 means 25 percentage points more likely
		# to be shrugged off — at parity that is a 35% resist instead of 10%.
		# potency/duration scale stay 0: hard control is never amplified by Disdain.
		"gut_stunned":
			return Buff.make({
				"id": "gut_stunned", "source": "Stunned",
				"desc": "Stunned: cannot act.",
				"kind": Buff.KIND_DEBUFF, "duration": 1,      # AUTHORED
				"stackable": false,
				"element": "physical",
				"stun": true,
				"resistible": true,
				"resist_bias": 25.0,                          # AUTHORED (§1.9)
				"potency_scale": 0.0, "duration_scale": 0.0,
			})


		# BRACE — the first enemy that DEFENDS. A 65% cut for ONE turn means the
		# player's biggest hit can simply be wasted, and WHEN you attack starts to
		# matter. The 65% and the single turn are AUTHORED; they are the mechanic.
		"braced":
			return Buff.make({
				"id": "braced", "source": "Braced",
				"desc_template": "Braced: takes {modpctabs:damage_taken_mult}% less damage ({turns} left).",
				"kind": Buff.KIND_BUFF, "duration": 1,
				"stackable": false,
				"mods": {"damage_taken_mult": -0.65},   # AUTHORED
			})

		"neuromuscular":
			return Buff.make({
				"id": "neuromuscular", "source": "Neuromuscular Block",
				"desc_template": "Neuromuscular Block: {mod:alacrity} Alacrity, {mod:vigor} Vigor ({turns} left).",
				"kind": Buff.KIND_DEBUFF, "duration": 2,
				"stackable": false,
				"element": "lightning",
				"potency_scale": 0.8, "duration_scale": 0.5,
				"mods": {"alacrity": -10.0, "vigor": -8.0},   # TUNE
			})

		"ordered":
			return Buff.make({
				"id": "ordered", "source": "Ordered",
				"desc_template": "Ordered: +{modpct:damage_dealt_mult}% damage, +{mod:accuracy_bonus} accuracy ({turns} left).",
				"kind": Buff.KIND_BUFF, "duration": 3,
				"stackable": false,
				"mods": {"damage_dealt_mult": 0.20, "accuracy_bonus": 3.0},   # TUNE
			})

		# STRIPPED — the officer's answer to a resistance build. Stacks.
		"stripped":
			return Buff.make({
				"id": "stripped", "source": "Stripped",
				"desc_template": "Stripped: all resistances reduced ({turns} left).",
				"kind": Buff.KIND_DEBUFF, "duration": 3,
				"stackable": true,
				"element": "physical",
				"potency_scale": 0.8, "duration_scale": 0.6,
				# TUNE — every element, so the debuff answers any defensive profile.
				"mods": {
					"physical_defense": -12.0, "spiritual_defense": -12.0,
					"ice_defense": -12.0, "fire_defense": -12.0,
					"lightning_defense": -12.0, "blood_defense": -12.0,
					"toxic_defense": -12.0, "mental_defense": -12.0,
				},
			})

		# NETTED — no duration; ESCAPED rather than waited out (§1.10). The escape is
		# rolled at the start of each of the bearer's own turns, through the SAME
		# curve as the resist roll, against the Disdain of whoever threw the net.
		# "magnificence and strength" — the stat vocabulary's name for strength is
		# VIGOR — weighted so the score stays on one stat's scale.
		#
		# It rolls BEFORE the stun check, so breaking free means acting that turn.
		"netted":
			return Buff.make({
				"id": "netted", "source": "Netted",
				"desc": "Netted: cannot act. Struggle free at the start of each of your turns.",
				"kind": Buff.KIND_DEBUFF, "duration": -1,     # AUTHORED: indefinite
				"stackable": false,
				"element": "physical",
				"stun": true,
				"escape_check": {"stats": {"magnificence": 0.5, "vigor": 0.5}},
				"potency_scale": 0.0, "duration_scale": 0.0,  # hard control: never amplified
			})

		# PROTECTED — the CHEAP half of §1.14, and the whole shield-officer link.
		# It sits on the ALLY and breaks the moment the officer who cast it takes
		# ACTUAL HEALTH damage (not shield). There is no Covering self-buff and no
		# two-way link: "hit the shield man to free his friend", in one field.
		"protected":
			return Buff.make({
				"id": "protected", "source": "Protected",
				"desc_template": "Protected: takes {modpctabs:damage_taken_mult}% less damage while the officer stands.",
				"kind": Buff.KIND_BUFF, "duration": -1,       # ends with the officer, not a clock
				"stackable": false,
				"breaks_when_caster_damaged": true,
				"mods": {"damage_taken_mult": -0.40},   # TUNE
			})

		# --- THE HARBOUR GATE -----------------------------------------------
		# AMPHETAMINES -> CRASH: a buff that becomes its own debuff, and the first
		# fight the player can win by SURVIVING. The ramp is what makes it legible —
		# the chip's badge counts down 1.00, 0.85, 0.70 ... on three guards at once,
		# and that visible clock IS the fight.
		"amphetamined":
			return Buff.make({
				"id": "amphetamined", "source": "Amphetamines",
				"desc_template": "Amphetamines: +{mod:vigor} Vigor, +{mod:alacrity} Alacrity, fading ({turns} left).",
				"kind": Buff.KIND_BUFF, "duration": 6,        # AUTHORED
				"stackable": false,
				"potency_per_turn": -0.15,                    # AUTHORED: 1.00 -> 0.25 over its life
				"expire_apply": [{"buff": "crash"}],          # AUTHORED: it always ends this way
				"mods": {"vigor": 14.0, "alacrity": 14.0},    # TUNE
			})

		"crash":
			return Buff.make({
				"id": "crash", "source": "Crash",
				"desc_template": "Crash: {mod:vigor} Vigor, {mod:alacrity} Alacrity, worsening ({turns} left).",
				"kind": Buff.KIND_DEBUFF, "duration": 6,      # AUTHORED
				"stackable": false,
				"resistible": false,                          # it is the bill, not an attack
				"potency_per_turn": 0.20,                     # AUTHORED: grows worse every turn
				"mods": {"vigor": -6.0, "alacrity": -6.0},    # TUNE
			})

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
				"desc_template": "Lowers all resistances by {modabs:ice_defense} (flat) and drains {spiritabs} spirit at the start of each turn ({turns} left).",
				"kind": Buff.KIND_DEBUFF,
				"visible": true,
				"duration": 5,
				"stackable": false,
				"weight": 1.0,
				"resistible": true,
				# DISDAIN SCALING: a broad stat-cut + drain. Scales well on both axes,
				# though not as hard as a pure damage-over-time.
				"potency_scale": 0.75,
				"duration_scale": 0.75,
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

		# --- Frost Ward: a PERMANENT innate ice resistance -------------------
		# Used as a PERMANENT buff (duration -1, so it never counts down): a
		# character module lists "frost_ward" in its permanent_buffs and combat
		# auto-applies it at battle start. Flat +40 ice defence via mods, so it
		# shows in the stat readouts like any flat resist.
		"frost_ward":
			return Buff.make({
				"id": "frost_ward",
				"source": "Frost Ward",
				"desc": "Wreathed in frost: +40 ice resistance. Permanent.",
				"kind": Buff.KIND_BUFF,
				"visible": true,
				"duration": -1,              # -1 => permanent, never expires
				"stackable": false,
				"weight": 1.0,
				"resistible": false,
				"element": "ice",
				"mods": {"ice_defense": 40.0},
			})

		# --- Frost Mantle: a PERMANENT reflect aura --------------------------
		# The boss's extra permanent buff: reflects a little ice damage back
		# whenever it is struck (via the generic on_struck "reflect" system —
		# see CombatBuffs.fire_on_struck). Permanent (duration -1).
		"frost_mantle":
			return Buff.make({
				"id": "frost_mantle",
				"source": "Frost Mantle",
				"desc": "A permanent mantle of frost: reflects 15 (+10% of the damage taken) as ice when struck.",
				"kind": Buff.KIND_BUFF,
				"visible": true,
				"duration": -1,              # -1 => permanent, never expires
				"stackable": false,
				"weight": 1.0,
				"resistible": false,
				"element": "ice",
				"on_struck": [
					{"effect": "reflect", "amount": 15.0, "percent": 0.10, "element": "ice"},
				],
			})

		# --- Guard (Tav): reduce ALL incoming damage until your next turn -----
		# Four rank-clones, identical EXCEPT the reduction fraction. combat.gd maps
		# the Guard ability's invested rank -> guard_1..guard_4 (see its
		# _maybe_apply_buff). The reduction is a flat incoming-damage multiplier read
		# by CombatMath (damage_taken_mult, stored in mods, additive around 0:
		# -0.80 => take 80% less). All four share id "guard" so re-casting refreshes
		# duration instead of stacking (two guards would be far too strong). Retune
		# the four numbers here — this is the single tuning spot.
		"guard_1":
			return _make_guard(0.80)
		"guard_2":
			return _make_guard(0.90)
		"guard_3":
			return _make_guard(0.95)
		"guard_4":
			return _make_guard(0.99)

		# --- Scaled Skin (Yesod): 20% damage resist + heal over time ----------
		# Three rank-clones, identical EXCEPT their duration (5/6/7 turns) and the
		# heal-per-turn fraction of the TARGET's Instinct (30/40/50%). combat.gd maps
		# the Scaled Skin ability's invested rank -> scaled_skin_1..3 (see its
		# _maybe_apply_buff), exactly like Guard. The 20% resist is a flat incoming-
		# damage multiplier (damage_taken_mult -0.20 in mods, read by CombatMath) and
		# is the same at every rank. The per-turn heal is snapshotted from the target's
		# Instinct at cast time into heal_per_turn (see _make_scaled_skin). All three
		# share id "scaled_skin" so re-casting refreshes duration instead of stacking.
		"scaled_skin_1":
			return _make_scaled_skin(5, 0.30, target)
		"scaled_skin_2":
			return _make_scaled_skin(6, 0.40, target)
		"scaled_skin_3":
			return _make_scaled_skin(7, 0.50, target)

		# --- Hematopoiesis (Altar of Water): pure heal over time --------------
		# Three rank-clones differing in duration (4/5/6 turns) and the heal-per-turn
		# fraction of the TARGET's (Vigor + Instinct) (100/200/325%). combat.gd maps
		# the ability's invested rank -> hematopoiesis_1..3 (see its _maybe_apply_buff),
		# exactly like Scaled Skin. The per-turn heal is snapshotted from the target's
		# stats at cast time into heal_per_turn (see _make_hematopoiesis). All three
		# share id "hematopoiesis" so re-casting refreshes duration instead of stacking.
		"hematopoiesis_1":
			return _make_hematopoiesis(4, 1.00, target)
		"hematopoiesis_2":
			return _make_hematopoiesis(5, 2.00, target)
		"hematopoiesis_3":
			return _make_hematopoiesis(6, 3.25, target)

		# --- Crystaline (Tzaddi): +100% to ALL resists, 5 turns --------------
		# A single-rank self buff: a true MULTIPLICATIVE resist bonus (resist_mult 1.0
		# => x2 all resists), read by CombatMath. Unlike resist_up_100 (Netzach) this
		# one does NOT stack — Crystalize is a 1-rank ability, so re-casting just
		# refreshes the 5-turn duration. Applied by the Crystalize ability.
		"crystaline":
			return Buff.make({
				"id": "crystaline",
				"source": "Crystaline",
				"desc": "Encased in crystal: all resistances increased by 100% for 5 turns.",
				"kind": Buff.KIND_BUFF,
				"visible": true,
				"duration": 5,
				"stackable": false,
				"weight": 1.0,
				"resistible": false,
				"element": "ice",
				"resist_mult": 1.0,          # +100% of all resists (multiplicative)
			})

		# --- Gliogenesis (Peh): passive per-turn health + spirit regen ---------
		# Four rank-clones, applied to the player as a PERMANENT buff (duration -1)
		# at combat start while the Gliogenesis passive sits in the wheel (see
		# combat._apply_passive_buffs). They differ only in the % of max health healed
		# per turn (2.5/5/7.5/10%) and the flat spirit gained per turn (0/0/4/6). The
		# heal is a LIVE fraction of current max HP (heal_pct_per_turn), read each turn.
		"gliogenesis_1":
			return _make_gliogenesis(0.025, 0.0)
		"gliogenesis_2":
			return _make_gliogenesis(0.05, 0.0)
		"gliogenesis_3":
			return _make_gliogenesis(0.075, 4.0)
		"gliogenesis_4":
			return _make_gliogenesis(0.10, 6.0)
		"sclerosis_1":
			return _make_sclerosis(5.0)
		"sclerosis_2":
			return _make_sclerosis(8.0)
		"sclerosis_3":
			return _make_sclerosis(12.0)
		"sclerosis_4":
			return _make_sclerosis(15.0)

		# --- Stunned: blocks all actions for 1 turn ---------------------------
		# Applied by Shatter when it consumes an ice debuff. The `stun` flag is read by
		# CombatBuffs.is_stunned (the wheel greys out for a stunned PLAYER; enemy turn
		# logic will consume it once the enemy action engine exists). Deliberately has
		# NO element tag so a later Shatter cannot consume the stun as an "ice debuff".
		"stunned":
			return Buff.make({
				"id": "stunned",
				"source": "Stunned",
				"desc": "Stunned: cannot act for 1 turn.",
				"kind": Buff.KIND_DEBUFF,
				"visible": true,
				"duration": 1,
				"stackable": false,
				"weight": 1.0,
				"resistible": false,   # already paid for by consuming an ice debuff
				# DISDAIN SCALING: a stun has no magnitude to amplify, and an extra turn
				# of it is the single most powerful thing a debuff can gain — so potency
				# is off entirely and the duration roll is the stingiest in the catalogue,
				# capped at ONE extra turn however far Disdain runs ahead.
				"potency_scale": 0.0,
				"duration_scale": 0.2,
				"max_extra_duration": 1,
				"stun": true,
			})

		# --- Hypothermia (Nun): -alacrity + spirit drain, 8 turns --------------
		# Two rank-clones differing only in the alacrity multiplier (-10% / -12%).
		# combat.gd maps the ability rank -> hypothermia_1/2 in _maybe_apply_buff.
		"hypothermia_1":
			return _make_hypothermia(-0.10)
		"hypothermia_2":
			return _make_hypothermia(-0.12)

		# --- Frost (Menorah): -alacrity + ice DoT, 2 turns --------------------
		# Two rank-clones differing in alacrity mult (-20% / -22%) and the ice DoT,
		# which is SNAPSHOTTED from the CASTER at cast: instinct_pct*Instinct +
		# vigor_pct*Vigor (50%/100% Instinct + 25% Vigor). Mapped by combat.gd rank.
		# RE-TUNED for mitigated DoT (x2.125 — see the Arc Burn note below). Only the
		# two DAMAGE shares moved; the alacrity multiplier is a stat debuff and is
		# untouched by mitigation.
		"frost_1":
			return _make_frost(-0.20, 1.06, 0.53, caster)
		"frost_2":
			return _make_frost(-0.22, 2.13, 0.53, caster)

		# --- Arc Burn (Neurostatic): a lightning DoT, ranks 1..3 ---------------
		# The per-turn damage is SNAPSHOTTED from the CASTER's Instinct at the moment
		# the debuff lands (the `frost` pattern), so it does not drift if the caster's
		# stats change mid-fight. Was 50 / 75 / 100% of Instinct for 3 turns.
		# >> RE-TUNED FOR MITIGATED DoT (§1.7 / C.8). Damage-over-time now runs
		#    through the real damage pipeline, so at the DEFAULT 45 elemental defense
		#    a DoT retains 47.1% of what it used to deal. Every percentage below was
		#    multiplied by 2.125 (= 1 / 0.4706) so a default-resistance target takes
		#    the SAME damage it took before the change. Against a RESISTANT target it
		#    now takes less and against a soft one more, which is the entire point of
		#    routing it — but the baseline is deliberately unmoved.
		"arc_burn_1":
			return _make_arc_burn(1.06, caster)
		"arc_burn_2":
			return _make_arc_burn(1.59, caster)
		"arc_burn_3":
			return _make_arc_burn(2.13, caster)

		# --- Electromyogenesis: +Alacrity equal to a % of the CASTER's Instinct -
		# Ranks 1..4: 25/30/35/40% of Instinct, for 3/3/4/4 turns. Snapshotted at
		# cast (a flat `mods` bonus), so it is the caster's Instinct that matters
		# even when the buff is handed to an ally.
		"electromyogenesis_1":
			return _make_electromyogenesis(0.25, 3, caster)
		"electromyogenesis_2":
			return _make_electromyogenesis(0.30, 3, caster)
		"electromyogenesis_3":
			return _make_electromyogenesis(0.35, 4, caster)
		"electromyogenesis_4":
			return _make_electromyogenesis(0.40, 4, caster)

		# --- Energized Form: the lightning ultimate (single rank) --------------
		# +30 Alacrity, +50% to all lightning damage dealt (lightning_amp — the
		# (A+1) coefficient in CombatMitigation), and a rider that adds 45% of the
		# bearer's Vigor as Lightning damage to every hit it lands (on_hit_damage).
		"energized_form":
			return Buff.make({
				"id": "energized_form",
				"source": "Energized Form",
				"desc": "Energized: +30 Alacrity, +50% Lightning damage, and every hit deals an extra 45% of Vigor as Lightning damage.",
				"kind": Buff.KIND_BUFF,
				"visible": true,
				"duration": 5,
				"stackable": false,
				"element": "lightning",
				"weight": 2.0,
				"resistible": false,
				"mods": {
					"alacrity": 30.0,
					"lightning_amp": 0.50,
				},
				"on_hit_damage": [
					{"element": "lightning", "scale_stat": "vigor", "pct": 0.45},
				],
			})

		# --- Electrostimulated: a self/ally power buff with a lightning price ---
		# Ranks 1..3. Every turn the bearer TAKES lightning damage equal to a % of the
		# CASTER's Instinct (snapshotted, like Arc Burn) — 40/35/30%, i.e. the cost
		# SHRINKS as the ability ranks up — and in exchange gains flat Alacrity, Vigor,
		# Instinct and spirit regen for 6/8/10 turns.
		"electrostimulated_1":
			return _make_electrostimulated(6, 0.85, 10.0, 5.0, 5.0, caster)
		"electrostimulated_2":
			return _make_electrostimulated(8, 0.74, 20.0, 10.0, 10.0, caster)
		"electrostimulated_3":
			return _make_electrostimulated(10, 0.64, 30.0, 15.0, 15.0, caster)

		# --- Pass Current (Bread): the caster's half of the ability ------------
		# A small, flat self buff riding on an attack (applies_buff_self). Identical
		# at every rank — only Pass Current's damage and its Arc Burn scale up.
		"pass_current":
			return Buff.make({
				"id": "pass_current",
				"source": "Pass Current",
				"desc": "Carrying the current: +5 Alacrity for 3 turns.",
				"kind": Buff.KIND_BUFF,
				"visible": true,
				"duration": 3,
				"stackable": false,
				"weight": 1.0,
				"resistible": false,
				"element": "lightning",
				"mods": {"alacrity": 5.0},
			})

		# --- Lightning Shell (Geburah): overfilled spirit becomes shield -------
		# The passive_buff of the Lightning Shell passive, ranks 1..10. Every 5 points
		# of spirit that WOULD have refilled past the bearer's maximum are converted
		# into an absorbing shield worth (10..100% of Vitality + 10% of Instinct) —
		# read LIVE off the bearer at conversion time, so the shield tracks the stats.
		# The shield carries no decay spec, so it lasts until it is spent. The engine
		# side is BattleCharacter.change_spirit -> _convert_spirit_overflow.
		"lightning_shell_1":
			return _make_lightning_shell(1)
		"lightning_shell_2":
			return _make_lightning_shell(2)
		"lightning_shell_3":
			return _make_lightning_shell(3)
		"lightning_shell_4":
			return _make_lightning_shell(4)
		"lightning_shell_5":
			return _make_lightning_shell(5)
		"lightning_shell_6":
			return _make_lightning_shell(6)
		"lightning_shell_7":
			return _make_lightning_shell(7)
		"lightning_shell_8":
			return _make_lightning_shell(8)
		"lightning_shell_9":
			return _make_lightning_shell(9)
		"lightning_shell_10":
			return _make_lightning_shell(10)

		# --- High Voltage: Lightning Shell's rank-10 capstone ------------------
		# A permanent on-struck reflect scaled off the BEARER's own Instinct (35%),
		# dealt as Lightning. Attacks-only like every other on_struck reaction — a
		# spell cast at the bearer does not get shocked back.
		"high_voltage":
			return Buff.make({
				"id": "high_voltage",
				"source": "High Voltage",
				"desc": "High Voltage: anything that strikes you in melee takes 35% of your Instinct as Lightning damage.",
				"kind": Buff.KIND_BUFF,
				"visible": true,
				"duration": -1,              # -1 => permanent, never expires
				"stackable": false,
				"weight": 2.0,
				"resistible": false,
				"element": "lightning",
				"on_struck": [
					{"effect": "reflect", "scale_stat": "instinct", "pct": 0.35, "element": "lightning"},
				],
			})

		# --- Rime Skin (Vav): -50% healing + self-damage when struck, 4 turns --
		# One entry (identical at every rank; only the applying attack scales). The
		# healing cut is a healing_received_mult -0.5 in mods; the on_struck reaction
		# deals 5% of the bearer's own max HP as ice each time a sourced attack hits it.
		"rime_skin":
			return Buff.make({
				"id": "rime_skin",
				"source": "Rime Skin",
				"desc": "Rime Skin: healing received cut by 50%; when struck by an attack, takes 5% of maximum health as ice damage.",
				"desc_template": "Rime Skin: healing received cut by {modpctabs:healing_received_mult}%; when struck by an attack, takes 5% of maximum health as ice damage. ({turns} left)",
				"kind": Buff.KIND_DEBUFF,
				"visible": true,
				"duration": 4,
				"stackable": false,
				"weight": 1.0,
				"resistible": true,
				# DISDAIN SCALING: modest — this already fires on every strike, so a big
				# amplification compounds fast.
				"potency_scale": 0.5,
				"duration_scale": 0.5,
				"element": "ice",
				"mods": {"healing_received_mult": -0.5},
				"on_struck": [
					{"effect": "self_pct_max_hp", "percent": 0.05, "element": "ice"},
				],
			})

		# --- Hoarfrost (Yod): amplify the next ice instance, then consume ------
		# A stacking marker debuff. It carries no stats: ice_amp_per_stack is read by
		# CombatBuffs.apply_incoming_ice_amp when a sourced ice hit lands, which boosts
		# that hit by 20% per stack and removes the debuff. Unlimited stacking (0).
		"hoarfrost":
			return Buff.make({
				"id": "hoarfrost",
				"source": "Hoarfrost",
				"desc": "Hoarfrost: the next ice damage taken is increased by 20% per stack, then consumed.",
				"kind": Buff.KIND_DEBUFF,
				"visible": true,
				"duration": 1,
				"stackable": true,
				"max_stacks": 0,
				"weight": 1.0,
				"resistible": false,   # a combo marker other abilities read; must land
				# DISDAIN SCALING: the amp itself grows (Buff.scale_potency reaches the
				# top-level ice_amp_per_stack), but the duration never does — this is a
				# one-turn marker meant to be spent, not sat on.
				"potency_scale": 0.5,
				"duration_scale": 0.0,
				"element": "ice",
				"ice_amp_per_stack": 0.2,
			})

		# --- Silenced (Mind Freeze): block spirit-cost abilities for 3 turns ---
		# The `silence` flag is read by CombatBuffs.is_silenced — the wheel greys out
		# spirit-cost slots for a silenced PLAYER; enemy targeting/action AI will consume
		# it once that engine exists (mirrors how `stunned` is wired). Fixed 3-turn
		# duration at every rank, so no per-rank clones are needed.
		"silenced":
			return Buff.make({
				"id": "silenced",
				"source": "Silenced",
				"desc": "Silenced: cannot use spirit-cost abilities for 3 turns.",
				"kind": Buff.KIND_DEBUFF,
				"visible": true,
				"duration": 3,
				"stackable": false,
				"weight": 1.0,
				"resistible": true,
				# DISDAIN SCALING: control, like the stun — nothing to amplify, and a
				# sparing duration roll capped at one extra turn.
				"potency_scale": 0.0,
				"duration_scale": 0.35,
				"max_extra_duration": 1,
				"silence": true,
			})

		# --- Wraith Form (Mercy): a defensive self-buff with an on-hit rider ------
		# Applied to the caster by the Wraith Form ability (SELF target). For 5 turns:
		# take 50% less damage (damage_taken_mult -0.5, the Guard lever read by CombatMath),
		# +50% Instinct (a base-stat multiplier that shows in readouts), and — via
		# on_hit_apply (see CombatBuffs.fire_on_hit) — coat every target the wraith strikes
		# in a 1-turn Rime Skin (the existing rime_skin debuff, duration overridden to 1).
		# Single-rank, so re-casting just refreshes the duration.
		"wraith_form":
			return Buff.make({
				"id": "wraith_form",
				"source": "Wraith Form",
				"desc": "Wraith Form: takes 50% less damage and has +50% Instinct for 5 turns; every target struck is coated in Rime Skin.",
				"kind": Buff.KIND_BUFF,
				"visible": true,
				"duration": 5,
				"stackable": false,
				"weight": 1.0,
				"resistible": false,
				"mods": {"damage_taken_mult": -0.5},
				"mult": {"instinct": 0.5},
				"on_hit_apply": [
					{"buff": "rime_skin", "duration": 1},
				],
			})

		# ====================================================================
		# ZONE 1 — THE ARCTIC  (the enemy catalogue; see the Menagerie)
		# ====================================================================
		# Seven entries, and the ratio is worth noting: everything above this line was
		# written for the PLAYER and almost none of it fits a creature. Budget roughly
		# one new buff per new creature until the enemy library is as deep.

		# --- Frenzied (Shambling Corpse): the zone's one CHARGED buff ----------
		# +200% damage dealt for the next THREE ATTACKS, expiring after 4 of the
		# bearer's own turns regardless — the charges are the real limit, the duration
		# only the outer bound. This is the first user of `charges`: nothing before it
		# measured a lifetime in USES. CombatBuffs.spend_attack_charges decrements it
		# on every attack the bearer lands, a killing blow included.
		#
		# The turn-one ban is NOT here — a buff cannot know whose turn it is. It lives
		# on the Frenzy .tres as ai_not_before_turn = 2, which keeps the ability out of
		# the AI's usable set entirely on the opening turn.
		"frenzied":
			return Buff.make({
				"id": "frenzied",
				"source": "Frenzy",
				"desc": "Frenzied: deals 200% more damage for its next 3 attacks (4 turns).",
				"kind": Buff.KIND_BUFF,
				"visible": true,
				"duration": 4,
				"charges": 3,
				"stackable": false,
				"weight": 1.0,
				"resistible": false,
				# The severity gauge earns a real number here: tripled damage is the
				# biggest single swing anything in the zone applies to itself.
				"magnitude": 3.5,
				"mods": {"damage_dealt_mult": 2.0},
			})

		# --- Thorns, PERMANENT (The Scavenger) -------------------------------
		# Identical to `thorns` above but duration -1, because a creature's innate
		# aura is granted through permanent_buffs and a 5-turn "permanent" buff would
		# quietly lapse partway through the boss fight. Not stackable either — the
		# stacking on `thorns` is a player mechanic (re-apply to build it up), and
		# nothing re-applies an innate hide. Same id, so if the player ever lands
		# thorns on the boss it refreshes rather than doubling.
		"thorns_permanent":
			return Buff.make({
				"id": "thorns",
				"source": "Thorns",
				"desc": "Thorns: reflects %d (+%d%% of the damage taken) back at anything that strikes it." % [
					int(THORNS_FLAT), int(round(THORNS_PCT * 100.0))],
				"kind": Buff.KIND_BUFF,
				"visible": true,
				"duration": -1,
				"stackable": false,
				"weight": 1.0,
				"resistible": false,
				"on_struck": [
					{"effect": "reflect", "amount": THORNS_FLAT, "percent": THORNS_PCT, "element": "physical"},
				],
			})

		# --- Frostnip (Frozen Corpse): a small ice DoT ------------------------
		# 50% of the CASTER's Instinct as ice per turn for 3 turns, snapshotted at
		# application (the arc_burn pattern) so it never drifts with the caster's
		# stats — and so the same creature met again at a higher ability rank in a
		# later zone bites harder with no second entry.
		"frostnip":
			return _make_snapshot_dot("frostnip", "Frostnip", "ice", 1.06, 3, caster)

		# (`infected` was folded into the unified `poison` on 2026-09-25 — its appliers,
		# contaminating_strike / infectious_strike / toxic_breath, now apply poison.)

		# --- Terrified (Unknown Entity): a mental DoT that also drains spirit --
		# The zone's only mental damage and its only spirit pressure. 25% of the
		# caster's Instinct per turn AND -15 spirit per turn for 4 turns: the damage is
		# incidental, the drain is the point. It makes the player spend before they
		# meant to, in the fight that has nothing else going on.
		"terrified":
			var t_inst := 0.0
			if caster != null:
				t_inst = maxf(0.0, caster.get_effective("instinct"))
			var t_dmg := 0.53 * t_inst   # RE-TUNED x2.125 for mitigated DoT (C.8)
			return Buff.make({
				"id": "terrified",
				"source": "Terrified",
				"desc": "Terrified: %d mental damage at the start of each turn (4 turns)." % int(round(t_dmg)),
				"desc_template": "Terrified: {dot} mental damage at the start of each turn ({turns} left).",
				"kind": Buff.KIND_DEBUFF,
				"visible": true,
				"duration": 4,
				"stackable": true,      # independent instances, like every snapshot DoT
				"max_stacks": 0,
				"weight": 1.0,
				"magnitude": 2.0,
				"resistible": true,
				# DISDAIN SCALING: full rate on both axes — a damage-over-time with a
				# resource cost bolted on, and neither half is control.
				"potency_scale": 1.0,
				"duration_scale": 1.0,
				"element": "mental",
				"dot": t_dmg,
				"dot_element": "mental",
				#"spirit_per_turn": -15.0,
			})

		# --- Rejuvenating Salve (Hunter): heal over time ----------------------
		# 40% of the CASTER's Instinct per turn for 5 turns, snapshotted — about 7 a
		# turn from a hunter, which is exactly what keeps the pair standing through the
		# Old Ice swarm. The numbers come from whoever CAST it, so handing it to a
		# partner does not silently rescale off the recipient.
		"rejuvenating_salve":
			var s_inst := 0.0
			if caster != null:
				s_inst = maxf(0.0, caster.get_effective("instinct"))
			var s_heal := 0.40 * s_inst
			return Buff.make({
				"id": "rejuvenating_salve",
				"source": "Rejuvenating Salve",
				"desc": "Rejuvenating Salve: restores %d health at the start of each turn (5 turns)." % int(round(s_heal)),
				"kind": Buff.KIND_BUFF,
				"visible": true,
				"duration": 5,
				"stackable": false,
				"weight": 1.0,
				"magnitude": 2.0,
				"resistible": false,
				"heal_per_turn": s_heal,
			})

		# --- Dark Blessing (the Chaplain): borrowed spiritual damage ----------
		# The blessed ally deals an extra 25% of THE CHAPLAIN'S Instinct as Spiritual
		# damage on every hit it lands — the energized_form on_hit_damage rider, aimed
		# at somebody else. Snapshotted at cast, so the number stays his even though
		# the buff lives on a Guard: the guards hit harder BECAUSE he is alive, which
		# is the fight's whole argument stated in damage rather than in dialogue.
		"dark_blessing":
			var d_inst := 0.0
			if caster != null:
				d_inst = maxf(0.0, caster.get_effective("instinct"))
			var d_bonus := 0.25 * d_inst
			return Buff.make({
				"id": "dark_blessing",
				"source": "Dark Blessing",
				"desc": "Dark Blessing: every hit deals an extra %d Spiritual damage (5 turns)." % int(round(d_bonus)),
				"kind": Buff.KIND_BUFF,
				"visible": true,
				"duration": 5,
				"stackable": false,
				"weight": 2.0,
				"magnitude": 2.0,
				"resistible": false,
				"element": "spiritual",
				"on_hit_damage": [
					{"element": "spiritual", "amount": d_bonus},
				],
			})

		# --- Gorged (The Scavenger): the boss's clock -------------------------
		# 3% of its OWN current max HP per turn for 2 turns, read LIVE
		# (heal_pct_per_turn, not a snapshot) — about 3.2 a turn against a player
		# netting 18.8, which is what stretches the boss from a 9-turn fight to an
		# 11-turn one. Self-applied by Gorge through applies_buff_self, so it never
		# rolls a resist.
		"gorged":
			return Buff.make({
				"id": "gorged",
				"source": "Gorged",
				"desc": "Gorged: restores 3% of maximum health at the start of each turn (2 turns).",
				"kind": Buff.KIND_BUFF,
				"visible": true,
				"duration": 2,
				"stackable": false,
				"weight": 1.0,
				"magnitude": 1.5,
				"resistible": false,
				"element": "blood",
				"heal_pct_per_turn": 0.03,
			})

		_:
			return {}

## A plain SNAPSHOT damage-over-time: `inst_pct` of the CASTER's Instinct per turn,
## as `element`, for `turns` of the bearer's own turns. The arc_burn / frost pattern
## generalised, because zone 1 wanted three of them (frostnip, infected, and the
## damage half of terrified) that differ in nothing but element, fraction and length.
##
## Snapshotting is what disconnects the debuff from its caster: the caster's Instinct
## and Disdain are baked in when it lands, and nothing afterwards reaches back to
## change it. Stacking as INDEPENDENT instances follows from that — a second, stronger
## application lands beside the first rather than overwriting it.
static func _make_snapshot_dot(p_id: String, p_source: String, element: String,
		inst_pct: float, turns: int, caster: CharacterBase) -> Dictionary:
	var dmg := 0.0
	if caster != null:
		dmg = inst_pct * maxf(0.0, caster.get_effective("instinct"))
	return Buff.make({
		"id": p_id,
		"source": p_source,
		"desc": "%s: %d %s damage at the start of each turn (%d turns)." % [
			p_source, int(round(dmg)), element, turns],
		"desc_template": "%s: {dot} %s damage at the start of each turn ({turns} left)." % [p_source, element],
		"kind": Buff.KIND_DEBUFF,
		"visible": true,
		"duration": turns,
		"stackable": true,
		"max_stacks": 0,          # unlimited independent instances
		"weight": 1.0,
		"resistible": true,
		# DISDAIN SCALING: pure damage-over-time — full rate on both axes, exactly
		# like arc_burn, which is the entry this one generalises.
		"potency_scale": 1.0,
		"duration_scale": 1.0,
		"element": element,
		"dot": dmg,
		"dot_element": element,
	})

## Build a Guard damage-reduction buff: a self buff that reduces ALL incoming damage
## by `reduction` (0.80 = take 80% less) until the caster's next turn (duration 1, so
## it protects through the enemies' turn and expires at the start of the caster's next
## turn). The four Guard ranks are clones of this differing ONLY in `reduction`. Stored
## as a `mods` entry (damage_taken_mult, additive around 0) so CombatMath reads it via
## get_basket_bonus, exactly like the attacker-side damage_dealt_mult layer. All ranks
## share id "guard" so applying it refreshes duration instead of stacking.
static func _make_guard(reduction: float) -> Dictionary:
	return Buff.make({
		"id": "guard",
		"source": "Guard",
		"desc": "Guarding: takes %d%% less damage until your next turn." % int(round(reduction * 100.0)),
		"kind": Buff.KIND_BUFF,
		"visible": true,
		"duration": 1,
		"stackable": false,
		"mods": {"damage_taken_mult": -reduction},
	})

## Constant fraction of ALL incoming damage that Scaled Skin removes, at every rank
## (0.20 = take 20% less). The single tuning spot for the resist half of the buff.
const SCALED_SKIN_RESIST := 0.20

## Build a Scaled Skin buff: a target buff that reduces ALL incoming damage by
## SCALED_SKIN_RESIST and restores `heal_pct` of the TARGET's Instinct at the start
## of each of the target's turns, for `turns` turns. The three ranks are clones of
## this differing only in `turns` (5/6/7) and `heal_pct` (0.30/0.40/0.50). The resist
## is a `mods` damage_taken_mult (read by CombatMath, same lever as Guard); the heal
## is SNAPSHOTTED here from the target's effective Instinct into heal_per_turn (read
## each turn by CombatBuffs.collect_turn_start -> combat applies it via heal()). All
## ranks share id "scaled_skin" so applying it refreshes duration instead of stacking.
static func _make_scaled_skin(turns: int, heal_pct: float, target: CharacterBase) -> Dictionary:
	var instinct := 0.0
	if target != null:
		instinct = maxf(0.0, target.get_effective("instinct"))
	var heal := heal_pct * instinct
	return Buff.make({
		"id": "scaled_skin",
		"source": "Scaled Skin",
		"desc": "Scaled Skin: takes %d%% less damage and restores %d health at the start of each turn for %d turns." % [
			int(round(SCALED_SKIN_RESIST * 100.0)), int(round(heal)), turns],
		"kind": Buff.KIND_BUFF,
		"visible": true,
		"duration": turns,
		"stackable": false,
		"element": "toxic",
		"mods": {"damage_taken_mult": -SCALED_SKIN_RESIST},
		"heal_per_turn": heal,
	})

## Build a Hematopoiesis buff: a pure heal-over-time that restores `heal_pct` of the
## TARGET's (Vigor + Instinct) at the start of each of the target's turns, for `turns`
## turns. The three ranks are clones differing only in `turns` (4/5/6) and `heal_pct`
## (1.00/2.00/3.25). The heal is SNAPSHOTTED here from the target's effective Vigor and
## Instinct into heal_per_turn (read each turn by CombatBuffs.collect_turn_start ->
## combat applies it via heal()). No resist / mods — it is heal only. All ranks share
## id "hematopoiesis" so applying it refreshes duration instead of stacking.
static func _make_hematopoiesis(turns: int, heal_pct: float, target: CharacterBase) -> Dictionary:
	var stat_sum := 0.0
	if target != null:
		stat_sum = maxf(0.0, target.get_effective("vigor")) + maxf(0.0, target.get_effective("instinct"))
	var heal := heal_pct * stat_sum
	return Buff.make({
		"id": "hematopoiesis",
		"source": "Hematopoiesis",
		"desc": "Hematopoiesis: restores %d health at the start of each turn for %d turns." % [int(round(heal)), turns],
		"kind": Buff.KIND_BUFF,
		"visible": true,
		"duration": turns,
		"stackable": false,
		"element": "blood",
		"heal_per_turn": heal,
	})

## Build a Gliogenesis buff: a PERMANENT self buff that, at the start of each of the
## bearer's turns, restores `heal_pct` of the bearer's CURRENT max HP and grants
## `spirit` flat spirit. Unlike Scaled Skin / Hematopoiesis (which snapshot a flat
## heal from a stat at cast), the health regen here is LIVE via heal_pct_per_turn, so
## it tracks any change to max HP during the fight. The four Gliogenesis ranks are
## clones of this differing only in `heal_pct` and `spirit`. Re-applying refreshes
## (shared id "gliogenesis"); the passive re-grants it every combat.
static func _make_gliogenesis(heal_pct: float, spirit: float) -> Dictionary:
	var pct_txt := ("%.1f" % (heal_pct * 100.0)).trim_suffix(".0")
	var spirit_txt := "" if spirit <= 0.0 else " and %d spirit" % int(round(spirit))
	return Buff.make({
		"id": "gliogenesis",
		"source": "Gliogenesis",
		"desc": "Gliogenesis: restores %s%% of maximum health%s at the start of each turn." % [pct_txt, spirit_txt],
		"kind": Buff.KIND_BUFF,
		"visible": true,
		"duration": -1,               # permanent for the fight; re-granted each combat by the passive
		"stackable": false,
		"weight": 1.0,
		"resistible": false,
		"element": "spiritual",
		"heal_pct_per_turn": heal_pct,
		"spirit_per_turn": spirit,
	})

## Build a Sclerosis in Binah buff: a PERMANENT self buff that, at the start of each of
## the bearer's turns, grants `spirit` flat spirit and takes 5% of the bearer's CURRENT
## max HP as TRUE damage. The hardening trade — understanding bought with the body.
##
## The damage is LIVE (dot_pct_per_turn, not a snapshot), so it tracks max HP through the
## fight, and it is dealt as "true", which means it ignores mitigation AND — since the
## true-damage shield bypass — ignores absorbing shields. You cannot shield your way out
## of the cost. Only the spirit differs across the four ranks; the 5% is flat, so higher
## ranks are strictly better (more spirit for the same bill).
##
## NB: DoT is multiplied by the bearer's `vulnerability` when the turn tick collects it,
## so a vulnerability debuff makes Sclerosis bite harder than 5%. That is intended — it
## is the one dial that makes the cost situational.
static func _make_sclerosis(spirit: float) -> Dictionary:
	return Buff.make({
		"id": "sclerosis",
		"source": "Sclerosis in Binah",
		"desc": "Sclerosis in Binah: +%d spirit at the start of each turn, paid for with 5%% of maximum health as true damage." % int(round(spirit)),
		"kind": Buff.KIND_BUFF,
		"visible": true,
		"duration": -1,               # permanent for the fight; re-granted each combat by the passive
		"stackable": false,
		"weight": 1.0,
		"resistible": false,
		"element": "true",
		"spirit_per_turn": spirit,
		"dot_pct_per_turn": 0.05,     # 5% of CURRENT max HP, read live
		"dot_element": "true",        # ignores mitigation and shields
	})

## Build a Hypothermia debuff: a multiplicative alacrity reduction plus a flat 5
## spirit drain per turn, for 8 turns. The two ranks differ only in `alac_mult`.
static func _make_hypothermia(alac_mult: float) -> Dictionary:
	return Buff.make({
		"id": "hypothermia",
		"source": "Hypothermia",
		"desc": "Hypothermia: %d%% alacrity and drains 5 spirit at the start of each turn (8 turns)." % int(round(alac_mult * 100.0)),
		"desc_template": "Hypothermia: {mult:alacrity}% alacrity and drains {spiritabs} spirit at the start of each turn ({turns} left).",
		"kind": Buff.KIND_DEBUFF,
		"visible": true,
		"duration": 8,
		"stackable": false,
		"weight": 1.0,
		"resistible": true,
		# DISDAIN SCALING: the alacrity cut deepens readily; the duration is already
		# a long 8 turns, so that axis is held back.
		"potency_scale": 0.75,
		"duration_scale": 0.5,
		"element": "ice",
		"mult": {"alacrity": alac_mult},
		"spirit_per_turn": -5.0,
	})

## Build a Frost debuff: a multiplicative alacrity reduction plus an ice DoT for 2
## turns. The DoT is SNAPSHOTTED from the CASTER at cast time (instinct_pct*Instinct
## + vigor_pct*Vigor), mirroring how Scaled Skin snapshots its heal. The two ranks
## differ in `alac_mult` and `instinct_pct` (vigor share is the same 25%).
static func _make_frost(alac_mult: float, instinct_pct: float, vigor_pct: float, caster: CharacterBase) -> Dictionary:
	var dmg := 0.0
	if caster != null:
		dmg = instinct_pct * maxf(0.0, caster.get_effective("instinct")) + vigor_pct * maxf(0.0, caster.get_effective("vigor"))
	return Buff.make({
		"id": "frost",
		"source": "Frost",
		"desc": "Frost: %d%% alacrity and %d ice damage at the start of each turn (2 turns)." % [int(round(alac_mult * 100.0)), int(round(dmg))],
		"desc_template": "Frost: {mult:alacrity}% alacrity and {dot} ice damage at the start of each turn ({turns} left).",
		"kind": Buff.KIND_DEBUFF,
		"visible": true,
		"duration": 2,
		"stackable": false,
		"weight": 1.0,
		"resistible": true,
		# DISDAIN SCALING: a damage-over-time is the cheapest thing to hand an extra
		# turn, so both axes run at full rate. This is the shape a Disdain build wants.
		"potency_scale": 1.0,
		"duration_scale": 1.0,
		"element": "ice",
		"mult": {"alacrity": alac_mult},
		"dot": dmg,
		"dot_element": "ice",
	})

## Build an Arc Burn debuff (Neurostatic): a pure lightning DoT for 3 turns whose
## per-turn damage is SNAPSHOTTED from the caster's Instinct at application time
## (instinct_pct * Instinct), mirroring how Frost / Scaled Skin snapshot theirs.
static func _make_arc_burn(instinct_pct: float, caster: CharacterBase) -> Dictionary:
	var dmg := 0.0
	if caster != null:
		dmg = instinct_pct * maxf(0.0, caster.get_effective("instinct"))
	return Buff.make({
		"id": "arc_burn",
		"source": "Arc Burn",
		"desc": "Arc Burn: %d Lightning damage at the start of each turn (3 turns)." % int(round(dmg)),
		"desc_template": "Arc Burn: {dot} Lightning damage at the start of each turn ({turns} left).",
		"kind": Buff.KIND_DEBUFF,
		"visible": true,
		"duration": 3,
		# STACKS, as independent instances. Every fresh Neurostatic / Pass Current adds
		# ANOTHER arc_burn entry carrying the Instinct snapshot and Disdain empowerment of
		# THAT cast, ticking and expiring on its own three-turn clock. Build Instinct or
		# Disdain mid-fight and the next application burns harder while the ones already
		# on the target keep their original numbers. No cap.
		"stackable": true,
		"weight": 1.0,
		"resistible": true,
		# DISDAIN SCALING: pure damage-over-time — full rate on both axes.
		"potency_scale": 1.0,
		"duration_scale": 1.0,
		"element": "lightning",
		"dot": dmg,
		"dot_element": "lightning",
	})


## Build an Electromyogenesis buff: flat Alacrity equal to `instinct_pct` of the
## CASTER's Instinct at cast time, for `turns` turns. Snapshotted, so handing it to an
## ally still pays out on the caster's Instinct.
static func _make_electromyogenesis(instinct_pct: float, turns: int, caster: CharacterBase) -> Dictionary:
	var alac := 0.0
	if caster != null:
		alac = instinct_pct * maxf(0.0, caster.get_effective("instinct"))
	return Buff.make({
		"id": "electromyogenesis",
		"source": "Electromyogenesis",
		"desc": "Electromyogenesis: +%d Alacrity (%d%% of Instinct) for %d turns." % [int(round(alac)), int(round(instinct_pct * 100.0)), turns],
		"kind": Buff.KIND_BUFF,
		"visible": true,
		"duration": turns,
		"stackable": false,
		"weight": 1.0,
		"resistible": false,
		"element": "lightning",
		"mods": {"alacrity": alac},
	})


## Build an Electrostimulated buff: a big flat stat package plus spirit regen, paid for
## with a self-inflicted lightning DoT equal to `instinct_pct` of the CASTER's Instinct
## (snapshotted at cast). The DoT runs through the bearer's own lightning resistance and
## `vulnerability` like any other DoT, so lightning resist is a real counterplay.
static func _make_electrostimulated(turns: int, instinct_pct: float, alac: float, vig: float, inst: float, caster: CharacterBase) -> Dictionary:
	var dmg := 0.0
	if caster != null:
		dmg = instinct_pct * maxf(0.0, caster.get_effective("instinct"))
	return Buff.make({
		"id": "electrostimulated",
		"source": "Electrostimulated",
		"desc": "Electrostimulated: +%d Alacrity, +%d Vigor, +%d Instinct and +5 spirit per turn, but take %d Lightning damage at the start of each turn (%d turns)." % [int(alac), int(vig), int(inst), int(round(dmg)), turns],
		"kind": Buff.KIND_BUFF,
		"visible": true,
		"duration": turns,
		"stackable": false,
		"weight": 2.0,
		"resistible": false,
		"element": "lightning",
		"mods": {
			"alacrity": alac,
			"vigor": vig,
			"instinct": inst,
		},
		"dot": dmg,
		"dot_element": "lightning",
		"spirit_per_turn": 5.0,
	})


## Build the Lightning Shell passive's hidden-machinery buff for invested `rank` (1..10).
## It carries no stat mods at all — its whole payload is the `overflow_shield` spec:
## every OVERFLOW_SHELL_PER_SPIRIT points of spirit the bearer would have gained above its
## maximum become an absorbing shield worth (rank x 10% of Vitality + 10% of Instinct).
## The scale fractions are read LIVE against the bearer when the conversion happens
## (BattleCharacter._convert_spirit_overflow), NOT snapshotted here, so the shield follows
## the bearer's Vitality and Instinct as gear and buffs move them. No "decay" key => the
## shield never decays and lasts until it is spent.
const OVERFLOW_SHELL_PER_SPIRIT := 5
const OVERFLOW_SHELL_VIT_PER_RANK := 0.10
const OVERFLOW_SHELL_INSTINCT := 0.10

static func _make_lightning_shell(rank: int) -> Dictionary:
	var r := clampi(rank, 1, 10)
	var vit := OVERFLOW_SHELL_VIT_PER_RANK * float(r)
	return Buff.make({
		"id": "lightning_shell",
		"source": "Lightning Shell",
		"desc": "Lightning Shell: every %d Spirit that would refill past your maximum becomes a shield worth %d%% of Vitality + %d%% of Instinct. The shield does not decay." % [
			OVERFLOW_SHELL_PER_SPIRIT, int(round(vit * 100.0)), int(round(OVERFLOW_SHELL_INSTINCT * 100.0))],
		"kind": Buff.KIND_BUFF,
		"visible": true,
		"duration": -1,              # -1 => permanent, never expires
		"stackable": false,
		"weight": 1.0,
		"resistible": false,
		"element": "lightning",
		"overflow_shield": {
			"per_spirit": OVERFLOW_SHELL_PER_SPIRIT,
			"scale": {
				"vitality": vit,
				"instinct": OVERFLOW_SHELL_INSTINCT,
			},
		},
	})


# ============================================================================
# THE NEPHILIC (2026-09-24) — the kit's buffs. Per-rank families are "<id>_<rank>";
# combat._rank_clone_id finds them generically, so none needs a match line there.
# Every magnitude is a `# TUNE` placeholder from NEPHILIC_PLAN unless it IS the spec.
# ============================================================================
const ON_FIRE_VIGOR := 0.20     # TUNE — unified On Fire: DoT = 20% applier Vigor
const POISON_VITALITY := 0.50   # TUNE — unified poison: DoT = 50% applier VITALITY (dev call 2026-09-25)

static func _neph_rank(id: String, base: String, n: int) -> int:
	if not id.begins_with(base + "_"):
		return 0
	var tail := id.substr(base.length() + 1)
	if not tail.is_valid_int():
		return 0
	var r := int(tail)
	return r if r >= 1 and r <= n else 0

static func _pick(arr: Array, r: int):
	return arr[clampi(r - 1, 0, arr.size() - 1)]

static func _build_nephilic(id: String, caster: CharacterBase) -> Dictionary:
	match id:
		# UNIFIED POISON (FUTURE_PLANS §2): one debuff for every applier, stacking as
		# independent instances; only the duration varies with the application.
		"poison":
			var dmg := POISON_VITALITY * (maxf(0.0, caster.get_effective("vitality")) if caster != null else 0.0)
			return Buff.make({
				"id": "poison", "source": "Poison",
				"desc_template": "Poison: {dot} toxic damage at the start of each turn ({turns} left).",
				"kind": Buff.KIND_DEBUFF, "duration": 4,
				"stackable": true, "max_stacks": 0,
				"element": "toxic",
				"potency_scale": 1.0, "duration_scale": 1.0,
				"dot": dmg, "dot_element": "toxic",
			})
		"stand_firm_lead":
			return Buff.make({
				"id": "stand_firm_lead", "source": "Stand Firm",
				"desc": "Your next Lead grants +25 spirit.",
				"kind": Buff.KIND_BUFF, "duration": -1, "stackable": false,
				"lead_spirit_bonus": 25,
			})
		"ablution_ward":
			return Buff.make({
				"id": "ablution_ward", "source": "Ablution",
				"desc_template": "Purified: cannot be debuffed ({turns} left).",
				"kind": Buff.KIND_BUFF, "duration": 1, "stackable": false,
				"debuff_immune": true,
			})
		"putrefaction_cost":
			return Buff.make({
				"id": "putrefaction_cost", "source": "Putrefaction",
				"desc_template": "Putrefaction: pay 3% max HP at the start of each turn ({turns} left).",
				"kind": Buff.KIND_DEBUFF, "duration": 4, "stackable": true,
				"resistible": false, "uncleansable": true,
				"element": "toxic",
				"hp_cost_pct_per_turn": 0.03,
			})
		"apotheosis":
			return Buff.make({
				"id": "apotheosis", "source": "Apotheosis",
				"desc_template": "Apotheosis: Crash costs no spirit and deals 60% damage ({turns} left).",
				"kind": Buff.KIND_BUFF, "duration": 3, "stackable": false,
				"crash_free": true, "crash_damage_mult": 0.6,
			})
		"grit_ward":
			return Buff.make({
				"id": "grit_ward", "source": "Grit",
				"desc_template": "Grit: takes {modpctabs:damage_taken_mult}% less damage while the shield holds.",
				"kind": Buff.KIND_BUFF, "duration": -1, "stackable": false,
				"expire_on_shield_break": true,
				"mods": {"damage_taken_mult": -0.25},
			})
	var r := 0
	r = _neph_rank(id, "stand_firm", 2)
	if r > 0:
		return Buff.make({
			"id": "stand_firm", "source": "Stand Firm",
			"desc_template": "Stand Firm: takes {modpctabs:damage_taken_mult}% less damage ({turns} left).",
			"kind": Buff.KIND_BUFF, "duration": 3, "stackable": false,
			"mods": {"damage_taken_mult": -float(_pick([0.40, 0.45], r))},
		})
	r = _neph_rank(id, "tithe", 3)
	if r > 0:
		return Buff.make({
			"id": "tithe", "source": "Tithe",
			"desc_template": "Tithe: deals {modpct:damage_dealt_mult}% more damage ({turns} left).",
			"kind": Buff.KIND_BUFF, "duration": 3, "stackable": false,   # TUNE duration
			"mods": {"damage_dealt_mult": float(_pick([0.20, 0.25, 0.30], r))},
		})
	r = _neph_rank(id, "inhale", 2)
	if r > 0:
		return Buff.make({
			"id": "inhale", "source": "Inhale",
			"desc_template": "Inhale: +{spirit} spirit at the start of each turn ({turns} left).",
			"kind": Buff.KIND_BUFF, "duration": int(_pick([4, 5], r)), "stackable": false,
			"spirit_per_turn": 10.0,
		})
	r = _neph_rank(id, "wormwood", 4)
	if r > 0:
		return Buff.make({
			"id": "wormwood", "source": "Wormwood",
			"desc_template": "Wormwood: {mod:toxic_defense} Toxic resistance ({turns} left).",
			"kind": Buff.KIND_DEBUFF, "duration": 4, "stackable": true,
			"element": "toxic",
			"potency_scale": 0.5, "duration_scale": 0.5,
			"mods": {"toxic_defense": -float(_pick([15, 20, 25, 30], r))},
		})
	r = _neph_rank(id, "waxing_moon", 4)
	if r > 0:
		var mods := _all_resist_mods(float(_pick([8, 12, 16, 20], r)))
		mods["damage_dealt_mult"] = float(_pick([0.15, 0.20, 0.25, 0.30], r))
		return Buff.make({
			"id": "waxing_moon", "source": "Waxing Moon",
			"desc_template": "Waxing Moon: deals {modpct:damage_dealt_mult}% more damage, +{mod:physical_defense} to every resistance ({turns} left).",
			"kind": Buff.KIND_BUFF, "duration": 4, "stackable": false,
			"mods": mods,
		})
	r = _neph_rank(id, "silver_mirror", 4)
	if r > 0:
		return Buff.make({
			"id": "silver_mirror", "source": "Silver Mirror",
			"desc_template": "Silver Mirror: the next enemy attacks that hit are turned aside ({turns} left).",
			"kind": Buff.KIND_BUFF, "duration": int(_pick([2, 3, 3, 3], r)), "stackable": false,
			"struck_charges": int(_pick([1, 1, 2, 3], r)),
		})
	r = _neph_rank(id, "epiphany", 5)
	if r > 0:
		return Buff.make({
			"id": "epiphany", "source": "Epiphany",
			"desc_template": "Epiphany: your other buffs are frozen, and each one adds damage ({turns} left).",
			"kind": Buff.KIND_BUFF, "duration": int(_pick([3, 3, 3, 4, 4], r)), "stackable": false,
			"freeze_buffs": true,
			"epiphany_per_buff": float(_pick([0.08, 0.10, 0.12, 0.14, 0.16], r)),
		})
	r = _neph_rank(id, "intercede", 4)
	if r > 0:
		return Buff.make({
			"id": "intercede", "source": "Intercede",
			"desc_template": "Interceded: part of the damage aimed at this unit is taken by its guardian ({turns} left).",
			"kind": Buff.KIND_BUFF, "duration": 3, "stackable": false,
			"redirect_pct": float(_pick([0.20, 0.30, 0.40, 0.50], r)),
		})
	r = _neph_rank(id, "putrefaction", 4)
	if r > 0:
		return Buff.make({
			"id": "putrefaction", "source": "Putrefaction",
			"desc_template": "Putrefaction: deals {modpct:damage_dealt_mult}% more damage ({turns} left).",
			"kind": Buff.KIND_BUFF, "duration": 4, "stackable": false,
			"mods": {"damage_dealt_mult": float(_pick([0.15, 0.20, 0.25, 0.30], r))},
		})
	r = _neph_rank(id, "first_sun", 5)
	if r > 0:
		return Buff.make({
			"id": "first_sun", "source": "First Sun",
			"desc_template": "First Sun: deals {modpct:damage_dealt_mult}% more damage ({turns} left).",
			"kind": Buff.KIND_BUFF, "duration": 3, "stackable": false,
			"mods": {"damage_dealt_mult": float(_pick([0.30, 0.35, 0.40, 0.45, 0.50], r))},
		})
	r = _neph_rank(id, "rejuvenation", 3)
	if r > 0:
		return Buff.make({
			"id": "rejuvenation", "source": "Rejuvenation",
			"desc_template": "Rejuvenation: heal {heal_pct}% of max HP at the start of each turn.",
			"kind": Buff.KIND_BUFF, "duration": -1, "stackable": false,
			"heal_pct_per_turn": float(_pick([0.02, 0.03, 0.04], r)),
		})
	r = _neph_rank(id, "heavy_hand", 3)
	if r > 0:
		return Buff.make({
			"id": "heavy_hand", "source": "Heavy Hand",
			"desc": "Heavy Hand: more crit damage.",
			"kind": Buff.KIND_BUFF, "duration": -1, "stackable": false, "visible": false,
			"mods": {"crit_damage_bonus": float(_pick([0.15, 0.30, 0.45], r))},
		})
	return {}

## True when `id` names a buff this library knows how to build.
## Cached per id (perf, 2026-09-25): whether an id resolves never changes at runtime,
## and combat asks for every buff application (_rank_clone_id), which used to build
## and throw away a whole entry each time.
static var _has_cache: Dictionary = {}

static func has(id: String) -> bool:
	if not _has_cache.has(id):
		_has_cache[id] = not build(id).is_empty()
	return bool(_has_cache[id])

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
