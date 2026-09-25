extends RefCounted
class_name CampaignFights
## ============================================================================
## CampaignFights  —  the LIBRARY of reusable fight sets
## ============================================================================
## Every campaign owns its fights: a module's fights() / training_fights() are
## the single place that campaign's content is decided. This file exists only so
## campaigns that want the SAME content don't have to copy-paste it.
##
## Today there is exactly ONE set — the "ice" set (5 ice sprites in a row + a
## large ice sprite boss) — and every campaign calls it, so the whole map is
## still identical on purpose. To make a campaign bespoke, DON'T edit this file:
## rewrite that campaign module's fights() to build its own array. To add another
## shared set (a "fire" set, say), add a new builder here and have the modules
## that want it call that instead.
##
## Every builder returns FRESH dictionaries each call, so one campaign mutating
## its fights can never reach into another's.
## ----------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Enemy specs
# ---------------------------------------------------------------------------
## Enemy specs just NAME a character module (see scenes/characters/units/). The
## creature's stats, colour, size, AI and permanent buffs all live in its module
## file; CharacterRegistry.build() instantiates it. A fight may layer per-fight
## overrides on top ({"character":"ice_spirit", "level":3, "stats":{"vigor":20}}).
static func ice_sprite_spec() -> Dictionary:
	return { "character": "ice_spirit" }

## The boss: its own module (LargeIceSpirit) — the same creature, bigger + tougher.
static func large_ice_sprite_spec() -> Dictionary:
	return { "character": "large_ice_spirit" }

## An INLINE spec (no character module): the unkillable practice dummy.
static func training_dummy_spec() -> Dictionary:
	return { "name": "Training Dummy", "type": "enemy", "max_hp": 9999, "ai": "none" }

# ---------------------------------------------------------------------------
# Loot tables
# ---------------------------------------------------------------------------
## THE XP BUDGET (widened curve — LevelTable total 2,160,000).
##
## These tables are SHARED by twenty-two campaigns sitting in eight different zones,
## so no single number can be right for all of them. They are priced for ZONE 2 — the
## first zone that calls them — which means every campaign past c2x currently UNDERPAYS
## on purpose: authoring a campaign means replacing its fights() with real content and
## real loot off the table below, and a placeholder that underpays is a bug you notice,
## while one that overpays is a bug you don't.
##
## Each zone's band is spent: 8 normals 1.814 units, miniboss 1.000, boss 1.150, and
## 6 training fights 1.036 (three tiers weighted 1 : 1.5 : 2, two fights each) =
## exactly 5.000 units, where unit = band / 5 = "one level's worth of XP".
##
##  Z  levels    band      unit   normals f1..f8                                 mini      boss    T1/T2/T3
##  1   1-5       525       131   23 25 27 28 30 33  (six, no mini)                  —       260   13/20 (x3)
##  2   5-10    1,415       283   55 55 60 65 65 70 70 75                          285       321   33/49/65
##  3  10-15    3,310       662   130 135 140 145 155 160 165 175                  650       775   75/115/150
##  4  15-20    7,650     1,530   295 310 325 340 355 370 385 400               1,550     1,740   175/265/350
##  5  20-25   17,750     3,550   700 700 750 800 800 850 900 950               3,550     4,130   410/600/800
##  6  25-30   41,850     8,370   1600 1700 1800 1850 1950 2000 2100 2200       8,500     9,450   950/1450/1950
##  7  30-35   97,500    19,500   3750 3950 4150 4350 4500 4700 4900 5000      19,500    22,500   2250/3350/4500
##  8  35-40  227,500    45,500   9000 9000 9500 10000 10500 11000 11500 12000  45,500    52,500   5000/8000/10500
##  9  40-45  529,500   105,900   20500 21500 22500 23500 24500 25500 26500 27500  106,000  121,500  12000/18500/24500
##
## Every row sums to its band exactly. Normal fights escalate 0.85x -> 1.15x inside a
## zone and always cross the boundary upward (zone 8's last normal 12,000 < zone 9's
## first 20,500), which is the constraint that caps within-zone escalation.
##
## Zone 1 is licensed to break the pattern (six fights, no miniboss, a two-unit boss);
## it is authored in c1.gd and does not use these tables. Levels 45-50 are postgame
## headroom (1,233,000 XP) and are deliberately not covered by any zone.
static func normal_loot() -> Dictionary:
	return {
		"money_min": 15, "money_max": 40,
		"xp_min": 55, "xp_max": 75,          # zone-2 normal band (f1..f8 = 55..75)
		"items": [
			{"id": "frost_shard", "name": "Frost Shard", "chance": 0.8},
			{"id": "sprite_dust", "name": "Sprite Dust", "chance": 0.4},
		],
	}

static func boss_loot() -> Dictionary:
	return {
		"money_min": 80, "money_max": 150,
		"xp_min": 321, "xp_max": 321,        # zone-2 boss, 1.150 units — flat, it is a gate
		"items": [
			{"id": "frost_core", "name": "Frost Core", "chance": 1.0},
			{"id": "sprite_dust", "name": "Sprite Dust", "chance": 0.75},
		],
	}

## The zone's MINIBOSS — one full level (1.000 units), zone-2 figure, same caveat as
## the two above. Nothing calls this yet: the shared ice set is six fights with no
## miniboss slot, so it is here for the first hand-authored campaign that wants one.
static func miniboss_loot() -> Dictionary:
	return {
		"money_min": 60, "money_max": 110,
		"xp_min": 285, "xp_max": 285,
		"items": [
			{"id": "frost_shard", "name": "Frost Shard", "chance": 1.0},
		],
	}

## Training pays nothing — it's practice.
static func no_loot() -> Dictionary:
	return { "money_min": 0, "money_max": 0, "xp_min": 0, "xp_max": 0, "items": [] }

# ---------------------------------------------------------------------------
# Fight sets
# ---------------------------------------------------------------------------
## THE STANDARD SET: fights 1-5 are one ice sprite each, fight 6 is the boss.
## Fight ids are prefixed with the campaign id so they stay unique across the map.
static func ice_fights(p_id: String) -> Array:
	var out: Array = []
	for n in range(1, 6):
		out.append({
			"id": "%s_fight_%d" % [p_id, n],
			"name": "Ice Sprite %d" % n,
			"is_boss": false,
			"enemies": [ ice_sprite_spec() ],
			"loot_table": normal_loot(),
		})
	out.append({
		"id": "%s_boss" % p_id,
		"name": "Large Ice Sprite",
		"is_boss": true,
		"enemies": [ large_ice_sprite_spec() ],
		"loot_table": boss_loot(),
	})
	return out

## THE PRACTICE DUMMY as a training fight spec. It gets its own builder because it
## is BOTH the default training pool AND the debug fallback that
## GameManager.go_to_training_dummy always reaches, and those two must not drift.
static func training_dummy_fight(p_id: String) -> Dictionary:
	return {
		"id": "%s_training_dummy" % p_id,
		"name": "Training Dummy",
		"is_boss": false,
		"enemies": [ training_dummy_spec() ],
		"loot_table": no_loot(),
	}

## THE STANDARD TRAINING SET: one unkillable dummy. Training fights use the SAME
## spec shape as campaign fights (id / name / is_boss / enemies / loot_table) PLUS
## the optional weight / min_cleared / max_cleared keys that make a pool a weighted,
## progress-gated SELECTION rather than a fixed menu (Campaign.training_roll).
##
## This set sets none of those three, so it is one always-available entry at weight
## 1 and rolling from it can only ever produce the dummy — which is why the twenty-
## two campaigns still calling it are completely unaffected by training becoming a
## roll. A campaign that wants a real training selection writes its own array (c1).
static func ice_training(p_id: String) -> Array:
	return [ training_dummy_fight(p_id) ]
