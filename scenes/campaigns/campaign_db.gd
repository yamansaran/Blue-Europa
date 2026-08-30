extends Node
## ============================================================================
## CampaignDB  —  AUTOLOAD "CampaignDB"
## ============================================================================
## Owns the campaign GRAPH (a map of linked Campaign modules) plus the player's
## PROGRESSION through it. Single source of truth for:
##   - which campaign is current
##   - how many fights of the current campaign are done
##   - which campaigns are completed
##   - total progression (fights cleared across every campaign)
##   - the path of forks the player has chosen
##
## THE MAP: c1 (The Arctic) opens onto THREE paths. You commit to the one you
## pick and walk it a campaign at a time; the only mid-run choice is at LEVEL 5,
## where each camp opens onto its own path's next stop OR its neighbour's. All
## three paths rejoin at c9 (Berlin). Nothing ever advances by itself — the
## player confirms every step on the post-boss popup, even when there is only
## one way on. (The world map screen stays a DEBUG jump.)
##
## Persists to user://campaign.save (JSON). Register as an autoload named
## "CampaignDB" and RESTART Godot after adding it (it also references the
## class_name globals Campaign + CampaignModule*).
## ----------------------------------------------------------------------------

const SAVE_PATH := "user://campaign.save"
const SAVE_VERSION := 2      # bumped when the map was rebuilt to 23 campaigns
const START_ID := "c1"

# --- the graph --------------------------------------------------------------
var campaigns: Dictionary = {}   # id(String) -> Campaign
var order: Array = []            # registration order (used by the world map)

# --- progression state ------------------------------------------------------
var current_id: String = START_ID
var fight_index: int = 0                    # fights completed in the CURRENT campaign
var completed_campaigns: Dictionary = {}    # id -> true
var total_fights_done: int = 0              # across every campaign (total progression)
var path_history: Array = []                # chosen campaign ids, in order

func _ready() -> void:
	_build_all()
	if not load_game():
		current_id = START_ID
		path_history = [START_ID]
		save_game()

# ---------------------------------------------------------------------------
# Graph build  —  add a campaign here to extend the map
# ---------------------------------------------------------------------------
## Registration order is also the world map's draw order, so these are listed by
## LEVEL (the column on the map), then by path a / b / c (the row).
func _build_all() -> void:
	campaigns.clear()
	order.clear()

	# level 1 — the start; forks into all three paths
	_register(CampaignModuleC1.build())

	# level 2
	_register(CampaignModuleC2A.build())
	_register(CampaignModuleC2B.build())
	_register(CampaignModuleC2C.build())

	# level 3
	_register(CampaignModuleC3A.build())
	_register(CampaignModuleC3B.build())
	_register(CampaignModuleC3C.build())

	# level 4
	_register(CampaignModuleC4A.build())
	_register(CampaignModuleC4B.build())
	_register(CampaignModuleC4C.build())

	# level 5 — the map's one mid-run choice (each opens onto two level-6 camps)
	_register(CampaignModuleC5A.build())
	_register(CampaignModuleC5B.build())
	_register(CampaignModuleC5C.build())

	# level 6
	_register(CampaignModuleC6A.build())
	_register(CampaignModuleC6B.build())
	_register(CampaignModuleC6C.build())

	# level 7
	_register(CampaignModuleC7A.build())
	_register(CampaignModuleC7B.build())
	_register(CampaignModuleC7C.build())

	# level 8 — all three rejoin at Berlin
	_register(CampaignModuleC8A.build())
	_register(CampaignModuleC8B.build())
	_register(CampaignModuleC8C.build())

	# level 9 — the end of the map
	_register(CampaignModuleC9.build())

func _register(c: Campaign) -> void:
	if c == null:
		return
	if campaigns.has(c.id):
		push_warning("CampaignDB: duplicate campaign id '%s' — the later one wins." % c.id)
	campaigns[c.id] = c
	order.append(c.id)

# ---------------------------------------------------------------------------
# Queries
# ---------------------------------------------------------------------------
func has_campaign(id: String) -> bool:
	return campaigns.has(id)

func get_campaign(id: String) -> Campaign:
	return campaigns.get(id, null)

func get_current() -> Campaign:
	return campaigns.get(current_id, null)

func fights_total() -> int:
	var c := get_current()
	return c.fight_count() if c else 0

## True once every fight (including the boss) of the current campaign is cleared.
func is_current_complete() -> bool:
	return fights_total() > 0 and fight_index >= fights_total()

## The next fight spec to play, or {} if the campaign is already complete.
func current_fight() -> Dictionary:
	var c := get_current()
	if c == null:
		return {}
	return c.fight_at(fight_index)

func is_current_fight_boss() -> bool:
	return bool(current_fight().get("is_boss", false))

func progress_fraction() -> float:
	var t := fights_total()
	if t <= 0:
		return 0.0
	return clampf(float(fight_index) / float(t), 0.0, 1.0)

func available_next() -> Array:
	var c := get_current()
	return c.next_ids.duplicate() if c else []

## The current campaign's TRAINING fights (same spec shape as campaign fights).
func training_fights() -> Array:
	var c := get_current()
	return c.training_pool.duplicate(true) if c else []

## The current campaign is finished AND there is somewhere to go. TRUE for a
## single onward step as well as a fork — the player always confirms the move,
## so this is what the overworld uses to decide whether to show the popup.
func can_advance() -> bool:
	return is_current_complete() and available_next().size() >= 1

## More than one way on — used only to word the popup ("choose your path").
func needs_choice() -> bool:
	return is_current_complete() and available_next().size() > 1

## The current campaign is finished AND there is nowhere left to go (map end).
func is_final() -> bool:
	return is_current_complete() and available_next().is_empty()

# ---------------------------------------------------------------------------
# Mutations
# ---------------------------------------------------------------------------
## Call once per won campaign fight (from the victory screen). Advances the
## fight counter and totals; marks the campaign complete when the boss falls.
func record_fight_win() -> void:
	if is_current_complete():
		return
	fight_index += 1
	total_fights_done += 1
	if is_current_complete():
		completed_campaigns[current_id] = true
	save_game()

## Move to a specific next campaign. Always player-driven: the post-boss popup
## calls this with whichever id was clicked, even when it offered only one.
func advance_to(next_id: String) -> void:
	if not has_campaign(next_id):
		return
	completed_campaigns[current_id] = true
	current_id = next_id
	fight_index = 0
	path_history.append(next_id)
	save_game()

## DEBUG (world map): jump straight to a campaign and restart its fights.
func jump_to(id: String) -> void:
	if not has_campaign(id):
		return
	current_id = id
	fight_index = 0
	save_game()

func reset() -> void:
	current_id = START_ID
	fight_index = 0
	completed_campaigns = {}
	total_fights_done = 0
	path_history = [START_ID]
	save_game()

# ---------------------------------------------------------------------------
# Save / load  (JSON)
# ---------------------------------------------------------------------------
func save_game() -> void:
	var data := {
		"version": SAVE_VERSION,
		"current_id": current_id,
		"fight_index": fight_index,
		"completed": completed_campaigns,
		"total_fights_done": total_fights_done,
		"path_history": path_history,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))
		f.close()

func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return false
	var txt := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	if int(parsed.get("version", -1)) != SAVE_VERSION:
		return false
	current_id = str(parsed.get("current_id", START_ID))
	if not has_campaign(current_id):
		current_id = START_ID
	fight_index = int(parsed.get("fight_index", 0))
	var comp = parsed.get("completed", {})
	completed_campaigns = comp if typeof(comp) == TYPE_DICTIONARY else {}
	total_fights_done = int(parsed.get("total_fights_done", 0))
	var ph = parsed.get("path_history", [START_ID])
	path_history = ph if typeof(ph) == TYPE_ARRAY else [START_ID]
	# keep the fight counter in range for the (possibly retuned) current campaign
	fight_index = clampi(fight_index, 0, fights_total())
	return true
