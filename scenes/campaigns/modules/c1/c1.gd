extends RefCounted
class_name CampaignModuleC1
## Campaign 1 — the start node. Clearing it forks into 2A or 2B.
## To customise this campaign later, edit build() (its enemies, fights, training
## pool and extra data all live here in the module).

static func build() -> Campaign:
	var c := Campaign.ice_campaign(
		"c1", "Arctic",
		"res://scenes/campaigns/modules/c1/overworld_c1.tscn",
		["c2a", "c2b"],
		Vector2(0.10, 0.5),
		Color(0.10, 0.55, 0.75))
	# room for extra per-campaign data:
	c.extra = {"biome": "coast", "intro": true}
	return c
