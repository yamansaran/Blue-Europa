extends Node
# Autoload singleton (registered in project.godot as "GameManager").

const SCENE_SHELL     := "res://scenes/shell.tscn"
const SCENE_OVERWORLD := "res://scenes/overworld.tscn"
const SCENE_SHOP      := "res://scenes/shop/shop.tscn"
const SCENE_TRAINING  := "res://scenes/training/training.tscn"
const SCENE_COMBAT    := "res://scenes/combat/combat.tscn"
const SCENE_VICTORY   := "res://scenes/victory/victory.tscn"
const SCENE_INVENTORY    := "res://scenes/inventory/inventory.tscn"
const SCENE_ABILITIES    := "res://scenes/abilities/abilities.tscn"
const SCENE_OPTIONS      := "res://scenes/options/options.tscn"
const SCENE_ACHIEVEMENTS := "res://scenes/achievements/achievements.tscn"
const SCENE_CAMPAIGN_MAP := "res://scenes/campaigns/campaign_map.tscn"

var active_shell: Node = null

# When set, the next shell boot loads this content instead of the overworld.
var pending_content_path: String = ""

var campaign_index: int = 0   # LEGACY: campaign progression now lives in CampaignDB
var completed: Dictionary = {}

func mark_completed(id: String) -> void:
	completed[id] = true

func is_completed(id: String) -> bool:
	return completed.get(id, false)

# --- legacy player stats / leveling (unused by the new Character-based flow) --
var level: int = 1
var xp: int = 0
var xp_to_next: int = 100
var skill_points: int = 0

var stats: Dictionary = {
	"max_hp": 100,
	"attack": 10,
	"defense": 5,
}

func gain_xp(amount: int) -> void:
	xp += amount
	while xp >= xp_to_next:
		xp -= xp_to_next
		_level_up()

func _level_up() -> void:
	level += 1
	skill_points += 1
	xp_to_next = int(xp_to_next * 1.25)
	stats["max_hp"] += 10
	stats["attack"] += 2
	stats["defense"] += 1

# --- legacy inventory --------------------------------------------------------
var inventory: Dictionary = {}
var gold: int = 0

func add_item(item_id: String, qty: int = 1) -> void:
	inventory[item_id] = inventory.get(item_id, 0) + qty

func remove_item(item_id: String, qty: int = 1) -> bool:
	var have: int = inventory.get(item_id, 0)
	if have < qty:
		return false
	inventory[item_id] = have - qty
	if inventory[item_id] <= 0:
		inventory.erase(item_id)
	return true

var skills_unlocked: Dictionary = {}

func can_unlock_skill(_skill_id: String) -> bool:
	return skill_points > 0

func unlock_skill(skill_id: String) -> bool:
	if skills_unlocked.get(skill_id, false):
		return false
	if not can_unlock_skill(skill_id):
		return false
	skills_unlocked[skill_id] = true
	skill_points -= 1
	return true

# ---------------------------------------------------------------------------
# Scene routing
# ---------------------------------------------------------------------------
func go_to_shell() -> void:
	active_shell = null
	get_tree().change_scene_to_file(SCENE_SHELL)

func _show_in_shell(scene_path: String) -> void:
	if active_shell != null and is_instance_valid(active_shell):
		active_shell.load_content(scene_path)
	else:
		get_tree().change_scene_to_file(SCENE_SHELL)

# --- shell-content destinations ---
## The overworld shown is the CURRENT campaign's own overworld scene. Before
## loading it, resolve any pending LINEAR advance (a finished campaign with a
## single next campaign moves on automatically; forks are left for the player to
## choose on the overworld itself).
func go_to_overworld() -> void:
	if typeof(CampaignDB) != TYPE_NIL:
		CampaignDB.auto_advance_if_linear()
	_show_in_shell(current_overworld_path())

## res:// path of the current campaign's overworld scene (legacy fallback if the
## campaign system is somehow unavailable).
func current_overworld_path() -> String:
	if typeof(CampaignDB) != TYPE_NIL:
		var c = CampaignDB.get_current()
		if c != null and c.overworld_scene != "":
			return c.overworld_scene
	return SCENE_OVERWORLD

func go_to_campaign_map() -> void:
	_show_in_shell(SCENE_CAMPAIGN_MAP)

func go_to_shop() -> void:
	_show_in_shell(SCENE_SHOP)

func go_to_inventory() -> void:
	_show_in_shell(SCENE_INVENTORY)

func go_to_abilities() -> void:
	_show_in_shell(SCENE_ABILITIES)

func go_to_options() -> void:
	_show_in_shell(SCENE_OPTIONS)

func go_to_achievements() -> void:
	_show_in_shell(SCENE_ACHIEVEMENTS)

# Boot the shell straight into the victory screen (keeps the toolbar).
func go_to_victory() -> void:
	active_shell = null
	pending_content_path = SCENE_VICTORY
	get_tree().change_scene_to_file(SCENE_SHELL)

# --- full-screen destinations (leave the shell) ---
func go_to_training() -> void:
	active_shell = null
	BattleState.clear()
	BattleState.clear_result()
	BattleState.battle_id = "training"
	BattleState.is_campaign = false
	# empty enemies => default Training Dummy (9999 HP, unkillable practice)
	get_tree().change_scene_to_file(SCENE_COMBAT)

## Stage and start the CURRENT campaign's next fight (from CampaignDB). If the
## campaign is already finished there is no fight to run — bounce to the
## overworld, where the fork chooser / completion note is handled.
func go_to_campaign_battle() -> void:
	if typeof(CampaignDB) == TYPE_NIL:
		return
	var fight: Dictionary = CampaignDB.current_fight()
	if fight.is_empty():
		go_to_overworld()
		return
	active_shell = null
	BattleState.clear()
	BattleState.clear_result()
	BattleState.is_campaign = true
	BattleState.battle_id = str(fight.get("id", "campaign_fight"))
	var enemies = fight.get("enemies", [])
	if typeof(enemies) == TYPE_ARRAY:
		BattleState.enemies = (enemies as Array).duplicate(true)
	var lt = fight.get("loot_table", null)
	if typeof(lt) == TYPE_DICTIONARY:
		BattleState.loot_table = (lt as Dictionary).duplicate(true)
	var camp = CampaignDB.get_current()
	if camp != null:
		BattleState.background_color = camp.background_color
	get_tree().change_scene_to_file(SCENE_COMBAT)
