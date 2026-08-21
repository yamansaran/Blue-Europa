extends RefCounted
class_name CampaignModuleC4
## Campaign 4 — the finale / convergence node. No next_ids (end of the map).

static func build() -> Campaign:
	var c := Campaign.ice_campaign(
		"c4", "Berlin",
		"res://scenes/campaigns/modules/c4/overworld_c4.tscn",
		[],                       # end of the map
		Vector2(0.88, 0.5),
		Color(0.16, 0.30, 0.55))
	c.shop_stock = ["ember_ring", "lucky_charm", "oak_shield", "leather_vest", "minor_potion"]
	c.extra = {"biome": "throne", "finale": true}
	return c
