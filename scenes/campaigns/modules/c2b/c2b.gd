extends RefCounted
class_name CampaignModuleC2B
## ============================================================================
## CAMPAIGN "c2b"  —  Godthaab   (level 2, path B)
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

const ID           := "c2b"
const DISPLAY_NAME := "Godthaab"
const OVERWORLD    := "res://scenes/campaigns/modules/c2b/overworld_c2b.tscn"
const MAP_POSITION := Vector2(0.1625, 0.50)
const BG_COLOR     := Color(0.11, 0.52, 0.78)
## Leads onward one step; the player confirms it on the post-boss popup.
const NEXT_IDS     := ["c3b"]
## This campaign's SHOP: Item ids from scenes/items/item_data/ (ITEM_PRIMER).
const SHOP_STOCK   := ["leather_vest", "swift_boots", "oak_shield", "minor_potion"]

static func build() -> Campaign:
	var c := Campaign.make(ID, DISPLAY_NAME, OVERWORLD, NEXT_IDS, MAP_POSITION, BG_COLOR)
	c.fights        = fights()
	c.training_pool = training_fights()
	c.shop_stock    = SHOP_STOCK.duplicate()
	c.extra         = {"biome": "glacier", "level": 2, "path": "b"}
	return c

## THIS CAMPAIGN'S FIGHTS — the Godthaab ladder (GODTHAAB_BUILD §2.6).
##
## >> EVERY LOOT FIGURE HERE IS A PLACEHOLDER (§2.7), and so is every stat inside
##    every module these specs name. What is AUTHORED is the COMPOSITION and the
##    SEATING — those are the design, and the fights do not work without them.
##
## >> PER-ENEMY MONEY/XP IS STILL MISSING (§1.19). c2b is the first zone with
##    genuinely mixed compositions, so the fight-level loot_table is now actually
##    WRONG rather than merely inelegant: six shambling corpses and a miniboss pay
##    out by the same rule. Left as-is deliberately; it needs CAMPAIGN_PRIMER work.
static func fights() -> Array:
	return [
		# --- 1 · THE WHARF --------------------------------------------------
		# ONE MODULE, TWO SPECS. Spec A is the module as authored (brute + Flurry);
		# spec B overrides `ai` and `abilities` into the chain-carrying plaguebearer.
		# B is a PLAGUEBEARER AND NOT A HEXER ON PURPOSE: Punished and Bruised are
		# only frightening stacked on one victim, and a hexer spreading them would
		# dilute the very mechanic they exist to teach.
		{"id": "%s_f1" % ID, "name": "The Quarantine Pier", "is_boss": false,
			"enemies": [
				{"character": "wharfinger"},
				{"character": "stevedore"},
				{"character": "stevedore", "ai": "plaguebearer",
					"abilities": ["chain_whip", "chain_bash"],
					"stats": {"ai_spite": 4.0}},
			],
			"loot_table": _loot(30, 20)},

		# --- 2 · THE REGISTRY -----------------------------------------------
		# Three guards, one of them the tanky warden spec: a tank whose job is making
		# somebody ELSE unkillable. First sight of Oversight, with room to read it.
		{"id": "%s_f2" % ID, "name": "The Processing Line", "is_boss": false,
			"enemies": [
				{"character": "security_guard"},
				{"character": "security_guard"},
				{"character": "security_guard", "ai": "warden",
					"abilities": ["electrified_baton_bash", "oversight"],
					"stats": {"ai_vigilance": 8.0}},
			],
			"loot_table": _loot(34, 24)},

		# --- 3 · THE REGISTRAR ----------------------------------------------
		# THE FIGHT BACK-ROW PROTECTION EXISTS FOR (§1.3). The Registrar sits at
		# col 0 row 2. The three FRONT seats cover rows 1, 2 and 3 — so all three
		# cover him, and KILLING THE CENTRE ONE IS NOT ENOUGH. That is the lesson,
		# and it is stated by the seating rather than by any ability text.
		{"id": "%s_f3" % ID, "name": "The Registrar", "is_boss": false,
			"enemies": [
				{"character": "registrar", "col": 0, "row": 2},
				{"character": "security_guard", "ai": "warden", "col": 1, "row": 1,
					"abilities": ["electrified_baton_bash", "oversight"],
					"stats": {"ai_vigilance": 8.0}},
				{"character": "enforcer", "col": 1, "row": 2},
				{"character": "security_guard", "ai": "warden", "col": 1, "row": 3,
					"abilities": ["electrified_baton_bash", "oversight"],
					"stats": {"ai_vigilance": 8.0}},
			],
			"loot_table": _loot(40, 30)},

		# --- 4 · THE BACK ROOMS ---------------------------------------------
		# The Rotting Corpse STACKS Infected where c1's Old Ice SPREAD it — same
		# debuff, opposite archetype. The Screaming Corpse is the zone's answer to
		# an armour build, and the first pierced damage-over-time in the game.
		{"id": "%s_f4" % ID, "name": "The Back Rooms", "is_boss": false,
			"enemies": [
				# c1's module, unchanged stats — only the bounty is spec'd, because c1
				# pays by loot_table and a module-level bounty would silently switch
				# every c1 fight that fields a corpse over to bounties.
				{"character": "shambling_corpse", "money": 5, "xp": 8},
				{"character": "shambling_corpse", "money": 5, "xp": 8},
				{"character": "rotting_corpse"},
				{"character": "screaming_corpse"},
			],
			"loot_table": _loot(44, 34)},

		# --- 5 · DEEPER IN --------------------------------------------------
		# SEATED 3 BY 3, EXPLICITLY (the dev's call, and §1.3's overflow warning is
		# why). Left to BattleGrid.assign, five would fill the back column and the
		# sixth would overflow into FRONT centre and start covering the others BY
		# ACCIDENT. Seated deliberately instead, this becomes the fight that TEACHES
		# the rule one fight before fight 3 states it.
		# p1: six LIGHTER corpses (40 hp, Vigor 7) — six single-target kills of the
		# module's 52-hp body is an 18-turn fight at L5 and a margin of 0.7. If the
		# player's kit has AoE this is the fight that shows it off.
		{"id": "%s_f5" % ID, "name": "Deeper In", "is_boss": false,
			"enemies": [
				{"character": "shambling_corpse", "col": 1, "row": 1,
					"max_hp": 40.0, "stats": {"vigor": 7.0, "instinct": 7.0}, "money": 6, "xp": 9},
				{"character": "shambling_corpse", "col": 1, "row": 2,
					"max_hp": 40.0, "stats": {"vigor": 7.0, "instinct": 7.0}, "money": 6, "xp": 9},
				{"character": "shambling_corpse", "col": 1, "row": 3,
					"max_hp": 40.0, "stats": {"vigor": 7.0, "instinct": 7.0}, "money": 6, "xp": 9},
				{"character": "shambling_corpse", "col": 0, "row": 1,
					"max_hp": 40.0, "stats": {"vigor": 7.0, "instinct": 7.0}, "money": 6, "xp": 9},
				{"character": "shambling_corpse", "col": 0, "row": 2,
					"max_hp": 40.0, "stats": {"vigor": 7.0, "instinct": 7.0}, "money": 6, "xp": 9},
				{"character": "shambling_corpse", "col": 0, "row": 3,
					"max_hp": 40.0, "stats": {"vigor": 7.0, "instinct": 7.0}, "money": 6, "xp": 9},
			],
			"loot_table": _loot(48, 38)},

		# --- MINIBOSS · THE BURNING GROUND ----------------------------------
		# A THREE-WAY SQUEEZE ON THREE DIFFERENT LINES OF THE PIPELINE: the Hulk
		# raises damage TAKEN, one corpse cuts healing RECEIVED, the other cuts
		# ACCURACY. None of the three is raw damage.
		{"id": "%s_mini" % ID, "name": "The Burning Ground", "is_boss": false,
			"enemies": [
				{"character": "burning_hulk"},
				{"character": "burning_corpse"},
				{"character": "burning_corpse"},
			],
			"loot_table": _loot(60, 50)},

		# --- 6 · THE SANITATION CORPS ---------------------------------------
		# Brace arrives here: the first enemy that DEFENDS, so WHEN you attack
		# starts to matter. Two technicians sharing a display name, and an engineer
		# who is the wharfinger's mind with a better kit.
		{"id": "%s_f6" % ID, "name": "The Sanitation Corps", "is_boss": false,
			"enemies": [
				{"character": "sanitation_tech_prod"},
				{"character": "sanitation_tech_hook"},
				{"character": "sanitation_engineer"},
			],
			"loot_table": _loot(55, 44)},

		# --- 7 · THE CORDON -------------------------------------------------
		# The zone's hardest non-boss fight, and where the officer cluster lands:
		# a net with no duration, and a shield man whose Protected breaks the moment
		# HE takes health damage. Hit the shield man to free his friend.
		{"id": "%s_f7" % ID, "name": "The Cordon", "is_boss": false,
			"enemies": [
				{"character": "sanitation_tech_prod"},
				{"character": "sanitation_engineer"},
				{"character": "sanitation_officer_net"},
				{"character": "sanitation_officer_shield"},
			],
			"loot_table": _loot(66, 56)},

		# --- 8 · THE HARBOUR GATE -------------------------------------------
		# THE FIRST FIGHT THE PLAYER CAN WIN BY SURVIVING. Three guards take
		# Amphetamines (gated to turn 3+), their chips visibly counting down, and
		# every one of them ends in Crash.
		{"id": "%s_f8" % ID, "name": "The Harbour Gate", "is_boss": false,
			"enemies": [
				{"character": "harbour_guard"},
				{"character": "harbour_guard"},
				{"character": "harbour_guard"},
			],
			"loot_table": _loot(72, 62)},

		# --- BOSS · THE CHIEF OF THE DETAIL ---------------------------------
		# >> THE CHIEF'S KIT IS THE DEV'S TO WRITE (§2.5). What the ladder already
		#    fixes is this composition: he arrives with two harbour guards, so
		#    Amphetamines is on the field and the fight has a six-turn shape
		#    whether or not he has one of his own.
		{"id": "%s_boss" % ID, "name": "The Chief of the Detail", "is_boss": true,
			"enemies": [
				{"character": "chief_of_the_detail"},
				{"character": "harbour_guard"},
				{"character": "harbour_guard"},
			],
			"loot_table": _loot(120, 110)},
	]

## FALLBACK ONLY. Every c2b fight now pays by per-enemy bounty (§1.19, summed in
## combat.gd's _win), and a bounty overrides the loot table outright — so these
## figures are dead unless a fight is authored with NO bounty on any enemy.
## The zone's real XP / money budget (§2.7 pass 1) lives on the modules:
##     ladder  40 / 45 / 52 / 50 / 54 / 60 / 70 / 78   ->  449
##     mini   200                                      (the burning ground)
##     boss   480                                      (2 guards 52 + chief 428)
##                                                    ----  1129 XP, 565 money
## 426 (c1, no training) + 1129 = 1555 = exactly level 9 on clearing the boss,
## mirroring c1: a player who never trains clears one level short of the band top.
static func _loot(money: int, xp: int) -> Dictionary:
	return {
		"money_min": money, "money_max": int(money * 1.6),
		"xp_min": xp * 10, "xp_max": int(xp * 16),
		"items": [],
	}

## THIS CAMPAIGN'S TRAINING FIGHTS — same spec shape as the campaign fights, run
## from this campaign's igloo. Currently the shared dummy.
static func training_fights() -> Array:
	return CampaignFights.ice_training(ID)
