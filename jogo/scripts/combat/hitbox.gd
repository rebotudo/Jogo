extends Area3D

@export var damage: int = 10
var already_hit: Array = []

func get_damage() -> int:
	return damage

func activate(dmg: int = -1):
	# Si el atacante pasa un daño (p.ej. su stat de ataque), lo usamos. Si no,
	# se queda el valor por defecto del hitbox.
	if dmg >= 0:
		damage = dmg
	already_hit.clear()
	monitoring = true
	await get_tree().process_frame
	await get_tree().physics_frame
	for area in get_overlapping_areas():
		_try_hit(area)

func _try_hit(area: Area3D):
	if area in already_hit:
		return
	if area.has_method("receive_hit"):
		already_hit.append(area)
		area.receive_hit(damage, _attacker_id())

func deactivate():
	monitoring = false

# Id de red del jugador atacante (el dueño de este hitbox), o 0 si no es jugador
# (p.ej. el hitbox de un enemigo). Sirve para saber quien mata y reparte recompensas.
func _attacker_id() -> int:
	var o := get_parent()
	if o and o.is_in_group("player"):
		return o.name.to_int()
	return 0
