extends Area3D

signal hit_received(damage: int)

@export var stats: CharacterStats

func _ready():
	area_entered.connect(_on_area_entered)

func _on_area_entered(area: Area3D):
	if area.has_method("get_damage"):
		var damage = area.get_damage()
		if stats:
			stats.take_damage(damage)
		hit_received.emit(damage)
