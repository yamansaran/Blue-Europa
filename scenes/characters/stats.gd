extends RefCounted
class_name Stats

## ============================================================================
## STATS  —  the canonical stat vocabulary for every character
## ============================================================================
## Pure data + helpers. No state lives here; it just defines what stats exist,
## their base defaults, the element list, and the deterministic name->colour
## hash. CharacterBase builds its base_stats from here, and combat/UI read the
## key names from here so nothing hard-codes stat strings in five places.
## ----------------------------------------------------------------------------

# --- categories -------------------------------------------------------------
enum CharType { CHARACTER, ALLY, ENEMY }
enum Race { HUMAN }
## Damage / defence elements. Order matters: the 8 real elements first, then the
## hidden TRUE element (ignores all pierce/defence/amp). element_key() maps these
## to the string prefixes used in the stat dictionary.
enum Element { PHYSICAL, SPIRITUAL, ICE, FIRE, LIGHTNING, BLOOD, TOXIC, MENTAL, TRUE }

# --- major stats ------------------------------------------------------------
## The seven visible majors + hidden luck + hidden magnetism. spirit doubles as
## the resource-bar max.
const MAJOR_DEFAULTS := {
	"vigor": 10.0,
	"vitality": 10.0,
	"instinct": 10.0,
	"alacrity": 10.0,
	"magnificence": 10.0,
	"disdain": 10.0,
	"spirit": 100.0,   # resource-bar maximum
	"luck": 7.0,       # hidden
	"magnetism": 100.0, # hidden — reserved for future targeting + character UI
}
## Stats the player never sees a raw number for (still fully functional). Because
## magnetism is hidden it is also excluded from attribute allocation (which draws
## from allocatable_major_keys(), i.e. visible & allocatable only).
const HIDDEN_MAJORS := ["luck", "magnetism"]
## Majors that exist and buff normally, but CANNOT take attribute points. Spirit
## is the resource-bar maximum and is grown by other means, never by points.
const NON_ALLOCATABLE_MAJORS := ["spirit"]

# --- minor stats (per element) ----------------------------------------------
const REAL_ELEMENTS := ["physical", "spiritual", "ice", "fire", "lightning", "blood", "toxic", "mental"]
const HIDDEN_ELEMENTS := ["true"]   # ignores pierce/defence/amp entirely
const PIERCE_DEFAULT := 15.0
const DEFENSE_DEFAULT := 45.0
const AMP_DEFAULT := 0.0

# --- element colours --------------------------------------------------------
## The per-element display palette now lives in its OWN file — element_colors.gd
## (class_name ElementColors) — so the colours are defined in exactly one place
## and every system (the damage numbers, the minor-attribute bars, anything
## future) reads them from there. This wrapper is kept only so existing callers
## of Stats.element_color() keep working; new code should call
## ElementColors.color(element) directly.
static func element_color(element: String) -> Color:
	return ElementColors.color(element)

# --- derived-HP tuning ------------------------------------------------------
const HP_BASE_DEFAULT := 100.0      # flat floor, buffable like any stat
const HP_PER_VITALITY := 10.0       # max_hp = hp_base + vitality * HP_PER_VITALITY

# --- crit tuning ------------------------------------------------------------
## Every character's base critical-damage multiplier. Read from the body's
## base_stats by CombatCrit; a character/enemy spec can override it via
## stats:{"crit_damage_mult": ...}. The ability's crit_damage_mult and any
## buff/debuff crit-damage bonus multiply on top of this.
const CRIT_DAMAGE_BASE_DEFAULT := 3.0

# --- mitigation tuning ------------------------------------------------------
## Per-character mitigation STIFFNESS (the `m` in the mitigation curve). It scales
## the (resistance - pierce) gap fed into the squash, so a SMALL value makes the
## curve gentle — the first points of net pierce/resist aren't oppressively strong
## and later points keep mattering (the curve saturates slowly). Read from the
## body's base_stats by CombatMitigation; overridable per character via
## stats:{"mitigation_stiffness": ...}.
const MITIGATION_STIFFNESS_DEFAULT := 0.025

# --- spirit regen tuning ----------------------------------------------------
## Spirit every character restores at the START of each of its turns, by default.
## It is a real base stat ("spirit_regen"), so it is per-character OVERRIDABLE via
## a spec (stats:{"spirit_regen": ...}) and BUFFABLE like anything else. Combat
## adds this to the per-turn spirit change from any spirit-regen/-drain buffs.
const SPIRIT_REGEN_DEFAULT := 15.0

# --- action points tuning ---------------------------------------------------
## The per-turn action-point BUDGET every character starts each of its turns with.
## It is a real (hidden) base stat ("action_points"), so it is per-character
## OVERRIDABLE via a spec (stats:{"action_points": ...}) and BUFFABLE like anything
## else. Combat refills a unit to this value at the start of its turn and spends
## each ability's action_cost from it; when it hits 0 the turn ends. It is NOT a
## major, so it never shows in the attribute screen or the debug stat panel.
const ACTION_POINTS_DEFAULT := 1.0

# --- vulnerability tuning ---------------------------------------------------
## A hidden per-character MULTIPLIER on the damage-over-time (DoT) this character
## TAKES from debuffs (bleed / poison / drain, etc.). Default 1.0 = no change; 1.5
## = takes 50% more DoT; 0.5 = takes half. It is a real base stat ("vulnerability")
## so it is per-character OVERRIDABLE via a spec (stats:{"vulnerability": ...}) and
## BUFFABLE like anything else (a debuff can raise it, a buff can lower it). Applied
## by CombatBuffs when a DoT entry computes its damage for the bearer, BEFORE that
## damage is dealt (see CombatBuffs.collect_turn_start). It is NOT a major, so —
## exactly like spirit_regen / action_points — it never shows in the attribute
## screen. (The debug stat panel adds a field for it so it can be tested.)
const VULNERABILITY_DEFAULT := 1.0

# --- heal / shield power tuning ---------------------------------------------
## Two hidden per-character stats measured in PERCENT. `heal_power` increases ALL
## healing this character is involved in, and `shield_power` increases ALL absorbing
## shields this character is involved in — on BOTH sides of the event: the amount a
## character DEALS is scaled by (1 + its stat/100) at cast time, and the amount a
## character RECEIVES is scaled by (1 + its stat/100) when it lands. So a heal cast by
## A on B is scaled by A's heal_power (dealt) and B's heal_power (received); a self-heal
## therefore benefits from both. Default 0.0 = no change. Both are real base stats
## ("heal_power" / "shield_power") so they are per-character OVERRIDABLE via a spec
## (stats:{"heal_power": ...}) and BUFFABLE / boostable by passives (Mercy) like anything
## else. Neither is a major, so — like vulnerability / action_points — they never show in
## the attribute screen. The dealt side is applied in combat.gd's HEAL/SHIELD branches;
## the received side in battle_character.heal() / gain_shield().
const HEAL_POWER_DEFAULT := 0.0
const SHIELD_POWER_DEFAULT := 0.0

# ----------------------------------------------------------------------------
## A fresh copy of the full base-stat dictionary (majors + hp_base + every
## element's pierce/defence/amp). Always returns a NEW dict so callers can mutate
## it freely without touching the shared defaults.
static func default_base_stats() -> Dictionary:
	var d := {}
	for k in MAJOR_DEFAULTS:
		d[k] = float(MAJOR_DEFAULTS[k])
	d["hp_base"] = HP_BASE_DEFAULT
	d["crit_damage_mult"] = CRIT_DAMAGE_BASE_DEFAULT
	d["mitigation_stiffness"] = MITIGATION_STIFFNESS_DEFAULT
	d["spirit_regen"] = SPIRIT_REGEN_DEFAULT
	d["action_points"] = ACTION_POINTS_DEFAULT
	d["vulnerability"] = VULNERABILITY_DEFAULT
	d["heal_power"] = HEAL_POWER_DEFAULT
	d["shield_power"] = SHIELD_POWER_DEFAULT
	for e in REAL_ELEMENTS:
		d[e + "_pierce"] = PIERCE_DEFAULT
		d[e + "_defense"] = DEFENSE_DEFAULT
		d[e + "_amp"] = AMP_DEFAULT
	for e in HIDDEN_ELEMENTS:
		d[e + "_pierce"] = 0.0
		d[e + "_defense"] = 0.0
		d[e + "_amp"] = 0.0
	return d

static func major_keys() -> Array:
	return MAJOR_DEFAULTS.keys()

static func visible_major_keys() -> Array:
	var out := []
	for k in MAJOR_DEFAULTS:
		if not HIDDEN_MAJORS.has(k):
			out.append(k)
	return out

## Visible majors that may actually receive attribute points (spirit excluded).
static func allocatable_major_keys() -> Array:
	var out := []
	for k in visible_major_keys():
		if not NON_ALLOCATABLE_MAJORS.has(k):
			out.append(k)
	return out

## Every element string, real ones then hidden "true".
static func element_keys() -> Array:
	return REAL_ELEMENTS + HIDDEN_ELEMENTS

## Element enum -> string prefix ("fire", "true", ...).
static func element_key(e: int) -> String:
	var all := element_keys()
	if e >= 0 and e < all.size():
		return str(all[e])
	return "physical"

static func pierce_key(element: String) -> String:
	return element + "_pierce"

static func defense_key(element: String) -> String:
	return element + "_defense"

static func amp_key(element: String) -> String:
	return element + "_amp"

# ----------------------------------------------------------------------------
## Deterministic name -> colour, used for the placeholder character model until
## a real sprite/rig is assigned. Same hash the dev specified.
static func name_to_color(name: String) -> Color:
	var h: int = name.hash()
	var r: float = float((h >> 16) & 0xFF) / 255.0
	var g: float = float((h >> 8) & 0xFF) / 255.0
	var b: float = float(h & 0xFF) / 255.0
	return Color(r, g, b)
