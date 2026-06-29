extends CharacterBody3D

@export var stats: CharacterStats

@export var speed: float = 5.0
const SPRINT_MULT: float = 1.6  # multiplicador de velocidad al correr (Mayús)
@export var jump_force: float = 5.0
@export var attack_cooldown: float = 0.5
@export var give_starter_kit: bool = false  # (PRUEBA) kit inicial de objetos

var attack_timer: float = 0.0
# Recuperacion del golpe melé secundario (daga del arquero con el arco equipado).
var _melee_timer: float = 0.0

# Combo de ataques basicos: cada clase define una secuencia de golpes
# [{mult, cd}, ...]. Cada golpe encadena al siguiente; el finisher pega mas
# fuerte pero tiene mas recuperacion. Si pasa COMBO_WINDOW sin atacar, se
# reinicia al primer golpe.
const COMBO_WINDOW: float = 1.2
var _combo: Array = []
var _combo_index: int = 0
var _combo_timer: float = 0.0

# Carga del arco (mantener clic): de toque (x0.5 daño) a carga completa (x2).
const BOW_MAX_CHARGE: float = 1.2
const BOW_MIN_MULT: float = 0.5
const BOW_MAX_MULT: float = 2.0
var _charging: bool = false
var _charge_time: float = 0.0

# --- Habilidades ---
const MANA_REGEN: float = 4.0           # maná regenerado por segundo
const MP_PUSH_INTERVAL: float = 0.5     # cada cuanto sincroniza el maná al dueño
const DASH_SPEED: float = 18.0
# Tipos de habilidad que hacen daño (rompen la invisibilidad). Dash/buff/cura no.
const DAMAGING_ABILITY_TYPES := ["aoe_damage", "aoe_stun", "projectile_strong", "shadow_dance", "beam", "storm", "drain", "smite_heal", "hammer", "pierce_arrow", "burst"]
var abilities: Array = []               # lista de habilidades de la clase
var _ability_cd: Array = [0.0, 0.0, 0.0, 0.0]     # cooldowns (servidor)
var _ability_cd_ui: Array = [0.0, 0.0, 0.0, 0.0]  # cooldowns para el HUD (dueño)
var _mana_acc: float = 0.0
var _mp_push_timer: float = 0.0
var _dash_time: float = 0.0
var _dash_dir: Vector3 = Vector3.ZERO
var _dash_speed: float = DASH_SPEED  # velocidad del dash/esquiva actual

# --- Cámara cenital y apuntado estilo V Rising ---
const CAM_PITCH_DEG: float = -55.0   # cuanto mira hacia abajo (inicial)
const CAM_DISTANCE: float = 9.0      # zoom (distancia camara-jugador)
const CAM_ROT_SENS: float = 0.006    # sensibilidad al rotar con clic derecho
const AIM_ROT_SPEED: float = 18.0    # rapidez con que el cuerpo gira hacia el cursor
var _cam_yaw: float = 0.0                          # giro horizontal de la camara
var _cam_pitch: float = deg_to_rad(CAM_PITCH_DEG)  # inclinacion de la camara
var _shake: float = 0.0                            # intensidad de temblor de camara

# Solo usamos tercera persona (la cenital se descarto).
enum CamMode { TOPDOWN, THIRD_PERSON }
var cam_mode: int = CamMode.THIRD_PERSON
const TP_DISTANCE: float = 3.5        # distancia camara en tercera persona
const TP_PITCH: float = -0.3          # inclinacion inicial (rad) en tercera persona
const DODGE_SPEED: float = 17.0
const DODGE_TIME: float = 0.2
const DODGE_COOLDOWN: float = 0.9
const DODGE_IFRAMES: float = 0.28
var _aim_dir: Vector3 = Vector3.FORWARD   # direccion horizontal hacia el cursor
var _aim_point: Vector3 = Vector3.ZERO    # punto del suelo bajo el cursor
var _dodge_cd: float = 0.0
var _invuln_time: float = 0.0             # i-frames (servidor): ignora daño mientras > 0

# Buffs temporales (solo servidor). Cada uno: { time_left, atk_add, def_add,
# lifesteal, dmg_mult, cc_immune, apoc }.
var _buffs: Array = []
var _lifesteal: float = 0.0          # fraccion de vida robada al dañar
var _dmg_taken_mult: float = 1.0     # multiplicador de daño recibido (<1 = reduccion)
var _cc_immune: bool = false

# Tanque: Guardia Protectora (redirige daño de aliados) y Bastión (zona).
const GUARD_RANGE: float = 12.0
var _guard_time: float = 0.0
var _guard_fraction: float = 0.0
var _bastion_time: float = 0.0
var _bastion_pos: Vector3 = Vector3.ZERO
var _bastion_radius: float = 7.0
var _bastion_ally_mult: float = 0.6
var _bastion_regen: int = 10
var _bastion_tick: float = 0.0

# Nigromante: id del esqueleto único de la E (para limitarlo a 1).
var _single_minion_id: int = 0

# Paladín: aura de curación de Ascensión Sagrada.
var _ascension_time: float = 0.0
var _ascension_radius: float = 12.0
var _ascension_heal: int = 0
var _ascension_tick: float = 0.0

# Curandero: curación gradual (HoT) acumulada de los buffs.
var _hot_per_sec: float = 0.0
var _hot_acc: float = 0.0
var _hot_tick: float = 0.0

# Mago/Arquero: tormenta o lluvia (zona que daña por ticks).
var _storm_time: float = 0.0
var _storm_pos: Vector3 = Vector3.ZERO
var _storm_radius: float = 8.0
var _storm_dmg: int = 0
var _storm_tick: float = 0.0
var _storm_color: Color = Color(0.95, 0.45, 0.95, 0.16)

# Arquero: trampa de caza.
var _trap_active: bool = false
var _trap_pos: Vector3 = Vector3.ZERO
var _trap_radius: float = 2.0
var _trap_stun: float = 3.0
var _trap_dmg: int = 0
var _trap_time: float = 0.0

# Asesino: invisibilidad (los enemigos no te ven) y veneno en los ataques.
var is_invisible: bool = false       # publico, lo consultan los enemigos
var _owner_invis: bool = false       # copia local del dueño (para romper sigilo al atacar)
var _poison_attacks: bool = false    # recomputado de los buffs

# Datos del personaje (los fija el servidor al aplicar el personaje elegido).
var char_name: String = ""
var char_class: String = ""
var char_start_city: String = ""

@onready var spring_arm = $SpringArm3D
@onready var camera = $SpringArm3D/Camera3D
@onready var hitbox = $Hitbox
@onready var hurtbox = $Hurtbox
@onready var mesh = $MeshInstance3D
@onready var collision = $CollisionShape3D

# Cuerpo 3D del jugador por clase (reemplaza la capsula al conocer la clase).
# Y Bot de Mixamo con animaciones direccionales (tintado por clase).
const CharacterVisual = preload("res://scripts/player/mixamo_visual.gd")
var _avatar: CharacterVisual = null
var _avatar_class: String = ""

var _projectile_scene: PackedScene = preload("res://scenes/combat/projectile.tscn")
var is_attacking: bool = false
var is_dead: bool = false

const RESPAWN_DELAY: float = 3.0

# Combate: el jugador esta "en combate" mientras este temporizador (en el
# servidor) sea > 0. Se pone al atacar o al recibir daño. Equipar solo se
# permite fuera de combate.
const COMBAT_DURATION: float = 5.0
var combat_timer: float = 0.0

const MAX_LEVEL: int = 200

var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
var mouse_sensitivity = 0.003

# Para jugadores REMOTOS: ultima transformada recibida de su dueño por RPC.
# Interpolamos hacia ella para que el movimiento se vea suave.
var _net_position: Vector3
var _net_rotation_y: float
var _has_net_target: bool = false

func _enter_tree():
	# El nombre del nodo es el peer_id (lo asigna NetworkManager al spawnear).
	# Fijar la autoridad aqui hace que is_multiplayer_authority() sea correcto
	# desde el primer frame: cada peer solo controla y difunde SU propio jugador.
	set_multiplayer_authority(name.to_int())

func _ready():
	# (PRUEBA) El servidor da un kit inicial para probar inventario y equipo.
	# Pon give_starter_kit = false en el inspector del jugador para desactivarlo.
	if multiplayer.is_server() and give_starter_kit:
		call_deferred("_grant_starter_kit")
	# El servidor escucha los cambios de vida para informar al grupo.
	if multiplayer.is_server():
		call_deferred("_server_connect_hp")

	# Solo el jugador LOCAL toma control de raton, camara y HUD.
	if not is_multiplayer_authority():
		set_process_unhandled_input(false)
		# Si somos un cliente, pedimos al servidor la clase de este jugador para
		# construir su muñeco (cubre el caso de unirse despues de que eligiera).
		if not multiplayer.is_server():
			call_deferred("_request_identity")
		return

	camera.current = true
	# Raton VISIBLE y confinado a la ventana: lo usamos para apuntar (V Rising).
	_apply_cam_mode()
	call_deferred("_setup_hud")
	call_deferred("_submit_character")


# Aplica la configuracion de la camara segun el modo elegido (cenital/3ª persona).
func _apply_cam_mode() -> void:
	if spring_arm == null:
		return
	if cam_mode == CamMode.TOPDOWN:
		spring_arm.spring_length = CAM_DISTANCE
		_cam_pitch = deg_to_rad(CAM_PITCH_DEG)
		# Alineamos el giro de la camara con la orientacion actual del cuerpo.
		_cam_yaw = rotation.y
		spring_arm.collision_mask = 0  # sin colision: distancia fija, no tiembla
	else:
		spring_arm.spring_length = TP_DISTANCE
		spring_arm.rotation = Vector3(TP_PITCH, 0.0, 0.0)
		spring_arm.collision_mask = 1  # vuelve a evitar atravesar paredes
	Input.mouse_mode = _play_mouse_mode()


# Modo de raton en juego segun la camara: capturado en 3ª persona (mouse-look),
# confinado y visible en cenital (apuntar con el cursor).
func _play_mouse_mode() -> int:
	return Input.MOUSE_MODE_CAPTURED if cam_mode == CamMode.THIRD_PERSON else Input.MOUSE_MODE_CONFINED


# Cambia entre cenital y tercera persona (tecla V).
func _toggle_cam_mode() -> void:
	cam_mode = CamMode.THIRD_PERSON if cam_mode == CamMode.TOPDOWN else CamMode.TOPDOWN
	_apply_cam_mode()

func _setup_hud():
	var hud = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.setup(hurtbox.stats, self)

func _unhandled_input(event):
	# set_process_unhandled_input(false) ya bloquea esto para los no-locales,
	# pero dejamos la guarda por seguridad.
	if not is_multiplayer_authority():
		return
	# Tercera persona: el raton gira el cuerpo y la inclinacion (mouse-look).
	if event is InputEventMouseMotion and _playing():
		rotate_y(-event.relative.x * mouse_sensitivity)
		spring_arm.rotate_x(-event.relative.y * mouse_sensitivity)
		spring_arm.rotation.x = clamp(spring_arm.rotation.x, -1.2, 0.4)
	# I: inventario. P: grupo.
	if event.is_action_pressed("inventory"):
		_toggle_inventory()
	if event.is_action_pressed("party"):
		_toggle_party()
	# Habilidades Q/E/R/F (solo en juego, no mientras navegamos un panel).
	if _playing():
		if event.is_action_pressed("ability_q"):
			request_cast(0)
		elif event.is_action_pressed("ability_e"):
			request_cast(1)
		elif event.is_action_pressed("ability_r"):
			request_cast(2)
		elif event.is_action_pressed("ability_f"):
			request_cast(3)
	# Escape: cierra inventario/grupo si estan abiertos; si no, abre/cierra el
	# menu de pausa (Jugar / Opciones / Salir).
	if event.is_action_pressed("open_menu"):
		var hud = get_tree().get_first_node_in_group("hud")
		if hud:
			var closed_panel := false
			if hud.has_method("is_inventory_open") and hud.is_inventory_open():
				hud.toggle_inventory()
				closed_panel = true
			if hud.has_method("is_party_open") and hud.is_party_open():
				hud.toggle_party()
				closed_panel = true
			if not closed_panel and hud.has_method("toggle_pause"):
				hud.toggle_pause()
			_update_mouse_mode(hud)

func _toggle_inventory():
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("toggle_inventory"):
		hud.toggle_inventory()
		_update_mouse_mode(hud)

func _toggle_party():
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("toggle_party"):
		hud.toggle_party()
		_update_mouse_mode(hud)

# El raton se libera si hay algun panel abierto; si no, se recaptura.
func _update_mouse_mode(hud) -> void:
	var any_open := false
	if hud.has_method("is_inventory_open") and hud.is_inventory_open():
		any_open = true
	if hud.has_method("is_party_open") and hud.is_party_open():
		any_open = true
	if hud.has_method("is_pause_open") and hud.is_pause_open():
		any_open = true
	# Con panel: raton libre. En juego: segun el modo de camara.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if any_open else _play_mouse_mode()


# Reajusta el modo de raton segun el estado de la UI (lo llama el HUD al cerrar
# el menu de pausa desde un boton, para recapturar el raton).
func refresh_mouse_mode() -> void:
	if not is_multiplayer_authority():
		return
	var hud = get_tree().get_first_node_in_group("hud")
	if hud:
		_update_mouse_mode(hud)


# ¿Estamos jugando (sin ningun panel de UI abierto)?
func _playing() -> bool:
	var hud = get_tree().get_first_node_in_group("hud")
	if hud == null:
		return true
	if hud.has_method("is_inventory_open") and hud.is_inventory_open():
		return false
	if hud.has_method("is_party_open") and hud.is_party_open():
		return false
	if hud.has_method("is_pause_open") and hud.is_pause_open():
		return false
	return true


# Entrada de movimiento. Cenital: relativa a la camara (8 dir). Tercera persona:
# relativa a hacia donde mira el cuerpo (como un shooter clasico).
func _world_move_input() -> Vector3:
	var dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var move := Vector3(dir.x, 0.0, dir.y)
	if move.length() > 1.0:
		move = move.normalized()
	if cam_mode == CamMode.TOPDOWN:
		return move.rotated(Vector3.UP, _cam_yaw)
	# Tercera persona: relativo al cuerpo.
	move = transform.basis * move
	move.y = 0.0
	return move


# Camara cenital: orientacion fija (no rota con el cuerpo). Tercera persona: la
# camara cuelga del cuerpo y la inclina el mouse-look, asi que no la tocamos.
func _update_camera() -> void:
	if spring_arm != null and cam_mode == CamMode.TOPDOWN:
		spring_arm.global_rotation = Vector3(_cam_pitch, _cam_yaw, 0.0)
	# Temblor de camara (decae con el tiempo).
	if camera != null:
		if _shake > 0.001:
			camera.h_offset = randf_range(-1.0, 1.0) * _shake
			camera.v_offset = randf_range(-1.0, 1.0) * _shake
			_shake = move_toward(_shake, 0.0, get_physics_process_delta_time() * 0.8)
		elif camera.h_offset != 0.0 or camera.v_offset != 0.0:
			camera.h_offset = 0.0
			camera.v_offset = 0.0


func add_shake(amount: float) -> void:
	if not FloatingText.shake_enabled:
		return
	_shake = maxf(_shake, amount)


# Calcula la direccion de apuntado. Cenital: hacia el cursor (y gira el cuerpo).
# Tercera persona: hacia donde mira el cuerpo (lo controla el mouse-look).
func _update_aim(delta: float) -> void:
	if cam_mode == CamMode.THIRD_PERSON:
		# Apuntamos hacia donde mira la camara (incluye la inclinacion: puedes
		# apuntar arriba/abajo). El cuerpo lo gira el mouse-look.
		if camera != null:
			var f: Vector3 = -camera.global_transform.basis.z
			if f.length() > 0.01:
				_aim_dir = f.normalized()
		return
	if camera == null:
		return
	var mouse := get_viewport().get_mouse_position()
	var from: Vector3 = camera.project_ray_origin(mouse)
	var ray: Vector3 = camera.project_ray_normal(mouse)
	var plane := Plane(Vector3.UP, global_position.y)
	var hit = plane.intersects_ray(from, ray)
	if hit != null:
		_aim_point = hit
		var d: Vector3 = hit - global_position
		d.y = 0.0
		if d.length() > 0.05:
			_aim_dir = d.normalized()
	if _aim_dir.length() > 0.01:
		var t := Transform3D(Basis(), Vector3.ZERO).looking_at(_aim_dir, Vector3.UP)
		var ty: float = t.basis.get_euler().y
		rotation.y = lerp_angle(rotation.y, ty, clampf(delta * AIM_ROT_SPEED, 0.0, 1.0))


# Esquiva: dash corto hacia el movimiento (o hacia el cursor si estas quieto)
# con breves i-frames (invulnerabilidad).
func _start_dodge(move: Vector3) -> void:
	if _dodge_cd > 0.0 or _dash_time > 0.0 or is_dead:
		return
	var d: Vector3 = move
	d.y = 0.0
	if d.length() < 0.1:
		d = _aim_dir
	if d.length() < 0.01:
		return
	_dash_dir = d.normalized()
	_dash_speed = DODGE_SPEED
	_dash_time = DODGE_TIME
	_dodge_cd = DODGE_COOLDOWN
	_report_combat()
	if multiplayer.is_server():
		_invuln_time = maxf(_invuln_time, DODGE_IFRAMES)
	else:
		_req_invuln.rpc_id(1, DODGE_IFRAMES)


# El dueño pide al servidor unos i-frames (al esquivar).
@rpc("any_peer", "reliable")
func _req_invuln(dur: float) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != name.to_int():
		return
	_invuln_time = maxf(_invuln_time, dur)


func _physics_process(delta):
	# El servidor (en TODAS las copias) descuenta combate, regenera maná y baja
	# los cooldowns de las habilidades.
	if multiplayer.is_server():
		if combat_timer > 0.0:
			combat_timer = maxf(combat_timer - delta, 0.0)
		if _invuln_time > 0.0:
			_invuln_time = maxf(_invuln_time - delta, 0.0)
		_server_ability_tick(delta)

	if not is_multiplayer_authority():
		# Jugador REMOTO: no lo simulamos. Interpolamos hacia la ultima
		# transformada que nos envio su dueño (ver _recv_transform).
		if _has_net_target:
			var t := clampf(delta * 15.0, 0.0, 1.0)
			global_position = global_position.lerp(_net_position, t)
			rotation.y = lerp_angle(rotation.y, _net_rotation_y, t)
		return

	# Muerto: no nos movemos ni atacamos hasta reaparecer.
	if is_dead:
		_cancel_charge()
		velocity = Vector3.ZERO
		return

	# Cooldowns de habilidades para el HUD (cuenta atras visual del dueño).
	_tick_ability_cooldowns_ui(delta)

	# Apuntado primero (puede girar el cuerpo) y LUEGO fijamos la camara, para que
	# la cenital no tiemble al girar el personaje.
	_update_aim(delta)
	_update_camera()
	if _dodge_cd > 0.0:
		_dodge_cd = maxf(_dodge_cd - delta, 0.0)

	# Dash de habilidad / esquiva: movimiento forzado breve (con colision).
	if _dash_time > 0.0:
		_dash_time -= delta
		if not is_on_floor():
			velocity.y -= gravity * delta
		velocity.x = _dash_dir.x * _dash_speed
		velocity.z = _dash_dir.z * _dash_speed
		move_and_slide()
		_recv_transform.rpc(global_position, rotation.y)
		return

	# Jugador LOCAL: simulacion normal.
	if attack_timer > 0:
		attack_timer -= delta
	if _melee_timer > 0.0:
		_melee_timer -= delta

	# Ventana de combo: si dejas de atacar, vuelve al primer golpe.
	if _combo_timer > 0.0:
		_combo_timer -= delta
		if _combo_timer <= 0.0:
			_combo_index = 0

	if not is_on_floor():
		velocity.y -= gravity * delta

	# Movimiento relativo a la CAMARA (8 direcciones), independiente de hacia
	# donde apunta el cuerpo. La camara es fija, asi que usamos ejes del mundo.
	var move: Vector3 = _world_move_input()

	if move.length() > 0.01:
		# Mantener Mayús izquierdo = correr (sprint).
		var spd: float = speed
		if Input.is_key_pressed(KEY_SHIFT):
			spd *= SPRINT_MULT
		velocity.x = move.x * spd
		velocity.z = move.z * spd
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)

	# Espacio: salto.
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_force

	# Ataque (solo en juego, no mientras navegamos la UI). El arco se carga
	# manteniendo el clic; el resto de armas es instantaneo. Apunta al cursor.
	if _playing():
		if _is_bow():
			_handle_bow_charge(delta)
			# Click derecho: golpe melé de respaldo (daga). En cenital el clic
			# derecho rota la camara, asi que el jab solo va en tercera persona.
			if cam_mode == CamMode.THIRD_PERSON and Input.is_action_just_pressed("secondary_attack") and not is_attacking and _melee_timer <= 0.0:
				_melee_jab()
		elif Input.is_action_just_pressed("attack") and not is_attacking and attack_timer <= 0:
			_attack()
	elif _charging:
		_cancel_charge()  # se abrio un menu mientras cargabamos

	move_and_slide()

	# Difundimos nuestra posicion y orientacion a los demas peers. Al ser la
	# autoridad de este nodo, el RPC se ejecuta en todos los OTROS clientes.
	_recv_transform.rpc(global_position, rotation.y)

func _attack():
	# Ataque instantaneo (melé o baston magico). El daño se resuelve en el
	# servidor via CombatManager (modelo autoritativo).
	is_attacking = true
	# Paso actual del combo: define el multiplicador de daño y la recuperacion.
	var mult: float = 1.0
	var cd: float = attack_cooldown
	if not _combo.is_empty():
		var step: Dictionary = _combo[_combo_index]
		mult = float(step.get("mult", 1.0))
		cd = float(step.get("cd", attack_cooldown))
		_combo_index = (_combo_index + 1) % _combo.size()
		_combo_timer = COMBO_WINDOW
	attack_timer = cd
	_report_combat()  # atacar te pone en combate
	_notify_attack_action()  # un ataque rompe la invisibilidad
	var base_atk: int = 10
	if hurtbox.stats != null:
		base_atk = int(hurtbox.stats.attack)
	var dmg: int = int(round(float(base_atk) * mult))
	var strong: bool = mult >= 1.4  # golpe finisher: gesto/feedback mas marcado
	if _weapon_type() == ItemData.WeaponType.STAFF:
		# Baston: bola magica instantanea.
		_fire_projectile(dmg, "magic")
		await get_tree().create_timer(0.2).timeout
	else:
		# Cuerpo a cuerpo: gesto + hitbox.
		play_attack.rpc(strong)
		hitbox.activate(dmg)
		await get_tree().create_timer(0.2).timeout
		hitbox.deactivate()
	is_attacking = false


# Golpe melé secundario del arquero (daga) al pulsar click derecho con el arco
# equipado. Pega menos que el arco porque el arma principal es el arco.
func _melee_jab() -> void:
	is_attacking = true
	_melee_timer = 0.6
	_cancel_charge()  # si estaba cargando el arco, lo interrumpe
	_update_charge_ui(-1.0)
	_report_combat()
	_notify_attack_action()  # golpear rompe la invisibilidad
	var base_atk: int = 10
	if hurtbox.stats != null:
		base_atk = int(hurtbox.stats.attack)
	var dmg: int = int(round(float(base_atk) * 0.5))
	play_attack.rpc(false)
	hitbox.activate(dmg)
	await get_tree().create_timer(0.18).timeout
	hitbox.deactivate()
	is_attacking = false


# Carga del arco: mantener para cargar, soltar para disparar (mas carga = mas daño).
func _handle_bow_charge(delta: float) -> void:
	if Input.is_action_pressed("attack") and attack_timer <= 0.0:
		_charging = true
		_charge_time = minf(_charge_time + delta, BOW_MAX_CHARGE)
		_update_charge_ui(_charge_time / BOW_MAX_CHARGE)
	if Input.is_action_just_released("attack") and _charging:
		_charging = false
		var ratio := _charge_time / BOW_MAX_CHARGE
		_charge_time = 0.0
		_update_charge_ui(-1.0)  # ocultar
		attack_timer = attack_cooldown
		_report_combat()
		_notify_attack_action()  # disparar rompe la invisibilidad
		var base_dmg: int = hurtbox.stats.attack if hurtbox.stats else 10
		var dmg := int(round(base_dmg * lerpf(BOW_MIN_MULT, BOW_MAX_MULT, ratio)))
		_fire_projectile(dmg, "arrow")


func _cancel_charge() -> void:
	if _charging or _charge_time > 0.0:
		_charging = false
		_charge_time = 0.0
		_update_charge_ui(-1.0)


func _update_charge_ui(ratio: float) -> void:
	if not is_multiplayer_authority():
		return
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("set_charge"):
		hud.set_charge(ratio)


# === Habilidades ================================================================

# Tick del servidor: regenera maná, baja cooldowns y sincroniza maná al dueño.
func _server_ability_tick(delta: float) -> void:
	if hurtbox.stats == null:
		return
	var s: CharacterStats = hurtbox.stats
	if s.current_mp < s.max_mp:
		_mana_acc += MANA_REGEN * delta
		if _mana_acc >= 1.0:
			var add := int(_mana_acc)
			_mana_acc -= float(add)
			s.current_mp = mini(s.current_mp + add, s.max_mp)
	for i in 4:
		if _ability_cd[i] > 0.0:
			_ability_cd[i] = maxf(_ability_cd[i] - delta, 0.0)
	# Buffs temporales: descontar tiempo y revertir los que expiran.
	if not _buffs.is_empty():
		var expired := false
		for i in range(_buffs.size() - 1, -1, -1):
			_buffs[i]["time_left"] -= delta
			if _buffs[i]["time_left"] <= 0.0:
				s.attack -= int(_buffs[i]["atk_add"])
				s.defense -= int(_buffs[i]["def_add"])
				_buffs.remove_at(i)
				expired = true
		if expired:
			_recompute_buffs()
			_push_inventory()  # resincronizar ataque/defensa al dueño
			_push_buffs()      # actualizar la barra de buffs
	# Ascensión Sagrada: aura que cura a los aliados cercanos cada segundo.
	if _ascension_time > 0.0:
		_ascension_time = maxf(_ascension_time - delta, 0.0)
		_ascension_tick -= delta
		if _ascension_tick <= 0.0:
			_ascension_tick = 1.0
			for id in PartyManager.members_of(name.to_int()):
				var ap := _player_by_id(id)
				if ap != null and is_instance_valid(ap) and not ap.get("is_dead"):
					if global_position.distance_to(ap.global_position) <= _ascension_radius and ap.has_method("server_heal"):
						ap.server_heal(_ascension_heal)
			_play_effect.rpc(global_position, 2.0, Color(1.0, 0.95, 0.5, 0.25))

	# Curación gradual (Renovación): cura por chunks cada 0.5 s.
	if _hot_per_sec > 0.0:
		_hot_acc += _hot_per_sec * delta
		_hot_tick -= delta
		if _hot_tick <= 0.0:
			_hot_tick = 0.5
			if _hot_acc >= 1.0:
				var h := int(_hot_acc)
				_hot_acc -= float(h)
				server_heal(h)

	# Tormenta/Lluvia: zona que daña por ticks.
	if _storm_time > 0.0:
		_storm_time = maxf(_storm_time - delta, 0.0)
		_storm_tick -= delta
		if _storm_tick <= 0.0:
			_storm_tick = 0.7
			_storm_pulse()

	# Trampa de Caza: aturde al primer enemigo que la pisa.
	if _trap_active:
		_trap_time -= delta
		if _trap_time <= 0.0:
			_trap_active = false
		else:
			for e in get_tree().get_nodes_in_group("enemy"):
				if not is_instance_valid(e):
					continue
				if _trap_pos.distance_to(e.global_position) <= _trap_radius:
					e.server_take_damage(_trap_dmg, name.to_int())
					if e.has_method("server_stun"):
						e.server_stun(_trap_stun)
					_trap_active = false
					_play_effect.rpc(_trap_pos, _trap_radius, Color(0.9, 0.7, 0.2, 0.4))
					break
	# Guardia Protectora: tiempo restante.
	if _guard_time > 0.0:
		_guard_time = maxf(_guard_time - delta, 0.0)
	# Bastión Imperecedero: zona de regeneracion + proteccion para aliados.
	if _bastion_time > 0.0:
		_bastion_time = maxf(_bastion_time - delta, 0.0)
		_bastion_tick -= delta
		if _bastion_tick <= 0.0:
			_bastion_tick = 1.0
			_bastion_pulse()
	_mp_push_timer -= delta
	if _mp_push_timer <= 0.0:
		_mp_push_timer = MP_PUSH_INTERVAL
		_push_mp()


func _push_mp() -> void:
	if not multiplayer.is_server() or hurtbox.stats == null:
		return
	var s: CharacterStats = hurtbox.stats
	var owner_id := name.to_int()
	if owner_id == multiplayer.get_unique_id():
		_apply_mp_ui(s.current_mp, s.max_mp)
	else:
		_recv_mp.rpc_id(owner_id, s.current_mp, s.max_mp)


@rpc("any_peer", "reliable")
func _recv_mp(cur: int, mx: int) -> void:
	if not _is_from_server() or hurtbox.stats == null:
		return
	hurtbox.stats.current_mp = cur
	hurtbox.stats.max_mp = mx
	_apply_mp_ui(cur, mx)


func _apply_mp_ui(cur: int, mx: int) -> void:
	if not is_multiplayer_authority():
		return
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("set_mp"):
		hud.set_mp(cur, mx)


# --- Lanzar (dueño pide, servidor valida) ---

func request_cast(slot: int) -> void:
	if slot < 0 or slot >= abilities.size():
		return  # slot sin habilidad
	if _ability_cd_ui[slot] > 0.0:
		return  # en cooldown (chequeo local para no spamear el servidor)
	if multiplayer.is_server():
		_server_cast(slot)
	else:
		_req_cast.rpc_id(1, slot)


@rpc("any_peer", "reliable")
func _req_cast(slot: int) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != name.to_int():
		return
	_server_cast(slot)


func _server_cast(slot: int) -> void:
	if not multiplayer.is_server() or is_dead or hurtbox.stats == null:
		return
	if slot < 0 or slot >= abilities.size() or _ability_cd[slot] > 0.0:
		return
	var ab: Dictionary = abilities[slot]
	var s: CharacterStats = hurtbox.stats
	var mana_cost := int(ab.get("mana", 0))
	if s.current_mp < mana_cost:
		server_notify("Maná insuficiente")
		return
	s.current_mp -= mana_cost
	var cd := float(ab.get("cooldown", 1.0))
	_ability_cd[slot] = cd
	_push_mp()
	# Efectos que resuelve el servidor.
	match String(ab.get("type", "")):
		"aoe_damage": _server_aoe_damage(ab)
		"heal_party": _server_heal_party(ab)
		"aoe_stun": _server_aoe_stun(ab)
		"buff": _server_apply_buff(ab)
		"guard": _server_guard(ab)
		"taunt": _server_taunt(ab)
		"bastion": _server_bastion(ab)
		"shadow_dance": _server_shadow_dance(ab)
		"beam": _server_beam(ab)
		"storm": _server_storm(ab)
		"heal_single": _server_heal_single(ab)
		"hot_party": _server_hot_party(ab)
		"purify": _server_purify(ab)
		"miracle": _server_miracle(ab)
		"drain": _server_drain(ab)
		"summon": _server_summon(ab)
		"curse": _server_curse(ab)
		"smite_heal": _server_smite_heal(ab)
		"hammer": _server_hammer(ab)
		"ascension": _server_ascension(ab)
		"trap": _server_trap(ab)
	# Una habilidad que hace daño rompe la invisibilidad (dash/buff/cura no).
	if String(ab.get("type", "")) in DAMAGING_ABILITY_TYPES:
		server_break_stealth()
	# Avisar al dueño: cooldown del HUD + efectos que ejecuta el propio dueño.
	var owner_id := name.to_int()
	if owner_id == multiplayer.get_unique_id():
		_on_cast_ok(slot, cd)
	else:
		_recv_cast_ok.rpc_id(owner_id, slot, cd)


@rpc("any_peer", "reliable")
func _recv_cast_ok(slot: int, cd: float) -> void:
	if not _is_from_server():
		return
	_on_cast_ok(slot, cd)


func _on_cast_ok(slot: int, cd: float) -> void:
	if not is_multiplayer_authority():
		return
	_ability_cd_ui[slot] = cd
	if slot < abilities.size():
		var ab: Dictionary = abilities[slot]
		match String(ab.get("type", "")):
			"projectile_strong": _owner_cast_projectile(ab)
			"dash": _owner_cast_dash(ab)
			"pierce_arrow": _owner_cast_pierce(ab)
			"burst": _owner_cast_burst(ab)


# --- Efectos que ejecuta el dueño (necesitan su camara/movimiento) ---

func _owner_cast_projectile(ab: Dictionary) -> void:
	var base: int = 10
	if hurtbox.stats != null:
		base = int(hurtbox.stats.attack)
	var dmg: int = int(round(float(base) * float(ab.get("damage_mult", 1.0))))
	_fire_projectile(dmg, String(ab.get("visual", "magic")), float(ab.get("speed", 22.0)), float(ab.get("explode_radius", 0.0)))


func _owner_cast_dash(ab: Dictionary) -> void:
	# Hacia donde caminas (WASD, relativo a camara). Si no te mueves, al cursor.
	var move := _world_move_input()
	move.y = 0.0
	if move.length() < 0.1:
		move = _aim_dir
		move.y = 0.0
	if move.length() < 0.01:
		return
	_dash_dir = move.normalized()
	_dash_speed = DASH_SPEED
	_dash_time = float(ab.get("distance", 6.0)) / DASH_SPEED


# --- Efectos que resuelve el servidor ---

func _server_aoe_damage(ab: Dictionary) -> void:
	var radius := float(ab.get("radius", 3.0))
	var base: int = 10
	if hurtbox.stats != null:
		base = int(hurtbox.stats.attack)
	var dmg: int = int(round(float(base) * float(ab.get("damage_mult", 1.0))))
	var aid := name.to_int()
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e):
			continue
		if global_position.distance_to(e.global_position) <= radius and e.has_method("server_take_damage"):
			e.server_take_damage(dmg, aid)
	_play_effect.rpc(global_position, radius, Color(1.0, 0.55, 0.1, 0.3))


func _server_heal_party(ab: Dictionary) -> void:
	var radius := float(ab.get("radius", 8.0))
	var amount := int(ab.get("amount", 30))
	for id in PartyManager.members_of(name.to_int()):
		var p := _player_by_id(id)
		if p == null or not is_instance_valid(p) or p.get("is_dead"):
			continue
		if global_position.distance_to(p.global_position) <= radius and p.has_method("server_heal"):
			p.server_heal(amount)
	_play_effect.rpc(global_position, radius, Color(0.3, 1.0, 0.45, 0.3))


func server_heal(amount: int) -> void:
	if not multiplayer.is_server() or hurtbox.stats == null or is_dead:
		return
	var s: CharacterStats = hurtbox.stats
	s.current_hp = mini(s.current_hp + amount, s.max_hp)
	s.hp_changed.emit(s.current_hp, s.max_hp)
	_recv_hp.rpc(s.current_hp, s.max_hp)


func _player_by_id(id: int) -> Node:
	for p in get_tree().get_nodes_in_group("player"):
		if p.name.to_int() == id:
			return p
	return null


# Daño de área + aturdimiento (Pisotón Sísmico).
func _server_aoe_stun(ab: Dictionary) -> void:
	var radius := float(ab.get("radius", 4.0))
	var stun := float(ab.get("stun", 1.5))
	var base: int = 10
	if hurtbox.stats != null:
		base = int(hurtbox.stats.attack)
	var dmg: int = int(round(float(base) * float(ab.get("damage_mult", 1.0))))
	var aid := name.to_int()
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e):
			continue
		if global_position.distance_to(e.global_position) <= radius:
			if e.has_method("server_take_damage"):
				e.server_take_damage(dmg, aid)
			if e.has_method("server_stun"):
				e.server_stun(stun)
	var c: Array = ab.get("color", [0.8, 0.6, 0.2, 0.3])
	_play_effect.rpc(global_position, radius, Color(c[0], c[1], c[2], c[3]))


# Aplica un buff temporal (Furia, Sed de Sangre, Apocalipsis, Muro de Acero...).
func _server_apply_buff(ab: Dictionary) -> void:
	if hurtbox.stats == null:
		return
	var s: CharacterStats = hurtbox.stats
	var atk_add := int(round(float(s.attack) * float(ab.get("atk_pct", 0.0))))
	var def_add := int(round(float(s.defense) * float(ab.get("def_pct", 0.0))))
	s.attack += atk_add
	s.defense += def_add
	var dur := float(ab.get("duration", 5.0))
	_buffs.append({
		"name": String(ab.get("name", "Buff")),
		"time_left": dur,
		"total": dur,
		"atk_add": atk_add,
		"def_add": def_add,
		"lifesteal": float(ab.get("lifesteal", 0.0)),
		"dmg_mult": float(ab.get("dmg_taken_mult", 1.0)),
		"cc_immune": bool(ab.get("cc_immune", false)),
		"apoc": bool(ab.get("apocalipsis", false)),
		"invis": bool(ab.get("invis", false)),
		"poison_attacks": bool(ab.get("poison_attacks", false)),
		"shield": int(ab.get("shield", 0)),
	})
	_recompute_buffs()
	_push_inventory()  # sincroniza el nuevo ataque/defensa al dueño
	_push_buffs()      # sincroniza la barra de buffs al dueño
	_play_effect.rpc(global_position, 1.6, Color(1.0, 0.4, 0.2, 0.35))


# Resta del daño lo que absorban los escudos activos (Escudo Divino).
func _absorb_shields(amount: int) -> int:
	for b in _buffs:
		if amount <= 0:
			break
		var sh := int(b.get("shield", 0))
		if sh > 0:
			var absorbed := mini(sh, amount)
			b["shield"] = sh - absorbed
			amount -= absorbed
	return amount


func _recompute_buffs() -> void:
	_lifesteal = 0.0
	_dmg_taken_mult = 1.0
	_cc_immune = false
	_poison_attacks = false
	_hot_per_sec = 0.0
	var inv := false
	for b in _buffs:
		_lifesteal = maxf(_lifesteal, float(b["lifesteal"]))
		_dmg_taken_mult *= float(b["dmg_mult"])
		_hot_per_sec += float(b.get("hot", 0.0))
		if bool(b["cc_immune"]):
			_cc_immune = true
		if b.get("invis", false):
			inv = true
		if b.get("poison_attacks", false):
			_poison_attacks = true
	# Al cambiar el estado de invisibilidad, avisar a todos para el visual.
	if inv != is_invisible:
		is_invisible = inv
		_set_invisible.rpc(inv)


# Lo consulta el enemigo al recibir daño de este jugador (robo de vida).
func get_lifesteal() -> float:
	return _lifesteal


# Lo llama el enemigo (servidor) al morir si lo mato este jugador: extiende los
# buffs marcados como "apoc" (Apocalipsis prolonga su duracion por cada kill).
func server_on_kill() -> void:
	if not multiplayer.is_server():
		return
	var changed := false
	for b in _buffs:
		if bool(b["apoc"]):
			b["time_left"] += 4.0
			b["total"] = maxf(float(b["total"]), float(b["time_left"]))
			changed = true
	if changed:
		_push_buffs()
	# Dash Sombrío: matar a un enemigo resetea el cooldown del dash.
	for i in abilities.size():
		if String(abilities[i].get("type", "")) == "dash" and _ability_cd[i] > 0.0:
			_ability_cd[i] = 0.0
			_set_owner_cooldown(i, 0.0)


# Sincroniza la lista de buffs activos (nombre + tiempo) al dueño para el HUD.
func _push_buffs() -> void:
	if not multiplayer.is_server():
		return
	var list: Array = []
	for b in _buffs:
		list.append({"name": b["name"], "time_left": b["time_left"], "total": b["total"]})
	var owner_id := name.to_int()
	if owner_id == multiplayer.get_unique_id():
		_apply_buffs_ui(list)
	else:
		_recv_buffs.rpc_id(owner_id, list)


@rpc("any_peer", "reliable")
func _recv_buffs(list: Array) -> void:
	if not _is_from_server():
		return
	_apply_buffs_ui(list)


func _apply_buffs_ui(list: Array) -> void:
	if not is_multiplayer_authority():
		return
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("set_buffs"):
		hud.set_buffs(list)


# --- Tanque: guardia, provocar, bastion ---

func _server_guard(ab: Dictionary) -> void:
	_guard_time = float(ab.get("duration", 6.0))
	_guard_fraction = float(ab.get("fraction", 0.4))
	_play_effect.rpc(global_position, 1.8, Color(0.4, 0.7, 1.0, 0.35))


func is_guarding() -> bool:
	return _guard_time > 0.0


func get_guard_fraction() -> float:
	return _guard_fraction


# Redirige parte del daño entrante a un tanque cercano que este protegiendo.
func _apply_guard_redirect(amount: int) -> int:
	for id in PartyManager.members_of(name.to_int()):
		if id == name.to_int():
			continue
		var g := _player_by_id(id)
		if g == null or not is_instance_valid(g) or g.get("is_dead"):
			continue
		if g.has_method("is_guarding") and g.is_guarding():
			if global_position.distance_to(g.global_position) <= GUARD_RANGE:
				var redirected := int(round(float(amount) * float(g.get_guard_fraction())))
				if redirected > 0:
					g.server_take_damage(redirected, 0, true)  # sin volver a redirigir
					return amount - redirected
	return amount


func _server_taunt(ab: Dictionary) -> void:
	var radius := float(ab.get("radius", 8.0))
	var dur := float(ab.get("duration", 3.0))
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e):
			continue
		if global_position.distance_to(e.global_position) <= radius and e.has_method("server_taunt"):
			e.server_taunt(self, dur)
	_play_effect.rpc(global_position, radius, Color(0.9, 0.3, 0.2, 0.25))


func _server_bastion(ab: Dictionary) -> void:
	var dur := float(ab.get("duration", 8.0))
	_bastion_time = dur
	_bastion_pos = global_position
	_bastion_radius = float(ab.get("radius", 7.0))
	_bastion_ally_mult = float(ab.get("ally_dmg_mult", 0.6))
	_bastion_regen = int(ab.get("regen", 10))
	_bastion_tick = 0.0
	# Reduccion de daño enorme y firmeza para el propio tanque.
	if hurtbox.stats != null:
		_buffs.append({
			"name": "Bastión", "time_left": dur, "total": dur,
			"atk_add": 0, "def_add": 0, "lifesteal": 0.0,
			"dmg_mult": float(ab.get("self_dmg_mult", 0.25)),
			"cc_immune": true, "apoc": false, "aura": false,
		})
		_recompute_buffs()
		_push_buffs()
	_spawn_ground_zone.rpc(_bastion_pos, _bastion_radius, dur, Color(0.3, 0.6, 1.0, 0.28))


# Pulso periodico del Bastión: cura y protege a los aliados dentro de la zona.
func _bastion_pulse() -> void:
	for id in PartyManager.members_of(name.to_int()):
		var p := _player_by_id(id)
		if p == null or not is_instance_valid(p) or p.get("is_dead"):
			continue
		if _bastion_pos.distance_to(p.global_position) <= _bastion_radius:
			if p.has_method("server_heal"):
				p.server_heal(_bastion_regen)
			if p.has_method("server_aura_dr"):
				p.server_aura_dr(_bastion_ally_mult, 1.5)


# Aplica/refresca un buff de proteccion de "aura" (no se acumula).
func server_aura_dr(mult: float, duration: float) -> void:
	if not multiplayer.is_server():
		return
	for b in _buffs:
		if b.get("aura", false):
			b["time_left"] = maxf(float(b["time_left"]), duration)
			b["total"] = maxf(float(b["total"]), duration)
			_recompute_buffs()
			_push_buffs()
			return
	_buffs.append({
		"name": "Protección", "time_left": duration, "total": duration,
		"atk_add": 0, "def_add": 0, "lifesteal": 0.0,
		"dmg_mult": mult, "cc_immune": false, "apoc": false, "aura": true,
	})
	_recompute_buffs()
	_push_buffs()


# --- Asesino: invisibilidad, veneno, danza de las sombras ---

# Visual de invisibilidad (translucido) en todos los peers.
@rpc("any_peer", "call_local", "reliable")
func _set_invisible(on: bool) -> void:
	if is_multiplayer_authority():
		_owner_invis = on
	# Invisible: el propio asesino y sus compañeros de grupo lo ven difuminado;
	# cualquier otro jugador NO lo ve en absoluto.
	var asesino_id := name.to_int()
	var allied := (asesino_id == multiplayer.get_unique_id()) or _viewer_in_party_with(asesino_id)
	var mode := "normal"
	if on:
		mode = "ghost" if allied else "hidden"
	if is_instance_valid(_avatar):
		_avatar.set_view(mode)
		return
	# Respaldo sobre la capsula (ejecucion sin clase/muñeco).
	if mesh == null:
		return
	if mode == "normal":
		mesh.visible = true
		mesh.material_override = null
	elif mode == "ghost":
		mesh.visible = true
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0.4, 0.45, 0.6, 0.22)
		mesh.material_override = mat
	else:
		mesh.visible = false


# ¿El jugador local va en el mismo grupo que el id dado?
func _viewer_in_party_with(id: int) -> bool:
	for m in PartyManager.my_members:
		if int(m.get("id", -1)) == id:
			return true
	return false


# Rompe la invisibilidad (al atacar o usar una habilidad que daña).
func server_break_stealth() -> void:
	if not multiplayer.is_server():
		return
	var removed := false
	for i in range(_buffs.size() - 1, -1, -1):
		if _buffs[i].get("invis", false):
			if hurtbox.stats != null:
				hurtbox.stats.attack -= int(_buffs[i]["atk_add"])
				hurtbox.stats.defense -= int(_buffs[i]["def_add"])
			_buffs.remove_at(i)
			removed = true
	if removed:
		_recompute_buffs()  # pone is_invisible=false y reaparece el modelo
		_push_buffs()


# Lo llama el dueño en sus ataques basicos para romper el sigilo (solo si lo esta).
func _notify_attack_action() -> void:
	if not _owner_invis:
		return
	if multiplayer.is_server():
		server_break_stealth()
	else:
		_req_break_stealth.rpc_id(1)


@rpc("any_peer", "reliable")
func _req_break_stealth() -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != name.to_int():
		return
	server_break_stealth()


# Lo consulta el enemigo: si es true, los ataques de este jugador envenenan.
func applies_poison() -> bool:
	return _poison_attacks


# Danza de las Sombras (ulti): golpea a los enemigos cercanos, teletransporta al
# asesino detras del objetivo principal y le asesta un golpe final.
func _server_shadow_dance(ab: Dictionary) -> void:
	if hurtbox.stats == null:
		return
	var radius := float(ab.get("radius", 8.0))
	var hit_mult := float(ab.get("hit_mult", 1.0))
	var final_mult := float(ab.get("final_mult", 3.0))
	var base := int(hurtbox.stats.attack)
	var aid := name.to_int()
	# Breve invulnerabilidad mientras "desaparece".
	_buffs.append({
		"name": "Danza", "time_left": 0.6, "total": 0.6,
		"atk_add": 0, "def_add": 0, "lifesteal": 0.0, "dmg_mult": 0.0,
		"cc_immune": true, "apoc": false, "invis": false, "poison_attacks": false,
	})
	_recompute_buffs()
	_push_buffs()
	# Golpe a todos los enemigos cercanos.
	var nearest: Node3D = null
	var best := INF
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e):
			continue
		var d := global_position.distance_to(e.global_position)
		if d <= radius:
			if e.has_method("server_take_damage"):
				e.server_take_damage(int(round(float(base) * hit_mult)), aid)
			_play_effect.rpc(e.global_position, 1.2, Color(0.5, 0.2, 0.8, 0.4))
			if d < best:
				best = d
				nearest = e
	# Golpe final al objetivo principal + teletransporte detras de el.
	if nearest != null and is_instance_valid(nearest):
		nearest.server_take_damage(int(round(float(base) * final_mult)), aid)
		var dir := (nearest.global_position - global_position)
		dir.y = 0
		if dir.length() > 0.1:
			dir = dir.normalized()
			var behind := nearest.global_position + dir * 1.6
			behind.y = global_position.y
			_server_teleport_owner(behind)
	_play_effect.rpc(global_position, 1.6, Color(0.6, 0.2, 0.9, 0.4))


# Teletransporta al dueño (autoridad de su posicion) a un punto.
func _server_teleport_owner(pos: Vector3) -> void:
	var owner_id := name.to_int()
	if owner_id == multiplayer.get_unique_id():
		velocity = Vector3.ZERO
		global_position = pos
	else:
		_recv_teleport.rpc_id(owner_id, pos)


@rpc("any_peer", "reliable")
func _recv_teleport(pos: Vector3) -> void:
	if not _is_from_server():
		return
	velocity = Vector3.ZERO
	global_position = pos


# Avisa al dueño de un cooldown concreto (p.ej. resetear el dash al matar).
func _set_owner_cooldown(slot: int, value: float) -> void:
	var owner_id := name.to_int()
	if owner_id == multiplayer.get_unique_id():
		if is_multiplayer_authority():
			_ability_cd_ui[slot] = value
			_update_ability_hud()
	else:
		_recv_cooldown.rpc_id(owner_id, slot, value)


@rpc("any_peer", "reliable")
func _recv_cooldown(slot: int, value: float) -> void:
	if not _is_from_server():
		return
	_ability_cd_ui[slot] = value
	_update_ability_hud()


# Zona en el suelo (disco) visible durante 'duration'. La usan Bastión y Tormenta.
@rpc("any_peer", "call_local", "reliable")
func _spawn_ground_zone(pos: Vector3, radius: float, duration: float, color: Color) -> void:
	var m := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = 0.25
	m.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = Color(color.r, color.g, color.b)
	mat.emission_energy_multiplier = 0.7
	m.material_override = mat
	get_tree().current_scene.add_child(m)
	m.global_position = pos + Vector3(0.0, 0.12, 0.0)
	get_tree().create_timer(duration).timeout.connect(m.queue_free)


# Efecto visual breve (esfera translucida) que ven todos los peers. Lo dispara el
# servidor (no siempre la autoridad del nodo), por eso es "any_peer".
@rpc("any_peer", "call_local", "reliable")
func _play_effect(pos: Vector3, radius: float, color: Color, duration: float = 0.25) -> void:
	var m := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	m.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = Color(color.r, color.g, color.b)
	m.material_override = mat
	get_tree().current_scene.add_child(m)
	m.global_position = pos
	get_tree().create_timer(duration).timeout.connect(m.queue_free)


# --- Cooldown del HUD (dueño) ---

func _tick_ability_cooldowns_ui(delta: float) -> void:
	var changed := false
	for i in 4:
		if _ability_cd_ui[i] > 0.0:
			_ability_cd_ui[i] = maxf(_ability_cd_ui[i] - delta, 0.0)
			changed = true
	if changed:
		_update_ability_hud()


func _configure_ability_hud() -> void:
	if not is_multiplayer_authority():
		return
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("set_abilities"):
		hud.set_abilities(abilities)


func _update_ability_hud() -> void:
	if not is_multiplayer_authority():
		return
	var hud = get_tree().get_first_node_in_group("hud")
	if hud == null or not hud.has_method("set_cooldown"):
		return
	for i in 4:
		var total := 1.0
		if i < abilities.size():
			total = float(abilities[i].get("cooldown", 1.0))
		hud.set_cooldown(i, _ability_cd_ui[i], total)


# Tipo del arma equipada (ItemData.WeaponType), o NONE si no hay arma.
func _weapon_type() -> int:
	var wpath: String = equipment.get("weapon", "")
	if wpath == "":
		return ItemData.WeaponType.NONE
	var item := load(wpath) as ItemData
	return item.weapon_type if item else ItemData.WeaponType.NONE


func _is_bow() -> bool:
	return _weapon_type() == ItemData.WeaponType.BOW


func _fire_projectile(dmg: int, kind: String, speed: float = 22.0, explode_radius: float = 0.0, pierce: bool = false) -> void:
	# Direccion = hacia donde apunta el jugador (la camara, con inclinacion).
	var fwd: Vector3 = _aim_dir
	if fwd.length() < 0.01:
		fwd = -global_transform.basis.z
	fwd = fwd.normalized()
	var origin: Vector3 = global_position + Vector3.UP * 1.2 + fwd * 0.6
	_spawn_projectile.rpc(origin, fwd, dmg, name.to_int(), kind, speed, explode_radius, pierce)


# Se ejecuta en TODOS los peers: cada uno crea su proyectil local (mismo origen
# y direccion). Solo el del atacante aplica daño (ver projectile.gd).
@rpc("authority", "call_local", "reliable")
func _spawn_projectile(origin: Vector3, dir: Vector3, dmg: int, aid: int, kind: String, speed: float, explode_radius: float, pierce: bool) -> void:
	var proj := _projectile_scene.instantiate()
	get_tree().current_scene.add_child(proj)  # primero al arbol (para tener multiplayer)
	proj.global_position = origin
	proj.speed = speed
	proj.explode_radius = explode_radius
	proj.pierce = pierce
	proj.setup(dir, dmg, aid, kind)


# Difunde un efecto visual en una posicion (lo usa CombatManager para explosiones).
func play_effect_at(pos: Vector3, radius: float, color: Color) -> void:
	_play_effect.rpc(pos, radius, color)


# --- Curandero ---

func get_hp_fraction() -> float:
	if hurtbox.stats == null or hurtbox.stats.max_hp <= 0:
		return 1.0
	return float(hurtbox.stats.current_hp) / float(hurtbox.stats.max_hp)


# Sanación Rápida: cura al aliado MAS herido dentro del rango (incluido tu).
func _server_heal_single(ab: Dictionary) -> void:
	var radius := float(ab.get("radius", 12.0))
	var amount := int(ab.get("amount", 50))
	var target: Node = null
	var lowest := 2.0
	for id in PartyManager.members_of(name.to_int()):
		var p := _player_by_id(id)
		if p == null or not is_instance_valid(p) or p.get("is_dead"):
			continue
		if global_position.distance_to(p.global_position) > radius:
			continue
		var frac: float = p.get_hp_fraction()
		if frac < lowest:
			lowest = frac
			target = p
	if target != null:
		target.server_heal(amount)
		_play_effect.rpc(target.global_position, 1.6, Color(0.4, 1.0, 0.5, 0.4))


# Renovación: cura gradual (HoT) a los aliados cercanos.
func _server_hot_party(ab: Dictionary) -> void:
	var radius := float(ab.get("radius", 12.0))
	var per_sec := int(ab.get("per_sec", 10))
	var dur := float(ab.get("duration", 6.0))
	for id in PartyManager.members_of(name.to_int()):
		var p := _player_by_id(id)
		if p == null or not is_instance_valid(p) or p.get("is_dead"):
			continue
		if global_position.distance_to(p.global_position) <= radius and p.has_method("server_apply_hot"):
			p.server_apply_hot(per_sec, dur)
	_play_effect.rpc(global_position, radius * 0.6, Color(0.4, 1.0, 0.5, 0.2))


# Purificación: limpia efectos negativos y cura un poco a los aliados cercanos.
func _server_purify(ab: Dictionary) -> void:
	var radius := float(ab.get("radius", 12.0))
	var amount := int(ab.get("amount", 20))
	for id in PartyManager.members_of(name.to_int()):
		var p := _player_by_id(id)
		if p == null or not is_instance_valid(p) or p.get("is_dead"):
			continue
		if global_position.distance_to(p.global_position) <= radius:
			if p.has_method("server_cleanse"):
				p.server_cleanse()
			if p.has_method("server_heal"):
				p.server_heal(amount)
	_play_effect.rpc(global_position, radius * 0.6, Color(0.9, 1.0, 0.6, 0.25))


# Milagro Celestial (ulti): cura por completo y da inmunidad a los aliados.
func _server_miracle(ab: Dictionary) -> void:
	var radius := float(ab.get("radius", 12.0))
	var imm := float(ab.get("immune_duration", 4.0))
	for id in PartyManager.members_of(name.to_int()):
		var p := _player_by_id(id)
		if p == null or not is_instance_valid(p) or p.get("is_dead"):
			continue
		if global_position.distance_to(p.global_position) <= radius:
			if p.has_method("server_full_heal"):
				p.server_full_heal()
			if p.has_method("server_apply_immunity"):
				p.server_apply_immunity(imm)
	_play_effect.rpc(global_position, radius, Color(1.0, 1.0, 0.7, 0.3))


# --- Métodos que reciben los aliados (servidor) ---

func server_apply_hot(per_sec: int, duration: float) -> void:
	if not multiplayer.is_server():
		return
	for b in _buffs:
		if b.get("hot_tag", false):
			b["time_left"] = maxf(float(b["time_left"]), duration)
			b["total"] = maxf(float(b["total"]), duration)
			b["hot"] = maxf(float(b.get("hot", 0.0)), float(per_sec))
			_recompute_buffs()
			_push_buffs()
			return
	_buffs.append({
		"name": "Renovación", "time_left": duration, "total": duration,
		"atk_add": 0, "def_add": 0, "lifesteal": 0.0, "dmg_mult": 1.0,
		"cc_immune": false, "apoc": false, "hot": float(per_sec), "hot_tag": true,
	})
	_recompute_buffs()
	_push_buffs()


func server_full_heal() -> void:
	if not multiplayer.is_server() or hurtbox.stats == null or is_dead:
		return
	hurtbox.stats.current_hp = hurtbox.stats.max_hp
	hurtbox.stats.hp_changed.emit(hurtbox.stats.current_hp, hurtbox.stats.max_hp)
	_recv_hp.rpc(hurtbox.stats.current_hp, hurtbox.stats.max_hp)


func server_apply_immunity(duration: float) -> void:
	if not multiplayer.is_server():
		return
	_buffs.append({
		"name": "Inmunidad", "time_left": duration, "total": duration,
		"atk_add": 0, "def_add": 0, "lifesteal": 0.0, "dmg_mult": 1.0,
		"cc_immune": true, "apoc": false,
	})
	_recompute_buffs()
	_push_buffs()


# Limpia los buffs marcados como negativos (preparado para debuffs futuros).
func server_cleanse() -> void:
	if not multiplayer.is_server():
		return
	var removed := false
	for i in range(_buffs.size() - 1, -1, -1):
		if _buffs[i].get("negative", false):
			if hurtbox.stats != null:
				hurtbox.stats.attack -= int(_buffs[i]["atk_add"])
				hurtbox.stats.defense -= int(_buffs[i]["def_add"])
			_buffs.remove_at(i)
			removed = true
	if removed:
		_recompute_buffs()
		_push_buffs()


# --- Paladín: golpe sagrado, martillo, ascensión ---

# Devuelve el enemigo mas cercano hacia donde miras, dentro del rango.
func _enemy_in_front(rng: float) -> Node3D:
	var fwd := -global_transform.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.01:
		return null
	fwd = fwd.normalized()
	var best: Node3D = null
	var best_dist := INF
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e):
			continue
		var to_e: Vector3 = e.global_position - global_position
		to_e.y = 0.0
		if to_e.length() <= rng and to_e.normalized().dot(fwd) > 0.5 and to_e.length() < best_dist:
			best_dist = to_e.length()
			best = e
	return best


# Luz Consagrada: golpea a un enemigo y cura a los aliados cercanos.
func _server_smite_heal(ab: Dictionary) -> void:
	var base: int = 10
	if hurtbox.stats != null:
		base = int(hurtbox.stats.attack)
	var dmg: int = int(round(float(base) * float(ab.get("damage_mult", 1.5))))
	var target := _enemy_in_front(float(ab.get("range", 6.0)))
	if target != null:
		target.server_take_damage(dmg, name.to_int())
		_play_effect.rpc(target.global_position, 1.4, Color(1.0, 0.95, 0.5, 0.4))
	var hr := float(ab.get("heal_radius", 10.0))
	var ha := int(ab.get("heal_amount", 25))
	for id in PartyManager.members_of(name.to_int()):
		var p := _player_by_id(id)
		if p != null and is_instance_valid(p) and not p.get("is_dead"):
			if global_position.distance_to(p.global_position) <= hr and p.has_method("server_heal"):
				p.server_heal(ha)


# Martillo del Juicio: daña y aturde al enemigo al que apuntas.
func _server_hammer(ab: Dictionary) -> void:
	var base: int = 10
	if hurtbox.stats != null:
		base = int(hurtbox.stats.attack)
	var dmg: int = int(round(float(base) * float(ab.get("damage_mult", 1.6))))
	var stun := float(ab.get("stun", 2.0))
	var target := _enemy_in_front(float(ab.get("range", 14.0)))
	if target != null:
		target.server_take_damage(dmg, name.to_int())
		if target.has_method("server_stun"):
			target.server_stun(stun)
		_play_effect.rpc(target.global_position, 1.6, Color(1.0, 0.85, 0.3, 0.45))


# Ascensión Sagrada (ulti): transforma (sube ataque y defensa) y cura en aura.
func _server_ascension(ab: Dictionary) -> void:
	if hurtbox.stats == null:
		return
	var s: CharacterStats = hurtbox.stats
	var atk_add := int(round(float(s.attack) * float(ab.get("atk_pct", 0.4))))
	var def_add := int(round(float(s.defense) * float(ab.get("def_pct", 0.5))))
	s.attack += atk_add
	s.defense += def_add
	var dur := float(ab.get("duration", 10.0))
	_buffs.append({
		"name": "Ascensión", "time_left": dur, "total": dur,
		"atk_add": atk_add, "def_add": def_add, "lifesteal": 0.0, "dmg_mult": 1.0,
		"cc_immune": true, "apoc": false, "shield": 0,
	})
	_recompute_buffs()
	_push_inventory()
	_push_buffs()
	_ascension_time = dur
	_ascension_radius = float(ab.get("heal_radius", 12.0))
	_ascension_heal = int(ab.get("heal_amount", 15))
	_ascension_tick = 0.0
	_play_effect.rpc(global_position, 2.2, Color(1.0, 0.95, 0.5, 0.3))


# --- Nigromante: drenar, invocar, maldecir ---

# Drenar Vida: daña al enemigo mas cercano en linea y te cura una parte.
func _server_drain(ab: Dictionary) -> void:
	var rng := float(ab.get("range", 16.0))
	var base: int = 10
	if hurtbox.stats != null:
		base = int(hurtbox.stats.attack)
	var dmg: int = int(round(float(base) * float(ab.get("damage_mult", 1.5))))
	var drain := float(ab.get("drain", 0.5))
	var aid := name.to_int()
	var fwd := -global_transform.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.01:
		return
	fwd = fwd.normalized()
	var origin := global_position
	var best: Node3D = null
	var best_dist := INF
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e):
			continue
		var to_e: Vector3 = e.global_position - origin
		to_e.y = 0.0
		if to_e.length() <= rng and to_e.normalized().dot(fwd) > 0.6 and to_e.length() < best_dist:
			best_dist = to_e.length()
			best = e
	if best != null:
		best.server_take_damage(dmg, aid)
		server_heal(int(round(float(dmg) * drain)))
		_play_beam.rpc(origin + Vector3.UP * 1.2, best.global_position + Vector3.UP * 1.0)


# Invocar Esqueleto / Ejército: crea minions alrededor del nigromante.
func _server_summon(ab: Dictionary) -> void:
	var count := int(ab.get("count", 1))
	var base: int = 10
	if hurtbox.stats != null:
		base = int(hurtbox.stats.attack)
	var dmg: int = int(round(float(base) * float(ab.get("dmg_mult", 0.7))))
	var life := float(ab.get("lifetime", 15.0))
	var hp := int(ab.get("minion_hp", 60))
	# "single": solo puede haber UN esqueleto a la vez (la ulti no es "single").
	if bool(ab.get("single", false)):
		if _single_minion_id > 0:
			MinionManager.server_despawn(_single_minion_id)
		var pos := global_position + Vector3(1.5, 0.0, 0.0)
		pos.y = global_position.y
		_single_minion_id = MinionManager.server_spawn(pos, name.to_int(), dmg, life, hp)
	else:
		for i in count:
			var ang := TAU * float(i) / float(count) + randf()
			var pos := global_position + Vector3(cos(ang) * 2.0, 0.0, sin(ang) * 2.0)
			pos.y = global_position.y
			MinionManager.server_spawn(pos, name.to_int(), dmg, life, hp)
	_play_effect.rpc(global_position, 2.5, Color(0.4, 0.8, 0.4, 0.3))


# Maldición de Debilidad: reduce daño y defensa de los enemigos cercanos.
func _server_curse(ab: Dictionary) -> void:
	var radius := float(ab.get("radius", 7.0))
	var dur := float(ab.get("duration", 6.0))
	var def_red := int(ab.get("def_reduction", 5))
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e):
			continue
		if global_position.distance_to(e.global_position) <= radius and e.has_method("server_curse"):
			e.server_curse(dur, def_red)
	_play_effect.rpc(global_position, radius, Color(0.5, 0.2, 0.6, 0.3))


# --- Mago: rayo y tormenta ---

# Rayo Arcano: hitscan que daña a los enemigos en linea hacia donde miras.
func _server_beam(ab: Dictionary) -> void:
	var rng := float(ab.get("range", 18.0))
	var base: int = 10
	if hurtbox.stats != null:
		base = int(hurtbox.stats.attack)
	var dmg: int = int(round(float(base) * float(ab.get("damage_mult", 1.0))))
	var aid := name.to_int()
	var fwd := -global_transform.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.01:
		return
	fwd = fwd.normalized()
	var origin := global_position
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e):
			continue
		var to_e: Vector3 = e.global_position - origin
		to_e.y = 0.0
		if to_e.length() <= rng and to_e.normalized().dot(fwd) > 0.7:
			if e.has_method("server_take_damage"):
				e.server_take_damage(dmg, aid)
	_play_beam.rpc(origin + Vector3.UP * 1.2, origin + fwd * rng + Vector3.UP * 1.2)


@rpc("any_peer", "call_local", "reliable")
func _play_beam(from: Vector3, to: Vector3) -> void:
	var dist := from.distance_to(to)
	if dist < 0.1:
		return
	var m := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.12, 0.12, dist)
	m.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.7, 0.4, 1.0, 0.85)
	mat.emission_enabled = true
	mat.emission = Color(0.6, 0.3, 1.0)
	mat.emission_energy_multiplier = 2.0
	m.material_override = mat
	get_tree().current_scene.add_child(m)
	m.global_position = (from + to) * 0.5
	m.look_at(to, Vector3.UP)
	get_tree().create_timer(0.25).timeout.connect(m.queue_free)


# Tormenta Elemental / Lluvia de Flechas (ulti): zona persistente que daña por ticks.
func _server_storm(ab: Dictionary) -> void:
	_storm_time = float(ab.get("duration", 6.0))
	_storm_pos = global_position
	_storm_radius = float(ab.get("radius", 8.0))
	var base: int = 10
	if hurtbox.stats != null:
		base = int(hurtbox.stats.attack)
	_storm_dmg = int(round(float(base) * float(ab.get("tick_mult", 0.5))))
	_storm_tick = 0.0
	var c: Array = ab.get("color", [0.9, 0.4, 0.9, 0.22])
	_storm_color = Color(c[0], c[1], c[2], 0.16)
	_spawn_ground_zone.rpc(_storm_pos, _storm_radius, _storm_time, Color(c[0], c[1], c[2], c[3]))


func _storm_pulse() -> void:
	var aid := name.to_int()
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e) and _storm_pos.distance_to(e.global_position) <= _storm_radius:
			if e.has_method("server_take_damage"):
				e.server_take_damage(_storm_dmg, aid)
	_play_effect.rpc(_storm_pos, _storm_radius * 0.9, _storm_color)


# --- Arquero: flecha perforante, ráfaga, trampa ---

func _owner_cast_pierce(ab: Dictionary) -> void:
	var base: int = 10
	if hurtbox.stats != null:
		base = int(hurtbox.stats.attack)
	var dmg: int = int(round(float(base) * float(ab.get("damage_mult", 1.8))))
	_fire_projectile(dmg, "arrow", float(ab.get("speed", 34.0)), 0.0, true)


func _owner_cast_burst(ab: Dictionary) -> void:
	var base: int = 10
	if hurtbox.stats != null:
		base = int(hurtbox.stats.attack)
	var dmg: int = int(round(float(base) * float(ab.get("damage_mult", 0.7))))
	var count := int(ab.get("count", 5))
	var spd := float(ab.get("speed", 34.0))
	var spread := float(ab.get("spread", 0.12))
	var fwd: Vector3 = _aim_dir
	if fwd.length() < 0.01:
		fwd = -global_transform.basis.z
	fwd = fwd.normalized()
	var origin: Vector3 = global_position + Vector3.UP * 1.2 + fwd * 0.6
	for i in count:
		var ang := (float(i) - float(count - 1) * 0.5) * spread
		var dir := fwd.rotated(Vector3.UP, ang)
		_spawn_projectile.rpc(origin, dir, dmg, name.to_int(), "arrow", spd, 0.0, false)


# Trampa de Caza: marca el suelo; aturde al primer enemigo que entra (ver tick).
func _server_trap(ab: Dictionary) -> void:
	_trap_active = true
	_trap_pos = global_position
	_trap_radius = float(ab.get("radius", 2.0))
	_trap_stun = float(ab.get("stun", 3.0))
	_trap_time = float(ab.get("lifetime", 12.0))
	var base: int = 10
	if hurtbox.stats != null:
		base = int(hurtbox.stats.attack)
	_trap_dmg = int(round(float(base) * float(ab.get("damage_mult", 1.0))))
	_spawn_ground_zone.rpc(_trap_pos, _trap_radius, _trap_time, Color(0.7, 0.5, 0.2, 0.3))


# Lo llama el dueño del jugador via .rpc(); se ejecuta en los demas peers, que
# guardan la transformada para interpolar hacia ella en _physics_process.
@rpc("authority", "unreliable_ordered")
func _recv_transform(pos: Vector3, rot_y: float) -> void:
	_net_position = pos
	_net_rotation_y = rot_y
	_has_net_target = true


# --- Daño (autoritativo en el servidor) -----------------------------------------

# Lo llama el CombatManager en el SERVIDOR cuando este jugador recibe un golpe
# (p.ej. de un enemigo). El servidor aplica el daño sobre su copia y reparte la
# vida resultante. La autoridad del jugador es su cliente, pero quien decide la
# vida es el servidor: por eso esto solo corre en el servidor.
func server_take_damage(amount: int, _attacker_id: int = 0, no_redirect: bool = false) -> void:
	if not multiplayer.is_server() or hurtbox.stats == null or is_dead:
		return
	if _invuln_time > 0.0:
		return  # esquiva: invulnerable durante los i-frames
	combat_timer = COMBAT_DURATION  # recibir daño te pone en combate
	# Guardia Protectora: un tanque cercano absorbe parte del daño.
	if not no_redirect:
		amount = _apply_guard_redirect(amount)
	# Reduccion de daño por buffs (Muro de Acero, Bastión, etc.).
	amount = int(round(amount * _dmg_taken_mult))
	# Escudo Divino: absorbe daño antes que la vida.
	amount = _absorb_shields(amount)
	if amount <= 0:
		return  # daño anulado (inmunidad o escudo)
	var hp_before: int = hurtbox.stats.current_hp
	hurtbox.stats.take_damage(amount)
	var dealt: int = hp_before - hurtbox.stats.current_hp
	_recv_hp.rpc(hurtbox.stats.current_hp, hurtbox.stats.max_hp)
	play_hit_flash.rpc()  # parpadeo de impacto en todos los peers
	_popup_dmg.rpc(dealt)  # numero de daño + temblor de camara (en el dueño)
	if hurtbox.stats.current_hp <= 0:
		_server_start_death()


# Enviado por el servidor (any_peer + comprobacion) para reflejar la vida en el
# cliente dueño, que actualiza su HUD. No usamos modo "authority" porque la
# autoridad de este nodo es el cliente, no el servidor que envia.
@rpc("any_peer", "reliable")
func _recv_hp(current: int, max_hp: int) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return  # solo aceptamos la vida que dicta el servidor
	if hurtbox.stats == null:
		return
	hurtbox.stats.current_hp = current
	hurtbox.stats.max_hp = max_hp
	hurtbox.stats.hp_changed.emit(current, max_hp)


# --- Feedback visual (se ejecuta en todos los peers) ----------------------------

@rpc("authority", "call_local", "reliable")
func play_attack(strong: bool = false) -> void:
	_attack_lunge(strong)


@rpc("any_peer", "call_local", "reliable")
func play_hit_flash() -> void:
	_hit_flash()


# Numero de daño flotante sobre el jugador (todos los peers) y temblor de camara
# para el dueño que lo recibe.
@rpc("any_peer", "call_local", "reliable")
func _popup_dmg(amount: int) -> void:
	if not _is_from_server():
		return
	if amount > 0:
		FloatingText.spawn(get_tree().current_scene, global_position + Vector3.UP * 2.4, str(amount), Color(1.0, 0.4, 0.35))
	if is_multiplayer_authority():
		add_shake(0.18)


func _attack_lunge(strong: bool = false) -> void:
	# Con muñeco: animacion de golpe del brazo. Sin el (ejecucion sin clase),
	# embestida de la capsula como respaldo.
	if is_instance_valid(_avatar):
		_avatar.attack(strong)
		return
	if mesh == null:
		return
	var dist: float = -0.7 if strong else -0.4
	var tween := create_tween()
	tween.tween_property(mesh, "position:z", dist, 0.08)
	tween.tween_property(mesh, "position:z", 0.0, 0.12)


func _hit_flash() -> void:
	# Parpadeo blanco breve al recibir daño.
	if is_instance_valid(_avatar):
		_avatar.flash()
		return
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


# --- Muerte y respawn (orquestado por el servidor) ------------------------------

func _server_start_death() -> void:
	# Solo servidor. Avisa a todos de la muerte y programa la reaparicion.
	_set_dead.rpc(true)
	get_tree().create_timer(RESPAWN_DELAY).timeout.connect(_server_respawn)


# Punto de aparicion: el centro de la ciudad de inicio del personaje (o el origen).
func _spawn_point() -> Vector3:
	var jitter := Vector3(randf_range(-5.0, 5.0), 1.0, randf_range(-5.0, 5.0))
	if char_start_city != "":
		var z := Zones.get_zone(char_start_city)
		if not z.is_empty():
			return Zones.center3(z) + jitter
	# Sin ciudad guardada: primera ciudad segura (nunca el centro letal del mundo).
	var cities := Zones.start_cities()
	if not cities.is_empty():
		return Zones.center3(cities[0]) + jitter
	return jitter


func _server_respawn() -> void:
	if not multiplayer.is_server() or hurtbox.stats == null:
		return
	# Vida llena en la copia del servidor y repartida a todos.
	hurtbox.stats.current_hp = hurtbox.stats.max_hp
	hurtbox.stats.hp_changed.emit(hurtbox.stats.max_hp, hurtbox.stats.max_hp)
	_recv_hp.rpc(hurtbox.stats.max_hp, hurtbox.stats.max_hp)
	_set_dead.rpc(false)
	# El dueño (autoridad de la posicion) reaparece en su ciudad de inicio.
	var pos := _spawn_point()
	var owner_id := name.to_int()
	if owner_id == multiplayer.get_unique_id():
		# El dueño es el propio servidor (host): aplicamos directamente.
		velocity = Vector3.ZERO
		global_position = pos
	else:
		_do_respawn.rpc_id(owner_id, pos)


# Se ejecuta en todos los peers. Activa/desactiva al jugador (visual, colision,
# posibilidad de recibir golpes) y muestra el aviso de muerte al dueño local.
@rpc("any_peer", "call_local", "reliable")
func _set_dead(dead: bool) -> void:
	if not _is_from_server():
		return
	is_dead = dead
	if is_instance_valid(_avatar):
		_avatar.set_dead(dead)
	elif mesh:
		mesh.visible = not dead
	if collision:
		collision.set_deferred("disabled", dead)
	if hurtbox:
		hurtbox.set_deferred("monitorable", not dead)
	# Aviso de muerte solo para el jugador local.
	if is_multiplayer_authority():
		var hud = get_tree().get_first_node_in_group("hud")
		if hud:
			if dead:
				hud.show_death(RESPAWN_DELAY)
			else:
				hud.hide_death()


# El servidor se lo envia solo al dueño, que es la autoridad de la posicion.
@rpc("any_peer", "reliable")
func _do_respawn(pos: Vector3) -> void:
	if not _is_from_server():
		return
	velocity = Vector3.ZERO
	global_position = pos


func _is_from_server() -> bool:
	# Aceptamos solo ordenes del servidor: id 1 (remoto) o 0 (ejecucion local
	# en el propio host via call_local).
	var s := multiplayer.get_remote_sender_id()
	return s == 0 or s == 1


# --- Muñeco 3D por clase --------------------------------------------------------

# Lo envia el servidor a todos los peers para que cada uno construya el muñeco
# de este jugador con la clase correcta.
@rpc("any_peer", "call_local", "reliable")
func _recv_identity(class_id: String) -> void:
	if not _is_from_server():
		return
	char_class = class_id
	_build_avatar(class_id)


# El cliente pide al servidor la clase de este jugador (al unirse tarde).
func _request_identity() -> void:
	_req_identity.rpc_id(1)


@rpc("any_peer", "reliable")
func _req_identity() -> void:
	if not multiplayer.is_server() or char_class == "":
		return
	var who := multiplayer.get_remote_sender_id()
	_recv_identity.rpc_id(who, char_class)


func _build_avatar(_class_id: String) -> void:
	# (Revertido a capsulas) Ya no construimos muñecos 3D animados. La capsula
	# original sigue visible y los efectos (flash, invisibilidad, muerte, golpe)
	# actuan sobre ella mediante los fallbacks de cada funcion.
	return


# --- Combate ---------------------------------------------------------------------

# Lo llama el jugador local al atacar; pone su copia del servidor en combate.
func _report_combat() -> void:
	if multiplayer.is_server():
		combat_timer = COMBAT_DURATION
	else:
		_server_enter_combat.rpc_id(1)


@rpc("any_peer", "reliable")
func _server_enter_combat() -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != name.to_int():
		return  # solo el dueño puede ponerse en combate a si mismo
	combat_timer = COMBAT_DURATION


# --- Inventario y equipamiento --------------------------------------------------
#
# Modelo autoritativo: el SERVIDOR guarda el inventario y el equipo de verdad y
# se lo sincroniza al cliente dueño para su UI. El inventario es sin limite; los
# objetos iguales se apilan (stack). Solo se puede equipar FUERA de combate.

# Inventario: lista de { "path": String, "amount": int }.
var inventory: Array = []
# Equipo: slot -> ruta del item ("" = vacio).
var equipment: Dictionary = {"weapon": "", "head": "", "torso": "", "legs": "", "feet": ""}


# --- Helpers de inventario (solo servidor) --------------------------------------

func _inv_add(path: String, amount: int) -> void:
	for entry in inventory:
		if entry["path"] == path:
			entry["amount"] += amount
			return
	inventory.append({"path": path, "amount": amount})


func _inv_remove(path: String, amount: int) -> bool:
	for i in range(inventory.size()):
		if inventory[i]["path"] == path:
			inventory[i]["amount"] -= amount
			if inventory[i]["amount"] <= 0:
				inventory.remove_at(i)
			return true
	return false


func _inv_has(path: String) -> bool:
	for entry in inventory:
		if entry["path"] == path and entry["amount"] > 0:
			return true
	return false


func _apply_bonus(item: ItemData, sign: int) -> void:
	if hurtbox.stats == null or item == null:
		return
	hurtbox.stats.attack += sign * item.attack_bonus
	hurtbox.stats.defense += sign * item.defense_bonus


# --- Recogida de loot (lo llama el LootManager en el servidor) -------------------

func server_grant_item(item_path: String, amount: int) -> void:
	if not multiplayer.is_server():
		return
	_inv_add(item_path, amount)
	var item := load(item_path) as ItemData
	var item_name := item.name if item else "objeto"
	_send_message("Recogiste: %s x%d" % [item_name, amount])
	_push_inventory()


# (PRUEBA) Entrega un surtido de objetos para probar el inventario y el equipo.
func _grant_starter_kit() -> void:
	if not multiplayer.is_server():
		return
	var kit := [
		["res://data/items/weapons/rusty_dagger.tres", 1],
		["res://data/items/iron_sword.tres", 1],
		["res://data/items/weapons/steel_axe.tres", 1],
		["res://data/items/weapons/dragon_blade.tres", 1],
		["res://data/items/armor/leather_helm.tres", 1],
		["res://data/items/armor/leather_chest.tres", 1],
		["res://data/items/armor/leather_legs.tres", 1],
		["res://data/items/armor/leather_boots.tres", 1],
		["res://data/items/armor/iron_helm.tres", 1],
		["res://data/items/armor/iron_chest.tres", 1],
		["res://data/items/armor/iron_legs.tres", 1],
		["res://data/items/armor/iron_boots.tres", 1],
		["res://data/items/materials/wolf_pelt.tres", 3],
		["res://data/items/materials/iron_ore.tres", 10],
		["res://data/items/monster_fang.tres", 5],
		["res://data/items/materials/mithril_shard.tres", 2],
	]
	for e in kit:
		_inv_add(e[0], e[1])
	_send_message("Kit de prueba recibido")
	_push_inventory()


# --- Personaje: aplicar clase, stats, inventario y equipo -----------------------

# Lo llama el dueño al spawnear: envia su personaje (de Session) al servidor.
func _submit_character() -> void:
	var data: Dictionary = Session.selected_character
	if data.is_empty():
		return  # sin personaje (ej. ejecucion directa): se queda con stats por defecto
	# Aplicamos la velocidad de movimiento y las habilidades localmente (las usa
	# el dueño al simular y para configurar el HUD).
	var cdata := Roles.get_class_data(data.get("class_id", ""))
	if not cdata.is_empty():
		speed = cdata.get("speed", speed)
		abilities = cdata.get("abilities", [])
		_combo = cdata.get("combo", [])
		_combo_index = 0
		_combo_timer = 0.0
		_configure_ability_hud()
	# Muñeco del propio jugador (lo construimos ya, sin esperar al servidor).
	var cid := String(data.get("class_id", ""))
	if cid != "":
		char_class = cid
		_build_avatar(cid)
	# Aparecer en la ciudad de inicio elegida (el dueño es la autoridad de su pos).
	char_start_city = String(data.get("start_city", ""))
	var sp := _spawn_point()
	global_position = sp
	velocity = Vector3.ZERO
	if multiplayer.is_server():
		_server_apply_character(data)
	else:
		_req_apply_character.rpc_id(1, data)


@rpc("any_peer", "reliable")
func _req_apply_character(data: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != name.to_int():
		return  # solo el dueño configura su personaje
	_server_apply_character(data)


# Solo servidor: configura este jugador segun el personaje elegido.
func _server_apply_character(data: Dictionary) -> void:
	if not multiplayer.is_server() or hurtbox.stats == null:
		return
	var class_id: String = data.get("class_id", "")
	var cdata := Roles.get_class_data(class_id)
	if cdata.is_empty():
		return
	char_name = data.get("name", "")
	char_class = class_id
	char_start_city = String(data.get("start_city", ""))
	abilities = cdata.get("abilities", [])
	# Todos los peers construyen el muñeco de este jugador con su clase.
	_recv_identity.rpc(class_id)
	var level: int = int(data.get("level", 1))
	var s: CharacterStats = hurtbox.stats
	# Stats base de la clase + escalado por nivel.
	s.level = level
	s.experience = int(data.get("exp", 0))
	s.max_hp = int(cdata["max_hp"]) + (level - 1) * 20
	s.max_mp = int(cdata["max_mp"]) + (level - 1) * 10
	s.attack = int(cdata["attack"]) + (level - 1) * 3
	s.defense = int(cdata["defense"]) + (level - 1) * 2
	s.speed = cdata["speed"]
	s.exp_to_next_level = _exp_needed(level)
	s.current_hp = s.max_hp
	s.current_mp = s.max_mp
	speed = cdata["speed"]
	# Inventario (normalizamos los numeros que vienen del JSON a int).
	inventory = []
	for e in data.get("inventory", []):
		inventory.append({"path": String(e.get("path", "")), "amount": int(e.get("amount", 1))})
	# Equipo: reconstruir slots y reaplicar bonos al stats.
	equipment = {"weapon": "", "head": "", "torso": "", "legs": "", "feet": ""}
	var saved_equip: Dictionary = data.get("equipment", {})
	for slot in equipment.keys():
		var path := String(saved_equip.get(slot, ""))
		if path != "":
			var item := load(path) as ItemData
			if item:
				equipment[slot] = path
				_apply_bonus(item, 1)
	s.hp_changed.emit(s.current_hp, s.max_hp)
	_recv_hp.rpc(s.current_hp, s.max_hp)
	_push_inventory()
	_push_progress()


# EXP necesaria para pasar del nivel dado al siguiente. Curva suave para llegar
# comodamente a nivel 200 sin numeros astronomicos.
func _exp_needed(level: int) -> int:
	return int(50.0 * pow(float(level), 1.5))


# --- Nivel y experiencia (autoritativo en el servidor) --------------------------

# Lo llaman los enemigos (en el servidor) al morir cerca de este jugador.
func server_gain_exp(amount: int) -> void:
	if not multiplayer.is_server() or hurtbox.stats == null:
		return
	var s: CharacterStats = hurtbox.stats
	if s.level >= MAX_LEVEL:
		return
	s.experience += amount
	var leveled := false
	while s.level < MAX_LEVEL and s.experience >= s.exp_to_next_level:
		s.experience -= s.exp_to_next_level
		s.level += 1
		s.max_hp += 20
		s.max_mp += 10
		s.attack += 3
		s.defense += 2
		s.exp_to_next_level = _exp_needed(s.level)
		leveled = true
	if s.level >= MAX_LEVEL:
		s.experience = 0  # ya al maximo, no acumulamos mas
	if leveled:
		s.current_hp = s.max_hp  # curacion completa al subir de nivel
		s.current_mp = s.max_mp
		s.hp_changed.emit(s.current_hp, s.max_hp)
		_recv_hp.rpc(s.current_hp, s.max_hp)
		_send_message("¡Subiste a nivel %d!" % s.level)
	_push_progress()


# Sincroniza nivel/exp al dueño (para HUD y guardado).
func _push_progress() -> void:
	if not multiplayer.is_server() or hurtbox.stats == null:
		return
	var s: CharacterStats = hurtbox.stats
	var owner_id := name.to_int()
	if owner_id == multiplayer.get_unique_id():
		_on_progress_synced()
	else:
		_recv_progress.rpc_id(owner_id, s.level, s.experience, s.exp_to_next_level, s.current_mp, s.max_mp)


@rpc("any_peer", "reliable")
func _recv_progress(level: int, exp: int, exp_to_next: int, cur_mp: int, max_mp: int) -> void:
	if not _is_from_server() or hurtbox.stats == null:
		return
	hurtbox.stats.level = level
	hurtbox.stats.experience = exp
	hurtbox.stats.exp_to_next_level = exp_to_next
	hurtbox.stats.current_mp = cur_mp
	hurtbox.stats.max_mp = max_mp
	_on_progress_synced()


func _on_progress_synced() -> void:
	if not is_multiplayer_authority():
		return
	_update_level_ui()
	_save_character_local()


func _update_level_ui() -> void:
	if not is_multiplayer_authority() or hurtbox.stats == null:
		return
	var hud = get_tree().get_first_node_in_group("hud")
	if hud == null:
		return
	var s: CharacterStats = hurtbox.stats
	if hud.has_method("set_level"):
		hud.set_level(s.level, s.experience, s.exp_to_next_level)
	if hud.has_method("set_mp"):
		hud.set_mp(s.current_mp, s.max_mp)


# --- Equipar / desequipar (peticion del cliente dueño) --------------------------

func request_equip(item_path: String) -> void:
	if multiplayer.is_server():
		_server_equip(item_path)
	else:
		_req_equip.rpc_id(1, item_path)


func request_unequip(slot: String) -> void:
	if multiplayer.is_server():
		_server_unequip(slot)
	else:
		_req_unequip.rpc_id(1, slot)


@rpc("any_peer", "reliable")
func _req_equip(item_path: String) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != name.to_int():
		return  # solo el dueño puede tocar su equipo
	_server_equip(item_path)


@rpc("any_peer", "reliable")
func _req_unequip(slot: String) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != name.to_int():
		return
	_server_unequip(slot)


# --- Logica de equipo (solo servidor) -------------------------------------------

func _server_equip(item_path: String) -> void:
	if not multiplayer.is_server():
		return
	if combat_timer > 0.0:
		_send_message("No puedes equipar en combate")
		return
	if not _inv_has(item_path):
		return
	var item := load(item_path) as ItemData
	if item == null:
		return
	var slot := _slot_for(item)
	if slot == "":
		_send_message("Ese objeto no se puede equipar")
		return
	# Restriccion de arma por clase.
	if slot == "weapon" and char_class != "" and not Roles.allows_weapon(char_class, item.weapon_type):
		_send_message("Tu clase no puede usar esa arma")
		return
	# Si el slot ya tiene algo, lo devolvemos al inventario primero.
	if equipment[slot] != "":
		_unequip_to_inventory(slot)
	_inv_remove(item_path, 1)
	equipment[slot] = item_path
	_apply_bonus(item, 1)
	_send_message("Equipado: %s" % item.name)
	_push_inventory()


func _server_unequip(slot: String) -> void:
	if not multiplayer.is_server():
		return
	if combat_timer > 0.0:
		_send_message("No puedes cambiar equipo en combate")
		return
	if not equipment.has(slot) or equipment[slot] == "":
		return
	_unequip_to_inventory(slot)
	_push_inventory()


# Traduce el EquipSlot del item a la clave del diccionario de equipo.
func _slot_for(item: ItemData) -> String:
	match item.equip_slot:
		ItemData.EquipSlot.WEAPON: return "weapon"
		ItemData.EquipSlot.HEAD: return "head"
		ItemData.EquipSlot.TORSO: return "torso"
		ItemData.EquipSlot.LEGS: return "legs"
		ItemData.EquipSlot.FEET: return "feet"
	return ""


# Quita el item del slot, le resta el bono y lo devuelve al inventario.
func _unequip_to_inventory(slot: String) -> void:
	var path: String = equipment[slot]
	if path == "":
		return
	var item := load(path) as ItemData
	if item:
		_apply_bonus(item, -1)
	equipment[slot] = ""
	_inv_add(path, 1)


# --- Sincronizacion del inventario al cliente dueño -----------------------------

func _push_inventory() -> void:
	if not multiplayer.is_server():
		return
	var atk: int = hurtbox.stats.attack if hurtbox.stats else 0
	var def_val: int = hurtbox.stats.defense if hurtbox.stats else 0
	var owner_id := name.to_int()
	if owner_id == multiplayer.get_unique_id():
		_refresh_inventory_ui()  # host: los datos ya son locales
	else:
		_recv_inventory.rpc_id(owner_id, inventory, equipment, atk, def_val)


@rpc("any_peer", "reliable")
func _recv_inventory(inv: Array, equip: Dictionary, atk: int, def_val: int) -> void:
	if not _is_from_server():
		return
	inventory = inv
	equipment = equip
	if hurtbox.stats:
		hurtbox.stats.attack = atk
		hurtbox.stats.defense = def_val
	_refresh_inventory_ui()


func _refresh_inventory_ui() -> void:
	if not is_multiplayer_authority():
		return
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("update_inventory"):
		hud.update_inventory(inventory, equipment)
	_save_character_local()


# Guarda en disco el personaje del dueño con su inventario/equipo actuales.
func _save_character_local() -> void:
	if not is_multiplayer_authority():
		return
	if Session.selected_character.is_empty():
		return
	var ch: Dictionary = Session.selected_character
	ch["inventory"] = inventory
	ch["equipment"] = equipment
	if hurtbox.stats:
		ch["level"] = hurtbox.stats.level
		ch["exp"] = hurtbox.stats.experience
	SaveManager.save_character(ch)
	Session.selected_character = ch


# --- Mensajes cortos al dueño (servidor -> cliente) -----------------------------

# --- Vida para los marcos de grupo ---------------------------------------------

func get_hp() -> int:
	return hurtbox.stats.current_hp if hurtbox.stats else 0

func get_max_hp() -> int:
	return hurtbox.stats.max_hp if hurtbox.stats else 1


func _server_connect_hp() -> void:
	if hurtbox.stats and not hurtbox.stats.hp_changed.is_connected(_on_server_hp_changed):
		hurtbox.stats.hp_changed.connect(_on_server_hp_changed)


func _on_server_hp_changed(_current: int, _max_hp: int) -> void:
	if multiplayer.is_server():
		PartyManager.server_notify_hp(name.to_int())


# Mensaje del servidor a este jugador (lo usan otros sistemas, p.ej. el loot).
func server_notify(text: String) -> void:
	_send_message(text)


func _send_message(text: String) -> void:
	if not multiplayer.is_server():
		return
	var owner_id := name.to_int()
	if owner_id == multiplayer.get_unique_id():
		_show_message(text)
	else:
		_recv_message.rpc_id(owner_id, text)


@rpc("any_peer", "reliable")
func _recv_message(text: String) -> void:
	if not _is_from_server():
		return
	_show_message(text)


func _show_message(text: String) -> void:
	if not is_multiplayer_authority():
		return
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("show_pickup"):
		hud.show_pickup(text)
