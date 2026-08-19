extends Node2D
class_name SkeletonRig

@onready var anim_player = $AnimationPlayer

func _ready():
	print("Scene loaded!")
	anim_player.play("idle")

func _input(event):
	if event.is_action_pressed("ui_accept"):
		play_attack()

func play_attack():
	anim_player.play("attack")
	await anim_player.animation_finished
	anim_player.play("idle")
func _process(_delta):
	check_bones($Skeleton2D)

func check_bones(node):
	for child in node.get_children():
		if child is Bone2D:
			if child.get_bone_length() == 0:
				print("Zero length: ", child.name)
			if child.scale.x == 0 or child.scale.y == 0:
				print("Zero scale: ", child.name)
		check_bones(child)
