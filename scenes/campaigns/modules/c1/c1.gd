extends RefCounted
class_name CampaignModuleC1
## ============================================================================
## CAMPAIGN "c1"  —  The Arctic   (level 1)
## ============================================================================
## A STANDALONE campaign block. Everything this campaign is lives in this file:
## its identity, its place on the world map, where it leads, its shop stock, its
## own ordered list of campaign FIGHTS and its own TRAINING POOL.
## Retuning this campaign means editing this file and nothing else.
##
## The one thing that is NOT here is the creatures: a fight's enemy specs name a
## character MODULE in scenes/characters/units/ (CHARACTER_PRIMER), so the same
## creature can be reused by any campaign without being copied into it.
##
## THE FIRST CAMPAIGN WITH ITS OWN CONTENT. Every other node on the map still calls
## CampaignFights.ice_fights() and is deliberately identical; c1 has been replaced
## with the seven-fight arctic ladder from the Menagerie. The shared ice set is
## untouched and ice_spirit / large_ice_spirit keep their modules — this zone simply
## stopped needing them.
## ----------------------------------------------------------------------------

const ID           := "c1"
const DISPLAY_NAME := "The Arctic"
const OVERWORLD    := "res://scenes/campaigns/modules/c1/overworld_c1.tscn"
const MAP_POSITION := Vector2(0.0500, 0.50)
const BG_COLOR     := Color(0.10, 0.55, 0.75)
## The map's OPENING split: three paths. You commit to the one you pick —
## from here on each campaign leads onward one step at a time.
const NEXT_IDS     := ["c2a", "c2b", "c2c"]
## This campaign's SHOP: Item ids from scenes/items/item_data/ (ITEM_PRIMER).
const SHOP_STOCK   := ["iron_sword", "leather_cap", "padded_greaves", "iron_gauntlets", "minor_potion"]

static func build() -> Campaign:
	var c := Campaign.make(ID, DISPLAY_NAME, OVERWORLD, NEXT_IDS, MAP_POSITION, BG_COLOR)
	c.fights        = fights()
	c.training_pool = training_fights()
	c.shop_stock    = SHOP_STOCK.duplicate()
	c.extra         = {"biome": "coast", "level": 1}
	return c

# ============================================================================
# THE LADDER  —  six fights and a boss
# ============================================================================
## Each fight introduces exactly ONE new thing, and the order is the teaching order:
##   1  that an enemy takes a turn at all
##   2  that the same creature comes at two strengths, and that it can buff itself
##   3  ELEMENTS — two creatures with opposite resistance profiles, side by side
##   4  that the thing in front of you has a mind, and this one hasn't got a good one
##   5  ALLIES, and that allies split incoming fire
##   6  TARGET PRIORITY — a wall, and the reason the wall keeps standing
##   7  a CLOCK — a boss that heals as it eats and gets angrier as it dies
##
## EVERY FIGHT FITS THE FORMATION GRID. Each side seats five (BattleGrid ROWS 5,
## back column, centre-out), and the largest here are fight 4's five Old Ice and
## fight 5's three-strong party. Nothing overflows into the FRONT column, which
## stays reserved for summons.
static func fights() -> Array:
	return [
		# --- 1 --------------------------------------------------------------
		# One creature, one attack, and a self-buff it is forbidden from using on
		# its first turn (frenzy.tres carries ai_not_before_turn = 2).
		{"id": "%s_f1" % ID, "name": "Wreckage", "is_boss": false,
			"enemies": [ {"character": "shambling_corpse"} ],
			# Dialogue lives in scenes/dialogue/zones/c1_dialogue.gd, keyed by this id.
			"loot_table": _loot(23, 10)},

		# --- 2 --------------------------------------------------------------
		# RULE ONE, in practice: a variant is a SPEC, not a module. The second corpse
		# is the same file with a level, a vitality and a Vigor override. NB the order
		# apply_spec_overrides runs in — `stats` first, then `max_hp` — is what lets
		# max_hp back-solve against the RAISED vitality rather than the module's.
		{"id": "%s_f2" % ID, "name": "The Cabin Line", "is_boss": false,
			"enemies": [
			{"character": "shambling_corpse"},
			{"character": "shambling_corpse", "level": 2,
				"stats": {"vitality": 4.0, "vigor": 12.0}, "max_hp": 72.0},
			],
			"loot_table": _loot(25, 14)},

		# --- 3 --------------------------------------------------------------
		# The lesson of the zone. Frozen Corpse: 75 physical, ZERO everything else.
		# Unknown Entity: the inverse. One fight, two answers to the same question.
		{"id": "%s_f3" % ID, "name": "White Expanse", "is_boss": false,
			"enemies": [
			{"character": "frozen_corpse", "level": 2},
			{"character": "unknown_entity", "level": 2},
			],
			"loot_table": _loot(27, 18)},

		# --- 4 --------------------------------------------------------------
		# THE FIGHT THAT IS FINISHED TODAY. `erratic` is uniform random across the
		# legal set, which is exactly what the AI's Phase 0 does — so this encounter
		# is correct right now while the rest of the zone waits on the scoring layers.
		{"id": "%s_f4" % ID, "name": "The Drift", "is_boss": false,
			"enemies": [
			{"character": "unknown_entity", "level": 1, "max_hp": 62.0},
			{"character": "unknown_entity", "level": 1, "max_hp": 62.0},
			{"character": "unknown_entity", "level": 2},
			],
			"loot_table": _loot(28, 22)},

		# --- 5 --------------------------------------------------------------
		# THE ALLY TUTORIAL, and the zone's only fight balanced against the PARTY
		# rather than against the player (the arithmetic is in old_ice.gd). Two
		# hunters at magnetism 110 against the player's 100 pull roughly two thirds
		# of the incoming fire. Cut them and this has to be rebuilt from three Old
		# Ice, not five.
		#
		# `allies` is read by GameManager._stage_fight into BattleState.allies — a
		# fight spec key nothing used before this one existed.
		{"id": "%s_f5" % ID, "name": "The Old Ice", "is_boss": false,
			"enemies": [
			{"character": "old_ice", "level": 3},
			{"character": "old_ice", "level": 3},
			{"character": "old_ice", "level": 3},
			{"character": "old_ice", "level": 3},
			{"character": "old_ice", "level": 3},
			],
			"allies": [
			{"character": "inuit_hunter", "name": "Hunter", "level": 3, "figure": "male"},
			{"character": "inuit_hunter", "name": "Hunter", "level": 3, "figure": "female"},
			],
			"loot_table": _loot(30, 28)},

		# --- 6 --------------------------------------------------------------
		# THE ONLY FIGHT IN THE ZONE YOU CAN LOSE, and that is the design. Read flat
		# the margin is 1.07 — a loss once a single roll goes badly. Kill the
		# Chaplain first and it becomes 1.37. It is placed last before the boss on
		# purpose: late enough that the player has the tools, early enough to matter.
		{"id": "%s_f6" % ID, "name": "The Chaplain", "is_boss": false,
			"enemies": [
			{"character": "strapped_passenger"},
			{"character": "shambling_guard"},
			{"character": "shambling_guard"},
			],
			"loot_table": _loot(33, 34)},

		# --- BOSS -----------------------------------------------------------
		{"id": "%s_boss" % ID, "name": "The Scavenger", "is_boss": true,
			"enemies": [ {"character": "the_scavenger"} ],
			"loot_table": _loot(260, 90)},
	]

# ============================================================================
# THE TRAINING POOL  —  a weighted selection, rolled fresh each visit
# ============================================================================
## The igloo no longer runs a fixed practice dummy: GameManager.go_to_training ROLLS
## one fight out of this pool (Campaign.training_roll), weighted, and re-rolls every
## time the player walks in.
##
## ZONE 1 HAS EXACTLY ONE SELECTION, so no entry sets a progress gate and all three
## are always available. To add a SECOND selection later, copy the block and give the
## old entries `"max_cleared": N` and the new ones `"min_cleared": N + 1` — the pool
## stays one flat array in one function however many tiers it grows.
##
## Training pays XP but NO money, and never advances the campaign: go_to_training
## leaves BattleState.is_campaign false, so a win cannot reach record_fight_win.
## (Victory.gd grants rewards regardless of is_campaign, so a training win does bank
## its XP — only the campaign counter is gated.)
##
## ALL THREE PAY 13 — they are TIER 1 of the curve's two zone-1 training tiers. The
## 20-XP tier 2 is not built yet: it wants three more entries at `"min_cleared": N`
## with `"max_cleared": N - 1` added to these three.
##
## THE PRACTICE DUMMY IS NOT IN HERE. It is reachable from the small DUMMY button
## floating over the igloo under the debug flag — a rolled fight is no use for
## exercising a stat edit or a new buff, which is what the dummy is for.
static func training_fights() -> Array:
	return [
		# 20% — the toxic pair. The lightest of the three on paper and the one most
		# likely to still be ticking after it is over.
		{"id": "%s_train_old_ice" % ID, "name": "Two of the Old Ice",
			"is_boss": false, "weight": 0.2,
			"enemies": [
			{"character": "old_ice", "level": 3},
			{"character": "old_ice", "level": 3},
			],
			"loot_table": _loot(13, 0)},

		# 40% — the straightforward one.
		{"id": "%s_train_corpses" % ID, "name": "Two Shambling Corpses",
			"is_boss": false, "weight": 0.4,
			"enemies": [
			{"character": "shambling_corpse", "level": 2},
			{"character": "shambling_corpse", "level": 2},
			],
			"loot_table": _loot(13, 0)},

		# 40% — a fast thing you cannot predict standing behind a slow thing you
		# cannot ignore. The most useful of the three to practise against.
		{"id": "%s_train_mixed" % ID, "name": "Unknown Entity and Guard",
			"is_boss": false, "weight": 0.4,
			"enemies": [
			{"character": "unknown_entity", "level": 1, "max_hp": 62.0},
			{"character": "shambling_guard", "level": 2},
			],
			"loot_table": _loot(13, 0)},
	]

# ============================================================================
# Loot
# ============================================================================
## Money and XP for one fight. Both are FLAT (min == max) rather than a range,
## because zone one's XP figures come straight off the XP-curve document and a roll
## would blur them. RETUNED for the widened curve (LevelTable total 2,160,000): the
## anchor did not move, so zone 1 barely moved either — its band went 475 -> 525.
## One "unit" (one level) = 131.25, and the zone spends it like this:
##     ladder   23 / 25 / 27 / 28 / 30 / 33        ->  166   (0.18-0.25 units each)
##     boss     260                                        (2.00 units — zone 1 has
##                                                           no miniboss, so the boss
##                                                           carries both roles)
##     training 13 x 3                             ->   39
##                                                     ----
##                                                      465, level 5 at 525
## The ladder plus the boss is 426, so a player who never trains reaches the boss at
## level 3 and clears the zone at 4 (cutoff 360) — training is what closes the gap,
## which is the whole point of the pool being repeatable. Adding the curve's unbuilt
## 20-XP tier 2 (3 x 20 = 60) lands the zone on 525, i.e. exactly the band.
##
## NOTE — f1 previously paid 100, against the 21 its own comment block documented. It
## is 23 here (the curve value for the first rung). If the 100 was deliberate — a
## first-fight bump to get the player onto the bar immediately — put it back; nothing
## else in this table depends on it, the zone just overshoots its band by ~77.
##
## They are a small fraction of CampaignFights.normal_loot(), which is priced for
## ZONE 2 — one fight of the shared table would carry a new player most of a level.
##
## No item drops: `loot_table.items` is authored but inert (drops are not granted to
## the bag yet), and the shipped placeholder ids do not exist in ItemDB. Money is a
## property of the FIGHT rather than of the enemies in it, so per-enemy drops would
## need a change to BattleState.roll_loot.
static func _loot(xp: int, money: int) -> Dictionary:
	return {
		"money_min": money, "money_max": money,
		"xp_min": xp, "xp_max": xp,
		"items": [],
	}
