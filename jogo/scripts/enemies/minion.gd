extends CharacterBody3D
## Minion (esqueleto invocado por el Nigromante).
## Server-autoritativo: el servidor decide su IA y mueve; los clientes interpolan.
## Busca al enemigo mas cercano, lo persigue y lo golpea. Vive un tiempo limitado.
## El daño se acredita a su invocador (owner_id) para EXP/loot.

@export var speed: float = 4.5
@export var attack_range: float = 1.7
@export var attack_cooldown: float = 1.2

# El esqueleto hace de guardia: se queda en un area alrededor de su invocador y
# solo ataca a enemigos que entren en ella (no persigue hasta el infinito).
const AGGRO_RADIUS: float = 11.0   # radio alrededor del jugador donde atacan
const LEASH_MARGIN: float = 3.0    # margen extra antes de soltar a un enemigo
const FOLLOW_DIST: float = 3.0     # distancia a la que se quedan del jugador en reposo
var owner_node: Node3D = null

@onready var hurtbox = $Hurtbox
@onready var health_bar = $MinionHealthBar

const CharacterVisual = preload("res://scripts/player/character_visual.gd")
var _avatar: CharacterVisual = null

var owner_id: int = 0
var damage: int = 10
var _life: float = 15.0
var _atk_timer: float = 0.0
var target: Node3D = null
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")


func _ready() -> void:
	add_to_group("minion")  # para que los enemigos lo detecten y ataquen
	# (Revertido a capsulas) sin muñeco animado: se queda la capsula del esqueleto.

# Para los clientes: ultima transformada recibida del servidor.
var _net_pos: Vector3
var _net_rot: float
var _has_net: bool = false


func setup(p_owner: int, p_damage: int, p_lifetime: float, p_max_hp: int) -> void:
	owner_id = p_owner
	damage = p_damage
	_life = p_lifetime
	if hurtbox != null and hurtbox.stats != null:
		hurtbox.stats.max_hp = p_max_hp
		hurtbox.stats.current_hp = p_max_hp
		if health_bar != null:
			health_bar.setup(hurtbox.stats)


# Lo llama el CombatManager cuando un enemigo golpea al minion.
func server_take_damage(amount: int, _attacker_id: int = 0) -> void:
	if not multiplayer.is_server() or hurtbox == null or hurtbox.stats == null:
		return
	hurtbox.stats.take_damage(amount)
	_recv_hp.rpc(hurtbox.stats.current_hp, hurtbox.stats.max_hp)
	play_hit_flash.rpc()  # parpadeo de impacto en todos los peers
	if hurtbox.stats.current_hp <= 0:
		MinionManager.server_despawn(name.to_int())


# Feedback visual en todos los peers (autoridad = servidor).
@rpc("authority", "call_local", "reliable")
func play_attack() -> void:
	if is_instance_valid(_avatar):
		_avatar.attack(false)


@rpc("authority", "call_local", "reliable")
func play_hit_flash() -> void:
	if is_instance_valid(_avatar):
		_avatar.flash()


@rpc("authority", "reliable")
func _recv_hp(cur: int, mx: int) -> void:
	if hurtbox == null or hurtbox.stats == null:
		return
	hurtbox.stats.current_hp = cur
	hurtbox.stats.hp_changed.emit(cur, mx)


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		if _has_net:
			var t := clampf(delta * 15.0, 0.0, 1.0)
			global_position = global_position.lerp(_net_pos, t)
			rotation.y = lerp_angle(rotation.y, _net_rot, t)
		return

	# --- SERVIDOR ---
	_life -= delta
	if _life <= 0.0:
		MinionManager.server_despawn(name.to_int())
		return

	if not is_on_floor():
		velocity.y -= gravity * delta
	if _atk_timer > 0.0:
		_atk_timer -= delta

	# Centro del area de guardia = el jugador que lo invoco (si sigue vivo).
	if not is_instance_valid(owner_node):
		owner_node = _find_owner()
	var center: Vector3 = global_position
	if is_instance_valid(owner_node):
		center = owner_node.global_position

	# Soltamos al objetivo si sale del area alrededor del jugador.
	if is_instance_valid(target):
		if center.distance_to(target.global_position) > AGGRO_RADIUS + LEASH_MARGIN:
			target = null
	if not is_instance_valid(target):
		target = _find_target(center)

	if target == null:
		# Sin enemigos en el area: volver/quedarse junto al jugador.
		_follow_owner(center)
		move_and_slide()
		_broadcast()
		return

	var d := global_position.distance_to(target.global_position)
	if d > attack_range:
		var dir := target.global_position - global_position
		dir.y = 0.0
		if dir.length() > 0.05:
			dir = dir.normalized()
			velocity.x = dir.x * speed
			velocity.z = dir.z * speed
			var lt := global_position + dir
			lt.y = global_position.y
			look_at(lt, Vector3.UP)
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		if _atk_timer <= 0.0:
			_atk_timer = attack_cooldown
			play_attack.rpc()  # gesto de golpe en todos los peers
			if target.has_method("server_take_damage"):
				target.server_take_damage(damage, owner_id)

	move_and_slide()
	_broadcast()


# Se mueve hacia el jugador y se detiene cerca (en reposo, sin enemigos).
func _follow_owner(center: Vector3) -> void:
	var d := global_position.distance_to(center)
	if d > FOLLOW_DIST:
		var dir := center - global_position
		dir.y = 0.0
		if dir.length() > 0.05:
			dir = dir.normalized()
			velocity.x = dir.x * speed
			velocity.z = dir.z * speed
			var lt := global_position + dir
			lt.y = global_position.y
			look_at(lt, Vector3.UP)
	else:
		velocity.x = 0.0
		velocity.z = 0.0


# Enemigo mas cercano DENTRO del area alrededor del jugador (no busca lejos).
func _find_target(center: Vector3) -> Node3D:
	var best: Node3D = null
	var best_dist := AGGRO_RADIUS
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e):
			continue
		var dd: float = center.distance_to(e.global_position)
		if dd <= AGGRO_RADIUS and dd < best_dist:
			best_dist = dd
			best = e
	return best


func _find_owner() -> Node3D:
	for p in get_tree().get_nodes_in_group("player"):
		if p.name.to_int() == owner_id:
			return p
	return null


func _broadcast() -> void:
	_recv_transform.rpc(global_position, rotation.y)


@rpc("authority", "unreliable_ordered")
func _recv_transform(pos: Vector3, rot_y: float) -> void:
	_net_pos = pos
	_net_rot = rot_y
	_has_net = true
