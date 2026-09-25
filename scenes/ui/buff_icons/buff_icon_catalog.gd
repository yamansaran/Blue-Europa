extends RefCounted
class_name BuffIconCatalog

## ============================================================================
## BUFF ICON CATALOG  —  WHAT each buff/debuff icon shows (colour + rune)
## ============================================================================
## Part of the BUFF ICON ENGINE (scenes/ui/buff_icons/). One line per effect: the
## colour the icon is graded from and the rune drawn inside it. HOW that is drawn
## (shape, shading, border, stroke) is BuffIconStyle's job, not this file's.
##
## KEYED BY THE BUFF ENTRY'S `id` — the family id, so guard_1..guard_4 all read
## "guard". An id with a trailing _N that is not listed falls back to its family.
##
## FIELDS (both optional):
##   "color": Color   — omitted -> the entry's element colour -> green buff / red debuff
##   "rune":  String  — a RuneGlyphs name; omitted -> ELEMENT_RUNES -> KIND_RUNES
##
## Two effects the player must tell apart should differ in AT LEAST one of the two.
## ----------------------------------------------------------------------------

const ICE := Color(0.56, 0.80, 0.97)          # ElementColors' ice is white; icons need a hue
const LIGHTNING := Color(0.95, 0.80, 0.16)
const SPIRIT := Color(0.25, 0.70, 0.86)
const TOXIC := Color(0.36, 0.70, 0.26)
const MENTAL := Color(0.58, 0.32, 0.82)
const BLOOD := Color(0.62, 0.08, 0.12)

const ENTRIES := {
	# --- defensive / resist -------------------------------------------------
	"resist_up_100":      {"color": Color(0.36, 0.52, 0.78), "rune": "algiz"},
	"guard":              {"color": Color(0.72, 0.56, 0.30), "rune": "algiz"},
	"frost_ward":         {"color": ICE,                     "rune": "ward"},
	"crystaline":         {"color": Color(0.70, 0.88, 0.98), "rune": "ingwaz"},
	"scaled_skin":        {"color": Color(0.22, 0.62, 0.58), "rune": "eihwaz"},
	"wraith_form":        {"color": Color(0.62, 0.74, 0.82), "rune": "eihwaz"},
	"lightning_shell":    {"color": LIGHTNING,               "rune": "ward"},
	# --- reflect / on-struck -----------------------------------------------
	"thorns":             {"color": Color(0.46, 0.56, 0.24), "rune": "thurisaz"},
	"thorns_permanent":   {"color": Color(0.38, 0.46, 0.20), "rune": "thurisaz"},
	"frost_mantle":       {"color": ICE,                     "rune": "thurisaz"},
	"high_voltage":       {"color": LIGHTNING,               "rune": "tiwaz"},
	# --- regeneration -------------------------------------------------------
	"spirit_regen_25":    {"color": SPIRIT,                  "rune": "ansuz"},
	"hematopoiesis":      {"color": BLOOD,                   "rune": "berkano"},
	"gliogenesis":        {"color": Color(0.30, 0.66, 0.40), "rune": "berkano"},
	"rejuvenating_salve": {"color": Color(0.46, 0.72, 0.36), "rune": "wunjo"},
	"sclerosis":          {"color": Color(0.16, 0.16, 0.20), "rune": "naudiz"},
	# --- offence / tempo ----------------------------------------------------
	"electromyogenesis":  {"color": LIGHTNING,               "rune": "sowilo"},
	"electrostimulated":  {"color": Color(0.86, 0.66, 0.10), "rune": "raidho"},
	"energized_form":     {"color": Color(1.00, 0.86, 0.30), "rune": "bolt"},
	"pass_current":       {"color": LIGHTNING,               "rune": "ehwaz"},
	"frenzied":           {"color": Color(0.80, 0.22, 0.18), "rune": "uruz"},
	"dark_blessing":      {"color": Color(0.36, 0.20, 0.44), "rune": "othala"},
	"gorged":             {"color": BLOOD,                   "rune": "fehu"},
	# --- debuffs --------------------------------------------------------------
	"resist_down_drain":  {"color": Color(0.46, 0.38, 0.56), "rune": "hagalaz"},
	"stunned":            {"color": Color(0.90, 0.72, 0.20), "rune": "naudiz"},
	"silenced":           {"color": MENTAL,                  "rune": "perthro"},
	"terrified":          {"color": Color(0.42, 0.22, 0.52), "rune": "mannaz"},
	"hypothermia":        {"color": ICE,                     "rune": "isa"},
	"frost":              {"color": ICE,                     "rune": "hagalaz"},
	"frostnip":           {"color": Color(0.66, 0.84, 0.96), "rune": "isa"},
	"hoarfrost":          {"color": Color(0.78, 0.90, 1.00), "rune": "gebo"},
	"rime_skin":          {"color": Color(0.48, 0.70, 0.86), "rune": "laguz"},
	"arc_burn":           {"color": Color(0.96, 0.70, 0.12), "rune": "kenaz"},
	# --- unified DoTs / toxic (FUTURE_PLANS §2d) ------------------------------
	"poison":             {"color": TOXIC,                   "rune": "drop"},
	"wormwood":           {"color": Color(0.66, 0.72, 0.20), "rune": "hagalaz"},   # a resist shred, like resist_down_drain
	# --- Nephilic (FUTURE_PLANS §9) -------------------------------------------
	"stand_firm":         {"color": Color(0.55, 0.60, 0.68), "rune": "algiz"},
	"stand_firm_lead":    {"color": Color(0.55, 0.60, 0.68), "rune": "tiwaz"},
	"tithe":              {"color": Color(0.85, 0.68, 0.25), "rune": "fehu"},
	"inhale":             {"color": Color(0.70, 0.88, 0.95), "rune": "kenaz"},
	"waxing_moon":        {"color": Color(0.78, 0.76, 0.92), "rune": "jera"},
	"silver_mirror":      {"color": Color(0.82, 0.84, 0.90), "rune": "dagaz"},
	"epiphany":           {"color": Color(1.00, 0.95, 0.70), "rune": "ansuz"},
	"intercede":          {"color": Color(0.30, 0.30, 0.38), "rune": "ward"},
	"putrefaction":       {"color": Color(0.42, 0.36, 0.20), "rune": "uruz"},
	"putrefaction_cost":  {"color": Color(0.30, 0.24, 0.14), "rune": "naudiz"},
	"first_sun":          {"color": Color(0.20, 0.14, 0.10), "rune": "sowilo"},   # the black sun
	"apotheosis":         {"color": Color(1.00, 0.85, 0.45), "rune": "ingwaz"},
	"grit_ward":          {"color": Color(0.60, 0.48, 0.34), "rune": "ward"},
	"rejuvenation":       {"color": Color(0.36, 0.74, 0.46), "rune": "jera"},
	"ablution_ward":      {"color": Color(0.40, 0.70, 0.90), "rune": "laguz"},
}

## Rune used when an entry is not in ENTRIES but carries an element tag.
const ELEMENT_RUNES := {
	"physical": "uruz", "spiritual": "ansuz", "ice": "isa", "fire": "kenaz",
	"lightning": "bolt", "blood": "drop", "toxic": "hagalaz", "mental": "perthro",
	"true": "dagaz",
}

## Last resort, by buff/debuff kind.
const KIND_RUNES := {"buff": "tiwaz", "debuff": "naudiz"}
const BUFF_COLOR := Color(0.28, 0.66, 0.34)
const DEBUFF_COLOR := Color(0.74, 0.26, 0.28)

# ----------------------------------------------------------------------------
## { "color": Color, "rune": String } for a buff entry dictionary (or a bare id).
static func look(entry) -> Dictionary:
	var id := ""
	var element := ""
	var is_debuff := false
	if typeof(entry) == TYPE_DICTIONARY:
		id = str(entry.get("id", ""))
		element = str(entry.get("element", ""))
		is_debuff = str(entry.get("kind", "buff")) == "debuff"
	else:
		id = str(entry)
	var row: Dictionary = _row_for(id)
	var col = row.get("color", null)
	if not (col is Color):
		if element != "":
			col = ICE if element == "ice" else ElementColors.color(element)
		else:
			col = DEBUFF_COLOR if is_debuff else BUFF_COLOR
	var rune := str(row.get("rune", ""))
	if rune == "":
		rune = str(ELEMENT_RUNES.get(element, KIND_RUNES["debuff" if is_debuff else "buff"]))
	return {"color": col, "rune": rune}

static func _row_for(id: String) -> Dictionary:
	if ENTRIES.has(id):
		return ENTRIES[id]
	# guard_3 -> guard
	var cut := id.rfind("_")
	if cut > 0 and id.substr(cut + 1).is_valid_int():
		var fam := id.substr(0, cut)
		if ENTRIES.has(fam):
			return ENTRIES[fam]
	return {}
