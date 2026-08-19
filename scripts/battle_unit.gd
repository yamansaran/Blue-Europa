extends Node2D
class_name BattleUnit

@export var unit_name: String = "Unit"
@export var max_hp: int = 100
var current_hp: int

func _ready():
	current_hp = max_hp

func take_damage(amount: int):
	current_hp -= amount
	# TODO: play hit animation, flash red
	if current_hp <= 0:
		die()

func die():
	# TODO: death animation
	queue_free()
