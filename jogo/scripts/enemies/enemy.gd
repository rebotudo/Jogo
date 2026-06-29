extends CharacterBody3D
## Enemy
## Modelo autoritativo: la IA, el movimiento, la vida y la muerte solo se
## calculan en el SERVIDOR. Los clientes no simulan nada; reciben la posicion y
## la vida por RPC y se limitan a mostrarlas.

@onready var hurtbox = $Hurtbox
@onready var nav_agent = $NavigationAgent3D
@onready var hitbox = $Hitbox
@onready var health_bar = $EnemyHealthBar

const CharacterVisual = preload("res://scripts/player/character_visual.gd")
var _avatar: CharacterVisual = null

@export var speed: float = 3.0
@export var detection_range: float = 8.0    # distancia a la que detecta al jugador
@export var attack_range: float = 1.5
@export var attack_cooldown: float = 1.5
@export var leash_range: float = 14.0       # max distancia de su origen antes de rendirse
@export var patrol_radius: float = 5.0      # radio de la zona de patrulla
@export var patrol_wait: float = 2.0        # pausa al llegar a un punto de patrulla
@export var return_speed_mult: float = 1.6  # vuelve mas rapido al rendirse
@export var exp_reward: int = 25            # EXP que da al morir

const EXP_SHARE_RANGE := 30.0  # los jugadores dentro de este rango reciben EXP
@export var loot_table: Array[LootEntry] = []

# Catalogo de tipos de monstruo. "behavior": "melee" o "ranged" (dispara).
# "loot": [ [ruta_item, probabilidad, min, max], ... ].
const MONSTERS := {
	"goblin": {
		"name": "Goblin", "color": Color(0.32, 0.55, 0.25), "size": 0.82,
		"hp": 55, "atk": 7, "def": 2, "speed": 4.4, "detect": 11.0,
		"atk_range": 1.7, "atk_cd": 0.9, "exp": 15, "behavior": "melee",
		"loot": [["res://data/items/materials/leather_scrap.tres", 0.6, 1, 2], ["res://data/items/monster_fang.tres", 0.4, 1, 1]],
	},
	"wolf": {
		"name": "Lobo", "color": Color(0.5, 0.5, 0.55), "size": 0.95,
		"hp": 75, "atk": 11, "def": 3, "speed": 6.2, "detect": 13.0,
		"atk_range": 1.8, "atk_cd": 1.0, "exp": 24, "behavior": "melee",
		"loot": [["res://data/items/materials/wolf_pelt.tres", 0.7, 1, 2], ["res://data/items/monster_fang.tres", 0.5, 1, 1]],
	},
	"brute": {
		"name": "Bruto", "color": Color(0.55, 0.18, 0.16), "size": 1.35,
		"hp": 190, "atk": 19, "def": 8, "speed": 2.8, "detect": 10.0,
		"atk_range": 2.3, "atk_cd": 1.9, "exp": 48, "behavior": "melee",
		"loot": [["res://data/items/materials/iron_ore.tres", 0.7, 1, 3], ["res://data/items/monster_fang.tres", 0.6, 1, 2], ["res://data/items/materials/steel_ingot.tres", 0.25, 1, 1]],
	},
	"shaman": {
		"name": "Chamán", "color": Color(0.46, 0.3, 0.62), "size": 1.0,
		"hp": 85, "atk": 13, "def": 3, "speed": 3.2, "detect": 17.0,
		"atk_range": 14.0, "atk_cd": 2.0, "exp": 36, "behavior": "ranged", "proj": "magic",
		"loot": [["res://data/items/materials/magic_essence.tres", 0.6, 1, 2], ["res://data/items/materials/bone_fragment.tres", 0.5, 1, 2]],
	},
	# --- Bioma AGUA ---
	"crab": {
		"name": "Cangrejo", "color": Color(0.2, 0.5, 0.55), "size": 1.1,
		"hp": 95, "atk": 9, "def": 7, "speed": 3.2, "detect": 10.0,
		"atk_range": 2.0, "atk_cd": 1.3, "exp": 20, "behavior": "melee", "proj": "magic",
		"loot": [["res://data/items/materials/leather_scrap.tres", 0.6, 1, 2], ["res://data/items/monster_fang.tres", 0.4, 1, 1]],
	},
	"naiad": {
		"name": "Náyade", "color": Color(0.35, 0.6, 0.85), "size": 1.0,
		"hp": 65, "atk": 11, "def": 2, "speed": 3.5, "detect": 16.0,
		"atk_range": 13.0, "atk_cd": 1.8, "exp": 26, "behavior": "ranged", "proj": "water",
		"loot": [["res://data/items/materials/magic_essence.tres", 0.6, 1, 2]],
	},
	"eel": {
		"name": "Anguila", "color": Color(0.18, 0.4, 0.42), "size": 0.85,
		"hp": 55, "atk": 10, "def": 2, "speed": 6.2, "detect": 12.0,
		"atk_range": 1.7, "atk_cd": 0.9, "exp": 22, "behavior": "melee", "proj": "magic",
		"loot": [["res://data/items/materials/leather_scrap.tres", 0.6, 1, 2]],
	},
	# --- Bioma FUEGO ---
	"imp": {
		"name": "Diablillo", "color": Color(0.9, 0.4, 0.15), "size": 0.85,
		"hp": 55, "atk": 11, "def": 2, "speed": 6.0, "detect": 12.0,
		"atk_range": 1.7, "atk_cd": 0.9, "exp": 24, "behavior": "melee", "proj": "fire",
		"loot": [["res://data/items/materials/leather_scrap.tres", 0.6, 1, 2], ["res://data/items/monster_fang.tres", 0.4, 1, 1]],
	},
	"magma_brute": {
		"name": "Bruto de Magma", "color": Color(0.5, 0.15, 0.1), "size": 1.35,
		"hp": 200, "atk": 20, "def": 9, "speed": 2.7, "detect": 10.0,
		"atk_range": 2.3, "atk_cd": 1.9, "exp": 50, "behavior": "melee", "proj": "fire",
		"loot": [["res://data/items/materials/iron_ore.tres", 0.7, 1, 3], ["res://data/items/materials/steel_ingot.tres", 0.3, 1, 1]],
	},
	"flame_caster": {
		"name": "Invocador Ígneo", "color": Color(1.0, 0.55, 0.2), "size": 1.0,
		"hp": 80, "atk": 14, "def": 3, "speed": 3.2, "detect": 17.0,
		"atk_range": 14.0, "atk_cd": 1.9, "exp": 38, "behavior": "ranged", "proj": "fire",
		"loot": [["res://data/items/materials/magic_essence.tres", 0.6, 1, 2]],
	},
	# --- Bioma JUNGLA ---
	"panther": {
		"name": "Pantera", "color": Color(0.18, 0.35, 0.2), "size": 0.95,
		"hp": 70, "atk": 12, "def": 3, "speed": 6.5, "detect": 13.0,
		"atk_range": 1.8, "atk_cd": 0.85, "exp": 26, "behavior": "melee", "proj": "poison",
		"loot": [["res://data/items/materials/wolf_pelt.tres", 0.7, 1, 2]],
	},
	"vinebeast": {
		"name": "Bestia de Lianas", "color": Color(0.25, 0.45, 0.2), "size": 1.25,
		"hp": 160, "atk": 16, "def": 7, "speed": 2.9, "detect": 10.0,
		"atk_range": 2.2, "atk_cd": 1.7, "exp": 44, "behavior": "melee", "proj": "poison",
		"loot": [["res://data/items/materials/leather_scrap.tres", 0.7, 1, 3], ["res://data/items/materials/iron_ore.tres", 0.4, 1, 2]],
	},
	"spore_shaman": {
		"name": "Chamán de Esporas", "color": Color(0.45, 0.6, 0.3), "size": 1.0,
		"hp": 80, "atk": 12, "def": 3, "speed": 3.2, "detect": 16.0,
		"atk_range": 13.0, "atk_cd": 1.9, "exp": 36, "behavior": "ranged", "proj": "poison",
		"loot": [["res://data/items/materials/magic_essence.tres", 0.6, 1, 2], ["res://data/items/materials/bone_fragment.tres", 0.5, 1, 2]],
	},
	# --- Bioma DESIERTO ---
	"scorpion": {
		"name": "Escorpión", "color": Color(0.8, 0.65, 0.35), "size": 1.1,
		"hp": 100, "atk": 13, "def": 7, "speed": 3.5, "detect": 11.0,
		"atk_range": 2.0, "atk_cd": 1.3, "exp": 28, "behavior": "melee", "proj": "sand",
		"loot": [["res://data/items/materials/bone_fragment.tres", 0.6, 1, 2]],
	},
	"sand_wretch": {
		"name": "Desdichado de Arena", "color": Color(0.85, 0.75, 0.5), "size": 0.85,
		"hp": 55, "atk": 10, "def": 2, "speed": 6.0, "detect": 12.0,
		"atk_range": 1.7, "atk_cd": 0.9, "exp": 22, "behavior": "melee", "proj": "sand",
		"loot": [["res://data/items/materials/leather_scrap.tres", 0.6, 1, 2]],
	},
	"dust_caster": {
		"name": "Conjurador de Polvo", "color": Color(0.78, 0.62, 0.32), "size": 1.0,
		"hp": 75, "atk": 13, "def": 3, "speed": 3.2, "detect": 16.0,
		"atk_range": 14.0, "atk_cd": 1.9, "exp": 36, "behavior": "ranged", "proj": "sand",
		"loot": [["res://data/items/materials/magic_essence.tres", 0.6, 1, 2]],
	},
	# --- Bioma HIELO ---
	"frostwolf": {
		"name": "Lobo Escarcha", "color": Color(0.7, 0.85, 0.95), "size": 0.95,
		"hp": 72, "atk": 11, "def": 3, "speed": 6.3, "detect": 13.0,
		"atk_range": 1.8, "atk_cd": 0.95, "exp": 25, "behavior": "melee", "proj": "ice",
		"loot": [["res://data/items/materials/wolf_pelt.tres", 0.7, 1, 2]],
	},
	"ice_golem": {
		"name": "Gólem de Hielo", "color": Color(0.55, 0.8, 0.92), "size": 1.4,
		"hp": 210, "atk": 19, "def": 10, "speed": 2.6, "detect": 10.0,
		"atk_range": 2.3, "atk_cd": 2.0, "exp": 52, "behavior": "melee", "proj": "ice",
		"loot": [["res://data/items/materials/iron_ore.tres", 0.7, 1, 3], ["res://data/items/materials/steel_ingot.tres", 0.3, 1, 1]],
	},
	"frost_caster": {
		"name": "Invocador Gélido", "color": Color(0.6, 0.85, 1.0), "size": 1.0,
		"hp": 80, "atk": 13, "def": 3, "speed": 3.2, "detect": 17.0,
		"atk_range": 14.0, "atk_cd": 1.9, "exp": 38, "behavior": "ranged", "proj": "ice",
		"loot": [["res://data/items/materials/magic_essence.tres", 0.6, 1, 2]],
	},
	# --- Bioma PANTANO ---
	"bog_crawler": {
		"name": "Reptador del Fango", "color": Color(0.3, 0.38, 0.24), "size": 1.2,
		"hp": 130, "atk": 14, "def": 6, "speed": 2.9, "detect": 10.0,
		"atk_range": 2.1, "atk_cd": 1.6, "exp": 38, "behavior": "melee", "proj": "poison",
		"loot": [["res://data/items/materials/leather_scrap.tres", 0.7, 1, 2], ["res://data/items/materials/bone_fragment.tres", 0.5, 1, 2]],
	},
	"leech": {
		"name": "Sanguijuela", "color": Color(0.35, 0.25, 0.28), "size": 0.8,
		"hp": 50, "atk": 9, "def": 2, "speed": 5.8, "detect": 11.0,
		"atk_range": 1.6, "atk_cd": 0.85, "exp": 20, "behavior": "melee", "proj": "poison",
		"loot": [["res://data/items/materials/leather_scrap.tres", 0.6, 1, 2]],
	},
	"witch": {
		"name": "Bruja del Pantano", "color": Color(0.42, 0.3, 0.45), "size": 1.0,
		"hp": 78, "atk": 13, "def": 3, "speed": 3.0, "detect": 16.0,
		"atk_range": 13.0, "atk_cd": 1.9, "exp": 36, "behavior": "ranged", "proj": "poison",
		"loot": [["res://data/items/materials/magic_essence.tres", 0.6, 1, 2], ["res://data/items/materials/bone_fragment.tres", 0.5, 1, 2]],
	},
}
const _PROJECTILE: PackedScene = preload("res://scenes/combat/projectile.tscn")

var monster_type: String = "goblin"
var behavior: String = "melee"
var monster_level: int = 1
var _proj_kind: String = "magic"   # tipo de proyectil del ataque a distancia
var _base_scale: Vector3 = Vector3.ONE   # escala del mesh (para el "punch" de impacto)

# Jefe de zona: mas fuerte y con un ataque de area TELEGRAFIADO (marca roja en el
# suelo que crece; al llenarse, golpea esa zona — hay que salir a tiempo).
var is_boss: bool = false
var is_world_boss: bool = false
var _tele_count: int = 1   # cuantas marcas suelta a la vez (world boss: varias)
var _tele_radius: float = 6.0
var _tele_damage: int = 30
var _tele_windup: float = 1.4
var _special_interval: float = 6.0
var _special_cd: float = 4.0
# Muro de la arena: sella el combate 1v1 mientras el jefe esta enganchado.
var _barrier: StaticBody3D = null
var _barrier_on: bool = false
var _arena_center: Vector3 = Vector3.ZERO
var _arena_radius: float = 14.0

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
var _last_attacker: int = 0  # id del ultimo jugador que le golpeo (recompensas)
var _stun_time: float = 0.0  # mientras > 0 el enemigo esta aturdido (no actua)
var _taunt_time: float = 0.0  # mientras > 0 esta provocado (obligado a atacar a _taunt_by)
var _taunt_by: Node3D = null
var _poison_stacks: int = 0   # veneno: ralentiza y debilita
var _poison_time: float = 0.0
var _curse_time: float = 0.0       # maldicion: reduce daño y defensa
var _curse_def_applied: int = 0    # defensa reducida (para restaurarla al expirar)

# Para los clientes: ultima transformada recibida del servidor (interpolamos).
var _net_position: Vector3
var _net_rotation_y: float
var _has_net_target: bool = false

enum State { PATROL, CHASE, ATTACK, RETURN }
var state: State = State.PATROL


func _ready():
	add_to_group("enemy")  # para habilidades de area que buscan enemigos
	# Los enemigos chocan ademas con el muro de arena (capa 7); los jugadores no.
	collision_mask = collision_mask | 64
	# (Revertido a capsulas) sin muñeco animado: se queda la capsula roja.
	# El medidor de vida se muestra en TODOS los peers.
	if hurtbox.stats == null:
		push_warning("Enemy sin stats asignado en el Hurtbox")
	else:
		health_bar.setup(hurtbox.stats)


# Configura el tipo de monstruo y su nivel (lo llama EnemyManager en todos los
# peers). El nivel escala vida/daño/defensa/EXP segun la zona.
func setup_type(type_id: String, level: int = 1) -> void:
	var cfg: Dictionary = MONSTERS.get(type_id, MONSTERS["goblin"])
	monster_type = type_id
	behavior = String(cfg["behavior"])
	_proj_kind = String(cfg.get("proj", "magic"))
	monster_level = level
	var lf: float = float(level - 1)
	# Aspecto: color + tamaño de la capsula.
	var m := get_node_or_null("MeshInstance3D") as MeshInstance3D
	if m != null:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = cfg["color"]
		m.set_surface_override_material(0, mat)
		m.scale = Vector3.ONE * float(cfg["size"])
		_base_scale = m.scale
	# Stats escalados por nivel (en todos los peers para que la barra sea correcta).
	if hurtbox.stats != null:
		hurtbox.stats.max_hp = int(round(float(cfg["hp"]) * (1.0 + lf * 0.12)))
		hurtbox.stats.current_hp = hurtbox.stats.max_hp
		hurtbox.stats.attack = int(round(float(cfg["atk"]) * (1.0 + lf * 0.08)))
		hurtbox.stats.defense = int(round(float(cfg["def"]) + lf * 0.5))
		hurtbox.stats.hp_changed.emit(hurtbox.stats.current_hp, hurtbox.stats.max_hp)
		if health_bar != null:
			health_bar.setup(hurtbox.stats)
	# Parametros de IA.
	speed = float(cfg["speed"])
	detection_range = float(cfg["detect"])
	attack_range = float(cfg["atk_range"])
	attack_cooldown = float(cfg["atk_cd"])
	exp_reward = int(round(float(cfg["exp"]) * (1.0 + lf * 0.1)))
	_apply_loot(cfg["loot"])


func _apply_loot(loot_cfg: Array) -> void:
	loot_table.clear()
	for entry in loot_cfg:
		var item := load(entry[0]) as ItemData
		if item == null:
			continue
		var le := LootEntry.new()
		le.item = item
		le.drop_chance = float(entry[1])
		le.min_amount = int(entry[2])
		le.max_amount = int(entry[3])
		loot_table.append(le)


# Configura este enemigo como JEFE de una zona (lo llama EnemyManager).
func setup_boss(zone_id: String) -> void:
	is_boss = true
	behavior = "melee"
	var z: Dictionary = Zones.get_zone(zone_id)
	var lvl: int = int(z.get("level", 10))
	var tier: int = int(z.get("tier", 1))
	monster_level = lvl
	monster_type = "boss"
	# Aspecto: grande y con brillo amenazante, tematizado por bioma.
	var biome: String = String(z.get("biome", "forest"))
	var body_col := Color(0.3, 0.08, 0.1)
	var glow_col := Color(0.7, 0.12, 0.12)
	match biome:
		"water":
			body_col = Color(0.12, 0.28, 0.4); glow_col = Color(0.2, 0.5, 0.9)
		"fire":
			body_col = Color(0.4, 0.12, 0.06); glow_col = Color(1.0, 0.45, 0.1)
		"jungle":
			body_col = Color(0.16, 0.3, 0.14); glow_col = Color(0.4, 0.9, 0.3)
		"desert":
			body_col = Color(0.5, 0.4, 0.2); glow_col = Color(0.95, 0.8, 0.35)
		"ice":
			body_col = Color(0.3, 0.55, 0.7); glow_col = Color(0.6, 0.9, 1.0)
		"swamp":
			body_col = Color(0.22, 0.28, 0.18); glow_col = Color(0.5, 0.85, 0.3)
	var m := get_node_or_null("MeshInstance3D") as MeshInstance3D
	if m != null:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = body_col
		mat.emission_enabled = true
		mat.emission = glow_col
		mat.emission_energy_multiplier = 0.6
		m.set_surface_override_material(0, mat)
		m.scale = Vector3.ONE * (1.9 + tier * 0.18)
		_base_scale = m.scale
	# Stats: muy por encima de un enemigo normal.
	if hurtbox.stats != null:
		hurtbox.stats.max_hp = int(round(400 + lvl * 60))
		hurtbox.stats.current_hp = hurtbox.stats.max_hp
		hurtbox.stats.attack = int(round(12 + lvl * 1.5))
		hurtbox.stats.defense = int(round(6 + lvl * 0.7))
		hurtbox.stats.hp_changed.emit(hurtbox.stats.current_hp, hurtbox.stats.max_hp)
		if health_bar != null:
			health_bar.setup(hurtbox.stats)
	speed = 3.2
	# El jefe solo se activa DENTRO de su arena y vuelve si te alejas de ella.
	detection_range = 12.0   # hay que pisar el circulo del jefe para activarlo
	attack_range = 2.6
	attack_cooldown = 1.6
	leash_range = 18.0       # al salir de la arena, el jefe regresa al centro
	patrol_radius = 0.0      # no deambula: se queda en el centro de la arena
	# Muro de la arena (sella el 1v1).
	_arena_center = Zones.center3(z)
	_arena_radius = 14.0
	_create_barrier(_arena_center)
	exp_reward = int(round(220 + lvl * 35))
	# Ataque telegrafiado escalado por tier/nivel.
	_tele_radius = 5.5 + tier * 0.7
	_tele_damage = int(round(22 + lvl * 2.2))
	_tele_windup = maxf(1.55 - tier * 0.05, 1.1)
	_special_interval = 5.5
	_special_cd = 3.5
	# Botin de jefe: materiales raros (mejor cuanto mas alto el tier).
	var loot: Array = [
		["res://data/items/materials/magic_essence.tres", 1.0, 2, 4],
		["res://data/items/materials/steel_ingot.tres", 0.8, 1, 3],
		["res://data/items/materials/mithril_shard.tres", 0.5 + tier * 0.08, 1, 2],
		["res://data/items/materials/dragon_scale.tres", 0.1 + tier * 0.12, 1, 1],
	]
	_apply_loot(loot)


# Configura este enemigo como WORLD BOSS de endgame (enorme, brutal, varios
# telegrafiados a la vez, en una gran arena de los confines).
func setup_world_boss(wb_id: String) -> void:
	is_boss = true
	is_world_boss = true
	behavior = "melee"
	var w: Dictionary = Zones.get_world_boss(wb_id)
	var lvl: int = int(w.get("level", 100))
	monster_level = lvl
	monster_type = "worldboss"
	var m := get_node_or_null("MeshInstance3D") as MeshInstance3D
	if m != null:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.12, 0.05, 0.16)
		mat.emission_enabled = true
		mat.emission = Color(0.8, 0.1, 0.5)
		mat.emission_energy_multiplier = 0.8
		m.set_surface_override_material(0, mat)
		m.scale = Vector3.ONE * 3.2
		_base_scale = m.scale
	if hurtbox.stats != null:
		hurtbox.stats.max_hp = int(round(3000 + lvl * 220))
		hurtbox.stats.current_hp = hurtbox.stats.max_hp
		hurtbox.stats.attack = int(round(30 + lvl * 2.2))
		hurtbox.stats.defense = int(round(14 + lvl * 1.0))
		hurtbox.stats.hp_changed.emit(hurtbox.stats.current_hp, hurtbox.stats.max_hp)
		if health_bar != null:
			health_bar.setup(hurtbox.stats)
	speed = 3.0
	detection_range = 20.0
	attack_range = 4.2
	attack_cooldown = 1.5
	leash_range = 30.0
	patrol_radius = 0.0
	exp_reward = int(round(2500 + lvl * 120))
	_arena_center = Zones.wb_center3(w)
	_arena_radius = 22.0
	_create_barrier(_arena_center)
	# Telegrafiado brutal: varias marcas a la vez, grandes y frecuentes.
	_tele_radius = 8.0
	_tele_damage = int(round(70 + lvl * 3.0))
	_tele_windup = 1.3
	_special_interval = 4.0
	_special_cd = 3.0
	_tele_count = 3
	# Botin de endgame: lo mejor del juego.
	var loot: Array = [
		["res://data/items/materials/dragon_scale.tres", 1.0, 2, 4],
		["res://data/items/materials/mithril_shard.tres", 1.0, 2, 4],
		["res://data/items/weapons/dragon_blade.tres", 0.3, 1, 1],
		["res://data/items/weapons/mithril_greatsword.tres", 0.3, 1, 1],
		["res://data/items/armor/mithril_chest.tres", 0.4, 1, 1],
		["res://data/items/armor/mithril_helm.tres", 0.4, 1, 1],
	]
	_apply_loot(loot)


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

	# Aturdido: no se mueve ni ataca.
	if _stun_time > 0.0:
		_stun_time -= delta
		velocity.x = 0
		velocity.z = 0
		move_and_slide()
		_broadcast_transform()
		return

	if attack_timer > 0:
		attack_timer -= delta

	# Veneno: caduca y limpia las acumulaciones.
	if _poison_time > 0.0:
		_poison_time -= delta
		if _poison_time <= 0.0:
			_poison_stacks = 0

	# Maldición: caduca y restaura la defensa reducida.
	if _curse_time > 0.0:
		_curse_time -= delta
		if _curse_time <= 0.0 and hurtbox.stats != null:
			hurtbox.stats.defense += _curse_def_applied
			_curse_def_applied = 0

	# Soltar al objetivo si ya no es valido, murio o se volvio invisible.
	if not is_instance_valid(player) or player.get("is_dead") or player.get("is_invisible"):
		player = null

	# Provocado: obligado a perseguir/atacar al tanque que le provoco.
	if _taunt_time > 0.0:
		_taunt_time -= delta
		if is_instance_valid(_taunt_by) and not _taunt_by.get("is_dead"):
			player = _taunt_by
			if state == State.PATROL or state == State.RETURN:
				state = State.CHASE
		else:
			_taunt_time = 0.0
			_taunt_by = null

	var dist_home := global_position.distance_to(home_position)
	var dist_player := INF
	if player:
		dist_player = global_position.distance_to(player.global_position)

	match state:
		State.PATROL:
			_patrol(delta)
			# Aggro: si hay un jugador dentro del rango de deteccion, perseguir.
			var target := _find_nearest_target()
			if target and global_position.distance_to(target.global_position) <= detection_range:
				player = target
				state = State.CHASE

		State.CHASE:
			if player == null:
				state = State.RETURN
			elif dist_home > leash_range and _taunt_time <= 0.0:
				player = null  # demasiado lejos de la zona: rendirse
				state = State.RETURN
			elif dist_player <= attack_range:
				state = State.ATTACK
			else:
				_move_towards(player.global_position)

		State.ATTACK:
			if player == null:
				state = State.RETURN
			elif dist_home > leash_range and _taunt_time <= 0.0:
				player = null
				state = State.RETURN
			elif dist_player > attack_range * 1.3:
				state = State.CHASE
			elif behavior == "ranged" and dist_player < attack_range * 0.35 and dist_home < leash_range - 3.0:
				_move_away_from(player.global_position)  # kiting, sin alejarse de su zona
			else:
				velocity.x = 0
				velocity.z = 0
				_face(player.global_position)
				if attack_timer <= 0:
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

	# Jefe: muro de arena (sella el 1v1) + ataque de area telegrafiado.
	if is_boss:
		# Si el jugador sale de la arena, el jefe se desengancha (no se le puede
		# atacar desde fuera del muro) y volvera a su sitio recuperando la vida.
		if is_instance_valid(player):
			var pd: float = Vector2(player.global_position.x, player.global_position.z).distance_to(Vector2(_arena_center.x, _arena_center.z))
			if pd > _arena_radius + 1.0:
				player = null
				if state == State.CHASE or state == State.ATTACK:
					state = State.RETURN
		var engaged: bool = (state == State.CHASE or state == State.ATTACK)
		if engaged != _barrier_on:
			_barrier_on = engaged
			_set_barrier.rpc(engaged)
			if engaged:
				_seal_arena()  # expulsa a los enemigos del entorno que esten dentro
		if _special_cd > 0.0:
			_special_cd -= delta
		elif is_instance_valid(player) and engaged:
			_special_cd = _special_interval
			_telegraph_attack()

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


func _find_nearest_target() -> Node3D:
	var nearest: Node3D = null
	var best_dist := INF
	for p in get_tree().get_nodes_in_group("player"):
		if not is_instance_valid(p):
			continue
		if p.get("is_dead") or p.get("is_invisible"):  # ignorar muertos e invisibles
			continue
		var d := global_position.distance_to(p.global_position)
		if d < best_dist:
			best_dist = d
			nearest = p
	# Tambien persiguen a los esqueletos invocados (minions).
	for m in get_tree().get_nodes_in_group("minion"):
		if not is_instance_valid(m):
			continue
		var dm := global_position.distance_to(m.global_position)
		if dm < best_dist:
			best_dist = dm
			nearest = m
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
	var spd := speed * speed_mult * _poison_slow()
	velocity.x = direction.x * spd
	velocity.z = direction.z * spd

	var look_target := global_position + direction
	look_target.y = global_position.y
	look_at(look_target, Vector3.UP)


func _attack():
	is_attacking = true
	attack_timer = attack_cooldown
	# El daño = el stat de ataque del enemigo, reducido por veneno y maldición.
	var base_dmg: int = hurtbox.stats.attack if hurtbox.stats else 10
	var dmg: int = int(round(float(base_dmg) * _poison_weaken() * _curse_weaken()))
	if behavior == "ranged":
		_ranged_attack(dmg)
		is_attacking = false
		return
	# Cuerpo a cuerpo: gesto + hitbox.
	play_attack.rpc()
	hitbox.activate(dmg)
	await get_tree().create_timer(0.2).timeout
	hitbox.deactivate()
	is_attacking = false


# Ataque a distancia (chaman): lanza un proyectil magico hacia el jugador.
func _ranged_attack(dmg: int) -> void:
	if not is_instance_valid(player):
		return
	play_attack.rpc()
	var origin: Vector3 = global_position + Vector3.UP * 1.4
	var target: Vector3 = player.global_position + Vector3.UP * 1.0
	var dir: Vector3 = (target - origin).normalized()
	origin += dir * 0.8
	_spawn_enemy_proj.rpc(origin, dir, dmg, _proj_kind)


# Crea el proyectil enemigo en todos los peers (golpea a JUGADORES, capa 2).
@rpc("authority", "call_local", "reliable")
func _spawn_enemy_proj(origin: Vector3, dir: Vector3, dmg: int, kind: String = "magic") -> void:
	var p := _PROJECTILE.instantiate()
	get_tree().current_scene.add_child(p)
	# Golpea a jugadores/minions (capa 2) y CHOCA con el muro de arena (capa 7),
	# para que los enemigos de fuera no disparen dentro del combate sellado.
	p.collision_mask = 2 | 64
	p.speed = 17.0
	p.global_position = origin
	p.setup(dir, dmg, 1, kind)  # aid=1: el servidor aplica el daño


# Ataque telegrafiado del jefe: marca el suelo donde esta el objetivo, espera, y
# golpea esa area. El jugador debe salir del circulo a tiempo.
func _telegraph_attack() -> void:
	if not is_instance_valid(player):
		return
	# Una o varias marcas (world boss): la primera sobre el jugador, las demas
	# alrededor, para que tenga que esquivar entre ellas.
	var spots: Array = []
	var base: Vector3 = player.global_position
	base.y = 0.0
	spots.append(base)
	for i in (_tele_count - 1):
		spots.append(base + Vector3(randf_range(-7.0, 7.0), 0.0, randf_range(-7.0, 7.0)))
	for s in spots:
		_play_telegraph.rpc(s, _tele_radius, _tele_windup)
	await get_tree().create_timer(_tele_windup).timeout
	if is_queued_for_deletion() or _dead:
		return  # el jefe murio durante el aviso
	# Daño (una vez) a quien siga dentro de ALGUNA de las marcas.
	var hit: Array = []
	for grp in ["player", "minion"]:
		for t in get_tree().get_nodes_in_group(grp):
			if not is_instance_valid(t) or t.get("is_dead") or t in hit:
				continue
			var tp := Vector2(t.global_position.x, t.global_position.z)
			for s in spots:
				if tp.distance_to(Vector2(s.x, s.z)) <= _tele_radius:
					hit.append(t)
					break
	for t in hit:
		if t.has_method("server_take_damage"):
			t.server_take_damage(_tele_damage, 0)
	for s in spots:
		_play_boom.rpc(s, _tele_radius)


# Marca roja que crece en el suelo durante la ventana de aviso (todos los peers).
@rpc("authority", "call_local", "reliable")
func _play_telegraph(pos: Vector3, radius: float, windup: float) -> void:
	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = 0.1
	disc.mesh = cm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.15, 0.12, 0.35)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.1, 0.1)
	mat.emission_energy_multiplier = 0.6
	disc.material_override = mat
	get_tree().current_scene.add_child(disc)
	disc.global_position = pos + Vector3(0, 0.07, 0)
	disc.scale = Vector3(0.05, 1.0, 0.05)  # crece de 0 a full = cuenta atras
	var t := disc.create_tween()
	t.tween_property(disc, "scale", Vector3(1, 1, 1), windup)
	t.tween_callback(disc.queue_free)


# Estallido al cumplirse el aviso.
@rpc("authority", "call_local", "reliable")
func _play_boom(pos: Vector3, radius: float) -> void:
	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = 0.2
	disc.mesh = cm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.5, 0.1, 0.7)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.5, 0.1)
	mat.emission_energy_multiplier = 2.5
	disc.material_override = mat
	get_tree().current_scene.add_child(disc)
	disc.global_position = pos + Vector3(0, 0.12, 0)
	var t := disc.create_tween()
	t.tween_property(mat, "albedo_color:a", 0.0, 0.35)
	t.tween_callback(disc.queue_free)


# Crea el anillo del muro de la arena (en todos los peers), inicialmente oculto
# y sin colision. Bloquea jugadores y enemigos (capa 1 = mundo).
func _create_barrier(center: Vector3) -> void:
	_barrier = StaticBody3D.new()
	_barrier.collision_layer = 64   # capa 7: solo la cruzan los enemigos, no el jugador
	_barrier.collision_mask = 0
	get_tree().current_scene.add_child(_barrier)
	_barrier.global_position = center
	var n := 30
	var seg_depth: float = (TAU * _arena_radius / float(n)) * 1.35
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.8, 1.0, 0.28)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.35, 0.7, 1.0)
	mat.emission_energy_multiplier = 1.3
	for i in n:
		var a: float = TAU * float(i) / float(n)
		var na: float = TAU * float(i + 1) / float(n)
		var off: Vector3 = Vector3(cos(a) * _arena_radius, 2.2, sin(a) * _arena_radius)
		var noff: Vector3 = Vector3(cos(na) * _arena_radius, 2.2, sin(na) * _arena_radius)
		var col := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(0.5, 4.4, seg_depth)
		col.shape = bs
		col.disabled = true
		_barrier.add_child(col)
		col.global_position = center + off
		col.look_at(center + noff, Vector3.UP)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.3, 4.4, seg_depth)
		mi.mesh = bm
		mi.material_override = mat
		_barrier.add_child(mi)
		mi.global_position = center + off
		mi.look_at(center + noff, Vector3.UP)
	_barrier.visible = false


# Activa/desactiva el muro en todos los peers.
@rpc("authority", "call_local", "reliable")
func _set_barrier(on: bool) -> void:
	if not is_instance_valid(_barrier):
		return
	_barrier.visible = on
	for ch in _barrier.get_children():
		if ch is CollisionShape3D:
			ch.set_deferred("disabled", not on)


# Al sellar la arena, empuja fuera a los enemigos del entorno que esten dentro.
func _seal_arena() -> void:
	for e in get_tree().get_nodes_in_group("enemy"):
		if e == self or not is_instance_valid(e) or e.get("is_boss"):
			continue
		var ep: Vector3 = e.global_position
		var d: float = Vector2(ep.x, ep.z).distance_to(Vector2(_arena_center.x, _arena_center.z))
		if d < _arena_radius:
			var dir: Vector3 = ep - _arena_center
			dir.y = 0.0
			if dir.length() < 0.1:
				dir = Vector3(1, 0, 0)
			dir = dir.normalized()
			e.global_position = _arena_center + dir * (_arena_radius + 4.0) + Vector3(0, 1.0, 0)


func _exit_tree() -> void:
	if is_instance_valid(_barrier):
		_barrier.queue_free()


func _face(pos: Vector3) -> void:
	var to: Vector3 = pos - global_position
	to.y = 0.0
	if to.length() > 0.1:
		var lt: Vector3 = global_position + to
		lt.y = global_position.y
		look_at(lt, Vector3.UP)


func _move_away_from(pos: Vector3) -> void:
	var away: Vector3 = global_position - pos
	away.y = 0.0
	if away.length() < 0.1:
		return
	away = away.normalized()
	var spd: float = speed * _poison_slow()
	velocity.x = away.x * spd
	velocity.z = away.z * spd
	_face(pos)


# --- Veneno (Veneno Paralizante del asesino) ------------------------------------

func add_poison_stack() -> void:
	if not multiplayer.is_server():
		return
	_poison_stacks = mini(_poison_stacks + 1, 5)
	_poison_time = 5.0  # se refresca con cada golpe envenenado


func _poison_slow() -> float:
	return clampf(1.0 - 0.12 * _poison_stacks, 0.35, 1.0)


func _poison_weaken() -> float:
	return clampf(1.0 - 0.1 * _poison_stacks, 0.4, 1.0)


# Maldición de Debilidad (Nigromante): reduce defensa al instante y daño mientras dura.
func server_curse(duration: float, def_reduction: int) -> void:
	if not multiplayer.is_server():
		return
	if _curse_time <= 0.0 and hurtbox.stats != null:
		_curse_def_applied = mini(def_reduction, hurtbox.stats.defense)
		hurtbox.stats.defense -= _curse_def_applied
	_curse_time = maxf(_curse_time, duration)


func _curse_weaken() -> float:
	return 0.6 if _curse_time > 0.0 else 1.0


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
func server_take_damage(amount: int, attacker_id: int = 0) -> void:
	if not multiplayer.is_server() or hurtbox.stats == null or _dead:
		return
	# Inmune mientras vuelve a su zona (reset estilo MMO: anti-kiteo).
	if state == State.RETURN:
		return
	if attacker_id > 0:
		_last_attacker = attacker_id  # recordamos quien le pego para repartir recompensas
	var hp_before: int = hurtbox.stats.current_hp
	hurtbox.stats.take_damage(amount)  # actualiza la vida del servidor y su medidor
	var dealt: int = hp_before - hurtbox.stats.current_hp
	_recv_hp.rpc(hurtbox.stats.current_hp, hurtbox.stats.max_hp)
	play_hit_flash.rpc()  # parpadeo de impacto en todos los peers
	_popup_dmg.rpc(dealt, attacker_id)  # numero de daño + "punch" en todos los peers
	# Efectos del atacante: robo de vida y veneno.
	if attacker_id > 0:
		var a := _player_by_id(attacker_id)
		if a != null:
			if a.has_method("get_lifesteal") and a.get_lifesteal() > 0.0:
				a.server_heal(int(round(float(amount) * a.get_lifesteal())))
			if a.has_method("applies_poison") and a.applies_poison():
				add_poison_stack()
	if hurtbox.stats.current_hp <= 0:
		_dead = true
		var killer := _player_by_id(_last_attacker)
		if killer != null and killer.has_method("server_on_kill"):
			killer.server_on_kill()  # extiende Apocalipsis (y similares por kill)
		var owners := _server_reward_owners()
		_server_grant_exp(owners)
		_server_drop_loot(owners)
		EnemyManager.server_on_enemy_died(name.to_int())


# Aturde al enemigo (lo llaman habilidades como Pisotón Sísmico).
func server_stun(duration: float) -> void:
	if not multiplayer.is_server():
		return
	_stun_time = maxf(_stun_time, duration)


# Provoca al enemigo: lo obliga a atacar al que lo provoco (Provocación).
func server_taunt(by: Node3D, duration: float) -> void:
	if not multiplayer.is_server():
		return
	_taunt_by = by
	_taunt_time = maxf(_taunt_time, duration)
	player = by
	if state == State.PATROL or state == State.RETURN:
		state = State.CHASE


# Dueños de las recompensas: el asesino y su grupo. [] si no hubo atacante claro.
func _server_reward_owners() -> Array:
	if _last_attacker <= 0:
		return []
	return PartyManager.members_of(_last_attacker)


# Da EXP al asesino y a sus compañeros de grupo vivos y cercanos (solo servidor).
func _server_grant_exp(owners: Array) -> void:
	for id in owners:
		var p := _player_by_id(id)
		if p == null or p.get("is_dead"):
			continue
		if global_position.distance_to(p.global_position) > EXP_SHARE_RANGE:
			continue
		if p.has_method("server_gain_exp"):
			p.server_gain_exp(exp_reward)


func _player_by_id(id: int) -> Node:
	for p in get_tree().get_nodes_in_group("player"):
		if p.name.to_int() == id:
			return p
	return null


# Recupera toda la vida al volver a su zona y la sincroniza a los clientes.
func _server_reset_to_full() -> void:
	if hurtbox.stats == null:
		return
	hurtbox.stats.current_hp = hurtbox.stats.max_hp
	hurtbox.stats.hp_changed.emit(hurtbox.stats.max_hp, hurtbox.stats.max_hp)
	_recv_hp.rpc(hurtbox.stats.max_hp, hurtbox.stats.max_hp)


# Suelta el botin segun la loot_table (solo servidor). 'owners' son los unicos
# que podran recogerlo (asesino + grupo); [] = libre para todos.
func _server_drop_loot(owners: Array) -> void:
	for entry in loot_table:
		if entry == null or entry.item == null:
			continue
		if randf() <= entry.drop_chance:
			var amount := randi_range(entry.min_amount, entry.max_amount)
			LootManager.server_drop(entry.item.resource_path, amount, global_position, owners)


# --- Feedback visual (se ejecuta en todos los peers) ----------------------------

@rpc("authority", "call_local", "reliable")
func play_attack() -> void:
	_attack_lunge()


@rpc("authority", "call_local", "reliable")
func play_hit_flash() -> void:
	_hit_flash()


# Numero de daño flotante + "punch" de escala al recibir un golpe.
@rpc("authority", "call_local", "reliable")
func _popup_dmg(amount: int, attacker_id: int = 0) -> void:
	if amount > 0:
		FloatingText.spawn(get_tree().current_scene, global_position + Vector3.UP * 2.2, str(amount), Color(1.0, 0.85, 0.3))
	_hit_punch()
	# Pequeño temblor para el jugador local que asesto el golpe.
	if attacker_id == multiplayer.get_unique_id():
		for p in get_tree().get_nodes_in_group("player"):
			if p.name.to_int() == attacker_id and p.has_method("add_shake"):
				p.add_shake(0.07)
				break


func _hit_punch() -> void:
	var m := get_node_or_null("MeshInstance3D") as Node3D
	if m == null:
		return
	var t := create_tween()
	t.tween_property(m, "scale", _base_scale * Vector3(1.25, 0.8, 1.25), 0.06)
	t.tween_property(m, "scale", _base_scale, 0.12)


func _attack_lunge() -> void:
	if is_instance_valid(_avatar):
		_avatar.attack(false)
		return
	var mesh := $MeshInstance3D as Node3D
	if mesh == null:
		return
	var tween := create_tween()
	tween.tween_property(mesh, "position:z", -0.4, 0.08)
	tween.tween_property(mesh, "position:z", 0.0, 0.12)


func _hit_flash() -> void:
	if is_instance_valid(_avatar):
		_avatar.flash()
		return
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
