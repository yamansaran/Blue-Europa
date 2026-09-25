extends Control

## ============================================================================
## OPTIONS  —  the options box (FUTURE_PLANS §5)
## ============================================================================
## A shell-content panel (GameManager.go_to_options). Entries: RETURN TO MAIN MENU,
## behind a confirm, because saving is manual (the toolbar's Save button) and leaving
## drops anything unsaved; and a DEBUG MODE toggle (GameManager.set_debug). NOT reachable from combat (dev
## call, 2026-09-25) — combat has no Options button, and this panel never checks.
## Esc (or Back) returns to the overworld, as before.
## ----------------------------------------------------------------------------

const BOX_W := 320.0
const BG := Color(0.16, 0.16, 0.19)
const BORDER := Color(0.36, 0.36, 0.42)

var _confirm: ConfirmationDialog

func _ready() -> void:
	_build()

func _build() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(BOX_W, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG
	sb.border_color = BORDER
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)

	var title := Label.new()
	title.text = "Options"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	col.add_child(title)

	var menu_btn := Button.new()
	menu_btn.text = "Return to Main Menu"
	menu_btn.custom_minimum_size = Vector2(0, 36)
	menu_btn.pressed.connect(_on_main_menu_pressed)
	col.add_child(menu_btn)

	# DEBUG MODE (2026-09-25): flips GameManager.debug_enabled and remembers it. The
	# shell's debug buttons update at once; other debug features (overworld cheats,
	# combat's log/panel, class select) pick it up the next time their screen opens.
	var dbg := CheckButton.new()
	dbg.text = "Debug mode"
	dbg.button_pressed = GameManager.is_debug()
	dbg.focus_mode = Control.FOCUS_NONE
	dbg.toggled.connect(GameManager.set_debug)
	col.add_child(dbg)

	var back_btn := Button.new()
	back_btn.text = "Back"
	back_btn.custom_minimum_size = Vector2(0, 30)
	back_btn.pressed.connect(GameManager.go_to_overworld)
	col.add_child(back_btn)

	_confirm = ConfirmationDialog.new()
	_confirm.title = "Return to Main Menu"
	_confirm.dialog_text = "Return to the main menu?\nAnything you haven't saved will be lost."
	_confirm.ok_button_text = "Return"
	_confirm.confirmed.connect(GameManager.go_to_main_menu)
	add_child(_confirm)

func _on_main_menu_pressed() -> void:
	_confirm.popup_centered()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not _confirm.visible:
		GameManager.go_to_overworld()
