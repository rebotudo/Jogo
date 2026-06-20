extends Area3D

signal hit_received(damage: int)

@export var stats: CharacterStats

func receive_hit(damage: int):
	if stats == null:
		push_warning("Hurtbox sin stats asignado: " + get_parent().name)
		return
	stats.take_damage(damage)
	hit_received.emit(damage)
