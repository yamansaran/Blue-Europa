extends Control
# Blank Options placeholder. Click / Esc returns to overworld.
func _ready() -> void:
	print("Options scene loaded")
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") \
	or (event is InputEventMouseButton and event.pressed):
		GameManager.go_to_overworld()
