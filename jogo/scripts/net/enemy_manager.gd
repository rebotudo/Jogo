extends Node
## EnemyManager
## Autoload que gestiona los enemigos del mundo abierto. El SERVIDOR es la unica
## autoridad. Lee las zonas de ZoneDB y mantiene poblacion SOLO en las zonas de
## combate que tienen algun jugador cerca (activacion perezosa), para que un mundo
## enorme no tenga miles de enemigos a la vez. Las ciudades son seguras (sin
## enemigos). Los enemigos aparecen del tipo y nivel de su zona.

const ACTIVATE_MARGIN: float = 55.0   # un jugador a esta distancia del borde activa la zona
const TICK_INTERVAL: float = 2.0
const BOSS_RESPAWN: float = 75.0      # tras morir el jefe, tarda esto en reaparecer
const WB_RESPAWN: float = 180.0       # respawn de world bosses
const WB_ARENA: float = 22.0          # radio de la arena de world boss

var _enemy_scene: PackedScene = null
func _get_enemy_scene() -> PackedScene:
	if _enemy_scene == null:
		_enemy_scene = load("res://scenes/enemies/enemy.tscn")
	return _enemy_scene

var enemies_container: Node = null

# Servidor: id_enemigo -> {pos, type, level, zone}. Y poblacion por zona.
var active_enemies: Dictionary = {}
var _zone_ids: Dictionary = {}        # zone_id -> Array de ids vivos
var _zone_boss: Dictionary = {}       # zone_id -> id del jefe vivo
var _boss_dead_until: Dictionary = {} # zone_id -> momento hasta el que no reaparece
var _next_id: int = 1
var _tick_acc: float = 0.0

# --- Endgame: progreso y world bosses ---
var _zone_boss_kills: int = 0
var _world_boss_kills: int = 0
var _wb_alive: Dictionary = {}        # wb_id -> id del enemigo vivo
var _wb_dead_until: Dictionary = {}   # wb_id -> momento hasta el que no reaparece
var _wb_announced: Dictionary = {}    # wb_id -> ya anunciado que esta disponible


func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


func register_world(container: Node) -> void:
	enemies_container = container
	if not multiplayer.is_server():
		request_enemies.rpc_id(1)


func _process(delta: float) -> void:
	if not multiplayer.is_server() or enemies_container == null:
		return
	_tick_acc += delta
	if _tick_acc < TICK_INTERVAL:
		return
	_tick_acc = 0.0
	_update_zones()
	_update_world_bosses()


# Mantiene poblacion en zonas activas (jugador cerca) y vacia las inactivas.
func _update_zones() -> void:
	var players: Array = get_tree().get_nodes_in_group("player")
	for z in Zones.combat_zones():
		var zid: String = z["id"]
		var center: Vector3 = Zones.center3(z)
		var activate: float = float(z["radius"]) + ACTIVATE_MARGIN
		var active := false
		for p in players:
			if is_instance_valid(p) and center.distance_to(p.global_position) <= activate:
				active = true
				break
		var ids: Array = _zone_ids.get(zid, [])
		if active:
			var target := _zone_target(z)
			while ids.size() < target:
				_spawn_in_zone(z)
				ids = _zone_ids.get(zid, [])
			# Jefe de la zona (en su arena).
			if String(z.get("boss", "")) != "":
				var bid: int = _zone_boss.get(zid, 0)
				var alive: bool = bid != 0 and active_enemies.has(bid)
				if not alive and _now() >= float(_boss_dead_until.get(zid, 0.0)):
					_spawn_boss(z)
		elif not ids.is_empty():
			for eid in ids.duplicate():
				_despawn(eid)
			_zone_boss.erase(zid)


func _zone_target(z: Dictionary) -> int:
	return clampi(int(float(z["radius"]) / 9.0), 4, 9)


# --- Endgame: aparicion de world bosses -----------------------------------------

func _condition_met(w: Dictionary) -> bool:
	match String(w.get("cond_type", "")):
		"zone_kills":
			return _zone_boss_kills >= int(w["cond_value"])
		"wb_kills":
			return _world_boss_kills >= int(w["cond_value"])
	return false


func _update_world_bosses() -> void:
	var players: Array = get_tree().get_nodes_in_group("player")
	for w in Zones.world_bosses():
		if not _condition_met(w):
			continue
		var wid: String = w["id"]
		# Anuncio (una vez) de que ya esta disponible.
		if not _wb_announced.get(wid, false):
			_wb_announced[wid] = true
			announce.rpc("☠ %s ha despertado en los confines del mundo." % String(w["name"]))
		# Ya vivo o en cooldown de respawn.
		var bid: int = _wb_alive.get(wid, 0)
		if bid != 0 and active_enemies.has(bid):
			continue
		if _now() < float(_wb_dead_until.get(wid, 0.0)):
			continue
		# Aparece cuando un jugador llega a su arena.
		var center: Vector3 = Zones.wb_center3(w)
		for p in players:
			if is_instance_valid(p) and center.distance_to(p.global_position) <= WB_ARENA + 30.0:
				_spawn_world_boss(w)
				announce.rpc("⚔ ¡%s ha aparecido! ¡Preparaos!" % String(w["name"]))
				break


func _spawn_world_boss(w: Dictionary) -> void:
	var wid: String = w["id"]
	var pos: Vector3 = Zones.wb_center3(w) + Vector3(0, 1.5, 0)
	var id := _next_id
	_next_id += 1
	active_enemies[id] = {"pos": pos, "type": "worldboss", "level": int(w["level"]), "zone": "", "boss": true, "world_boss": true, "wb_id": wid}
	_wb_alive[wid] = id
	spawn_world_boss.rpc(id, pos, wid)


@rpc("authority", "call_local", "reliable")
func spawn_world_boss(id: int, pos: Vector3, wb_id: String) -> void:
	if enemies_container == null or enemies_container.has_node(str(id)):
		return
	var e := _get_enemy_scene().instantiate()
	e.name = str(id)
	enemies_container.add_child(e)
	e.set_multiplayer_authority(1, true)
	e.global_position = pos
	e.setup_world_boss(wb_id)


# Mensaje global en el HUD de cada peer.
@rpc("authority", "call_local", "reliable")
func announce(text: String) -> void:
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("show_pickup"):
		hud.show_pickup(text)


func _spawn_in_zone(z: Dictionary) -> void:
	var zid: String = z["id"]
	var center: Vector3 = Zones.center3(z)
	var r: float = float(z["radius"])
	var ang: float = randf() * TAU
	var dist: float = randf_range(14.0, r - 3.0)
	var pos: Vector3 = center + Vector3(cos(ang) * dist, 1.0, sin(ang) * dist)
	var types: Array = z["enemies"]
	var type_id: String = "goblin"
	if not types.is_empty():
		type_id = String(types[randi() % types.size()])
	var lvl: int = int(z["level"])
	var id := _next_id
	_next_id += 1
	active_enemies[id] = {"pos": pos, "type": type_id, "level": lvl, "zone": zid}
	if not _zone_ids.has(zid):
		_zone_ids[zid] = []
	_zone_ids[zid].append(id)
	spawn_enemy.rpc(id, pos, type_id, lvl)


func _spawn_boss(z: Dictionary) -> void:
	var zid: String = z["id"]
	var pos: Vector3 = Zones.center3(z) + Vector3(0, 1.0, 0)
	var id := _next_id
	_next_id += 1
	active_enemies[id] = {"pos": pos, "type": "boss", "level": int(z["level"]), "zone": zid, "boss": true}
	if not _zone_ids.has(zid):
		_zone_ids[zid] = []
	_zone_ids[zid].append(id)
	_zone_boss[zid] = id
	spawn_boss.rpc(id, pos, zid)


func _despawn(id: int) -> void:
	if not active_enemies.has(id):
		return
	var zid: String = active_enemies[id]["zone"]
	active_enemies.erase(id)
	if _zone_ids.has(zid):
		_zone_ids[zid].erase(id)
	despawn_enemy.rpc(id)


# Lo llama el enemigo (servidor) al morir.
func server_on_enemy_died(id: int) -> void:
	if not multiplayer.is_server():
		return
	if active_enemies.has(id):
		var info: Dictionary = active_enemies[id]
		if info.get("world_boss", false):
			var wid: String = String(info.get("wb_id", ""))
			_world_boss_kills += 1
			_wb_dead_until[wid] = _now() + WB_RESPAWN
			_wb_alive.erase(wid)
			announce.rpc("🏆 ¡%s ha sido derrotado!" % _wb_name(wid))
		elif info.get("boss", false):
			_zone_boss_kills += 1
			_boss_dead_until[info["zone"]] = _now() + BOSS_RESPAWN
			_zone_boss.erase(info["zone"])
	_despawn(id)  # el tick repondra la poblacion de la zona si sigue activa


func _wb_name(wid: String) -> String:
	var w: Dictionary = Zones.get_world_boss(wid)
	return String(w.get("name", "El jefe"))


@rpc("any_peer", "reliable")
func request_enemies() -> void:
	if not multiplayer.is_server():
		return
	var who := multiplayer.get_remote_sender_id()
	for eid in active_enemies.keys():
		var info: Dictionary = active_enemies[eid]
		if info.get("world_boss", false):
			spawn_world_boss.rpc_id(who, eid, info["pos"], String(info.get("wb_id", "")))
		elif info.get("boss", false):
			spawn_boss.rpc_id(who, eid, info["pos"], info["zone"])
		else:
			spawn_enemy.rpc_id(who, eid, info["pos"], info["type"], info["level"])


# --- RPCs en TODOS los peers ----------------------------------------------------

@rpc("authority", "call_local", "reliable")
func spawn_enemy(id: int, pos: Vector3, type_id: String = "goblin", level: int = 1) -> void:
	if enemies_container == null:
		return
	if enemies_container.has_node(str(id)):
		return
	var e := _get_enemy_scene().instantiate()
	e.name = str(id)
	enemies_container.add_child(e)
	e.set_multiplayer_authority(1, true)
	e.global_position = pos
	e.setup_type(type_id, level)


@rpc("authority", "call_local", "reliable")
func spawn_boss(id: int, pos: Vector3, zone_id: String) -> void:
	if enemies_container == null:
		return
	if enemies_container.has_node(str(id)):
		return
	var e := _get_enemy_scene().instantiate()
	e.name = str(id)
	enemies_container.add_child(e)
	e.set_multiplayer_authority(1, true)
	e.global_position = pos
	e.setup_boss(zone_id)


@rpc("authority", "call_local", "reliable")
func despawn_enemy(id: int) -> void:
	if enemies_container == null:
		return
	var n := enemies_container.get_node_or_null(str(id))
	if n:
		n.queue_free()
