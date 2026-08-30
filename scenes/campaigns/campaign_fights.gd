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
static func normal_loot() -> Dictionary:
	return {
		"money_min": 15, "money_max": 40,
		"xp_min": 500, "xp_max": 800,
		"items": [
			{"id": "frost_shard", "name": "Frost Shard", "chance": 0.8},
			{"id": "sprite_dust", "name": "Sprite Dust", "chance": 0.4},
		],
	}

static func boss_loot() -> Dictionary:
	return {
		"money_min": 80, "money_max": 150,
		"xp_min": 2000, "xp_max": 3000,
		"items": [
			{"id": "frost_core", "name": "Frost Core", "chance": 1.0},
			{"id": "sprite_dust", "name": "Sprite Dust", "chance": 0.75},
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

## THE STANDARD TRAINING SET: one unkillable dummy. Training fights use the SAME
## spec shape as campaign fights (id / name / is_boss / enemies / loot_table), so
## a training fight can hold several characters and its own loot just like a real
## one. (The training SCREEN is still a placeholder — this data is authored and
## waiting for it.)
static func ice_training(p_id: String) -> Array:
	return [
		{
			"id": "%s_training_dummy" % p_id,
			"name": "Training Dummy",
			"is_boss": false,
			"enemies": [ training_dummy_spec() ],
			"loot_table": no_loot(),
		},
	]
