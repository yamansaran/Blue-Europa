extends Node
## BattleState — what the combat engine reads to build a battle, plus the loot
## table for the fight and the rolled result the victory screen displays.

enum Team { PLAYER, ALLY, ENEMY }

# --- battle setup -------------------------------------------------------
var background_path: String = ""
var background_color: Color = Color(0.10, 0.12, 0.16)
var player_spec: Dictionary = {}
var allies: Array = []
var enemies: Array = []
var battle_id: String = ""
var is_campaign: bool = false

# --- loot table (rolled on victory) ------------------------------------
var loot_table: Dictionary = {
	"money_min": 5, "money_max": 15,
	"xp_min": 20, "xp_max": 40,
	"items": [],   # each: {"id":..., "name":..., "chance":0..1}
}

# --- rolled result (read by the victory screen) ------------------------
var result_money: int = 0
var result_xp: int = 0
var result_items: Array = []
var result_party: Array = []

func has_config() -> bool:
	return not player_spec.is_empty() or not allies.is_empty() or not enemies.is_empty()

func clear() -> void:
	background_path = ""
	background_color = Color(0.10, 0.12, 0.16)
	player_spec = {}
	allies = []
	enemies = []
	battle_id = ""
	is_campaign = false
	loot_table = {"money_min": 5, "money_max": 15, "xp_min": 20, "xp_max": 40, "items": []}

func clear_result() -> void:
	result_money = 0
	result_xp = 0
	result_items = []
	result_party = []

func configure(p_player: Dictionary = {}, p_allies: Array = [], p_enemies: Array = [], p_bg_path: String = "") -> void:
	player_spec = p_player
	allies = p_allies
	enemies = p_enemies
	background_path = p_bg_path

func roll_loot() -> Dictionary:
	var money := _rand_range(int(loot_table.get("money_min", 0)), int(loot_table.get("money_max", 0)))
	var xp := _rand_range(int(loot_table.get("xp_min", 0)), int(loot_table.get("xp_max", 0)))
	var items := []
	for it in loot_table.get("items", []):
		if randf() <= float(it.get("chance", 1.0)):
			items.append({"id": str(it.get("id", "")), "name": str(it.get("name", it.get("id", "item")))})
	return {"money": money, "xp": xp, "items": items}

func _rand_range(a: int, b: int) -> int:
	if b < a:
		return a
	return randi_range(a, b)