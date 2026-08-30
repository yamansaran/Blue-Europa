extends RefCounted
## ============================================================================
## RETIRED — this folder is a leftover and should be DELETED.
## ============================================================================
## "c4" was the old join/end node from the six-campaign test map. The map is now
## 23 campaigns (c1 -> three paths of seven -> c9 Berlin) and level 4 lives in
## modules/c4a, c4b and c4c instead.
##
## The file is emptied rather than left as it was because its old body called
## Campaign.ice_campaign(), which no longer exists — a campaign's fights now live
## in its own module (see any modules/<id>/<id>.gd) and the shared fight sets live
## in scenes/campaigns/campaign_fights.gd.
##
## SAFE TO DELETE: remove the whole scenes/campaigns/modules/c4/ folder (c4.gd,
## c4.gd.uid and overworld_c4.tscn). Nothing references it.
## ----------------------------------------------------------------------------
