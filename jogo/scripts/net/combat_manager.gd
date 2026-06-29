extends Node
## CombatManager
## Autoload que resuelve TODO el daño en el servidor (modelo autoritativo).
##
## Flujo:
##   1. El Hitbox del atacante (corriendo en su propio peer) detecta que ha
##      golpeado un Hurtbox y llama a report_hit(objetivo, dano).
##   2. Si ese peer ya es el servidor, aplica el dano directamente.
##      Si es un cliente, manda el golpe al servidor por RPC.
##   3. El servidor aplica el dano sobre la entidad y esta se encarga de
##      propagar su nueva vida a todos los peers.
##
## Asi el cliente nunca decide cuanta vida pierde nadie: solo informa de un
## golpe, y el servidor tiene la ultima palabra.


# Lo llama el Hitbox del atacante. 'target' es la entidad golpeada (Player o
# Enemy), 'damage' el dano base, 'attacker_id' el id del jugador atacante (0 si no).
func report_hit(target: Node, damage: int, attacker_id: int = 0) -> void:
	if target == null:
		return
	if multiplayer.is_server():
		_apply(target, damage, attacker_id)
	else:
		# Cliente: pide al servidor que aplique el golpe. Mandamos la ruta del
		# nodo porque es identica en todos los peers (mismo arbol de escena).
		_request_hit.rpc_id(1, target.get_path(), damage, attacker_id)


@rpc("any_peer", "reliable")
func _request_hit(target_path: NodePath, damage: int, attacker_id: int) -> void:
	if not multiplayer.is_server():
		return
	var target := get_node_or_null(target_path)
	if target:
		_apply(target, damage, attacker_id)


# Solo se ejecuta en el servidor.
func _apply(target: Node, damage: int, attacker_id: int) -> void:
	if target.has_method("server_take_damage"):
		target.server_take_damage(damage, attacker_id)


# --- Explosiones en area (Bola de Fuego) ---------------------------------------

func report_explosion(pos: Vector3, radius: float, damage: int, attacker_id: int) -> void:
	if multiplayer.is_server():
		_apply_explosion(pos, radius, damage, attacker_id)
	else:
		_request_explosion.rpc_id(1, pos, radius, damage, attacker_id)


@rpc("any_peer", "reliable")
func _request_explosion(pos: Vector3, radius: float, damage: int, attacker_id: int) -> void:
	if multiplayer.is_server():
		_apply_explosion(pos, radius, damage, attacker_id)


func _apply_explosion(pos: Vector3, radius: float, damage: int, attacker_id: int) -> void:
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e) and pos.distance_to(e.global_position) <= radius:
			if e.has_method("server_take_damage"):
				e.server_take_damage(damage, attacker_id)
	# Visual de la explosion (lo difunde el jugador atacante a todos los peers).
	var a := _player_node(attacker_id)
	if a != null and a.has_method("play_effect_at"):
		a.play_effect_at(pos, radius, Color(1.0, 0.5, 0.12, 0.4))


func _player_node(id: int) -> Node:
	for p in get_tree().get_nodes_in_group("player"):
		if p.name.to_int() == id:
			return p
	return null
