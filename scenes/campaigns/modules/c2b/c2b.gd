extends RefCounted
class_name CampaignModuleC2B
## Campaign 2B — the other second-stage branch. Also forks into 3A or 3B.

static func build() -> Campaign:
	var c := Campaign.ice_campaign(
		"c2b", "Svalbard",
		"res://scenes/campaigns/modules/c2b/overworld_c2b.tscn",
		["c3a", "c3b"],
		Vector2(0.35, 0.72),
		Color(0.10, 0.45, 0.70))
	c.extra = {"biome": "delta"}
	return c
