extends RefCounted
class_name CampaignModuleC9
## ============================================================================
## CAMPAIGN "c9"  —  Berlin   (level 9)
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

const ID           := "c9"
const DISPLAY_NAME := "Berlin"
const OVERWORLD    := "res://scenes/campaigns/modules/c9/overworld_c9.tscn"
const MAP_POSITION := Vector2(0.9500, 0.50)
const BG_COLOR     := Color(0.24, 0.20, 0.50)
## The FINAL campaign: nothing follows it, so clearing it ends the map.
const NEXT_IDS     := []
## This campaign's SHOP: Item ids from scenes/items/item_data/ (ITEM_PRIMER).
const SHOP_STOCK   := ["ember_ring", "lucky_charm", "oak_shield", "leather_vest", "minor_potion"]

static func build() -> Campaign:
	var c := Campaign.make(ID, DISPLAY_NAME, OVERWORLD, NEXT_IDS, MAP_POSITION, BG_COLOR)
	c.fights        = fights()
	c.training_pool = training_fights()
	c.shop_stock    = SHOP_STOCK.duplicate()
	c.extra         = {"biome": "heartland", "level": 9}
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
