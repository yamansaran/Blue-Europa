extends RefCounted
class_name CampaignModuleC3B
## Campaign 3B — the other third-stage branch. Also leads to the finale, 4.

static func build() -> Campaign:
	var c := Campaign.ice_campaign(
		"c3b", "Helsinki",
		"res://scenes/campaigns/modules/c3b/overworld_c3b.tscn",
		["c4"],
		Vector2(0.62, 0.72),
		Color(0.10, 0.40, 0.66))
	c.extra = {"biome": "peaks"}
	return c
