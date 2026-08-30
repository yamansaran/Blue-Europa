extends Resource
class_name Campaign
## ============================================================================
## CAMPAIGN  —  one modular campaign in the world-map graph
## ============================================================================
## A campaign is a self-contained MODULE. Everything a campaign IS lives in its
## own module file (scenes/campaigns/modules/<id>/<id>.gd): its identity, its
## place on the map, where it leads, its SHOP STOCK, its own ordered list of
## campaign FIGHTS and its own list of TRAINING FIGHTS. This resource is just
## the container those modules fill in, and CampaignDB is the registry that
## holds them all.
##
## THIS FILE HOLDS NO CONTENT. Reusable fight sets (the shared "ice" set, the
## enemy specs, the loot tables) live in CampaignFights (campaign_fights.gd) so
## a module can either call one of those builders or hand-build its own array.
## Characters are NOT defined here either — a fight's enemy specs just NAME a
## character module in scenes/characters/units/ (see CHARACTER_PRIMER).
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
## Ids of the campaign(s) this one leads to. 0 = map end, 1 = a single onward
## step, >1 = a fork the player picks between. Either way the player confirms it
## on the post-boss popup; nothing advances automatically.
var next_ids: Array = []

# --- content ----------------------------------------------------------------
## This campaign's ordered campaign battles. Each is a plain fight spec:
##   { "id", "name", "is_boss":bool, "enemies":[spec...], "loot_table":{...} }
## Filled by the module's fights().
var fights: Array = []
## This campaign's training fights, available from its igloo. SAME fight spec
## shape as `fights`. Filled by the module's training_fights().
var training_pool: Array = []
## Clickable objects on this campaign's overworld. Buttons can be placed
## differently per campaign. Each: { "name", "rect":Rect2, "action" }.
var overworld_objects: Array = []
## The items this campaign's SHOP sells: a list of Item ids (Strings) that exist
## in ItemDB. Set per-module; the shop screen reads this from the current
## campaign. Empty -> the shop shows nothing for this campaign.
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

func training_count() -> int:
	return training_pool.size()

func training_at(i: int) -> Dictionary:
	if i < 0 or i >= training_pool.size():
		return {}
	return training_pool[i]

## The shop stock as a clean Array of String ids (defensive copy).
func shop_stock_ids() -> Array:
	var out := []
	for v in shop_stock:
		out.append(str(v))
	return out

# ---------------------------------------------------------------------------
# Construction  (what every module's build() starts from)
# ---------------------------------------------------------------------------
## Makes an EMPTY campaign shell: identity, map placement, links and the default
## overworld layout. It deliberately sets NO fights, NO training fights and NO
## shop stock — the module supplies those, so a campaign's content never comes
## from somewhere the module's author can't see.
static func make(p_id: String, p_name: String, p_scene: String,
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
	c.fights = []
	c.training_pool = []
	c.shop_stock = []
	return c

# ---------------------------------------------------------------------------
# Default overworld layout (a module can replace c.overworld_objects wholesale)
# ---------------------------------------------------------------------------
static func default_objects() -> Array:
	return [
		{"name": "shop",     "rect": Rect2(180, 270, 160, 160),  "action": "shop"},
		{"name": "training", "rect": Rect2(688, 270, 160, 160),  "action": "training"},
		{"name": "campaign", "rect": Rect2(1060, 240, 360, 220), "action": "campaign"},
	]
