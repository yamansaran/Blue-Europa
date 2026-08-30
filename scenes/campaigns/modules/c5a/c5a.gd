extends RefCounted
class_name CampaignModuleC5A
## ============================================================================
## CAMPAIGN "c5a"  —  Churchill   (level 5, path A)
## ============================================================================
## A STANDALONE campaign block. Everything this campaign is lives in this file:
## its identity, its place on the world map, where it leads, its shop stock, its
## own ordered list of campaign FIGHTS and its own list of TRAINING FIGHTS.
## Retuning this campaign means editing this file and nothing else.
##
## The one thing that is NOT here is the creatures: a fight's enemy specs name a
## character MODULE in scenes/characters/units/ (CHARACTER_PRIMER), so the same
## creature can be reused by any campaign without being copied into it.
## ----------------------------------------------------------------------------

const ID           := "c5a"
const DISPLAY_NAME := "Churchill"
const OVERWORLD    := "res://scenes/campaigns/modules/c5a/overworld_c5a.tscn"
const MAP_POSITION := Vector2(0.5000, 0.18)
const BG_COLOR     := Color(0.16, 0.41, 0.78)
## LEVEL 5 is the map's one mid-run choice: Churchill opens onto Boston or Oslo.
const NEXT_IDS     := ["c6a", "c6b"]
## This campaign's SHOP: Item ids from scenes/items/item_data/ (ITEM_PRIMER).
const SHOP_STOCK   := ["ember_ring", "lucky_charm", "padded_greaves", "minor_potion"]

static func build() -> Campaign:
	var c := Campaign.make(ID, DISPLAY_NAME, OVERWORLD, NEXT_IDS, MAP_POSITION, BG_COLOR)
	c.fights        = fights()
	c.training_pool = training_fights()
	c.shop_stock    = SHOP_STOCK.duplicate()
	c.extra         = {"biome": "tundra", "level": 5, "path": "a"}
	return c

## THIS CAMPAIGN'S FIGHTS — the ordered campaign battles, each with its own
## characters and its own loot table. Right now it borrows the shared "ice" set
## so every campaign is still identical; to make this one bespoke, replace the
## body with a hand-built array (see CampaignFights for the shapes):
##     return [
##         {"id": "%s_f1" % ID, "name": "Ambush", "is_boss": false,
##          "enemies": [{"character": "fire_imp"}, {"character": "fire_imp", "level": 2}],
##          "loot_table": CampaignFights.normal_loot()},
##     ]
static func fights() -> Array:
	return CampaignFights.ice_fights(ID)

## THIS CAMPAIGN'S TRAINING FIGHTS — same spec shape as the campaign fights, run
## from this campaign's igloo. Currently the shared dummy.
static func training_fights() -> Array:
	return CampaignFights.ice_training(ID)
