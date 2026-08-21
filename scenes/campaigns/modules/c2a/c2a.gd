extends RefCounted
class_name CampaignModuleC2A
## Campaign 2A — one of the two second-stage branches. Forks into 3A or 3B.

static func build() -> Campaign:
	var c := Campaign.ice_campaign(
		"c2a", "Newfoundland",
		"res://scenes/campaigns/modules/c2a/overworld_c2a.tscn",
		["c3a", "c3b"],
		Vector2(0.35, 0.28),
		Color(0.12, 0.50, 0.80))
	c.shop_stock = ["leather_vest", "swift_boots", "oak_shield", "minor_potion"]
	c.extra = {"biome": "glacier"}
	return c
