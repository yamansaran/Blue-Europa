extends Control
# Overworld as a CONTENT PANEL inside the Shell's ContentArea.
# Root is a Control; map-object clicks are hit-tested in LOCAL coordinates
# via _gui_input, so they line up no matter where the content area sits.
# Regions are rectangles in this panel's local space (matching the
# placeholder ColorRects in overworld.tscn).

var regions := [
	{"name": "shop",     "rect": Rect2(180, 270, 160, 160),  "action": "shop"},
	{"name": "training", "rect": Rect2(688, 270, 160, 160),  "action": "training"},
	{"name": "campaign", "rect": Rect2(1060, 240, 360, 220), "action": "campaign"},
]

func _ready() -> void:
	print("Overworld content ready.")
	# Make sure this Control actually receives gui input across its whole rect.
	mouse_filter = Control.MOUSE_FILTER_STOP

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton \
	and event.button_index == MOUSE_BUTTON_LEFT \
	and event.pressed:
		var pos: Vector2 = event.position  # local to this Control
		for r in regions:
			if (r["rect"] as Rect2).has_point(pos):
				_do(r["action"])
				accept_event()
				return

func _do(action: String) -> void:
	match action:
		"shop":     GameManager.go_to_shop()
		"training": GameManager.go_to_training()
		"campaign": GameManager.go_to_campaign_battle()
