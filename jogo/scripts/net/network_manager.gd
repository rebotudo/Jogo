extends Node
## NetworkManager
## Autoload singleton que gestiona la conexion en red y el spawn de jugadores.
##
## Modelo: el HOST (peer id 1) es la autoridad. Cuando un cliente entra al mundo,
## le pide al servidor que lo registre (request_join). El servidor entonces:
##   1. Le manda al recien llegado todos los jugadores que YA estan en el mundo.
##   2. Crea al recien llegado en TODOS los peers (incluido el host).
## El despawn lo dispara el servidor cuando un peer se desconecta.

const PORT: int = 7777
const MAX_PLAYERS: int = 32

var player_scene: PackedScene = preload("res://scenes/player/player.tscn")

# Contenedor de jugadores dentro de la escena World (lo registra World._ready).
var players_container: Node = null

# Solo el servidor lo usa: peer_id -> posicion de aparicion.
var active_players: Dictionary = {}


# --- Crear/unirse a una partida -------------------------------------------------

func host_game() -> bool:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_PLAYERS)
	if err != OK:
		push_error("No se pudo crear el servidor (error %d)" % err)
		return false
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	return true


func join_game(ip: String) -> bool:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, PORT)
	if err != OK:
		push_error("No se pudo iniciar el cliente (error %d)" % err)
		return false
	multiplayer.multiplayer_peer = peer
	return true


func disconnect_from_game() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	active_players.clear()
	players_container = null


# --- Registro del mundo (lo llama World._ready en cada peer) --------------------

func register_world(container: Node) -> void:
	players_container = container
	if multiplayer.is_server():
		# El host se crea a si mismo (peer id 1).
		_server_add_player(1)
	else:
		# Los clientes piden entrar; el servidor responde con el spawn.
		request_join.rpc_id(1)


# --- Logica de servidor ---------------------------------------------------------

@rpc("any_peer", "reliable")
func request_join() -> void:
	if not multiplayer.is_server():
		return
	var new_id := multiplayer.get_remote_sender_id()
	# 1. Avisar al recien llegado de quienes ya estan en el mundo.
	for pid in active_players.keys():
		spawn_player.rpc_id(new_id, pid, active_players[pid])
	# 2. Crear al recien llegado en todos los peers.
	_server_add_player(new_id)


func _server_add_player(id: int) -> void:
	var pos := _random_spawn()
	active_players[id] = pos
	spawn_player.rpc(id, pos)  # call_local => tambien se crea en el servidor


func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server():
		return
	active_players.erase(id)
	despawn_player.rpc(id)


func _random_spawn() -> Vector3:
	return Vector3(randf_range(-5.0, 5.0), 1.0, randf_range(-5.0, 5.0))


# --- RPCs que se ejecutan en TODOS los peers ------------------------------------

@rpc("authority", "call_local", "reliable")
func spawn_player(id: int, pos: Vector3) -> void:
	if players_container == null:
		return
	if players_container.has_node(str(id)):
		return
	var p := player_scene.instantiate()
	p.name = str(id)  # el nombre = peer_id; el jugador usa esto para su autoridad
	players_container.add_child(p)
	# Fijamos la autoridad AHORA que el jugador ya esta en el arbol, para que
	# is_multiplayer_authority() sea correcto y cada peer difunda solo su jugador.
	p.set_multiplayer_authority(id, true)
	p.global_position = pos


@rpc("authority", "call_local", "reliable")
func despawn_player(id: int) -> void:
	if players_container == null:
		return
	var n := players_container.get_node_or_null(str(id))
	if n:
		n.queue_free()
