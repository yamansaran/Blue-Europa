extends Control
class_name Shell
# Persistent shell: ContentArea on top (80%), Toolbar on bottom (20%).

@onready var content_area: Control    = $ContentArea
@onready var inventory_btn: Button    = $Toolbar/Left/HBox/InventoryButton
@onready var abilities_btn: Button    = $Toolbar/Left/HBox/AbilitiesButton
@onready var save_btn: Button         = $Toolbar/Left/HBox/SaveButton
@onready var options_btn: Button      = $Toolbar/Left/HBox/OptionsButton
@onready var achievements_btn: Button = $Toolbar/Left/HBox/AchievementsButton
@onready var world_map_btn: Button    = $Toolbar/Center/WorldMapButton
@onready var save_dialog: AcceptDialog = $Toolbar/SaveDialog
@onready var progress_bar: ProgressBar = $Toolbar/Right/ProgressBar
@onready var progress_label: Label     = $Toolbar/Right/ProgressLabel

func _ready() -> void:
	GameManager.active_shell = self
	inventory_btn.pressed.connect(func(): load_content(GameManager.SCENE_INVENTORY))
	abilities_btn.pressed.connect(func(): load_content(GameManager.SCENE_ABILITIES))
	options_btn.pressed.connect(func(): load_content(GameManager.SCENE_OPTIONS))
	achievements_btn.pressed.connect(func(): load_content(GameManager.SCENE_ACHIEVEMENTS))
	save_btn.pressed.connect(_on_save_pressed)
	world_map_btn.pressed.connect(_on_world_map_pressed)
	# Boot into a requested content panel (e.g. the victory screen) if one was
	# staged; otherwise into the CURRENT campaign's overworld (via GameManager,
	# which also resolves any pending linear campaign advance).
	if GameManager.pending_content_path != "":
		var boot_path := GameManager.pending_content_path
		GameManager.pending_content_path = ""
		load_content(boot_path)
	else:
		GameManager.go_to_overworld()

func load_content(scene_path: String) -> void:
	for child in content_area.get_children():
		child.queue_free()
	var packed: PackedScene = load(scene_path)
	if packed == null:
		push_error("Shell.load_content: could not load " + scene_path)
		return
	var instance := packed.instantiate()
	content_area.add_child(instance)
	if instance is Control:
		var c := instance as Control
		c.anchor_left = 0.0
		c.anchor_top = 0.0
		c.anchor_right = 1.0
		c.anchor_bottom = 1.0
		c.offset_left = 0.0
		c.offset_top = 0.0
		c.offset_right = 0.0
		c.offset_bottom = 0.0
	# Keep the persistent toolbar's campaign progression bar current on every
	# screen swap (after a campaign win, a fork pick, a debug map jump, etc.).
	refresh_progress()

## Update the toolbar's right-side campaign progression bar from CampaignDB.
func refresh_progress() -> void:
	if typeof(CampaignDB) == TYPE_NIL:
		return
	var frac: float = CampaignDB.progress_fraction()
	if progress_bar:
		progress_bar.value = frac * 100.0
	if progress_label:
		var camp = CampaignDB.get_current()
		var nm: String = camp.display_name if camp else "—"
		var suffix := ""
		if CampaignDB.is_current_complete():
			suffix = "  (cleared)"
		progress_label.text = "%s   %d/%d%s" % [
			nm, CampaignDB.fight_index, CampaignDB.fights_total(), suffix]

## DEBUG (temporary): the Save button wipes the save and starts a fresh level-1
## character rather than persisting the current one. Character.reset_to_defaults()
## resets every field to its new-game value and overwrites user://character.save.
func _on_save_pressed() -> void:
	if typeof(Character) != TYPE_NIL and Character.has_method("reset_to_defaults"):
		Character.reset_to_defaults()
	if save_dialog:
		save_dialog.dialog_text = "DEBUG: save cleared — reset to a fresh Level 1."
		save_dialog.popup_centered()

func _on_world_map_pressed() -> void:
	GameManager.go_to_campaign_map()