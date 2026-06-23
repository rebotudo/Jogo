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
# Enemy), 'damage' el dano base del hitbox.
func report_hit(target: Node, damage: int) -> void:
	if target == null:
		return
	if multiplayer.is_server():
		_apply(target, damage)
	else:
		# Cliente: pide al servidor que aplique el golpe. Mandamos la ruta del
		# nodo porque es identica en todos los peers (mismo arbol de escena).
		_request_hit.rpc_id(1, target.get_path(), damage)


@rpc("any_peer", "reliable")
func _request_hit(target_path: NodePath, damage: int) -> void:
	if not multiplayer.is_server():
		return
	var target := get_node_or_null(target_path)
	if target:
		_apply(target, damage)


# Solo se ejecuta en el servidor.
func _apply(target: Node, damage: int) -> void:
	if target.has_method("server_take_damage"):
		target.server_take_damage(damage)
