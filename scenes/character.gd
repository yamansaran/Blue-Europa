extends Node

## ============================================================================
## CHARACTER  —  the player's memory file (autoload singleton "Character")
## ============================================================================
## Persistent player record. Rev6: the stat block now lives in a CharacterBase
## `body`; base numbers never change, and every bonus is a hidden buff in one of
## the body's baskets:
##   - levels     : one entry per level gained         (rebuilt from `level`)
##   - attributes : points spent into major stats      (rebuilt, refundable)
##   - items      : per-EQUIPPED-item stat mods         (rebuilt from equipped_items)
##   - buffs/debuffs : combat-only, not persisted here
## The autoload keeps the progression bookkeeping (xp, money, skill tree, wheel,
## ability pool, bag + equipped gear) and drives the body; `base_stats`/`get_stat`
## remain as a read-only compatibility surface for code that still wants a flat
## dict. Rev9: equippable items — the items basket now reflects what is EQUIPPED
## (equipped_items), not everything held. Items resolve through ItemDB by id.
## Saved to user://character.save as JSON. Old (pre-rev9) saves are discarded.
## ----------------------------------------------------------------------------

signal changed

const SAVE_PATH := "user://character.save"
const SAVE_VERSION := 3          # bump discards any older save (fresh start)
const WHEEL_SLOTS := 10

## Each attribute point adds this much to its major stat.
const ATTRIBUTE_STEP := 1.0

## Fallback money gained when selling an item that carries no explicit value.
const DEFAULT_SELL_VALUE := 10

# --- the shared stat body ---------------------------------------------------
var body: CharacterBase = CharacterBase.new()

# --- identity / progression -------------------------------------------------
var char_name: String = "Sonny"
var level: int = 1
var items: Array = []            # BAG: loot/purchase dicts {id, name, (opt) mods}
var xp: int = 0
var money: int = 100

## EQUIPPED gear: slot_key(String from Item.SLOT_KEYS) -> item dict {id,name,mods}.
## Only equipped items contribute stat bonuses (via the "items" basket).
var equipped_items: Dictionary = {}

# --- skill tree -------------------------------------------------------------
var skill_points: int = 5
var allocations: Dictionary = {}          # node_id(String) -> points(int)

# --- attribute points (spent into MAJOR stats) ------------------------------
var attribute_points: int = 5
var attribute_allocations: Dictionary = {}  # major_key(String) -> points(int)

# --- abilities --------------------------------------------------------------
var unlocked_abilities: Array = ["strike"]
var equipped_abilities: Array = ["strike", "", "", "", "", "", "", "", "", ""]

# --- read-only compatibility view -------------------------------------------
## Flat effective-stat dictionary (base + all baskets), plus derived max_hp and
## a legacy "focus" alias for spirit. Combat / older code read this.
var base_stats: Dictionary:
	get:
		return _stats_snapshot()


func _ready() -> void:
	load_game()


func _stats_snapshot() -> Dictionary:
	var d := body.effective_stats()
	d["max_hp"] = float(body.max_hp())
	d["focus"] = float(body.max_spirit())   # legacy alias
	return d


func _item_db() -> Node:
	return get_node_or_null("/root/ItemDB")


## Resolve a bag/equip entry (or a raw id) to its Item resource via ItemDB.
func _resolve_item(id_or_entry) -> Item:
	var iid := ""
	if typeof(id_or_entry) == TYPE_DICTIONARY:
		iid = str(id_or_entry.get("id", ""))
	else:
		iid = str(id_or_entry)
	if iid == "":
		return null
	var db := _item_db()
	if db and db.has_method("get_item"):
		return db.get_item(iid)
	return null


# ============================================================================
# Body assembly — rebuild every basket from current progression
# ============================================================================
func _rebuild_body() -> void:
	body.char_name = char_name
	body.level = level
	body.char_type = Stats.CharType.CHARACTER
	_rebuild_level_basket()
	_rebuild_attribute_basket()
	_rebuild_item_basket()
	body.init_vitals()


func _rebuild_level_basket() -> void:
	body.clear_basket("levels")
	# One hidden entry per level gained; more levels => the buff "stacks".
	for lvl in range(2, level + 1):
		var mods := _level_mods(lvl)
		body.add_entry("levels", CharacterBase.make_entry("lvl_%d" % lvl, "Level %d" % lvl, mods))


## Per-level stat growth. LEFT EMPTY ON PURPOSE — plug your level curve in here.
## Example: return {"hp_base": 5.0, "vigor": 1.0}
func _level_mods(_lvl: int) -> Dictionary:
	return {}


## Derive `level` from the continuous total `xp` using the LevelTable curve, and
## rebuild the level basket if it changed. XP itself is NEVER reset — only the
## derived level moves. Returns true if the level went up. Callers that also
## touch other baskets should re-init vitals afterwards (gain_rewards does).
func _apply_xp_level() -> bool:
	var new_level := LevelTable.level_for_xp(xp)
	if new_level == level:
		return false
	var old_level := level
	level = new_level
	body.level = level
	if new_level > old_level:
		_grant_level_up_rewards(old_level, new_level)
	_rebuild_level_basket()
	return true


## Award the per-level payout for every level gained crossing from `from_level`
## up to `to_level`: a flat SKILL_POINTS_PER_LEVEL skill points plus the bracketed
## attribute points for each level reached. Called only when the level rises (xp is
## monotonic), and the totals are persisted via the normal save that follows.
func _grant_level_up_rewards(from_level: int, to_level: int) -> void:
	for lvl in range(from_level + 1, to_level + 1):
		skill_points += LevelTable.SKILL_POINTS_PER_LEVEL
		attribute_points += LevelTable.attribute_points_for_level(lvl)


func _rebuild_attribute_basket() -> void:
	body.clear_basket("attributes")
	for major in attribute_allocations.keys():
		var pts := int(attribute_allocations[major])
		if pts > 0:
			body.add_entry("attributes",
				CharacterBase.make_entry("attr_%s" % major, "Attribute: %s" % major,
					{str(major): float(pts) * ATTRIBUTE_STEP}))


## The items basket reflects EQUIPPED gear only. Each equipped slot contributes
## one entry whose mods are the item's `stats` (resolved through ItemDB), with a
## `mods` snapshot on the equip dict as a fallback if ItemDB is unavailable.
func _rebuild_item_basket() -> void:
	body.clear_basket("items")
	for slot_key in equipped_items.keys():
		var entry = equipped_items[slot_key]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var iid := str(entry.get("id", ""))
		if iid == "":
			continue
		var mods := {}
		var item := _resolve_item(iid)
		if item != null and typeof(item.stats) == TYPE_DICTIONARY:
			mods = (item.stats as Dictionary).duplicate(true)
		if mods.is_empty():
			var snap = entry.get("mods", null)
			if typeof(snap) == TYPE_DICTIONARY:
				mods = (snap as Dictionary).duplicate(true)
		if not mods.is_empty():
			var iname := str(entry.get("name", iid))
			body.add_entry("items", CharacterBase.make_entry("equip_%s" % slot_key, iname, mods))


# ============================================================================
# Skill tree API (unchanged)
# ============================================================================
func get_points(node_id: String) -> int:
	return int(allocations.get(node_id, 0))

## A node counts as UNLOCKED once it has at least one point invested. This is what
## child nodes test for their parent prerequisites.
func node_unlocked(node_id: String) -> bool:
	return get_points(node_id) > 0

## Whether a node's UNLOCK PREREQUISITES are met: the player is at least
## `node_required_level` AND every parent node (by node_id) is already unlocked.
## A node with no parents (a tree root, e.g. Malkuth) only needs the level. Called
## by SkillNode both to gate investing and to show a locked/available look.
func can_unlock_node(node_required_level: int = 1, parents: Array = []) -> bool:
	if level < node_required_level:
		return false
	for p in parents:
		if not node_unlocked(str(p)):
			return false
	return true

## Invest one point in a node. Rev14b: now gated by the node's level requirement +
## parent prerequisites (both default-open, so old callers that pass neither behave
## exactly as before). Returns false — investing nothing — if the gate isn't met.
func invest(node_id: String, node_max: int, node_required_level: int = 1, parents: Array = []) -> bool:
	if node_id == "":
		return false
	if skill_points <= 0:
		return false
	var current := get_points(node_id)
	if current >= node_max:
		return false
	if not can_unlock_node(node_required_level, parents):
		return false
	allocations[node_id] = current + 1
	skill_points -= 1
	changed.emit()
	save_game()
	return true

func respec() -> void:
	var refunded := 0
	for v in allocations.values():
		refunded += int(v)
	skill_points += refunded
	allocations.clear()
	changed.emit()
	save_game()


# ============================================================================
# Attribute API — spend points into MAJOR stats (a hidden, refundable buff)
# ============================================================================
func get_attribute_points() -> int:
	return attribute_points

func get_attribute_invested(major: String) -> int:
	return int(attribute_allocations.get(major, 0))

func can_allocate_attribute(major: String) -> bool:
	# Spirit (and any NON_ALLOCATABLE major) can never take attribute points.
	return attribute_points > 0 and Stats.allocatable_major_keys().has(major)

func allocate_attribute(major: String) -> bool:
	if not can_allocate_attribute(major):
		return false
	attribute_allocations[major] = get_attribute_invested(major) + 1
	attribute_points -= 1
	_rebuild_attribute_basket()
	body.init_vitals()
	changed.emit()
	save_game()
	return true

## Refund every attribute point back into the pool.
func respec_attributes() -> void:
	var refunded := 0
	for v in attribute_allocations.values():
		refunded += int(v)
	attribute_points += refunded
	attribute_allocations.clear()
	_rebuild_attribute_basket()
	body.init_vitals()
	changed.emit()
	save_game()


# ============================================================================
# Stats compatibility API
# ============================================================================
## Effective (base + baskets) value of any stat key. Handles a couple of legacy
## aliases so old callers keep working.
func get_stat(stat_name) -> int:
	var s := str(stat_name)
	match s:
		"max_hp": return body.max_hp()
		"focus": return body.max_spirit()
		_: return body.get_effective_int(s)

func get_body() -> CharacterBase:
	return body


# ============================================================================
# Ability API (unchanged)
# ============================================================================
func is_unlocked(id) -> bool:
	return unlocked_abilities.has(str(id))

func unlock_ability(id) -> void:
	var s := str(id)
	if s != "" and not unlocked_abilities.has(s):
		unlocked_abilities.append(s)
		changed.emit()
		save_game()

func get_equipped() -> Array:
	return equipped_abilities.duplicate()

func count_equipped(id) -> int:
	var s := str(id)
	var n := 0
	for e in equipped_abilities:
		if str(e) == s:
			n += 1
	return n

func _max_equipped_for(id) -> int:
	var db := get_node_or_null("/root/AbilityDB")
	if db and db.has_method("get_ability"):
		var ab = db.get_ability(id)
		if ab != null:
			return int(ab.max_equipped)
	return 2

func can_equip(slot: int, id) -> bool:
	var s := str(id)
	if slot < 0 or slot >= WHEEL_SLOTS:
		return false
	if s == "" or not is_unlocked(s):
		return false
	if str(equipped_abilities[slot]) == s:
		return true
	return count_equipped(s) < _max_equipped_for(s)

func equip_ability(slot: int, id) -> bool:
	if not can_equip(slot, id):
		return false
	equipped_abilities[slot] = str(id)
	changed.emit()
	save_game()
	return true

func unequip_slot(slot: int) -> void:
	if slot < 0 or slot >= WHEEL_SLOTS:
		return
	if str(equipped_abilities[slot]) == "":
		return
	equipped_abilities[slot] = ""
	changed.emit()
	save_game()

func move_equipped(from_slot: int, to_slot: int) -> bool:
	if from_slot < 0 or from_slot >= WHEEL_SLOTS:
		return false
	if to_slot < 0 or to_slot >= WHEEL_SLOTS:
		return false
	if from_slot == to_slot:
		return true
	var tmp = equipped_abilities[from_slot]
	equipped_abilities[from_slot] = equipped_abilities[to_slot]
	equipped_abilities[to_slot] = tmp
	changed.emit()
	save_game()
	return true

func _normalize_wheel() -> void:
	while equipped_abilities.size() < WHEEL_SLOTS:
		equipped_abilities.append("")
	if equipped_abilities.size() > WHEEL_SLOTS:
		equipped_abilities.resize(WHEEL_SLOTS)
	for i in equipped_abilities.size():
		equipped_abilities[i] = str(equipped_abilities[i])


# ============================================================================
# Equipment API — bag <-> gear slots (rev9)
# ============================================================================
## The item dict currently in a physical slot ("head", "weapon_off", ...), or
## null when the slot is empty.
func get_equipped_item(slot_key: String):
	return equipped_items.get(slot_key, null)

## Equip the bag item at `bag_index` into `slot_key`. The item must be equippable
## and fit that slot family. Any item already in the slot is returned to the bag.
## Returns true on success.
func equip_from_bag(bag_index: int, slot_key: String) -> bool:
	if bag_index < 0 or bag_index >= items.size():
		return false
	if not Item.SLOT_KEYS.has(slot_key):
		return false
	var bag_entry = items[bag_index]
	if typeof(bag_entry) != TYPE_DICTIONARY:
		return false
	var iid := str(bag_entry.get("id", ""))
	var item := _resolve_item(iid)
	if item == null or not item.equippable:
		return false
	if not item.fits_slot_key(slot_key):
		return false

	items.remove_at(bag_index)
	# swap out whatever was there
	if equipped_items.has(slot_key) and equipped_items[slot_key] != null:
		items.append(equipped_items[slot_key])
	# store a fresh snapshot (id + name + mods) so stats survive a cold load
	equipped_items[slot_key] = {
		"id": iid,
		"name": item.display_name,
		"mods": item.stats.duplicate(true),
	}
	_rebuild_item_basket()
	body.init_vitals()
	changed.emit()
	save_game()
	return true

## Remove the item in `slot_key` back to the bag. Returns true if something moved.
func unequip_item_slot(slot_key: String) -> bool:
	if not equipped_items.has(slot_key) or equipped_items[slot_key] == null:
		return false
	items.append(equipped_items[slot_key])
	equipped_items.erase(slot_key)
	_rebuild_item_basket()
	body.init_vitals()
	changed.emit()
	save_game()
	return true


# ============================================================================
# Shop API — buying (selling lives under "Selling" below)
# ============================================================================
func can_afford(amount: int) -> bool:
	return money >= amount

## Buy one copy of `item_id` (must exist in ItemDB and be affordable). Adds it to
## the bag and deducts its value. Returns true on success.
func buy_item(item_id) -> bool:
	var item := _resolve_item(str(item_id))
	if item == null:
		return false
	if money < item.value:
		return false
	money -= item.value
	items.append(item.to_bag())
	changed.emit()
	save_game()
	return true


# ============================================================================
# Persistence  (rev9 format; older saves are discarded on load)
# ============================================================================
func save_game() -> void:
	var data := {
		"save_version": SAVE_VERSION,
		"char_name": char_name,
		"level": level,
		"items": items,
		"equipped_items": equipped_items,
		"xp": xp,
		"money": money,
		"skill_points": skill_points,
		"allocations": allocations,
		"attribute_points": attribute_points,
		"attribute_allocations": attribute_allocations,
		"unlocked_abilities": unlocked_abilities,
		"equipped_abilities": equipped_abilities,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))
		f.close()

func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		_rebuild_body()
		changed.emit()
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		_rebuild_body()
		return
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	# discard anything that isn't a current-version save -> clean fresh start
	if typeof(parsed) != TYPE_DICTIONARY or int(parsed.get("save_version", 0)) != SAVE_VERSION:
		_rebuild_body()
		changed.emit()
		save_game()   # overwrite the stale file with a fresh one
		return

	char_name = str(parsed.get("char_name", char_name))
	level = int(parsed.get("level", level))
	items = parsed.get("items", items)
	xp = int(parsed.get("xp", xp))
	money = int(parsed.get("money", money))
	skill_points = int(parsed.get("skill_points", skill_points))
	attribute_points = int(parsed.get("attribute_points", attribute_points))

	var eqi = parsed.get("equipped_items", {})
	equipped_items = {}
	if typeof(eqi) == TYPE_DICTIONARY:
		for key in eqi.keys():
			if typeof(eqi[key]) == TYPE_DICTIONARY:
				equipped_items[str(key)] = eqi[key]

	var a = parsed.get("allocations", {})
	if typeof(a) == TYPE_DICTIONARY:
		allocations = {}
		for key in a.keys():
			allocations[str(key)] = int(a[key])

	var aa = parsed.get("attribute_allocations", {})
	if typeof(aa) == TYPE_DICTIONARY:
		attribute_allocations = {}
		for key in aa.keys():
			attribute_allocations[str(key)] = int(aa[key])

	var ul = parsed.get("unlocked_abilities", null)
	if typeof(ul) == TYPE_ARRAY:
		unlocked_abilities = []
		for v in ul:
			unlocked_abilities.append(str(v))
	if not unlocked_abilities.has("strike"):
		unlocked_abilities.append("strike")

	var eq = parsed.get("equipped_abilities", null)
	if typeof(eq) == TYPE_ARRAY:
		equipped_abilities = []
		for v in eq:
			equipped_abilities.append(str(v))
	_normalize_wheel()

	# Level is a pure function of the continuous xp + the LevelTable curve, so
	# re-derive it on load (keeps saves consistent if the curve was retuned).
	level = LevelTable.level_for_xp(xp)
	_rebuild_body()
	changed.emit()

func reset_to_defaults() -> void:
	char_name = "Sonny"
	level = 1
	items = []
	equipped_items = {}
	xp = 0
	money = 100
	skill_points = 5
	allocations = {}
	attribute_points = 5
	attribute_allocations = {}
	unlocked_abilities = ["strike"]
	equipped_abilities = ["strike", "", "", "", "", "", "", "", "", ""]
	_rebuild_body()
	changed.emit()
	save_game()


# ============================================================================
# Inventory / rewards
# ============================================================================
func add_item(item) -> void:
	items.append(item)
	changed.emit()
	save_game()

func gain_rewards(money_amt: int, xp_amt: int, new_items: Array) -> void:
	money += money_amt
	xp += xp_amt
	for it in new_items:
		items.append(it)
	_apply_xp_level()          # continuous xp may push the level up
	body.init_vitals()
	changed.emit()
	save_game()


## Add XP only (no money/items) and re-derive the level. Handy for scripted xp.
func gain_xp(xp_amt: int) -> void:
	xp += xp_amt
	_apply_xp_level()
	body.init_vitals()
	changed.emit()
	save_game()


# ============================================================================
# Selling
# ============================================================================
## Money an item is worth when sold. Prefers the Item's sell value (via ItemDB),
## then an explicit value/sell on the dict, then DEFAULT_SELL_VALUE.
func item_sell_value(it) -> int:
	if typeof(it) == TYPE_DICTIONARY:
		var item := _resolve_item(it)
		if item != null:
			return item.get_sell_value()
		return int(it.get("value", it.get("sell", DEFAULT_SELL_VALUE)))
	return DEFAULT_SELL_VALUE

## Sell (remove) the BAG item at `index`, crediting its value to money. Returns the
## money gained, or -1 if the index was invalid. (Equipped items must be
## unequipped first — they are not in the bag.)
func sell_item(index: int) -> int:
	if index < 0 or index >= items.size():
		return -1
	var value := item_sell_value(items[index])
	items.remove_at(index)
	money += value
	changed.emit()
	save_game()
	return value
