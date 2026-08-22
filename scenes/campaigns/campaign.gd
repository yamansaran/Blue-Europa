extends Resource
class_name Campaign
## ============================================================================
## CAMPAIGN  —  one modular campaign in the world-map graph
## ============================================================================
## A campaign is a self-contained module: an ordered list of fights, a training
## pool, links to the next campaign(s) in the map, its OWN overworld scene, its
## SHOP STOCK, plus a free-form `extra` dict for future per-campaign data.
##
## Campaigns are built in code by their module scripts
## (scenes/campaigns/modules/<id>/<id>.gd) and registered in CampaignDB. The
## module can either call Campaign.ice_campaign(...) for the standard test layout
## (5 ice sprites in a row + one large ice sprite boss) or hand-build `fights`
## itself for a bespoke campaign later. The shop that campaign shows is whatever
## the module puts in `shop_stock` (a list of Item ids from ItemDB).
## ----------------------------------------------------------------------------

# --- identity / presentation ------------------------------------------------
@export var id: String = ""
@export var display_name: String = ""
## res:// path to THIS campaign's overworld scene (loaded when it is current).
@export var overworld_scene: String = ""
@export var background_color: Color = Color(0.10, 0.55, 0.75)
## Normalised (0..1) position of this node on the world-map graph.
@export var map_position: Vector2 = Vector2(0.5, 0.5)

# --- graph links ------------------------------------------------------------
## Ids of the campaign(s) this one leads to. 0 = end, 1 = linear, >1 = fork.
var next_ids: Array = []

# --- content ----------------------------------------------------------------
## Ordered fights; each is a plain spec Dictionary (see the fight builders).
##   { "id", "name", "is_boss":bool, "enemies":[spec...], "loot_table":{...} }
var fights: Array = []
## Training fights available from this campaign's igloo (dummy for now).
var training_pool: Array = []
## Clickable objects on this campaign's overworld. Buttons can be placed
## differently per campaign. Each: { "name", "rect":Rect2, "action" }.
var overworld_objects: Array = []
## The items this campaign's SHOP sells: a list of Item ids (Strings) that exist
## in ItemDB. Set per-module in <id>.gd; the shop screen reads this from the
## current campaign. Empty -> the shop shows nothing for this campaign.
var shop_stock: Array = []
## Free-form room for future per-campaign data (story flags, rewards, etc.).
var extra: Dictionary = {}

# ---------------------------------------------------------------------------
# Queries
# ---------------------------------------------------------------------------
func fight_count() -> int:
	return fights.size()

func fight_at(i: int) -> Dictionary:
	if i < 0 or i >= fights.size():
		return {}
	return fights[i]

## The shop stock as a clean Array of String ids (defensive copy).
func shop_stock_ids() -> Array:
	var out := []
	for v in shop_stock:
		out.append(str(v))
	return out

# ---------------------------------------------------------------------------
# Default overworld layout (matches the old single overworld placement)
# ---------------------------------------------------------------------------
static func default_objects() -> Array:
	return [
		{"name": "shop",     "rect": Rect2(180, 270, 160, 160),  "action": "shop"},
		{"name": "training", "rect": Rect2(688, 270, 160, 160),  "action": "training"},
		{"name": "campaign", "rect": Rect2(1060, 240, 360, 220), "action": "campaign"},
	]

# ---------------------------------------------------------------------------
# Enemy / fight builders  (the standard "ice" content for now)
# ---------------------------------------------------------------------------
## Enemy specs now just NAME a character module (see scenes/characters/units/).
## The creature's stats, colour, size, AI and permanent buffs all live in its
## module file — CharacterRegistry.build() instantiates it. A fight can still add
## per-fight overrides to the returned dict (e.g. {"character":"ice_spirit",
## "level":3, "stats":{"vigor":20}}) and apply_spec_overrides layers them on top.
static func ice_sprite_spec() -> Dictionary:
	return { "character": "ice_spirit" }

## The boss: its own module (LargeIceSpirit) — the same creature, bigger + tougher.
static func large_ice_sprite_spec() -> Dictionary:
	return { "character": "large_ice_spirit" }

static func normal_loot() -> Dictionary:
	return {
		"money_min": 15, "money_max": 40,
		"xp_min": 50, "xp_max": 80,
		"items": [
			{"id": "frost_shard", "name": "Frost Shard", "chance": 0.8},
			{"id": "sprite_dust", "name": "Sprite Dust", "chance": 0.4},
		],
	}

static func boss_loot() -> Dictionary:
	return {
		"money_min": 80, "money_max": 150,
		"xp_min": 200, "xp_max": 300,
		"items": [
			{"id": "frost_core", "name": "Frost Core", "chance": 1.0},
			{"id": "sprite_dust", "name": "Sprite Dust", "chance": 0.75},
		],
	}

static func dummy_training_pool(p_id: String) -> Array:
	return [
		{
			"id": "%s_dummy" % p_id, "name": "Training Dummy",
			"type": "enemy", "max_hp": 9999, "ai": "none",
		},
	]

# ---------------------------------------------------------------------------
# Standard test campaign: 5 ice sprites in a row + one large ice sprite boss.
# ---------------------------------------------------------------------------
## NOTE: this factory does NOT set shop_stock — each module declares its own so
## the shop's contents live in that campaign's file, not hard-coded in the shop.
static func ice_campaign(p_id: String, p_name: String, p_scene: String,
		p_next: Array, p_map: Vector2,
		p_bg: Color = Color(0.10, 0.55, 0.75)) -> Campaign:
	var c := Campaign.new()
	c.id = p_id
	c.display_name = p_name
	c.overworld_scene = p_scene
	c.next_ids = p_next.duplicate()
	c.map_position = p_map
	c.background_color = p_bg
	c.overworld_objects = default_objects()
	c.training_pool = dummy_training_pool(p_id)

	c.fights = []
	for n in range(1, 6):   # fights 1..5 — one ice sprite each, in a row
		c.fights.append({
			"id": "%s_fight_%d" % [p_id, n],
			"name": "Ice Sprite %d" % n,
			"is_boss": false,
			"enemies": [ ice_sprite_spec() ],
			"loot_table": normal_loot(),
		})
	# fight 6 — the boss
	c.fights.append({
		"id": "%s_boss" % p_id,
		"name": "Large Ice Sprite",
		"is_boss": true,
		"enemies": [ large_ice_sprite_spec() ],
		"loot_table": boss_loot(),
	})
	return c
