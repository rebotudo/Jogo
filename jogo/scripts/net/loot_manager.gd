extends Node
## LootManager
## Autoload que gestiona el botin en red. El SERVIDOR decide que se suelta y
## quien lo recoge; los clientes solo ven aparecer/desaparecer los objetos.

const SCATTER: float = 0.8        # dispersion al caer al suelo
const LOOT_FREE_AFTER: float = 45.0  # tras este tiempo, el botin pasa a ser libre

# Cargamos la escena de forma diferida (en el primer uso) y no con preload, para
# evitar una dependencia circular al arrancar: loot_pickup.gd referencia a
# LootManager, asi que no debemos forzar su parseo mientras este autoload se carga.
var _loot_scene: PackedScene = null

func _get_loot_scene() -> PackedScene:
	if _loot_scene == null:
		_loot_scene = load("res://scenes/items/loot_pickup.tscn")
	return _loot_scene

# Contenedor de loot dentro de World (lo registra World._ready en cada peer).
var loot_container: Node = null

# Solo el servidor: id -> { path, amount, pos }. Y un contador de ids.
var active_loot: Dictionary = {}
var _next_id: int = 1


# --- Registro del mundo ---------------------------------------------------------

func register_world(container: Node) -> void:
	loot_container = container
	if not multiplayer.is_server():
		# Cliente que entra: pide el loot que ya esta en el suelo.
		request_loot.rpc_id(1)


@rpc("any_peer", "reliable")
func request_loot() -> void:
	if not multiplayer.is_server():
		return
	var nid := multiplayer.get_remote_sender_id()
	for lid in active_loot.keys():
		var e: Dictionary = active_loot[lid]
		spawn_loot.rpc_id(nid, lid, e["path"], e["amount"], e["pos"])


# --- Logica de servidor ---------------------------------------------------------

# Lo llama el enemigo (en el servidor) al morir, por cada objeto que cae.
# 'owners' son los unicos peers que pueden recogerlo (asesino + grupo). [] = libre.
func server_drop(item_path: String, amount: int, origin: Vector3, owners: Array = []) -> void:
	if not multiplayer.is_server() or item_path == "":
		return
	var id := _next_id
	_next_id += 1
	var pos := origin + Vector3(randf_range(-SCATTER, SCATTER), 0.0, randf_range(-SCATTER, SCATTER))
	pos.y = 0.5
	active_loot[id] = {"path": item_path, "amount": amount, "pos": pos, "owners": owners.duplicate()}
	spawn_loot.rpc(id, item_path, amount, pos)
	# Tras un tiempo, el botin reservado pasa a ser libre para cualquiera.
	if owners.size() > 0:
		get_tree().create_timer(LOOT_FREE_AFTER).timeout.connect(_free_loot.bind(id))


func _free_loot(id: int) -> void:
	if active_loot.has(id):
		active_loot[id]["owners"] = []


# Lo llama el LootPickup (en el servidor) cuando un jugador lo toca.
# Devuelve true si el jugador se lo lleva. 'notify' avisa al jugador si no es suyo.
func server_collect(loot_id: int, player: Node, notify: bool = true) -> bool:
	if not multiplayer.is_server():
		return false
	if not active_loot.has(loot_id):
		return false
	var e: Dictionary = active_loot[loot_id]
	var owners: Array = e.get("owners", [])
	var pid := player.name.to_int() if player else 0
	# Si el botin esta reservado y este jugador no es dueño, no puede cogerlo.
	if owners.size() > 0 and not (pid in owners):
		if notify and player and player.has_method("server_notify"):
			player.server_notify("Ese botín no es tuyo")
		return false
	active_loot.erase(loot_id)
	despawn_loot.rpc(loot_id)
	if player and player.has_method("server_grant_item"):
		player.server_grant_item(e["path"], e["amount"])
	return true


# --- RPCs que se ejecutan en TODOS los peers ------------------------------------

@rpc("authority", "call_local", "reliable")
func spawn_loot(id: int, path: String, amount: int, pos: Vector3) -> void:
	if loot_container == null:
		return
	if loot_container.has_node(str(id)):
		return
	var l := _get_loot_scene().instantiate()
	l.name = str(id)
	l.item_path = path
	l.amount = amount
	loot_container.add_child(l)
	l.set_multiplayer_authority(1, true)
	l.global_position = pos


@rpc("authority", "call_local", "reliable")
func despawn_loot(id: int) -> void:
	if loot_container == null:
		return
	var n := loot_container.get_node_or_null(str(id))
	if n:
		n.queue_free()
