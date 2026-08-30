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
##   - passives   : per-PASSIVE-ability stat mods       (rebuilt from the wheel)
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
const WHEEL_SLOTS := 10       # BASE wheel slots; Overmind adds on top (wheel_slot_count)

## Each attribute point adds this much to its major stat.
const ATTRIBUTE_STEP := 1.0

## Fallback money gained when selling an item that carries no explicit value.
const DEFAULT_SELL_VALUE := 10

# --- the shared stat body ---------------------------------------------------
## The player's body is a PlayerCharacter (a thin CharacterBase module) so the
## player is a character module like every other unit and has a home for
## player-wide permanent buffs. Its STATS are still driven entirely by this
## autoload (levels / attributes / items / passives rebuilt into the baskets).
var body: CharacterBase = PlayerCharacter.new()

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
## node_id(String) -> ability_id(String). Records which ability each invested (or
## registered) skill-tree node grants, so combat can turn an equipped ability id
## back into the RANK the player invested (allocations is keyed by node, the wheel
## by ability). Written on invest and on register_node (a tree node announcing
## itself at load); persisted so the rank survives a reload even before the tree
## screen is opened.
var node_abilities: Dictionary = {}

# --- attribute points (spent into MAJOR stats) ------------------------------
var attribute_points: int = 5
var attribute_allocations: Dictionary = {}  # major_key(String) -> points(int)

# --- abilities --------------------------------------------------------------
var unlocked_abilities: Array = ["claw", "scour"]
var equipped_abilities: Array = ["claw", "scour", "", "", "", "", "", "", "", ""]

# --- read-only compatibility view -------------------------------------------
## Flat effective-stat dictionary (base + all baskets), plus derived max_hp and
## a legacy "focus" alias for spirit. Combat / older code read this.
var base_stats: Dictionary:
	get:
		return _stats_snapshot()


func _ready() -> void:
	load_game()
	# Character autoloads BEFORE AbilityDB, so at load time abilities can't be resolved
	# (Overmind's wheel-slot bonus and any per-rank passive read as absent). Re-sync once
	# every autoload is ready — call_deferred runs after AbilityDB._ready has scanned the
	# ability folder.
	call_deferred("_post_autoload_sync")


## Second-pass sync after all autoloads (incl. AbilityDB) are ready: size the wheel to
## include Overmind's bonus slots and rebuild the passives basket at the invested rank.
func _post_autoload_sync() -> void:
	_normalize_wheel()
	_rebuild_passive_basket()
	_rebuild_crown_basket()
	_rebuild_derived_basket()
	body.clamp_vitals()
	changed.emit()


func _stats_snapshot() -> Dictionary:
	var d := body.effective_stats()
	d["max_hp"] = float(body.max_hp())
	d["focus"] = float(body.max_spirit())   # legacy alias
	return d


func _item_db() -> Node:
	return get_node_or_null("/root/ItemDB")


func _ability_db() -> Node:
	return get_node_or_null("/root/AbilityDB")


## Resolve an ability id to its Ability resource via AbilityDB (null if unknown).
func _resolve_ability(id) -> Ability:
	var s := str(id)
	if s == "":
		return null
	var db := _ability_db()
	if db and db.has_method("get_ability"):
		return db.get_ability(s)
	return null


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
	_rebuild_passive_basket()
	_rebuild_crown_basket()
	_rebuild_derived_basket()
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


## The passives basket reflects PASSIVE abilities currently sitting in the combat
## wheel. Each wheel slot holding a PASSIVE with a stat bonus contributes ONE entry
## (flat `passive_mods` + multiplier `passive_mult`). Two copies of the same passive
## in two slots stack (two entries). Rebuilt whenever the wheel changes, so a passive
## only affects stats WHILE it is slotted — removing it from the wheel drops its
## entry. This basket is PERSISTENT (never cleared at end of combat).
func _rebuild_passive_basket() -> void:
	body.clear_basket("passives")
	for i in equipped_abilities.size():
		var id := str(equipped_abilities[i])
		if id == "":
			continue
		var ab := _resolve_ability(id)
		if ab == null or not ab.has_passive_bonus():
			continue
		# ALWAYS-ACTIVE passives are sourced from the invested node below, never the wheel
		# — skip them here so a copy in a slot can't also contribute (which would double
		# the bonus). None ship today (Beautiful Form is a normal equippable passive); this
		# keeps the always_active flag usable for a future node-sourced stat passive.
		if ab.has_method("is_always_active") and ab.is_always_active():
			continue
		# Resolve the FLAT + MULTIPLIER bonus at the player's invested rank, so a
		# per-rank passive (e.g. Mercy) contributes its current rank's values.
		var rank := ability_rank(id)
		var mods := {}
		var mods_src = ab.passive_mods_at(rank)
		if typeof(mods_src) == TYPE_DICTIONARY:
			mods = (mods_src as Dictionary).duplicate(true)
		var mult := {}
		var mult_src = ab.passive_mult_at(rank)
		if typeof(mult_src) == TYPE_DICTIONARY:
			mult = (mult_src as Dictionary).duplicate(true)
		# id keyed by slot so multiple copies stack and removing one is clean.
		body.add_entry("passives",
			CharacterBase.make_entry("passive_slot_%d" % i, ab.display_name, mods, mult))
	# ALWAYS-ACTIVE passives: applied from the INVESTED NODE, not the wheel — they never
	# need to be equipped and are kept out of the ability pool. Scan every node with points
	# invested; if its ability is an always-active passive that carries a stat bonus, add
	# one entry at the invested rank. Nothing hits this today (Sinewed / Overmind / Crown
	# are always-active but have no passive_mods, so has_passive_bonus() is false and they
	# contribute nothing here — their effects live elsewhere); it stands ready for a future
	# node-sourced stat passive using the always_active flag.
	for nid in allocations.keys():
		var pts := int(allocations[nid])
		if pts <= 0:
			continue
		var aid := str(node_abilities.get(nid, nid))
		var nab := _resolve_ability(aid)
		if nab == null or not nab.has_method("is_always_active") or not nab.is_always_active():
			continue
		if not nab.has_passive_bonus():
			continue
		var n_mods := {}
		var n_mods_src = nab.passive_mods_at(pts)
		if typeof(n_mods_src) == TYPE_DICTIONARY:
			n_mods = (n_mods_src as Dictionary).duplicate(true)
		var n_mult := {}
		var n_mult_src = nab.passive_mult_at(pts)
		if typeof(n_mult_src) == TYPE_DICTIONARY:
			n_mult = (n_mult_src as Dictionary).duplicate(true)
		body.add_entry("passives",
			CharacterBase.make_entry("passive_node_%s" % str(nid), nab.display_name, n_mods, n_mult))


## Re-apply passive bonuses after the wheel changed, then re-clamp vitals (a
## passive could move max HP / max Spirit) and notify listeners.
func _refresh_passives_after_wheel_change() -> void:
	_rebuild_passive_basket()
	_rebuild_crown_basket()
	_rebuild_derived_basket()
	body.clamp_vitals()


## Rebuild the CROWN basket. The always-on Keter / Crown node scales the player's BONUS
## stats (the summed flat mods across the other baskets — NOT the base value) by
## bonus_per_level, per invested point, per CHARACTER LEVEL. Scans invested skill-tree
## nodes for any whose ability is a bonus-scaling node (Ability.is_bonus_scaling),
## snapshots each listed stat's CURRENT bonus (the crown basket is cleared first, so it
## never scales off itself), and adds ONE flat entry. Rebuilt alongside the other baskets
## whenever progression changes; it needs AbilityDB to resolve abilities, so the deferred
## post-load sync re-runs it once AbilityDB is ready (mirrors Overmind's wheel bonus).
func _rebuild_crown_basket() -> void:
	body.clear_basket("crown")
	var mods := {}
	for nid in allocations.keys():
		var pts := int(allocations[nid])
		if pts <= 0:
			continue
		var aid := str(node_abilities.get(nid, nid))
		var ab := _resolve_ability(aid)
		if ab == null or not ab.has_method("is_bonus_scaling") or not ab.is_bonus_scaling():
			continue
		# 1% (bonus_per_level) of each listed stat's bonus, per point, per character level.
		var factor := float(ab.bonus_per_level) * float(pts) * float(level)
		if factor == 0.0:
			continue
		for stat in ab.bonus_per_level_stats:
			var key := str(stat)
			var bonus := body.get_bonus(key)   # crown cleared above -> excludes itself
			if bonus == 0.0:
				continue
			mods[key] = float(mods.get(key, 0.0)) + bonus * factor
	if not mods.is_empty():
		body.add_entry("crown", CharacterBase.make_entry("crown", "Crown", mods))


## Rebuild the DERIVED basket. A PASSIVE may express a flat bonus as a FRACTION OF
## ANOTHER STAT (Ability.passive_scale, e.g. Galvanism: +Alacrity equal to 30% of
## Instinct). passive_mods is a static dict and cannot do that, so those passives are
## resolved here instead, live: the basket is cleared first and each target stat is
## recomputed from the CURRENT effective value of its source stat, so the bonus tracks
## gear, levels and other passives as they move. Clearing first also means a passive can
## never scale off its own output. Sources scanned, mirroring _rebuild_passive_basket:
## every EQUIPPED wheel slot holding a normal passive, plus every INVESTED node holding
## an always-active one. Runs AFTER the passives + crown baskets so it sees their totals.
func _rebuild_derived_basket() -> void:
	body.clear_basket("derived")
	var mods := {}
	# --- equipped (normal) passives ---
	for i in equipped_abilities.size():
		var id := str(equipped_abilities[i])
		if id == "":
			continue
		var ab := _resolve_ability(id)
		if ab == null or not ab.has_method("has_passive_scale") or not ab.has_passive_scale():
			continue
		# always-active passives are sourced from the node below, never the wheel
		if ab.has_method("is_always_active") and ab.is_always_active():
			continue
		_accumulate_derived(mods, ab, ability_rank(id))
	# --- always-active passives, sourced from the INVESTED NODE ---
	for nid in allocations.keys():
		var pts := int(allocations[nid])
		if pts <= 0:
			continue
		var aid := str(node_abilities.get(nid, nid))
		var nab := _resolve_ability(aid)
		if nab == null or not nab.has_method("is_always_active") or not nab.is_always_active():
			continue
		if not nab.has_method("has_passive_scale") or not nab.has_passive_scale():
			continue
		_accumulate_derived(mods, nab, pts)
	if not mods.is_empty():
		body.add_entry("derived", CharacterBase.make_entry("derived", "Derived", mods))


## Fold one passive's stat-derived bonus (Ability.passive_scale_at) into `mods`.
## Each target stat gains Σ (source stat's CURRENT effective value × fraction). The
## derived basket was cleared by the caller, so these reads never include our own output.
func _accumulate_derived(mods: Dictionary, ab, rank: int) -> void:
	var spec = ab.passive_scale_at(rank)
	if typeof(spec) != TYPE_DICTIONARY:
		return
	for target_stat in (spec as Dictionary):
		var sources = spec[target_stat]
		if typeof(sources) != TYPE_DICTIONARY:
			continue
		var add := 0.0
		for src_stat in (sources as Dictionary):
			add += body.get_effective(str(src_stat)) * float(sources[src_stat])
		if add != 0.0:
			var key := str(target_stat)
			mods[key] = float(mods.get(key, 0.0)) + add


# ============================================================================
# Combat-wheel size (Overmind — an always-on wheel-slot passive)
# ============================================================================
## Extra combat-wheel slots granted by invested WHEEL-SLOT passives (Overmind). Scans
## every skill-tree node with points invested; if the ability that node grants is a
## wheel-slot passive (wheel_slots_per_point != 0), adds points * per-point slots. The
## passive need NOT be equipped — the bonus is live while any point sits in the node.
func extra_wheel_slots() -> int:
	var extra := 0
	for nid in allocations.keys():
		var pts := int(allocations[nid])
		if pts <= 0:
			continue
		var aid := str(node_abilities.get(nid, nid))
		var ab := _resolve_ability(aid)
		if ab != null and ab.has_method("is_wheel_slot_passive") and ab.is_wheel_slot_passive():
			extra += pts * int(ab.wheel_slots_per_point)
	return extra

## The current number of combat-wheel slots: the base WHEEL_SLOTS plus any Overmind
## bonus. The wheel + equip logic size themselves off this.
func wheel_slot_count() -> int:
	return WHEEL_SLOTS + maxi(0, extra_wheel_slots())


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
## A node with no parents (a tree root, e.g. Malkuth) only needs the level. The
## default requirement is level 0 — i.e. no level gate — so a node only demands a
## level when its scene explicitly sets one (furnishing nodes ask for 5). Called by
## SkillNode both to gate investing and to show a locked/available look.
func can_unlock_node(node_required_level: int = 0, parents: Array = []) -> bool:
	if level < node_required_level:
		return false
	for p in parents:
		if not node_unlocked(str(p)):
			return false
	return true

## Record that `node_id` grants `ability_id` (idempotent). Called by every tree
## node as it enters the scene, so the node->ability map is complete once a tree is
## opened — repairing it for saves made before this map existed — without changing
## any invested points. Purely in-memory here; it is persisted on the next invest
## (or any other save), and the rank still falls back sensibly until then.
func register_node(node_id: String, ability_id: String) -> void:
	if node_id == "" or ability_id == "":
		return
	if str(node_abilities.get(node_id, "")) != ability_id:
		node_abilities[node_id] = ability_id

## The RANK (invested points) the player has in an ability, resolved through the
## node that grants it: the max points over every node mapped to this ability id.
## Falls back to 1 for an unlocked ability with no known node (e.g. the default
## Strike, or a debug unlock), and 0 when the ability is not unlocked at all.
func ability_rank(ability_id) -> int:
	var aid := str(ability_id)
	if aid == "":
		return 0
	var best := 0
	for nid in node_abilities.keys():
		if str(node_abilities[nid]) == aid:
			best = maxi(best, get_points(str(nid)))
	if best > 0:
		return best
	return 1 if is_unlocked(aid) else 0

## Invest one point in a node. Rev14b: gated by the node's level requirement +
## parent prerequisites (both default-open, so old callers that pass neither behave
## exactly as before). `ability_id` records the node->ability mapping for the rank
## lookup. Returns false — investing nothing — if the gate isn't met.
func invest(node_id: String, node_max: int, node_required_level: int = 0, parents: Array = [], ability_id: String = "") -> bool:
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
	if ability_id != "":
		node_abilities[node_id] = ability_id
	skill_points -= 1
	# A rank change can grow the wheel (Overmind) and/or change an equipped per-rank
	# passive's bonus (Beautiful Form) — resize the wheel and rebuild passives so the
	# effect is live the instant the point is spent.
	_normalize_wheel()
	_refresh_passives_after_wheel_change()
	changed.emit()
	save_game()
	return true

func respec() -> void:
	var refunded := 0
	for v in allocations.values():
		refunded += int(v)
	skill_points += refunded
	allocations.clear()
	# Refunding the points also re-locks every node, so the abilities those nodes
	# granted must leave the pool — otherwise they linger as unlocked forever.
	_resync_unlocked_from_allocations()
	# Overmind's bonus slots are gone now — shrink the wheel back (only trailing empty
	# slots are dropped) and rebuild passives at their reset ranks.
	_normalize_wheel()
	_refresh_passives_after_wheel_change()
	changed.emit()
	save_game()


## Rebuild `unlocked_abilities` to exactly what the player currently earns: the
## always-free defaults (strike) plus every ability granted by a node that STILL
## has at least one point invested. Anything else — e.g. an ability from a node
## whose points were just refunded by respec() — is dropped from the pool, and any
## wheel slot holding a now-locked ability is cleared (rebuilding passives). Safe to
## call any time allocations change; it only ever removes abilities that no invested
## node backs, never adds one.
func _resync_unlocked_from_allocations() -> void:
	var kept := {"claw": true, "scour": true}
	for nid in allocations.keys():
		if int(allocations[nid]) > 0:
			var aid := str(node_abilities.get(nid, ""))
			if aid != "":
				kept[aid] = true
				# An invested node also keeps alive whatever its ability GRANTS
				# (Severity -> Vicious Strike), so a respec drops the granted
				# ability exactly when the granting node loses its last point.
				var gab := _resolve_ability(aid)
				if gab != null and "unlocks_ability" in gab:
					var granted := String(gab.unlocks_ability)
					if granted != "":
						kept[granted] = true
	var new_unlocked: Array = []
	for id in unlocked_abilities:
		var s := str(id)
		if kept.has(s) and not new_unlocked.has(s):
			new_unlocked.append(s)
	unlocked_abilities = new_unlocked
	for def_id in ["claw", "scour"]:
		if not unlocked_abilities.has(def_id):
			unlocked_abilities.append(def_id)
	# Drop any equipped ability that is no longer unlocked, then rebuild passives so
	# a slotted passive that just got re-locked stops contributing its stat bonus.
	var wheel_changed := false
	for i in equipped_abilities.size():
		var eid := str(equipped_abilities[i])
		if eid != "" and not unlocked_abilities.has(eid):
			equipped_abilities[i] = ""
			wheel_changed = true
	if wheel_changed:
		_refresh_passives_after_wheel_change()


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
	_rebuild_crown_basket()
	_rebuild_derived_basket()
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
	_rebuild_crown_basket()
	_rebuild_derived_basket()
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
# Ability API (unchanged except: wheel changes now rebuild the passives basket)
# ============================================================================
func is_unlocked(id) -> bool:
	return unlocked_abilities.has(str(id))

func unlock_ability(id) -> void:
	var s := str(id)
	if s == "" or unlocked_abilities.has(s):
		return
	# ALWAYS-ACTIVE node abilities are live straight from the skill tree and are never
	# cast or equipped, so keep them out of the ability pool. is_always_active() covers
	# them all: the explicit always_active passive (unused today), upgrade-only nodes
	# (Sinewed), wheel-slot passives (Overmind) and bonus-scaling nodes (Crown).
	var ab := _resolve_ability(s)
	if ab != null and ab.has_method("is_always_active") and ab.is_always_active():
		return
	unlocked_abilities.append(s)
	# CASCADE: an ability may GRANT another one (Severity hands out Vicious Strike).
	# Append it too — inline rather than recursing, so the signal + save fire once, and
	# so a granted ability that itself grants nothing can't loop.
	if ab != null and "unlocks_ability" in ab:
		var granted := String(ab.unlocks_ability)
		if granted != "" and granted != s and not unlocked_abilities.has(granted):
			unlocked_abilities.append(granted)
	changed.emit()
	save_game()

## Total extra per-stat scaling that invested UPGRADE nodes grant to `ability_id`.
## Scans every node with points invested; if the ability that node grants carries an
## `upgrades` map naming this ability, adds points × each listed per-point scaling
## bonus. Returns { stat_key: extra_multiplier } (empty when nothing upgrades it).
## Combat passes the result into CombatMath.resolve -> Ability.compute_damage.
func ability_scaling_bonus(ability_id) -> Dictionary:
	var target := str(ability_id)
	var out: Dictionary = {}
	if target == "":
		return out
	for nid in allocations.keys():
		var pts := int(allocations[nid])
		if pts <= 0:
			continue
		var aid := str(node_abilities.get(nid, nid))
		var ab := _resolve_ability(aid)
		if ab == null or typeof(ab.upgrades) != TYPE_DICTIONARY:
			continue
		if not ab.upgrades.has(target):
			continue
		var per_point = ab.upgrades[target]
		if typeof(per_point) != TYPE_DICTIONARY:
			continue
		for stat in per_point.keys():
			var k := str(stat)
			out[k] = float(out.get(k, 0.0)) + float(per_point[stat]) * float(pts)
	return out

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
	var ab := _resolve_ability(id)
	if ab != null:
		return int(ab.max_equipped)
	return 2

func can_equip(slot: int, id) -> bool:
	var s := str(id)
	if slot < 0 or slot >= wheel_slot_count():
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
	_refresh_passives_after_wheel_change()
	changed.emit()
	save_game()
	return true

func unequip_slot(slot: int) -> void:
	if slot < 0 or slot >= wheel_slot_count():
		return
	if str(equipped_abilities[slot]) == "":
		return
	equipped_abilities[slot] = ""
	_refresh_passives_after_wheel_change()
	changed.emit()
	save_game()

func move_equipped(from_slot: int, to_slot: int) -> bool:
	if from_slot < 0 or from_slot >= wheel_slot_count():
		return false
	if to_slot < 0 or to_slot >= wheel_slot_count():
		return false
	if from_slot == to_slot:
		return true
	var tmp = equipped_abilities[from_slot]
	equipped_abilities[from_slot] = equipped_abilities[to_slot]
	equipped_abilities[to_slot] = tmp
	# Passive entries are keyed by slot index, so a move can change which slot a
	# passive occupies — rebuild so the basket matches the wheel.
	_refresh_passives_after_wheel_change()
	changed.emit()
	save_game()
	return true

## Size equipped_abilities to the current wheel_slot_count() (base + Overmind bonus).
## GROWS to the target, but only SHRINKS by dropping TRAILING EMPTY slots — so an
## equipped ability is never silently deleted if the count drops (e.g. AbilityDB not
## ready yet at cold boot, or a respec removed Overmind). The deferred post-load sync
## re-runs this once AbilityDB is available to restore any bonus slots.
func _normalize_wheel() -> void:
	for i in equipped_abilities.size():
		equipped_abilities[i] = str(equipped_abilities[i])
	var target := wheel_slot_count()
	while equipped_abilities.size() < target:
		equipped_abilities.append("")
	while equipped_abilities.size() > target and str(equipped_abilities[equipped_abilities.size() - 1]) == "":
		equipped_abilities.remove_at(equipped_abilities.size() - 1)


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
	_rebuild_crown_basket()
	_rebuild_derived_basket()
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
	_rebuild_crown_basket()
	_rebuild_derived_basket()
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
		"node_abilities": node_abilities,
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

	var na = parsed.get("node_abilities", {})
	node_abilities = {}
	if typeof(na) == TYPE_DICTIONARY:
		for key in na.keys():
			node_abilities[str(key)] = str(na[key])

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
	for def_id in ["claw", "scour"]:
		if not unlocked_abilities.has(def_id):
			unlocked_abilities.append(def_id)

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
	node_abilities = {}
	attribute_points = 5
	attribute_allocations = {}
	unlocked_abilities = ["claw", "scour"]
	equipped_abilities = ["claw", "scour", "", "", "", "", "", "", "", ""]
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
	_rebuild_crown_basket()
	_rebuild_derived_basket()
	body.init_vitals()
	changed.emit()
	save_game()


## Add XP only (no money/items) and re-derive the level. Handy for scripted xp.
func gain_xp(xp_amt: int) -> void:
	xp += xp_amt
	_apply_xp_level()
	_rebuild_crown_basket()
	_rebuild_derived_basket()
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
