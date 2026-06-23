extends Node
## EnemyManager
## Autoload que gestiona los enemigos en red. El SERVIDOR es la unica autoridad:
## decide cuantos enemigos hay, donde aparecen y cuando reaparecen. Los clientes
## solo reciben ordenes de crear/eliminar y muestran lo que el servidor manda.
##
## Mantiene siempre TARGET_ENEMIES enemigos vivos. Cuando uno muere, programa
## su reaparicion tras RESPAWN_DELAY segundos.

const TARGET_ENEMIES: int = 3
const RESPAWN_DELAY: float = 5.0

# Carga diferida (en el primer uso) para evitar dependencias circulares al
# arrancar: enemy.tscn referencia a otros autoloads.
var _enemy_scene: PackedScene = null

func _get_enemy_scene() -> PackedScene:
	if _enemy_scene == null:
		_enemy_scene = load("res://scenes/enemies/enemy.tscn")
	return _enemy_scene

# Contenedor de enemigos dentro de World (lo registra World._ready en cada peer).
var enemies_container: Node = null

# Solo el servidor: id_enemigo -> posicion. Y un contador para ids unicos.
var active_enemies: Dictionary = {}
var _next_id: int = 1


# --- Registro del mundo ---------------------------------------------------------

func register_world(container: Node) -> void:
	enemies_container = container
	if multiplayer.is_server():
		# Poblamos el mundo con la cantidad objetivo de enemigos.
		for i in TARGET_ENEMIES:
			_server_spawn_enemy()
	else:
		# Cliente que entra: pide los enemigos que ya existen.
		request_enemies.rpc_id(1)


# --- Logica de servidor ---------------------------------------------------------

@rpc("any_peer", "reliable")
func request_enemies() -> void:
	if not multiplayer.is_server():
		return
	var new_id := multiplayer.get_remote_sender_id()
	for eid in active_enemies.keys():
		spawn_enemy.rpc_id(new_id, eid, active_enemies[eid])


func _server_spawn_enemy() -> void:
	var id := _next_id
	_next_id += 1
	var pos := _random_spawn()
	active_enemies[id] = pos
	spawn_enemy.rpc(id, pos)  # call_local => tambien aparece en el servidor


# Lo llama el enemigo (en el servidor) cuando su vida llega a 0.
func server_on_enemy_died(id: int) -> void:
	if not multiplayer.is_server():
		return
	if not active_enemies.has(id):
		return
	active_enemies.erase(id)
	despawn_enemy.rpc(id)
	# Programar reaparicion para mantener la poblacion objetivo.
	get_tree().create_timer(RESPAWN_DELAY).timeout.connect(_server_spawn_enemy)


func _random_spawn() -> Vector3:
	return Vector3(randf_range(-8.0, 8.0), 1.0, randf_range(-8.0, 8.0))


# --- RPCs que se ejecutan en TODOS los peers ------------------------------------

@rpc("authority", "call_local", "reliable")
func spawn_enemy(id: int, pos: Vector3) -> void:
	if enemies_container == null:
		return
	if enemies_container.has_node(str(id)):
		return
	var e := _get_enemy_scene().instantiate()
	e.name = str(id)
	enemies_container.add_child(e)
	# La autoridad de TODO enemigo es el servidor (peer id 1). La fijamos con el
	# nodo ya en el arbol para que las RPC de sincronizacion funcionen bien.
	e.set_multiplayer_authority(1, true)
	e.global_position = pos


@rpc("authority", "call_local", "reliable")
func despawn_enemy(id: int) -> void:
	if enemies_container == null:
		return
	var n := enemies_container.get_node_or_null(str(id))
	if n:
		n.queue_free()
