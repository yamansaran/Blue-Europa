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
## shape as `fights` PLUS three optional keys that turn the list into a weighted,
## progress-gated SELECTION rather than a fixed menu (see training_roll below):
##   "weight"      float  relative chance within the current selection (default 1.0)
##   "min_cleared" int    earliest campaign fight_index this entry appears at (default 0)
##   "max_cleared" int    last fight_index it appears at (default: no upper limit)
## An entry that sets none of the three is simply always in the pool at weight 1,
## which is exactly the old behaviour — so a pool of one dummy is unchanged.
## Filled by the module's training_fights().
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

# ---------------------------------------------------------------------------
# The training pool  —  a weighted selection that moves with the player
# ---------------------------------------------------------------------------
## THE SELECTION at a given point in the campaign: every training entry whose
## min_cleared / max_cleared gate contains `cleared` (the campaign's fight_index,
## i.e. how many of its fights are done). An ungated entry is in every selection.
##
## WHY A GATE RATHER THAN ONE POOL PER TIER: the pool is authored as a flat list and
## each entry says when it is available, so a zone whose training changes twice is
## still ONE array in ONE function, and an entry that spans two tiers is written
## once rather than copied into both.
func training_available(cleared: int) -> Array:
	var out := []
	for e in training_pool:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		if cleared < int(e.get("min_cleared", 0)):
			continue
		if e.has("max_cleared") and cleared > int(e["max_cleared"]):
			continue
		out.append(e)
	return out

## ROLL one training fight out of the current selection, weighted. Returns a deep
## COPY (so the caller can hand it straight to BattleState and nothing can mutate
## the campaign's own data), or {} when the selection is empty.
##
## Weights are relative, not percentages — [0.2, 0.4, 0.4] and [1, 2, 2] roll the
## same. A non-positive weight is treated as 0 and can never come up; if every
## weight in the selection is 0 the pick falls back to uniform, so a typo produces
## a fight rather than an empty igloo.
func training_roll(cleared: int) -> Dictionary:
	var pool := training_available(cleared)
	if pool.is_empty():
		return {}
	var total := 0.0
	for e in pool:
		total += maxf(0.0, float(e.get("weight", 1.0)))
	if total <= 0.0:
		return (pool[randi() % pool.size()] as Dictionary).duplicate(true)
	var roll := randf() * total
	for e in pool:
		roll -= maxf(0.0, float(e.get("weight", 1.0)))
		if roll <= 0.0:
			return (e as Dictionary).duplicate(true)
	return (pool[pool.size() - 1] as Dictionary).duplicate(true)

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
