extends Node
## ZoneDB (autoload "Zones")
## Definicion en datos del mundo abierto: ciudades seguras (sin enemigos, con
## NPCs/tiendas en el futuro) y zonas de combate con su tier de dificultad,
## nivel, mezcla de enemigos y jefe. Todo lo demas (mapa, spawner) lee de aqui.
##
## Campos de cada zona:
##   id, name, type ("city"|"combat"), center (Vector2 x,z), radius,
##   tier (0 = ciudad), level (nivel de sus enemigos), enemies (Array de tipos),
##   boss (id del jefe de zona), color (tinte del suelo), start (ciudad inicial?).

const ZONES := [
	# --- 5 grandes ciudades seguras (puntos de inicio), en anillo ---
	{"id": "valoria", "name": "Valoria", "type": "city", "center": Vector2(0, 200), "radius": 30.0, "tier": 0, "level": 1, "enemies": [], "boss": "", "color": Color(0.52, 0.5, 0.5), "start": true},
	{"id": "solmar", "name": "Solmar", "type": "city", "center": Vector2(-190, 62), "radius": 30.0, "tier": 0, "level": 1, "enemies": [], "boss": "", "color": Color(0.52, 0.5, 0.5), "start": true},
	{"id": "brakka", "name": "Brakka", "type": "city", "center": Vector2(-118, -162), "radius": 30.0, "tier": 0, "level": 1, "enemies": [], "boss": "", "color": Color(0.52, 0.5, 0.5), "start": true},
	{"id": "thornvale", "name": "Thornvale", "type": "city", "center": Vector2(118, -162), "radius": 30.0, "tier": 0, "level": 1, "enemies": [], "boss": "", "color": Color(0.52, 0.5, 0.5), "start": true},
	{"id": "ravenhold", "name": "Ravenhold", "type": "city", "center": Vector2(190, 62), "radius": 30.0, "tier": 0, "level": 1, "enemies": [], "boss": "", "color": Color(0.52, 0.5, 0.5), "start": true},

	# --- Tier 1: una zona facil PEGADA a cada ciudad (mismo radio exterior) ---
	{"id": "greenwood", "name": "Vega del Lago", "type": "combat", "biome": "water", "center": Vector2(0, 270), "radius": 40.0, "tier": 1, "level": 4, "enemies": ["crab", "naiad", "eel"], "boss": "boss_greenwood", "color": Color(0.2, 0.45, 0.5)},
	{"id": "meadows", "name": "Praderas del Sol", "type": "combat", "center": Vector2(-257, 83), "radius": 40.0, "tier": 1, "level": 3, "enemies": ["goblin"], "boss": "boss_meadows", "color": Color(0.3, 0.55, 0.3)},
	{"id": "quietwood", "name": "Selva Susurrante", "type": "combat", "biome": "jungle", "center": Vector2(-159, -218), "radius": 40.0, "tier": 1, "level": 4, "enemies": ["panther", "spore_shaman"], "boss": "boss_quietwood", "color": Color(0.18, 0.42, 0.2)},
	{"id": "dawnclear", "name": "Arenas del Alba", "type": "combat", "biome": "desert", "center": Vector2(159, -218), "radius": 40.0, "tier": 1, "level": 4, "enemies": ["scorpion", "sand_wretch"], "boss": "boss_dawnclear", "color": Color(0.78, 0.66, 0.4)},
	{"id": "greenpath", "name": "Sendero Verde", "type": "combat", "center": Vector2(257, 83), "radius": 40.0, "tier": 1, "level": 5, "enemies": ["goblin"], "boss": "boss_greenpath", "color": Color(0.3, 0.55, 0.3)},

	# --- Zonas interiores: mas duras cuanto mas cerca del centro del mundo ---
	{"id": "mossy", "name": "Marisma Musgosa", "type": "combat", "biome": "swamp", "center": Vector2(67, 117), "radius": 42.0, "tier": 2, "level": 13, "enemies": ["bog_crawler", "leech", "witch"], "boss": "boss_mossy", "color": Color(0.26, 0.33, 0.22)},
	{"id": "howling", "name": "Bosque Aullante", "type": "combat", "biome": "forest", "center": Vector2(-95, 116), "radius": 42.0, "tier": 2, "level": 15, "enemies": ["wolf", "goblin"], "boss": "boss_howling", "color": Color(0.24, 0.45, 0.26)},
	{"id": "frostfang", "name": "Valle Colmillo", "type": "combat", "biome": "ice", "center": Vector2(151, -63), "radius": 42.0, "tier": 2, "level": 13, "enemies": ["frostwolf", "frost_caster"], "boss": "boss_frostfang", "color": Color(0.62, 0.74, 0.82)},
	{"id": "stoneback", "name": "Dunas Pétreas", "type": "combat", "biome": "desert", "center": Vector2(10, -109), "radius": 44.0, "tier": 3, "level": 26, "enemies": ["scorpion", "sand_wretch", "dust_caster"], "boss": "boss_stoneback", "color": Color(0.75, 0.62, 0.38)},
	{"id": "ashen", "name": "Bosque Ceniciento", "type": "combat", "biome": "fire", "center": Vector2(89, 21), "radius": 44.0, "tier": 3, "level": 27, "enemies": ["imp", "magma_brute", "flame_caster"], "boss": "boss_ashen", "color": Color(0.34, 0.24, 0.2)},
	{"id": "gloomfen", "name": "Marisma Lúgubre", "type": "combat", "biome": "swamp", "center": Vector2(-77, -40), "radius": 46.0, "tier": 4, "level": 50, "enemies": ["bog_crawler", "witch", "leech"], "boss": "boss_gloomfen", "color": Color(0.24, 0.3, 0.2)},
	{"id": "dread", "name": "Caldera del Pavor", "type": "combat", "biome": "fire", "center": Vector2(-24, 49), "radius": 48.0, "tier": 5, "level": 88, "enemies": ["magma_brute", "flame_caster", "imp"], "boss": "boss_dread", "color": Color(0.3, 0.16, 0.12)},
]


# --- ENDGAME: 9 world bosses, en grandes arenas en los confines del mundo. ---
# Aparecen al cumplir condiciones: matar jefes de zona (zone_kills) y, los mas
# duros, haber matado world bosses previos (wb_kills).
const WORLD_BOSSES := [
	{"id": "leviathan", "name": "Leviatán de las Mareas", "center": Vector2(301, 109), "level": 100, "cond_type": "zone_kills", "cond_value": 3},
	{"id": "magmacolossus", "name": "Coloso de Magma", "center": Vector2(160, 277), "level": 110, "cond_type": "zone_kills", "cond_value": 6},
	{"id": "jungletyrant", "name": "Tirano de la Selva", "center": Vector2(-56, 315), "level": 120, "cond_type": "zone_kills", "cond_value": 10},
	{"id": "eternalpharaoh", "name": "Faraón Eterno", "center": Vector2(-245, 206), "level": 130, "cond_type": "zone_kills", "cond_value": 12},
	{"id": "frostmonarch", "name": "Monarca de Hielo", "center": Vector2(-320, 0), "level": 140, "cond_type": "wb_kills", "cond_value": 1},
	{"id": "swamphorror", "name": "Horror del Pantano", "center": Vector2(-245, -206), "level": 150, "cond_type": "wb_kills", "cond_value": 3},
	{"id": "souldevourer", "name": "Devorador de Almas", "center": Vector2(-56, -315), "level": 165, "cond_type": "wb_kills", "cond_value": 5},
	{"id": "voidherald", "name": "Heraldo del Vacío", "center": Vector2(160, -277), "level": 180, "cond_type": "wb_kills", "cond_value": 7},
	{"id": "apocalypse", "name": "El Apocalipsis", "center": Vector2(301, -109), "level": 200, "cond_type": "wb_kills", "cond_value": 8},
]


func world_bosses() -> Array:
	return WORLD_BOSSES


func get_world_boss(id: String) -> Dictionary:
	for w in WORLD_BOSSES:
		if w["id"] == id:
			return w
	return {}


func wb_center3(w: Dictionary) -> Vector3:
	var c: Vector2 = w["center"]
	return Vector3(c.x, 0.0, c.y)


func all_zones() -> Array:
	return ZONES


func combat_zones() -> Array:
	var out: Array = []
	for z in ZONES:
		if z["type"] == "combat":
			out.append(z)
	return out


func cities() -> Array:
	var out: Array = []
	for z in ZONES:
		if z["type"] == "city":
			out.append(z)
	return out


# Ciudades elegibles como punto de inicio.
func start_cities() -> Array:
	var out: Array = []
	for z in ZONES:
		if z["type"] == "city" and z.get("start", false):
			out.append(z)
	return out


func get_zone(id: String) -> Dictionary:
	for z in ZONES:
		if z["id"] == id:
			return z
	return {}


# Centro de una zona como Vector3 (y=0).
func center3(z: Dictionary) -> Vector3:
	var c: Vector2 = z["center"]
	return Vector3(c.x, 0.0, c.y)


# Zona que contiene un punto del mundo (o {} si esta en campo abierto).
func zone_at(pos: Vector3) -> Dictionary:
	var p := Vector2(pos.x, pos.z)
	for z in ZONES:
		if p.distance_to(z["center"]) <= float(z["radius"]):
			return z
	return {}
