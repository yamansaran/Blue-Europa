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
	# --- debug-only toolbar bits (GameManager.debug_enabled) ---
	# The "CS" Creation Studio button (over Inventory), the "RST" reset button (over
	# Save) and the World Map (campaign-jump) button. Rebuilt live when Options
	# toggles debug mode.
	refresh_debug()
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

## True while the game's debug features are switched on (GameManager.debug_enabled).
func _debug_on() -> bool:
	return typeof(GameManager) != TYPE_NIL and GameManager.has_method("is_debug") \
		and GameManager.is_debug()


## Build or remove the debug-only toolbar bits to match GameManager.is_debug(). Safe to
## call any number of times (Options' debug toggle calls it through GameManager).
func refresh_debug() -> void:
	var on := _debug_on()
	world_map_btn.visible = on
	for n in [_studio_btn, _reset_btn]:
		if n != null and is_instance_valid(n):
			n.queue_free()
	_studio_btn = null
	_reset_btn = null
	if on:
		_studio_btn = _add_corner_button(inventory_btn, "CS", "Open Creation Studio (debug)", _open_creation_studio)
		_reset_btn = _add_corner_button(save_btn, "RST", "Reset this save to a fresh Level 1 (debug)", _on_reset_pressed)

var _studio_btn: Button = null
var _reset_btn: Button = null
var _reset_confirm: ConfirmationDialog = null

## SAVE — always a real save now (the debug reset moved to its own "RST" button).
func _on_save_pressed() -> void:
	if typeof(Character) == TYPE_NIL or not Character.has_method("save_game"):
		return
	var has_slot := typeof(SaveSlots) == TYPE_NIL or SaveSlots.active_slot >= 0
	Character.save_game()
	if save_dialog:
		save_dialog.dialog_text = "Game saved." if has_slot else "No save slot is active — nothing was written."
		save_dialog.popup_centered()

## DEBUG RESET ("RST" over Save): confirm, then Character.reset_to_defaults() — a fresh
## level-1 character of the CURRENT class, saved over this slot.
func _on_reset_pressed() -> void:
	if not _debug_on():
		return
	if _reset_confirm == null or not is_instance_valid(_reset_confirm):
		_reset_confirm = ConfirmationDialog.new()
		_reset_confirm.title = "Debug Reset"
		_reset_confirm.dialog_text = "Reset this save to a fresh Level 1 of the same class?\nThis overwrites the slot."
		_reset_confirm.ok_button_text = "Reset"
		_reset_confirm.confirmed.connect(_do_reset)
		add_child(_reset_confirm)
	_reset_confirm.popup_centered()

func _do_reset() -> void:
	if typeof(Character) != TYPE_NIL and Character.has_method("reset_to_defaults"):
		Character.reset_to_defaults()
	if save_dialog:
		save_dialog.dialog_text = "DEBUG: save reset to a fresh Level 1."
		save_dialog.popup_centered()

func _on_world_map_pressed() -> void:
	if _debug_on():
		GameManager.go_to_campaign_map()

## DEBUG: a small button overlaid on the top-left corner of a toolbar button ("CS" on
## Inventory, "RST" on Save). Parented to that button so it rides along wherever the
## toolbar HBox puts it; the host button's own size/position are untouched.
func _add_corner_button(host: Button, label: String, tip: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = label
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE              # don't steal spacebar / keyboard focus
	b.mouse_filter = Control.MOUSE_FILTER_STOP     # consume its own clicks so the host doesn't also fire
	b.add_theme_font_size_override("font_size", 10)
	b.pressed.connect(action)
	host.add_child(b)
	b.set_anchors_preset(Control.PRESET_TOP_LEFT)  # pin to the host button's top-left corner
	b.position = Vector2(2, 2)
	b.size = Vector2(34 if label.length() > 2 else 30, 18)
	return b

## DEBUG: instance the Creation Studio window over the shell. It frees itself on
## close (see creation_studio.gd _on_close). Guarded so a second click is a no-op
## while it's already open.
func _open_creation_studio() -> void:
	if has_node("CreationStudioPopup"):
		return
	var packed: PackedScene = load("res://scenes/tools/creation_studio.tscn")
	if packed == null:
		push_error("Shell: could not load res://scenes/tools/creation_studio.tscn")
		return
	var studio := packed.instantiate()
	studio.name = "CreationStudioPopup"
	add_child(studio)
	if studio is Window:
		(studio as Window).popup_centered(Vector2i(780, 860))
