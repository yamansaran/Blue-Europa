class_name Item
extends Resource

## ============================================================================
## ITEM  —  data template for one item (class_name global)
## ============================================================================
## One .tres per item in scenes/items/item_data/, indexed by ItemDB (autoload).
## Mirrors the Ability/AbilityDB pattern: this describes what an item IS; the
## player's held/equipped copies are lightweight dicts ({id, name, ...}) that
## resolve back to the full Item through ItemDB by `id`.
##
## Every item shares this inherited structure:
##   name, short description, square image asset, stats (if applicable),
##   class/type, model (if applicable), equippable flag, slot (if equippable),
##   rarity, and value (for buying / selling).
##
## When an equippable item is equipped its `stats` become a hidden buff entry in
## the character's "items" basket (see Character + CharacterBase). Nothing here
## mutates the character directly.
## ----------------------------------------------------------------------------

## Presentation only — colour ramps + display names live in RARITY_COLORS/NAMES.
enum Rarity { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }

## Which equip-slot family an item belongs to. NONE = not equippable.
## A family maps to one or more physical slots on the character (SLOT_TARGETS):
## WEAPON fits either weapon slot, ACCESSORY fits either accessory slot.
enum Slot { NONE, HEAD, BODY, LEGS, GLOVES, FEET, WEAPON, ACCESSORY }

# --- the nine physical equip slots on the character (order = display order) --
const SLOT_KEYS := [
	"head", "body", "legs", "gloves", "feet",
	"weapon_main", "weapon_off", "accessory_1", "accessory_2",
]
## Human label for each physical slot (empty-slot text + tooltips).
const SLOT_LABELS := {
	"head": "Headwear",
	"body": "Bodywear",
	"legs": "Leggings",
	"gloves": "Gloves",
	"feet": "Footwear",
	"weapon_main": "Primary Weapon",
	"weapon_off": "Secondary Weapon",
	"accessory_1": "Charm",       # the slot to the right of the model
	"accessory_2": "Trinket",     # the slot centred below the model
}
## Slot family (enum) -> the physical slot keys it may occupy.
const SLOT_TARGETS := {
	Slot.HEAD: ["head"],
	Slot.BODY: ["body"],
	Slot.LEGS: ["legs"],
	Slot.GLOVES: ["gloves"],
	Slot.FEET: ["feet"],
	Slot.WEAPON: ["weapon_main", "weapon_off"],
	Slot.ACCESSORY: ["accessory_1", "accessory_2"],
}
const SLOT_FAMILY_NAMES := {
	Slot.NONE: "",
	Slot.HEAD: "Head",
	Slot.BODY: "Body",
	Slot.LEGS: "Legs",
	Slot.GLOVES: "Gloves",
	Slot.FEET: "Feet",
	Slot.WEAPON: "Weapon",
	Slot.ACCESSORY: "Accessory",
}

const RARITY_NAMES := {
	Rarity.COMMON: "Common",
	Rarity.UNCOMMON: "Uncommon",
	Rarity.RARE: "Rare",
	Rarity.EPIC: "Epic",
	Rarity.LEGENDARY: "Legendary",
}
const RARITY_COLORS := {
	Rarity.COMMON: Color(0.78, 0.78, 0.80),      # off-white
	Rarity.UNCOMMON: Color(0.42, 0.82, 0.42),    # green
	Rarity.RARE: Color(0.36, 0.62, 1.0),         # blue
	Rarity.EPIC: Color(0.72, 0.44, 0.96),        # purple
	Rarity.LEGENDARY: Color(1.0, 0.68, 0.24),    # orange
}

## Fallback tint for a box whose item has no icon asset ("a pink square").
const NO_ICON_COLOR := Color(1.0, 0.31, 0.72)

# --- identity / presentation ------------------------------------------------
@export var id: StringName = &"item"
@export var display_name: String = "Item"
@export_multiline var description: String = ""
## Optional flavour text, shown in italics at the bottom of the hover card.
@export_multiline var flavor: String = ""
## Square image asset. Null -> the box/tooltip fall back to a pink square.
@export var icon: Texture2D = null

# --- classification ---------------------------------------------------------
## Free-form class/type shown on the middle tooltip panel (e.g. "Sword",
## "Helmet", "Ring", "Potion").
@export var item_type: String = "Misc"
## Item level, shown as "Lv:X" on the middle tooltip panel.
@export var level: int = 1
@export var rarity: Rarity = Rarity.COMMON

# --- equipping --------------------------------------------------------------
@export var equippable: bool = false
## Slot family this item occupies when equipped (NONE for non-equippables).
@export var slot: Slot = Slot.NONE
## Stat mods applied while equipped: { stat_key(String): amount(float) }. Keys
## come from the Stats vocabulary (e.g. "vigor", "fire_amp", "physical_defense").
@export var stats: Dictionary = {}
## Optional character-model piece shown on the rig when equipped (future art).
@export var model: PackedScene = null

# --- economy ----------------------------------------------------------------
@export var value: int = 10          # buy price
## Sell price. Leave <= 0 to derive it as half of `value`.
@export var sell_value: int = 0

# ============================================================================
# Helpers
# ============================================================================
func get_sell_value() -> int:
	return sell_value if sell_value > 0 else maxi(1, int(value / 2))

func rarity_color() -> Color:
	return RARITY_COLORS.get(rarity, RARITY_COLORS[Rarity.COMMON])

func rarity_name() -> String:
	return str(RARITY_NAMES.get(rarity, "Common"))

## Display name of the slot family ("Weapon", "Head", ...); "" if not equippable.
func slot_family_name() -> String:
	return str(SLOT_FAMILY_NAMES.get(slot, ""))

## Does this item fit the given physical slot key ("head", "weapon_off", ...)?
func fits_slot_key(slot_key: String) -> bool:
	if not equippable:
		return false
	return SLOT_TARGETS.get(slot, []).has(slot_key)

## The middle tooltip line: "Lv:5   Sword".
func type_line() -> String:
	return "Lv:%d   %s" % [level, item_type]

## A lightweight dict for the bag / equip slots (everything else re-resolves
## through ItemDB by id). A `mods` snapshot is included so equipped stats still
## apply even if ItemDB is unavailable at load time.
func to_bag() -> Dictionary:
	return {"id": String(id), "name": display_name, "mods": stats.duplicate(true)}

## Pretty "Vigor +5" / "Fire Amp -3" lines for the tooltip's stat panel.
func stat_lines() -> Array:
	var out := []
	for key in stats.keys():
		var amt := float(stats[key])
		if amt == 0.0:
			continue
		out.append("%s  %s" % [str(key).capitalize(), _fmt_amount(amt)])
	return out

func _fmt_amount(amt: float) -> String:
	var sign_txt := "+" if amt >= 0.0 else "-"
	var mag := absf(amt)
	if mag == floorf(mag):
		return "%s%d" % [sign_txt, int(mag)]
	return "%s%s" % [sign_txt, str(mag)]
