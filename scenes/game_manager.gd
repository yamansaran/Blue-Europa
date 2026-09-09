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

# ---------------------------------------------------------------------------
# DEBUG MASTER SWITCH
# ---------------------------------------------------------------------------
## One flag that every debug-only feature in the game obeys. When false, none of
## them are built at all (no button, no panel, no entry point) — the game shows
## only the real player-facing UI.
##
## Currently gated by this flag:
##   - shell toolbar: the "CS" Creation Studio button
##   - shell toolbar: the World Map button (jump to any campaign)
##   - shell toolbar: the Save button's SAVE-WIPING behaviour (with the flag off
##     the Save button performs a normal Character.save_game())
##   - combat: the training-fight "DEBUG" button + dummy stat panel
##   - combat: the floating COMBAT LOG terminal (CombatLog) — one line per
##     ability any unit resolves. EVERY fight, not just the training one.
##   - combat: the unit-AI decision ledger (AITurn) and the AI primitive
##     self-test run at battle start (AIDebug)
##   - abilities screen: the skill-tree node-UID readout
##   - overworld: the "DUMMY" button floating over the IGLOO — the unkillable
##     practice dummy, bypassing the campaign's rolled training pool
##     (go_to_training_dummy)
##   - overworld: the "FIGHT ▾" box floating over the EXPANSE — a picker that sets
##     which campaign fight is next, i.e. edits progress through the current zone
##     (CampaignDB.debug_set_fight_index, itself flag-gated a second time)
##
## Anything debug-only added from here on should check GameManager.is_debug()
## before it builds itself.
var debug_enabled: bool = true

func is_debug() -> bool:
	return debug_enabled

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
## The overworld shown is the CURRENT campaign's own overworld scene. Nothing is
## advanced on the way in: a finished campaign stays finished until the player
## confirms the move on the overworld's own popup, whether it offers one way on
## or several.
func go_to_overworld() -> void:
	_show_in_shell(current_overworld_path())

## res:// path of the current campaign's overworld scene (legacy fallback if the
## campaign system is somehow unavailable).
func current_overworld_path() -> String:
	if typeof(CampaignDB) != TYPE_NIL:
		var c = CampaignDB.get_current()
		if c != null and c.overworld_scene != "":
			return c.overworld_scene
	return SCENE_OVERWORLD

## DEBUG-only screen (jump to any campaign). Refuses to open with the debug flag
## off, so the shell's hidden World Map button isn't the only thing guarding it.
func go_to_campaign_map() -> void:
	if not is_debug():
		return
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
## THE TRAINING FIGHT. No longer a fixed practice dummy: the current campaign owns a
## training POOL, and this ROLLS one fight out of it — a weighted pick from the
## entries whose progress gate contains the player's position in the campaign, so
## the SELECTION moves as the zone is cleared (Campaign.training_roll).
##
## A training fight is staged exactly like a campaign fight — same spec shape, same
## enemies / allies / loot keys — with ONE difference: `is_campaign` stays FALSE, so
## winning never reaches CampaignDB.record_fight_win and training can never advance
## the campaign, however real the fight is.
##
## FALLBACK: a campaign with no pool (or a roll that somehow comes back empty) drops
## through to the bare dummy, so training is never a dead button.
func go_to_training() -> void:
	var fight: Dictionary = {}
	if typeof(CampaignDB) != TYPE_NIL:
		fight = CampaignDB.training_fight()
	if fight.is_empty():
		go_to_training_dummy()
		return
	_stage_fight(fight, false)

## DEBUG-only entry point: the practice dummy, whatever the campaign's training pool
## says. Reached by the small button over the igloo (campaign_overworld.gd), and used
## as the fallback above. Worth keeping precisely because a real fight is no use for
## exercising a stat edit or a new buff — which is what the dummy is for.
func go_to_training_dummy() -> void:
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
	_stage_fight(fight, true)

## Stage ONE fight spec into BattleState and enter combat. Shared by the campaign
## battle and the training roll, because a training fight IS a fight spec — the only
## thing that differs is `is_campaign`, which is what decides whether a win advances
## the campaign. Reads `allies` as well as `enemies` (a fight can hand the player
## temporary companions — c1's hunters), and takes the background from the campaign.
func _stage_fight(fight: Dictionary, is_campaign: bool) -> void:
	active_shell = null
	BattleState.clear()
	BattleState.clear_result()
	BattleState.is_campaign = is_campaign
	BattleState.battle_id = str(fight.get("id", "campaign_fight" if is_campaign else "training"))
	var enemies = fight.get("enemies", [])
	if typeof(enemies) == TYPE_ARRAY:
		BattleState.enemies = (enemies as Array).duplicate(true)
	var allies = fight.get("allies", [])
	if typeof(allies) == TYPE_ARRAY:
		BattleState.allies = (allies as Array).duplicate(true)
	var lt = fight.get("loot_table", null)
	if typeof(lt) == TYPE_DICTIONARY:
		BattleState.loot_table = (lt as Dictionary).duplicate(true)
	if typeof(CampaignDB) != TYPE_NIL:
		var camp = CampaignDB.get_current()
		if camp != null:
			BattleState.background_color = camp.background_color
	get_tree().change_scene_to_file(SCENE_COMBAT)
