extends RefCounted
class_name AIRules

## ============================================================================
## AI RULES  —  the ARCHETYPE CATALOGUE  (AI_PRIMER §13)
## ============================================================================
## `CharacterBase.ai` names an archetype. Each entry supplies:
##   "preset"        the archetype's STAT BLOCK — applied to a body ONLY where the
##                   module / fight spec left that stat at its Stats.AI_DEFAULTS value,
##                   so a module can name an archetype and still override two numbers.
##                   Never baked into base_stats (it would pollute nothing, but it keeps
##                   "what the module said" and "what the archetype says" separable).
##   "target_gains"  per-intent WIRING: which [signal, gain stat] terms bend magnetism.
##                   An intent not listed uses STANDARD_WIRING's — and today every
##                   archetype uses the standard wiring (it already consults every
##                   signal; an archetype's personality is its NUMBERS).
##   "label"         a player-facing name (for the future ally-behaviour picker, §14.2).
##
## A NEW ARCHETYPE IS ONE DICTIONARY ENTRY. Unknown ids fall back to "standard" with a
## one-time warning (a typo is never a silent pass).
##
## SIGNATURE + TEXTURE (§4.6): one big gain, three to five small ones, silence elsewhere.
##
## class_name global — RESTART Godot once after adding this script.
## ----------------------------------------------------------------------------

## Per-intent target wiring (§8.2). Each term: [signal name, gain stat].
const STANDARD_WIRING := {
	"offense": [
		["missing_hp", "ai_bloodlust"], ["hp_frac", "ai_gluttony"], ["lethal", "ai_opportunism"],
		["threat", "ai_caution"], ["shield_frac", "ai_shield_aversion"], ["spirit_frac", "ai_spirit_hunger"],
		["debuff_severity", "ai_spite"], ["combo_ready", "ai_combo_drive"], ["element_advantage", "ai_element_savvy"],
		["softness", "ai_efficiency"], ["reputation", "ai_grudge"], ["cooldown_load", "ai_pressure"],
		["is_female", "ai_spare_female"], ["is_child", "ai_spare_child"],
	],
	"debuff": [
		["debuff_severity", "ai_tidiness"], ["hp_frac", "ai_prudence"], ["threat", "ai_sapper"],
		["resist_chance", "ai_resist_awareness"], ["element_advantage", "ai_element_savvy"],
		["softness", "ai_efficiency"], ["reputation", "ai_grudge"], ["cooldown_load", "ai_pressure"],
		["is_female", "ai_spare_female"], ["is_child", "ai_spare_child"],
	],
	"buff": [
		["missing_hp", "ai_mercy"], ["debuff_severity", "ai_triage"], ["buff_severity", "ai_tidiness"],
		["incoming_pressure", "ai_vigilance"], ["ally_power", "ai_favoritism"], ["is_self", "ai_self_buff"],
	],
}

const RULES := {
	# --- baseline ------------------------------------------------------------
	"standard": {"label": "Balanced", "preset": {}},
	"erratic": {"label": "Erratic", "preset": {"ai_decisiveness": 0.0, "ai_focus": 0.0}},

	# --- offense family ------------------------------------------------------
	"brute": {"label": "Brute", "preset": {
		"ai_intent_offense": 0.85, "ai_intent_defense": 0.05, "ai_intent_buff": 0.0, "ai_intent_debuff": 0.0,
		"ai_focus": 1.0, "magnetism": 130.0, "ai_efficiency": 2.0}},
	"assassin": {"label": "Assassin", "preset": {
		"ai_intent_offense": 0.90, "ai_intent_debuff": 0.15, "ai_intent_defense": 0.05, "ai_intent_buff": 0.0,
		"ai_focus": 2.5, "magnetism": 55.0, "ai_bloodlust": 40.0, "ai_opportunism": 30.0,
		"ai_efficiency": 3.0, "ai_pressure": 2.5, "ai_grudge": 2.0, "ai_caution": 0.7}},
	"executioner": {"label": "Executioner", "preset": {
		"ai_intent_offense": 0.85, "ai_intent_defense": 0.10, "ai_intent_buff": 0.0, "ai_intent_debuff": 0.0,
		"ai_bloodlust": 4.0, "ai_finisher": 40.0, "ai_opportunism": 60.0,
		"ai_efficiency": 3.5, "ai_pressure": 2.0, "ai_gluttony": 1.4}},
	"coward": {"label": "Coward", "preset": {
		"ai_intent_offense": 0.60, "ai_intent_defense": 0.30, "ai_intent_buff": 0.0, "ai_intent_debuff": 0.10,
		"ai_panic": 12.0, "magnetism": 70.0, "ai_caution": 0.12,
		"ai_efficiency": 2.5, "ai_pressure": 2.0, "ai_grudge": 0.6}},
	"duelist": {"label": "Duelist", "preset": {
		"ai_intent_offense": 0.85, "ai_intent_defense": 0.10, "ai_intent_buff": 0.0, "ai_intent_debuff": 0.0,
		"ai_focus": 4.0, "ai_opportunism": 12.0, "ai_caution": 6.0,
		"ai_grudge": 3.0, "ai_efficiency": 0.8, "ai_pressure": 1.6}},
	"berserker": {"label": "Berserker", "preset": {
		"ai_intent_offense": 0.70, "ai_intent_defense": 0.05, "ai_intent_buff": 0.0, "ai_intent_debuff": 0.0,
		"ai_panic": 0.2, "ai_opportunism": 15.0, "ai_bloodrage": 10.0,
		"ai_efficiency": 2.5, "ai_caution": 1.5, "ai_pressure": 1.5}},
	"titan_slayer": {"label": "Titan Slayer", "preset": {
		"ai_intent_offense": 0.85, "ai_intent_defense": 0.10, "ai_intent_buff": 0.0, "ai_intent_debuff": 0.0,
		"ai_bloodlust": 0.5, "ai_gluttony": 6.0,
		"ai_efficiency": 0.7, "ai_grudge": 2.0, "ai_shield_aversion": 1.0}},
	"enforcer": {"label": "Enforcer", "preset": {
		"ai_intent_offense": 0.85, "ai_intent_defense": 0.10, "ai_intent_buff": 0.0, "ai_intent_debuff": 0.0,
		"ai_grudge": 15.0,
		"ai_gluttony": 3.0, "ai_efficiency": 2.0, "ai_caution": 1.5,
		# MEMORY: reputation reads the NEWEST past fight only — he goes for whoever
		# did the most damage last time, before this fight has told him anything.
		"ai_memory_from": 0.0, "ai_memory_span": 1.0}},
	"shield_reaver": {"label": "Shield Reaver", "preset": {
		"ai_intent_offense": 0.85, "ai_intent_defense": 0.10, "ai_intent_buff": 0.0, "ai_intent_debuff": 0.0,
		"ai_shield_aversion": 3.5, "ai_efficiency": 2.0, "ai_pressure": 2.2, "ai_grudge": 1.8}},
	"spirit_leech": {"label": "Spirit Leech", "preset": {
		"ai_intent_offense": 0.55, "ai_intent_defense": 0.15, "ai_intent_buff": 0.0, "ai_intent_debuff": 0.35,
		"ai_prudence": 1.0, "ai_spirit_hunger": 6.0,
		"ai_pressure": 3.0, "ai_grudge": 2.5, "ai_efficiency": 1.8, "ai_thirst": 8.0}},
	"chevalier": {"label": "Chevalier", "preset": {
		"ai_intent_offense": 0.75, "ai_intent_defense": 0.20, "ai_intent_buff": 0.0, "ai_intent_debuff": 0.05,
		"ai_focus": 2.0, "magnetism": 120.0, "ai_spare_child": 0.05,
		"ai_spare_female": 0.5, "ai_caution": 3.0, "ai_efficiency": 1.5, "ai_grudge": 2.2}},
	"lockjaw": {"label": "Lockjaw", "preset": {
		"ai_intent_offense": 0.45, "ai_intent_defense": 0.05, "ai_intent_buff": 0.0, "ai_intent_debuff": 0.50,
		"ai_focus": 2.5, "ai_pressure": 12.0,
		"ai_efficiency": 2.0, "ai_grudge": 3.0, "ai_prudence": 2.0, "ai_tidiness": 0.6}},

	# --- control family --------------------------------------------------------
	"hexer": {"label": "Hexer", "preset": {
		"ai_intent_debuff": 0.80, "ai_intent_offense": 0.25, "ai_intent_defense": 0.15, "ai_intent_buff": 0.05,
		"ai_offer_drive": 8.0, "ai_tidiness": 0.15,
		"ai_prudence": 2.2, "ai_efficiency": 1.8, "ai_grudge": 2.0, "ai_pressure": 1.6}},
	"plaguebearer": {"label": "Plaguebearer", "preset": {
		"ai_intent_debuff": 0.80, "ai_intent_offense": 0.25, "ai_intent_defense": 0.15, "ai_intent_buff": 0.05,
		"ai_tidiness": 1.0, "ai_focus": 3.0, "ai_spite": 4.0,
		"ai_pressure": 2.5, "ai_efficiency": 2.0, "ai_prudence": 1.8}},
	"sapper": {"label": "Sapper", "preset": {
		"ai_intent_debuff": 0.70, "ai_intent_offense": 0.35, "ai_intent_defense": 0.15, "ai_intent_buff": 0.0,
		"ai_prudence": 2.5, "ai_sapper": 6.0, "ai_grudge": 3.5, "ai_pressure": 2.0, "ai_efficiency": 1.5}},
	"disabler": {"label": "Disabler", "preset": {
		"ai_intent_debuff": 0.75, "ai_intent_offense": 0.30, "ai_intent_defense": 0.15, "ai_intent_buff": 0.0,
		"ai_prudence": 2.5, "ai_offer_drive": 10.0, "ai_grudge": 3.0, "ai_pressure": 2.5, "ai_efficiency": 1.5}},
	"combo_setter": {"label": "Combo Setter", "preset": {
		"ai_intent_debuff": 0.60, "ai_intent_offense": 0.50, "ai_intent_defense": 0.10, "ai_intent_buff": 0.0,
		"ai_tidiness": 0.5, "ai_combo_drive": 10.0,
		"ai_efficiency": 2.5, "ai_prudence": 2.0, "ai_pressure": 1.5}},
	"warlock": {"label": "Warlock", "preset": {
		"ai_smart": 1.0, "ai_decisiveness": 3.0,
		"ai_intent_debuff": 0.70, "ai_intent_offense": 0.40, "ai_intent_defense": 0.20, "ai_intent_buff": 0.10,
		"magnetism": 90.0, "ai_resist_awareness": 0.15,
		"ai_element_savvy": 3.5, "ai_grudge": 3.0, "ai_efficiency": 2.5, "ai_pressure": 2.0}},

	# --- support family ----------------------------------------------------------
	"medic": {"label": "Medic", "preset": {
		"ai_intent_buff": 0.70, "ai_intent_defense": 0.30, "ai_intent_offense": 0.15, "ai_intent_debuff": 0.05,
		"ai_triage": 6.0, "ai_altruism": 8.0, "ai_self_buff": 0.15, "ai_offer_drive": 8.0, "magnetism": 85.0,
		"ai_mercy": 25.0, "ai_vigilance": 2.5, "ai_favoritism": 2.0, "ai_thirst": 6.0}},
	"warden": {"label": "Warden", "preset": {
		"ai_intent_buff": 0.55, "ai_intent_defense": 0.35, "ai_intent_offense": 0.10, "ai_intent_debuff": 0.05,
		"ai_mercy": 6.0, "ai_vigilance": 8.0, "ai_favoritism": 3.0, "ai_triage": 2.5, "ai_thirst": 5.0}},
	"zealot": {"label": "Zealot", "preset": {
		"ai_intent_buff": 0.60, "ai_intent_offense": 0.30, "ai_intent_defense": 0.15, "ai_intent_debuff": 0.05,
		"ai_mercy": 3.0, "ai_favoritism": 6.0, "ai_vigilance": 3.0, "ai_triage": 2.0, "ai_thirst": 5.0}},
	"martyr": {"label": "Martyr", "preset": {
		"ai_intent_buff": 0.65, "ai_intent_defense": 0.10, "ai_intent_offense": 0.20, "ai_intent_debuff": 0.05,
		"ai_mercy": 20.0, "ai_altruism": 8.0, "ai_self_buff": 0.0,
		"ai_triage": 5.0, "ai_vigilance": 3.0, "ai_favoritism": 2.0}},
	"cleanser": {"label": "Cleanser", "preset": {
		"ai_intent_buff": 0.60, "ai_intent_defense": 0.25, "ai_intent_offense": 0.10, "ai_intent_debuff": 0.05,
		"ai_mercy": 5.0, "ai_triage": 20.0, "ai_vigilance": 2.5, "ai_favoritism": 2.0}},
	"summoner": {"label": "Summoner", "preset": {
		"ai_intent_buff": 0.60, "ai_intent_offense": 0.30, "ai_intent_defense": 0.10, "ai_intent_debuff": 0.0,
		"ai_retinue": 4.0, "ai_focus": 1.5, "ai_retinue_drive": 12.0,
		"ai_mercy": 4.0, "ai_vigilance": 3.0, "ai_panic": 8.0, "ai_efficiency": 2.0}},

	# --- defensive family --------------------------------------------------------
	"turtle": {"label": "Turtle", "preset": {
		"ai_intent_defense": 0.60, "ai_intent_offense": 0.35, "ai_intent_buff": 0.05, "ai_intent_debuff": 0.10,
		"ai_defense_sat": 0.10, "magnetism": 150.0, "ai_panic": 20.0,
		"ai_efficiency": 2.0, "ai_grudge": 2.0, "ai_thirst": 5.0}},
	"bulwark": {"label": "Bulwark", "preset": {
		"ai_intent_defense": 0.40, "ai_intent_buff": 0.30, "ai_intent_offense": 0.30, "ai_intent_debuff": 0.05,
		"ai_panic": 8.0, "magnetism": 180.0,
		"ai_vigilance": 4.0, "ai_efficiency": 1.8, "ai_grudge": 1.8}},
	"stalwart": {"label": "Stalwart", "preset": {
		"ai_intent_offense": 0.70, "ai_intent_defense": 0.20, "ai_intent_buff": 0.05, "ai_intent_debuff": 0.10,
		"ai_opportunism": 10.0, "ai_panic": 1.5,
		"ai_efficiency": 2.0, "ai_pressure": 1.8, "ai_grudge": 1.5}},

	# --- allies (§14.1) ------------------------------------------------------------
	"ally_attack": {"label": "Aggressive", "preset": {
		"ai_intent_offense": 1.0, "ai_intent_defense": 0.0, "ai_intent_buff": 0.0, "ai_intent_debuff": 0.0}},
	"ally_defense": {"label": "Protective", "preset": {
		"ai_intent_defense": 0.60, "ai_intent_buff": 0.30, "ai_intent_offense": 0.20, "ai_intent_debuff": 0.05,
		"ai_vigilance": 6.0, "ai_panic": 8.0}},
	"ally_neutral": {"label": "Balanced", "preset": {
		"ai_intent_offense": 0.50, "ai_intent_defense": 0.20, "ai_intent_buff": 0.25, "ai_intent_debuff": 0.20,
		"ai_self_buff": 0.40}},
	"ally_heal": {"label": "Healer only", "preset": {
		"ai_intent_buff": 1.0, "ai_intent_offense": 0.0, "ai_intent_defense": 0.05, "ai_intent_debuff": 0.0}},
	"ally_support": {"label": "Support", "preset": {
		"ai_intent_buff": 0.60, "ai_intent_debuff": 0.35, "ai_intent_offense": 0.20, "ai_intent_defense": 0.15,
		"ai_offer_drive": 8.0}},
}

## Archetypes whose id we already warned about this session.
static var _warned: Dictionary = {}

static func has(ai_id: String) -> bool:
	return RULES.has(ai_id)

static func rule(ai_id: String) -> Dictionary:
	if RULES.has(ai_id):
		return RULES[ai_id]
	if ai_id != "" and ai_id != "none" and ai_id != "player" and not _warned.has(ai_id):
		_warned[ai_id] = true
		push_warning("[ai] unknown archetype '%s' — using 'standard'. Add it to AIRules.RULES." % ai_id)
	return RULES["standard"]

static func preset(ai_id: String) -> Dictionary:
	return rule(ai_id).get("preset", {})

static func label(ai_id: String) -> String:
	return str(rule(ai_id).get("label", ai_id))

## The target-layer wiring for one intent.
static func target_gains(ai_id: String, intent: String) -> Array:
	var tg = rule(ai_id).get("target_gains", {})
	if typeof(tg) == TYPE_DICTIONARY and (tg as Dictionary).has(intent):
		return tg[intent]
	return STANDARD_WIRING.get(intent, [])

## THE STAT READ every AI layer uses: the body's EFFECTIVE value of `key`, with the
## archetype preset standing in for the BASE wherever the module / spec left the base
## at its default. Buffs still apply on top: (base + flat) * (1 + mult).
static func stat(body: CharacterBase, ai_id: String, key: String) -> float:
	if body == null:
		return float(Stats.AI_DEFAULTS.get(key, 0.0))
	var base := body.get_base(key)
	var p: Dictionary = preset(ai_id)
	if p.has(key):
		var def: float = float(Stats.AI_DEFAULTS.get(key, Stats.MAJOR_DEFAULTS.get(key, base)))
		if not body.base_stats.has(key) or is_equal_approx(base, def):
			base = float(p[key])
	return (base + body.get_bonus(key)) * (1.0 + body.get_mult_bonus(key))

## DEBUG: warn once per unit about a GAIN stat sitting at exactly 0 (AI_PRIMER §4.4).
static func validate(body: CharacterBase, ai_id: String, unit_name: String) -> void:
	for key in Stats.AI_DEFAULTS:
		if str(key).begins_with("ai_intent_") or key == "ai_smart" or key == "ai_retinue" \
		or key == "ai_decisiveness" or key == "ai_focus" or key == "ai_self_buff" \
		or key == "ai_memory_from" or key == "ai_memory_span":
			continue
		if is_zero_approx(stat(body, ai_id, key)):
			push_warning("[ai] %s: gain '%s' is 0.0 — gains are neutral at 1.0, and 0 clamps to a 50x REPULSION." % [unit_name, key])
