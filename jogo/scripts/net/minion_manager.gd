extends Node
## MinionManager
## Autoload que gestiona los minions invocados (esqueletos del Nigromante).
## El SERVIDOR decide cuando aparecen/desaparecen; los clientes solo los ven.
## Son temporales, asi que no sincronizamos los existentes a quien entra tarde.

var _minion_scene: PackedScene = null

func _get_scene() -> PackedScene:
	if _minion_scene == null:
		_minion_scene = load("res://scenes/enemies/minion.tscn")
	return _minion_scene

# Contenedor de minions dentro de World (lo registra World._ready).
var minions_container: Node = null
var _next_id: int = 1


func register_world(container: Node) -> void:
	minions_container = container


# Lo llama el Nigromante (en el servidor) al invocar. Devuelve el id del minion.
func server_spawn(pos: Vector3, owner_id: int, damage: int, lifetime: float, max_hp: int) -> int:
	if not multiplayer.is_server():
		return 0
	var id := _next_id
	_next_id += 1
	spawn_minion.rpc(id, pos, owner_id, damage, lifetime, max_hp)
	return id


func server_despawn(id: int) -> void:
	if not multiplayer.is_server():
		return
	despawn_minion.rpc(id)


@rpc("authority", "call_local", "reliable")
func spawn_minion(id: int, pos: Vector3, owner_id: int, damage: int, lifetime: float, max_hp: int) -> void:
	if minions_container == null:
		return
	if minions_container.has_node(str(id)):
		return
	var m := _get_scene().instantiate()
	m.name = str(id)
	minions_container.add_child(m)
	m.set_multiplayer_authority(1, true)  # autoridad: servidor
	m.global_position = pos
	m.setup(owner_id, damage, lifetime, max_hp)


@rpc("authority", "call_local", "reliable")
func despawn_minion(id: int) -> void:
	if minions_container == null:
		return
	var n := minions_container.get_node_or_null(str(id))
	if n:
		n.queue_free()
