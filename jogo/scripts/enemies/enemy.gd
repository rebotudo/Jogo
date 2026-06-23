extends CharacterBody3D
## Enemy
## Modelo autoritativo: la IA, el movimiento, la vida y la muerte solo se
## calculan en el SERVIDOR. Los clientes no simulan nada; reciben la posicion y
## la vida por RPC y se limitan a mostrarlas.

@onready var hurtbox = $Hurtbox
@onready var nav_agent = $NavigationAgent3D
@onready var hitbox = $Hitbox
@onready var health_bar = $EnemyHealthBar

@export var speed: float = 3.0
@export var detection_range: float = 8.0    # distancia a la que detecta al jugador
@export var attack_range: float = 1.5
@export var attack_cooldown: float = 1.5
@export var leash_range: float = 14.0       # max distancia de su origen antes de rendirse
@export var patrol_radius: float = 5.0      # radio de la zona de patrulla
@export var patrol_wait: float = 2.0        # pausa al llegar a un punto de patrulla
@export var return_speed_mult: float = 1.6  # vuelve mas rapido al rendirse
@export var loot_table: Array[LootEntry] = []

# Zona de origen (se fija al aparecer) y punto de patrulla actual.
var home_position: Vector3
var _home_set: bool = false
var patrol_target: Vector3
var _patrol_wait_timer: float = 0.0

var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
var player: Node3D = null
var is_attacking: bool = false
var attack_timer: float = 0.0
var _dead: bool = false  # evita disparar muerte/loot dos veces

# Para los clientes: ultima transformada recibida del servidor (interpolamos).
var _net_position: Vector3
var _net_rotation_y: float
var _has_net_target: bool = false

enum State { PATROL, CHASE, ATTACK, RETURN }
var state: State = State.PATROL


func _ready():
	# El medidor de vida se muestra en TODOS los peers.
	if hurtbox.stats == null:
		push_warning("Enemy sin stats asignado en el Hurtbox")
	else:
		health_bar.setup(hurtbox.stats)


func _physics_process(delta):
	# --- CLIENTES: solo mostrar. Interpolar hacia lo que mando el servidor. ---
	if not multiplayer.is_server():
		if _has_net_target:
			var t := clampf(delta * 15.0, 0.0, 1.0)
			global_position = global_position.lerp(_net_position, t)
			rotation.y = lerp_angle(rotation.y, _net_rotation_y, t)
		return

	# --- SERVIDOR: IA + movimiento + combate ---
	# Fijar la zona de origen la primera vez (EnemyManager ya coloco al enemigo).
	if not _home_set:
		home_position = global_position
		patrol_target = home_position
		_home_set = true

	if not is_on_floor():
		velocity.y -= gravity * delta

	if attack_timer > 0:
		attack_timer -= delta

	# Soltar al objetivo si ya no es valido o murio.
	if not is_instance_valid(player) or player.get("is_dead"):
		player = null

	var dist_home := global_position.distance_to(home_position)
	var dist_player := INF
	if player:
		dist_player = global_position.distance_to(player.global_position)

	match state:
		State.PATROL:
			_patrol(delta)
			# Aggro: si hay un jugador dentro del rango de deteccion, perseguir.
			var target := _find_nearest_player()
			if target and global_position.distance_to(target.global_position) <= detection_range:
				player = target
				state = State.CHASE

		State.CHASE:
			if player == null:
				state = State.RETURN
			elif dist_home > leash_range:
				player = null  # demasiado lejos de la zona: rendirse
				state = State.RETURN
			elif dist_player <= attack_range:
				state = State.ATTACK
			else:
				_move_towards(player.global_position)

		State.ATTACK:
			velocity.x = 0
			velocity.z = 0
			if player == null:
				state = State.RETURN
			elif dist_home > leash_range:
				player = null
				state = State.RETURN
			elif dist_player > attack_range * 1.3:
				state = State.CHASE
			elif attack_timer <= 0:
				_attack()

		State.RETURN:
			# Se rindio: vuelve a su zona SIN perseguir (inmune por el camino).
			# Solo al llegar a casa recupera toda la vida y vuelve a patrullar.
			# Asi evitamos la oscilacion en el borde y el kiteo.
			player = null
			if dist_home <= 0.6:
				_server_reset_to_full()
				state = State.PATROL
				_patrol_wait_timer = 0.0
			else:
				_move_towards(home_position, return_speed_mult)

	move_and_slide()
	_broadcast_transform()


# Deambula por puntos aleatorios dentro de la zona de patrulla.
func _patrol(delta: float) -> void:
	if _patrol_wait_timer > 0:
		_patrol_wait_timer -= delta
		velocity.x = 0
		velocity.z = 0
		return
	if global_position.distance_to(patrol_target) <= 0.6:
		# Llegamos: esperar un poco y elegir el siguiente punto.
		_patrol_wait_timer = patrol_wait
		patrol_target = _pick_patrol_target()
		velocity.x = 0
		velocity.z = 0
		return
	_move_towards(patrol_target)


func _pick_patrol_target() -> Vector3:
	var angle := randf() * TAU
	var r := randf() * patrol_radius
	var t := home_position + Vector3(cos(angle) * r, 0.0, sin(angle) * r)
	t.y = home_position.y
	return t


func _find_nearest_player() -> Node3D:
	var nearest: Node3D = null
	var best_dist := INF
	for p in get_tree().get_nodes_in_group("player"):
		if not is_instance_valid(p):
			continue
		if p.get("is_dead"):  # ignorar jugadores muertos
			continue
		var d := global_position.distance_to(p.global_position)
		if d < best_dist:
			best_dist = d
			nearest = p
	return nearest


func _move_towards(target_pos: Vector3, speed_mult: float = 1.0) -> void:
	# Vector directo (plano) hacia el destino.
	var to_target := target_pos - global_position
	to_target.y = 0
	if to_target.length() < 0.15:
		velocity.x = 0
		velocity.z = 0
		return

	# Intentamos seguir el camino del NavigationAgent (esquiva obstaculos). Si el
	# mapa de navegacion aun no tiene ruta lista, vamos directos hacia el destino
	# para no quedarnos clavados. En un suelo plano sin obstaculos esto basta.
	nav_agent.target_position = target_pos
	var direction := to_target
	if not nav_agent.is_navigation_finished():
		var next_pos: Vector3 = nav_agent.get_next_path_position()
		var nav_dir := next_pos - global_position
		nav_dir.y = 0
		if nav_dir.length() >= 0.15:
			direction = nav_dir

	direction = direction.normalized()
	velocity.x = direction.x * speed * speed_mult
	velocity.z = direction.z * speed * speed_mult

	var look_target := global_position + direction
	look_target.y = global_position.y
	look_at(look_target, Vector3.UP)


func _attack():
	is_attacking = true
	attack_timer = attack_cooldown
	# Gesto de ataque visible en todos los peers.
	play_attack.rpc()
	# El daño = el stat de ataque del enemigo.
	var dmg: int = hurtbox.stats.attack if hurtbox.stats else 10
	hitbox.activate(dmg)
	await get_tree().create_timer(0.2).timeout
	hitbox.deactivate()
	is_attacking = false


# --- Sincronizacion (servidor -> clientes) --------------------------------------

func _broadcast_transform() -> void:
	_recv_transform.rpc(global_position, rotation.y)


@rpc("authority", "unreliable_ordered")
func _recv_transform(pos: Vector3, rot_y: float) -> void:
	_net_position = pos
	_net_rotation_y = rot_y
	_has_net_target = true


@rpc("authority", "reliable")
func _recv_hp(current: int, max_hp: int) -> void:
	# Solo en clientes: reflejar la vida que dicta el servidor.
	if hurtbox.stats == null:
		return
	hurtbox.stats.current_hp = current
	hurtbox.stats.hp_changed.emit(current, max_hp)


# --- Daño (solo servidor) -------------------------------------------------------

# Lo llama el CombatManager en el servidor cuando este enemigo recibe un golpe.
func server_take_damage(amount: int) -> void:
	if not multiplayer.is_server() or hurtbox.stats == null or _dead:
		return
	# Inmune mientras vuelve a su zona (reset estilo MMO: anti-kiteo).
	if state == State.RETURN:
		return
	hurtbox.stats.take_damage(amount)  # actualiza la vida del servidor y su medidor
	_recv_hp.rpc(hurtbox.stats.current_hp, hurtbox.stats.max_hp)
	play_hit_flash.rpc()  # parpadeo de impacto en todos los peers
	if hurtbox.stats.current_hp <= 0:
		_dead = true
		_server_drop_loot()
		EnemyManager.server_on_enemy_died(name.to_int())


# Recupera toda la vida al volver a su zona y la sincroniza a los clientes.
func _server_reset_to_full() -> void:
	if hurtbox.stats == null:
		return
	hurtbox.stats.current_hp = hurtbox.stats.max_hp
	hurtbox.stats.hp_changed.emit(hurtbox.stats.max_hp, hurtbox.stats.max_hp)
	_recv_hp.rpc(hurtbox.stats.max_hp, hurtbox.stats.max_hp)


# Suelta el botin segun la loot_table (solo servidor).
func _server_drop_loot() -> void:
	for entry in loot_table:
		if entry == null or entry.item == null:
			continue
		if randf() <= entry.drop_chance:
			var amount := randi_range(entry.min_amount, entry.max_amount)
			LootManager.server_drop(entry.item.resource_path, amount, global_position)


# --- Feedback visual (se ejecuta en todos los peers) ----------------------------

@rpc("authority", "call_local", "reliable")
func play_attack() -> void:
	_attack_lunge()


@rpc("authority", "call_local", "reliable")
func play_hit_flash() -> void:
	_hit_flash()


func _attack_lunge() -> void:
	var mesh := $MeshInstance3D as Node3D
	if mesh == null:
		return
	var tween := create_tween()
	tween.tween_property(mesh, "position:z", -0.4, 0.08)
	tween.tween_property(mesh, "position:z", 0.0, 0.12)


func _hit_flash() -> void:
	var mesh := $MeshInstance3D as MeshInstance3D
	if mesh == null:
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 1, 1)
	mat.emission_enabled = true
	mat.emission = Color(1, 1, 1)
	mat.emission_energy_multiplier = 2.0
	mesh.material_override = mat
	await get_tree().create_timer(0.12).timeout
	if is_instance_valid(mesh):
		mesh.material_override = null
