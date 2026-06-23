extends Area3D

signal hit_received(damage: int)

@export var stats: CharacterStats

func _ready():
	if stats:
		# Cada entidad necesita SU propia copia de stats. El .tres se comparte
		# entre todas las instancias de la escena, asi que sin duplicar, todos
		# los jugadores compartirian el mismo HP. Duplicamos por instancia.
		stats = stats.duplicate(true)
		stats.ensure_initialized()

func receive_hit(damage: int):
	if stats == null:
		push_warning("Hurtbox sin stats asignado: " + get_parent().name)
		return
	# El daño NO se aplica aqui. Se delega al CombatManager, que lo resuelve en
	# el servidor (modelo autoritativo). get_parent() es la entidad (Player/Enemy),
	# que implementa server_take_damage().
	hit_received.emit(damage)
	CombatManager.report_hit(get_parent(), damage)
