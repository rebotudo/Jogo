extends CharacterBody3D

@export var stats: CharacterStats

@export var speed: float = 5.0
@export var jump_force: float = 5.0
@export var attack_cooldown: float = 0.5

var attack_timer: float = 0.0

@onready var spring_arm = $SpringArm3D
@onready var camera = $SpringArm3D/Camera3D
@onready var hitbox = $Hitbox
@onready var hurtbox = $Hurtbox
@onready var mesh = $MeshInstance3D
@onready var collision = $CollisionShape3D
var is_attacking: bool = false
var is_dead: bool = false

const RESPAWN_DELAY: float = 3.0

# Combate: el jugador esta "en combate" mientras este temporizador (en el
# servidor) sea > 0. Se pone al atacar o al recibir daño. Equipar solo se
# permite fuera de combate.
const COMBAT_DURATION: float = 5.0
var combat_timer: float = 0.0

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
	# Solo el jugador LOCAL toma control de raton, camara y HUD.
	if not is_multiplayer_authority():
		set_process_unhandled_input(false)
		return

	camera.current = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	call_deferred("_setup_hud")

func _setup_hud():
	var hud = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.setup(hurtbox.stats, self)

func _unhandled_input(event):
	# set_process_unhandled_input(false) ya bloquea esto para los no-locales,
	# pero dejamos la guarda por seguridad.
	if not is_multiplayer_authority():
		return
	# La camara solo gira con el raton capturado (no mientras navegamos la UI).
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		spring_arm.rotate_x(-event.relative.y * mouse_sensitivity)
		spring_arm.rotation.x = clamp(spring_arm.rotation.x, -0.8, 0.5)
	# I: abre/cierra el inventario.
	if event.is_action_pressed("inventory"):
		_toggle_inventory()
	# Escape: solo cierra el inventario si esta abierto. No libera el raton.
	if event.is_action_pressed("open_menu"):
		var hud = get_tree().get_first_node_in_group("hud")
		if hud and hud.has_method("is_inventory_open") and hud.is_inventory_open():
			_toggle_inventory()

func _toggle_inventory():
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("toggle_inventory"):
		var is_open: bool = hud.toggle_inventory()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if is_open else Input.MOUSE_MODE_CAPTURED

func _physics_process(delta):
	# El servidor descuenta el temporizador de combate en TODAS las copias
	# (la del host y las de los clientes remotos), sin importar la autoridad.
	if multiplayer.is_server() and combat_timer > 0.0:
		combat_timer = maxf(combat_timer - delta, 0.0)

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
		velocity = Vector3.ZERO
		return

	# Jugador LOCAL: simulacion normal.
	if attack_timer > 0:
		attack_timer -= delta

	if not is_on_floor():
		velocity.y -= gravity * delta

	var dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var move = (transform.basis * Vector3(dir.x, 0, dir.y)).normalized()

	if move:
		velocity.x = move.x * speed
		velocity.z = move.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_force

	# Solo atacamos con el raton capturado (no mientras el inventario/menu esta
	# abierto), para no entrar en combate sin querer al navegar la UI.
	if Input.is_action_just_pressed("attack") and not is_attacking and attack_timer <= 0 \
			and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_attack()

	move_and_slide()

	# Difundimos nuestra posicion y orientacion a los demas peers. Al ser la
	# autoridad de este nodo, el RPC se ejecuta en todos los OTROS clientes.
	_recv_transform.rpc(global_position, rotation.y)

func _attack():
	# El ataque solo corre en el jugador local. El Hitbox detecta a quien golpea
	# y el dano se resuelve en el servidor via CombatManager (modelo autoritativo).
	is_attacking = true
	attack_timer = attack_cooldown
	_report_combat()  # atacar te pone en combate
	# Mostramos el gesto de ataque en TODOS los peers (incluido el local).
	play_attack.rpc()
	# El daño = nuestro stat de ataque.
	var dmg: int = hurtbox.stats.attack if hurtbox.stats else 10
	hitbox.activate(dmg)
	await get_tree().create_timer(0.2).timeout
	hitbox.deactivate()
	is_attacking = false


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
func server_take_damage(amount: int) -> void:
	if not multiplayer.is_server() or hurtbox.stats == null or is_dead:
		return
	combat_timer = COMBAT_DURATION  # recibir daño te pone en combate
	hurtbox.stats.take_damage(amount)
	_recv_hp.rpc(hurtbox.stats.current_hp, hurtbox.stats.max_hp)
	play_hit_flash.rpc()  # parpadeo de impacto en todos los peers
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
	hurtbox.stats.hp_changed.emit(current, max_hp)


# --- Feedback visual (se ejecuta en todos los peers) ----------------------------

@rpc("authority", "call_local", "reliable")
func play_attack() -> void:
	_attack_lunge()


@rpc("any_peer", "call_local", "reliable")
func play_hit_flash() -> void:
	_hit_flash()


func _attack_lunge() -> void:
	# Pequeña embestida hacia adelante (-z) del mesh y vuelta.
	if mesh == null:
		return
	var tween := create_tween()
	tween.tween_property(mesh, "position:z", -0.4, 0.08)
	tween.tween_property(mesh, "position:z", 0.0, 0.12)


func _hit_flash() -> void:
	# Parpadeo blanco breve al recibir daño.
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


func _server_respawn() -> void:
	if not multiplayer.is_server() or hurtbox.stats == null:
		return
	# Vida llena en la copia del servidor y repartida a todos.
	hurtbox.stats.current_hp = hurtbox.stats.max_hp
	hurtbox.stats.hp_changed.emit(hurtbox.stats.max_hp, hurtbox.stats.max_hp)
	_recv_hp.rpc(hurtbox.stats.max_hp, hurtbox.stats.max_hp)
	_set_dead.rpc(false)
	# El dueño (autoridad de la posicion) se teletransporta al punto de aparicion.
	var pos := Vector3(randf_range(-5.0, 5.0), 1.0, randf_range(-5.0, 5.0))
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
	if mesh:
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
var equipment: Dictionary = {"weapon": "", "armor": ""}


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
	var slot := ""
	if item.type == ItemData.ItemType.WEAPON:
		slot = "weapon"
	elif item.type == ItemData.ItemType.ARMOR:
		slot = "armor"
	else:
		_send_message("Ese objeto no se puede equipar")
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


# --- Mensajes cortos al dueño (servidor -> cliente) -----------------------------

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
