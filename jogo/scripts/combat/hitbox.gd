extends Area3D

@export var damage: int = 10

func get_damage() -> int:
	return damage

func activate():
	monitoring = true

func deactivate():
	monitoring = false
