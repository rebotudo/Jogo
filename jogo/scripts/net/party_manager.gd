extends Node
## PartyManager
## Autoload que gestiona los grupos (parties). El SERVIDOR es la autoridad: lleva
## la cuenta de quien esta con quien y resuelve invitar/aceptar/salir. Los
## clientes solo piden acciones y reciben su lista de miembros para la UI.
##
## Sirve para que la EXP y el loot se compartan SOLO entre miembros del mismo
## grupo (ver members_of / same_party, que usa el resto del juego en el servidor).

signal party_changed                 # mi grupo cambio (UI)
signal invite_received(from_name)    # me han invitado (UI)
signal player_list_received(players) # respuesta a request_player_list (UI)

# --- Estado solo-servidor ---
var _party_of: Dictionary = {}   # peer_id -> party_id
var _parties: Dictionary = {}    # party_id -> Array[int]
var _next_id: int = 1
var _invites: Dictionary = {}    # invitado_id -> invitador_id

# --- Estado local (para la UI de este peer) ---
var my_members: Array = []       # [{id, name}] de mi grupo; vacio si voy solo


func _ready() -> void:
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)


func _on_peer_disconnected(id: int) -> void:
	if multiplayer.is_server():
		_invites.erase(id)
		_do_leave(id)


# === Consultas del servidor (las usa el reparto de EXP/loot) ====================

# Devuelve los peers del grupo de 'peer' (incluyendolo). Si va solo, [peer].
func members_of(peer: int) -> Array:
	if _party_of.has(peer):
		return (_parties.get(_party_of[peer], [peer]) as Array).duplicate()
	return [peer]


func same_party(a: int, b: int) -> bool:
	if a == b:
		return true
	return _party_of.has(a) and _party_of.has(b) and _party_of[a] == _party_of[b]


# Lo llama un jugador (en el servidor) cuando cambia su vida: re-envia el estado
# del grupo (con vida) a todos sus miembros, para los marcos de grupo.
func server_notify_hp(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	if _party_of.has(peer_id):
		_notify_party(_party_of[peer_id])


# === API que llama la UI (en el peer local) =====================================

func request_player_list() -> void:
	if multiplayer.is_server():
		_send_player_list(multiplayer.get_unique_id())
	else:
		_req_player_list.rpc_id(1)

func invite_player(target_id: int) -> void:
	if multiplayer.is_server():
		_do_invite(multiplayer.get_unique_id(), target_id)
	else:
		_req_invite.rpc_id(1, target_id)

func accept_invite() -> void:
	if multiplayer.is_server():
		_do_accept(multiplayer.get_unique_id())
	else:
		_req_accept.rpc_id(1)

func decline_invite() -> void:
	if multiplayer.is_server():
		_invites.erase(multiplayer.get_unique_id())
	else:
		_req_decline.rpc_id(1)

func leave_party() -> void:
	if multiplayer.is_server():
		_do_leave(multiplayer.get_unique_id())
	else:
		_req_leave.rpc_id(1)


# === Logica de servidor =========================================================

func _player_node(id: int) -> Node:
	for p in get_tree().get_nodes_in_group("player"):
		if p.name.to_int() == id:
			return p
	return null

func _player_name(id: int) -> String:
	var p := _player_node(id)
	if p:
		var n: String = p.get("char_name")
		return n if n != "" else str(id)
	return str(id)


func _send_player_list(requester: int) -> void:
	if not multiplayer.is_server():
		return
	var list: Array = []
	for p in get_tree().get_nodes_in_group("player"):
		list.append({"id": p.name.to_int(), "name": p.get("char_name")})
	if requester == multiplayer.get_unique_id():
		player_list_received.emit(list)
	else:
		_recv_player_list.rpc_id(requester, list)


func _do_invite(inviter: int, target: int) -> void:
	if not multiplayer.is_server() or inviter == target:
		return
	if _player_node(target) == null:
		return
	_invites[target] = inviter
	var inviter_name := _player_name(inviter)
	if target == multiplayer.get_unique_id():
		invite_received.emit(inviter_name)
	else:
		_recv_invite.rpc_id(target, inviter_name)


func _do_accept(invited: int) -> void:
	if not multiplayer.is_server() or not _invites.has(invited):
		return
	var inviter: int = _invites[invited]
	_invites.erase(invited)
	if _player_node(inviter) == null:
		return
	_remove_from_party(invited)
	var pid: int
	if _party_of.has(inviter):
		pid = _party_of[inviter]
	else:
		pid = _next_id
		_next_id += 1
		_parties[pid] = [inviter]
		_party_of[inviter] = pid
	if not (invited in _parties[pid]):
		_parties[pid].append(invited)
	_party_of[invited] = pid
	_notify_party(pid)


func _do_leave(peer: int) -> void:
	if not multiplayer.is_server():
		return
	var pid: int = _party_of.get(peer, 0)
	_remove_from_party(peer)
	_send_members(peer, [])  # al que sale, grupo vacio
	if pid != 0 and _parties.has(pid):
		var remaining: Array = _parties[pid]
		if remaining.size() <= 1:
			# Grupo de una sola persona: disolver.
			for m in remaining.duplicate():
				_party_of.erase(m)
				_send_members(m, [])
			_parties.erase(pid)
		else:
			_notify_party(pid)


func _remove_from_party(peer: int) -> void:
	if not _party_of.has(peer):
		return
	var pid: int = _party_of[peer]
	_party_of.erase(peer)
	if _parties.has(pid):
		(_parties[pid] as Array).erase(peer)


func _notify_party(pid: int) -> void:
	if not _parties.has(pid):
		return
	var members: Array = _parties[pid]
	for m in members:
		_send_members(m, members)


func _send_members(peer: int, members: Array) -> void:
	var data: Array = []
	for id in members:
		var p := _player_node(id)
		var cur := 0
		var mx := 1
		if p and p.has_method("get_hp"):
			cur = p.get_hp()
			mx = p.get_max_hp()
		data.append({"id": id, "name": _player_name(id), "current": cur, "max": mx})
	if peer == multiplayer.get_unique_id():
		my_members = data
		party_changed.emit()
	else:
		_recv_party.rpc_id(peer, data)


# === RPCs cliente -> servidor ===================================================

@rpc("any_peer", "reliable")
func _req_player_list() -> void:
	if multiplayer.is_server():
		_send_player_list(multiplayer.get_remote_sender_id())

@rpc("any_peer", "reliable")
func _req_invite(target: int) -> void:
	if multiplayer.is_server():
		_do_invite(multiplayer.get_remote_sender_id(), target)

@rpc("any_peer", "reliable")
func _req_accept() -> void:
	if multiplayer.is_server():
		_do_accept(multiplayer.get_remote_sender_id())

@rpc("any_peer", "reliable")
func _req_decline() -> void:
	if multiplayer.is_server():
		_invites.erase(multiplayer.get_remote_sender_id())

@rpc("any_peer", "reliable")
func _req_leave() -> void:
	if multiplayer.is_server():
		_do_leave(multiplayer.get_remote_sender_id())


# === RPCs servidor -> cliente ===================================================

@rpc("authority", "reliable")
func _recv_player_list(list: Array) -> void:
	player_list_received.emit(list)

@rpc("authority", "reliable")
func _recv_invite(from_name: String) -> void:
	invite_received.emit(from_name)

@rpc("authority", "reliable")
func _recv_party(members: Array) -> void:
	my_members = members
	party_changed.emit()
