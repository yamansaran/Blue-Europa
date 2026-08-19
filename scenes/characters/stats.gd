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
## The seven visible majors + hidden luck. spirit doubles as the resource-bar max.
const MAJOR_DEFAULTS := {
	"vigor": 10.0,
	"vitality": 10.0,
	"instinct": 10.0,
	"alacrity": 10.0,
	"magnificence": 10.0,
	"disdain": 10.0,
	"spirit": 100.0,   # resource-bar maximum
	"luck": 7.0,       # hidden
}
## Stats the player never sees a raw number for (still fully functional).
const HIDDEN_MAJORS := ["luck"]
## Majors that exist and buff normally, but CANNOT take attribute points. Spirit
## is the resource-bar maximum and is grown by other means, never by points.
const NON_ALLOCATABLE_MAJORS := ["spirit"]

# --- minor stats (per element) ----------------------------------------------
const REAL_ELEMENTS := ["physical", "spiritual", "ice", "fire", "lightning", "blood", "toxic", "mental"]
const HIDDEN_ELEMENTS := ["true"]   # ignores pierce/defence/amp entirely
const PIERCE_DEFAULT := 15.0
const DEFENSE_DEFAULT := 45.0
const AMP_DEFAULT := 0.0

# --- derived-HP tuning ------------------------------------------------------
const HP_BASE_DEFAULT := 100.0      # flat floor, buffable like any stat
const HP_PER_VITALITY := 10.0       # max_hp = hp_base + vitality * HP_PER_VITALITY

# ----------------------------------------------------------------------------
## A fresh copy of the full base-stat dictionary (majors + hp_base + every
## element's pierce/defence/amp). Always returns a NEW dict so callers can mutate
## it freely without touching the shared defaults.
static func default_base_stats() -> Dictionary:
	var d := {}
	for k in MAJOR_DEFAULTS:
		d[k] = float(MAJOR_DEFAULTS[k])
	d["hp_base"] = HP_BASE_DEFAULT
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
