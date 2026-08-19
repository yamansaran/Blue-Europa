extends Resource
class_name CharacterBase

## ============================================================================
## CHARACTER BASE  —  the shared root of every combatant
## ============================================================================
## Player, ally, and enemy are all built from this. It holds:
##   - identity (name, level, type, race, organic/incorporeal, portrait)
##   - BASE stats (never mutated after setup)
##   - BASKETS of bonus entries (items / levels / attributes / buffs / debuffs)
##   - runtime vitals (current_hp, current_spirit)
##
## THE STAT MODEL
## --------------
## base_stats holds the untouched base numbers. Every bonus lives in a basket as
## an individual, labelled entry. An effective stat is:
##       base + sum of every matching mod across every basket entry.
## "Everything is a hidden buff": equipping an item adds an entry to the items
## basket, gaining a level adds one to the levels basket, spending an attribute
## point adds one to the attributes basket, and combat buffs/debuffs add to
## theirs. Removing the source removes its entry; the base never changes, so a
## respec / unequip / buff-expiry is just "drop that entry".
##
## An entry is a plain Dictionary (JSON-friendly for saving):
##       { "id": String, "source": String, "mods": { stat_key: float, ... } }
## Use CharacterBase.make_entry(...) to build one.
## ----------------------------------------------------------------------------

# --- identity ---------------------------------------------------------------
@export var char_name: String = "Character"
@export var level: int = 1
@export var char_type: int = Stats.CharType.CHARACTER
@export var race: int = Stats.Race.HUMAN
@export var organic: bool = true
@export var incorporeal: bool = false
## Blank until a real asset is assigned; the model falls back to a name-hash rect.
@export var portrait: Texture2D = null

# --- stats ------------------------------------------------------------------
## Untouched base numbers. Defaults come from Stats.default_base_stats().
var base_stats: Dictionary = Stats.default_base_stats()

## Bonus baskets. Each value is an Array of entry Dictionaries (see header).
var baskets: Dictionary = {
	"items": [],
	"levels": [],
	"attributes": [],
	"buffs": [],
	"debuffs": [],
}

# --- runtime vitals ---------------------------------------------------------
var current_hp: int = 0
var current_spirit: int = 0

## Optional explicit model colour; when null the name-hash colour is used.
var color_override = null

# ============================================================================
# Stat resolution
# ============================================================================
func get_base(stat: String) -> float:
	return float(base_stats.get(stat, 0.0))

## Sum of every mod for `stat` across every basket entry.
func get_bonus(stat: String) -> float:
	var total := 0.0
	for basket_name in baskets:
		for entry in baskets[basket_name]:
			var mods = entry.get("mods", {})
			if typeof(mods) == TYPE_DICTIONARY and mods.has(stat):
				total += float(mods[stat])
	return total

## Bonus contributed by a single basket (e.g. just "items").
func get_basket_bonus(basket_name: String, stat: String) -> float:
	var total := 0.0
	if not baskets.has(basket_name):
		return total
	for entry in baskets[basket_name]:
		var mods = entry.get("mods", {})
		if typeof(mods) == TYPE_DICTIONARY and mods.has(stat):
			total += float(mods[stat])
	return total

func get_effective(stat: String) -> float:
	return get_base(stat) + get_bonus(stat)

func get_effective_int(stat: String) -> int:
	return int(round(get_effective(stat)))

## Flat stat snapshot (base+bonus) for systems that still want a plain Dictionary
## (e.g. the current Ability.compute_damage(caster_stats)).
func effective_stats() -> Dictionary:
	var out := {}
	for stat in base_stats:
		out[stat] = get_effective(stat)
	return out

# ============================================================================
# Derived vitals
# ============================================================================
func max_hp() -> int:
	return int(round(get_effective("hp_base") + get_effective("vitality") * Stats.HP_PER_VITALITY))

func max_spirit() -> int:
	return int(round(get_effective("spirit")))

## Snap current vitals to full. Call after building/leveling/equipping.
func init_vitals() -> void:
	current_hp = max_hp()
	current_spirit = max_spirit()

## Re-clamp current vitals into range after a max change (keeps ratios sane).
func clamp_vitals() -> void:
	current_hp = clampi(current_hp, 0, max_hp())
	current_spirit = clampi(current_spirit, 0, max_spirit())

# ============================================================================
# Basket API  —  "everything is a hidden buff"
# ============================================================================
static func make_entry(id: String, source: String, mods: Dictionary) -> Dictionary:
	return {"id": id, "source": source, "mods": mods}

func add_entry(basket_name: String, entry: Dictionary) -> void:
	if not baskets.has(basket_name):
		baskets[basket_name] = []
	baskets[basket_name].append(entry)

## Remove every entry in `basket_name` whose id matches (an item/buff can only be
## in a basket once by id; this drops it cleanly).
func remove_entry(basket_name: String, id: String) -> void:
	if not baskets.has(basket_name):
		return
	var kept := []
	for e in baskets[basket_name]:
		if str(e.get("id", "")) != id:
			kept.append(e)
	baskets[basket_name] = kept

func has_entry(basket_name: String, id: String) -> bool:
	if not baskets.has(basket_name):
		return false
	for e in baskets[basket_name]:
		if str(e.get("id", "")) == id:
			return true
	return false

func clear_basket(basket_name: String) -> void:
	baskets[basket_name] = []

func set_basket(basket_name: String, entries: Array) -> void:
	baskets[basket_name] = entries

# ============================================================================
# Presentation
# ============================================================================
## Placeholder model colour: explicit override if set, else the name-hash colour.
func model_color() -> Color:
	if color_override is Color:
		return color_override
	return Stats.name_to_color(char_name)

## A deep, independent copy (identity + base_stats + every basket). Combat clones
## the player/enemy bodies so battle HP/Spirit changes never touch the saved
## originals. (Resource.duplicate() would miss these non-@export fields.)
func clone() -> CharacterBase:
	var cb := CharacterBase.new()
	cb.char_name = char_name
	cb.level = level
	cb.char_type = char_type
	cb.race = race
	cb.organic = organic
	cb.incorporeal = incorporeal
	cb.portrait = portrait
	cb.color_override = color_override
	cb.base_stats = base_stats.duplicate(true)
	cb.baskets = baskets.duplicate(true)
	cb.init_vitals()
	return cb

# ============================================================================
# Factory  —  build a CharacterBase from a plain spec Dictionary
# ============================================================================
## Spec keys (all optional): name, level, type ("character"/"ally"/"enemy" or int),
## race, organic, incorporeal, color, stats{stat_key: value overrides onto base}.
## Legacy bridges: "max_hp" sets hp_base so the derived HP matches; "focus" maps
## onto spirit. This keeps the old dict-based enemy defs working while everything
## migrates onto the base + vitality model.
static func from_spec(spec: Dictionary) -> CharacterBase:
	var cb := CharacterBase.new()
	cb.char_name = str(spec.get("name", "Character"))
	cb.level = int(spec.get("level", 1))
	cb.char_type = _parse_type(spec.get("type", Stats.CharType.CHARACTER))
	cb.race = int(spec.get("race", Stats.Race.HUMAN))
	cb.organic = bool(spec.get("organic", true))
	cb.incorporeal = bool(spec.get("incorporeal", false))
	cb.base_stats = Stats.default_base_stats()

	var overrides = spec.get("stats", {})
	if typeof(overrides) == TYPE_DICTIONARY:
		for k in overrides:
			cb.base_stats[str(k)] = float(overrides[k])

	# legacy bridges -----------------------------------------------------
	if spec.has("focus"):
		cb.base_stats["spirit"] = float(spec["focus"])
	if spec.has("max_hp"):
		# back-solve hp_base so max_hp() reproduces the requested value
		cb.base_stats["hp_base"] = float(spec["max_hp"]) - cb.get_effective("vitality") * Stats.HP_PER_VITALITY

	if spec.has("color") and spec["color"] is Color:
		cb.color_override = spec["color"]

	cb.init_vitals()
	if spec.has("current_hp"):
		cb.current_hp = clampi(int(spec["current_hp"]), 0, cb.max_hp())
	return cb

static func _parse_type(v) -> int:
	if typeof(v) == TYPE_INT:
		return v
	match str(v).to_lower():
		"ally": return Stats.CharType.ALLY
		"enemy": return Stats.CharType.ENEMY
		_: return Stats.CharType.CHARACTER

# ============================================================================
# Save / load  (JSON-friendly; portrait is not serialized as a texture)
# ============================================================================
func to_dict() -> Dictionary:
	return {
		"char_name": char_name,
		"level": level,
		"char_type": char_type,
		"race": race,
		"organic": organic,
		"incorporeal": incorporeal,
		"base_stats": base_stats,
		"baskets": baskets,
	}

func from_dict(d: Dictionary) -> void:
	char_name = str(d.get("char_name", char_name))
	level = int(d.get("level", level))
	char_type = int(d.get("char_type", char_type))
	race = int(d.get("race", race))
	organic = bool(d.get("organic", organic))
	incorporeal = bool(d.get("incorporeal", incorporeal))

	var bs = d.get("base_stats", null)
	if typeof(bs) == TYPE_DICTIONARY:
		base_stats = Stats.default_base_stats()
		for k in bs:
			base_stats[str(k)] = float(bs[k])

	var bk = d.get("baskets", null)
	baskets = {"items": [], "levels": [], "attributes": [], "buffs": [], "debuffs": []}
	if typeof(bk) == TYPE_DICTIONARY:
		for name in bk:
			if typeof(bk[name]) == TYPE_ARRAY:
				baskets[str(name)] = bk[name]
	init_vitals()

# ============================================================================
# Debug — call `print(CharacterBase.debug_demo())` from any _ready() to verify.
# ============================================================================
static func debug_demo() -> String:
	var cb := CharacterBase.new()
	cb.char_name = "Sonny"
	cb.init_vitals()
	var lines := []
	lines.append("=== CharacterBase demo: %s ===" % cb.char_name)
	lines.append("BASE  vig=%d vit=%d spirit=%d luck=%d  max_hp=%d max_spirit=%d" % [
		int(cb.get_base("vigor")), int(cb.get_base("vitality")),
		int(cb.get_base("spirit")), int(cb.get_base("luck")),
		cb.max_hp(), cb.max_spirit()])
	lines.append("minor(fire): pierce=%d defense=%d amp=%d | true: %d/%d/%d" % [
		int(cb.get_effective("fire_pierce")), int(cb.get_effective("fire_defense")),
		int(cb.get_effective("fire_amp")),
		int(cb.get_effective("true_pierce")), int(cb.get_effective("true_defense")),
		int(cb.get_effective("true_amp"))])
	# equip an item and gain a level, both as hidden baskets
	cb.add_entry("items", make_entry("iron_sword", "Iron Sword", {"vigor": 5.0, "fire_amp": 20.0}))
	cb.add_entry("levels", make_entry("lvl_2", "Level 2", {"vigor": 1.0, "vitality": 2.0}))
	cb.init_vitals()
	lines.append("AFTER Iron Sword + Level 2:")
	lines.append("  vig  base=%d + bonus=%d = eff=%d" % [
		int(cb.get_base("vigor")), int(cb.get_bonus("vigor")), int(cb.get_effective("vigor"))])
	lines.append("  vit  eff=%d -> max_hp=%d ; fire_amp eff=%d" % [
		int(cb.get_effective("vitality")), cb.max_hp(), int(cb.get_effective("fire_amp"))])
	lines.append("  model colour = %s" % str(cb.model_color()))
	return "\n".join(lines)
