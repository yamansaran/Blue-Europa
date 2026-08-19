extends Node2D
class_name SkeletonRig2

@onready var anim_player = $AnimationPlayer

func _ready():
	print("Scene loaded!")
	anim_player.play("Idle")

func _input(event):
	if event.is_action_pressed("ui_accept"):
		print("Space/Enter pressed!")
		play_attack()

func play_attack():
	anim_player.play("Attack")
	await anim_player.animation_finished
	anim_player.play("Idle")
