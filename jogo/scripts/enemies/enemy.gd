extends CharacterBody3D

@onready var hurtbox = $Hurtbox

func _ready():
	if hurtbox.stats == null:
		push_warning("Enemy sin stats asignado en el Hurtbox")
	else:
		hurtbox.stats.died.connect(_on_died)

func _on_died():
	queue_free()
