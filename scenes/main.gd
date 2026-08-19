extends Node2D
# Boot scene. Immediately hands off to the persistent shell,
# which loads the overworld into its content area.
func _ready() -> void:
	# Deferred by one frame on purpose: calling change_scene_to_file() straight
	# from the ROOT scene's _ready() can trip Godot's "parent is busy adding/
	# removing children" error, because the boot scene isn't fully in the tree
	# yet. call_deferred() lets _ready() finish first, then the swap runs safely.
	GameManager.go_to_shell.call_deferred()
