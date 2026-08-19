extends Node2D
# Placeholder Shop scene. Click anywhere or press Esc to return to overworld.
func _ready() -> void:
	print("Shop scene loaded")
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") \
	or (event is InputEventMouseButton and event.pressed):
		GameManager.go_to_overworld()
