extends RefCounted
class_name CampaignModuleC3A
## Campaign 3A — a third-stage branch. Leads (linearly) to the finale, 4.

static func build() -> Campaign:
	var c := Campaign.ice_campaign(
		"c3a", "Nova Scotia",
		"res://scenes/campaigns/modules/c3a/overworld_c3a.tscn",
		["c4"],
		Vector2(0.62, 0.28),
		Color(0.14, 0.55, 0.82))
	c.extra = {"biome": "forest"}
	return c
