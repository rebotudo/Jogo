extends Node3D
## MapDecorator
## Decora el mundo abierto LEYENDO ZoneDB (autoload "Zones"), de forma procedural
## y determinista. Cada ciudad es un hub seguro con edificios y fuente; cada zona
## de combate tiene su tinte de suelo, su arena de jefe y su bosque. Una red de
## caminos conecta ciudades y zonas. Arboles/rocas/edificios tienen colision.

const SEED: int = 99173
const MAP_HALF: float = 350.0
const PATH_HALF_WIDTH: float = 2.6
const PATH_CLEAR: float = 4.0
const ARENA_R: float = 12.0
const WILD_TREES: int = 140

var _path_pts: Array = []

var _ground := _mat(Color(0.3, 0.45, 0.28))      # campo abierto entre zonas
var _trunk := _mat(Color(0.36, 0.25, 0.15))
var _leaf := _mat(Color(0.16, 0.42, 0.2))
var _leaf2 := _mat(Color(0.22, 0.5, 0.26))
var _path := _mat(Color(0.55, 0.46, 0.32))
var _stone := _mat(Color(0.4, 0.4, 0.45))
var _rock := _mat(Color(0.45, 0.45, 0.48))
var _wood := _mat(Color(0.45, 0.32, 0.2))
var _roof := _mat(Color(0.5, 0.22, 0.2))
var _water := _mat(Color(0.2, 0.45, 0.7, 0.72))
var _foam := _mat(Color(0.85, 0.92, 0.95, 0.8))
var _reed := _mat(Color(0.3, 0.5, 0.28))
var _wetrock := _mat(Color(0.32, 0.36, 0.42))
var _willow := _mat(Color(0.3, 0.5, 0.42))
var _lava := _glow_mat(Color(1.0, 0.35, 0.08), 2.2)
var _charred := _mat(Color(0.15, 0.13, 0.12))
var _jungle_leaf := _mat(Color(0.16, 0.5, 0.18))
var _vine := _mat(Color(0.2, 0.4, 0.18))
var _sand := _mat(Color(0.82, 0.71, 0.45))
var _cactus := _mat(Color(0.3, 0.5, 0.28))
var _sandstone := _mat(Color(0.72, 0.58, 0.36))
var _ice := _mat(Color(0.7, 0.88, 0.98, 0.85))
var _crystal := _glow_mat(Color(0.55, 0.85, 1.0), 1.4)
var _snow := _mat(Color(0.92, 0.95, 0.98))
var _mud := _mat(Color(0.28, 0.3, 0.2))
var _bog := _mat(Color(0.25, 0.35, 0.22, 0.78))


static func _glow_mat(c: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	return m


static func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


func _ready() -> void:
	_tint_floor()
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	_build_roads(rng)
	for z in Zones.all_zones():
		_ground_disc(Zones.center3(z), float(z["radius"]), _mat(z["color"]))
		if String(z["type"]) == "city":
			_decorate_city(z, rng)
		else:
			_decorate_combat(z, rng)
	_build_world_boss_arenas(rng)
	_scatter_wilderness(rng)


# Grandes arenas oscuras de los world bosses, en los confines del mundo.
func _build_world_boss_arenas(rng: RandomNumberGenerator) -> void:
	var dark := _mat(Color(0.22, 0.18, 0.26))
	var pmat := _glow_mat(Color(0.45, 0.12, 0.45), 0.7)
	for w in Zones.world_bosses():
		var c: Vector3 = Zones.wb_center3(w)
		_ground_disc(c, 27.0, _mat(Color(0.16, 0.12, 0.2)))
		# Disco de piedra de la arena.
		var disc := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 22.0
		cm.bottom_radius = 22.0
		cm.height = 0.18
		disc.mesh = cm
		disc.material_override = dark
		add_child(disc)
		disc.global_position = c + Vector3(0, 0.08, 0)
		# Anillo de pilares altos con brillo.
		for i in 16:
			var a: float = TAU * float(i) / 16.0
			_make_pillar(c + Vector3(cos(a), 0, sin(a)) * 21.0, 8.0, 0.8, pmat)
		# Obelisco/altar al fondo de la arena.
		_make_building(c + Vector3(0, 0, 19.0), Vector3(3.0, 12.0, 3.0), dark)
		_glow_orb(c + Vector3(0, 13.5, 19.0), 1.0, Color(0.7, 0.1, 0.6), 2.0)
		_make_sign(c + Vector3(0, 0, -24.0), "☠ " + String(w["name"]))


func _tint_floor() -> void:
	var fm := get_parent().get_node_or_null("NavigationRegion3D/Floor/MeshInstance3D") as MeshInstance3D
	if fm != null:
		fm.material_override = _ground


func _ground_disc(c: Vector3, r: float, mat: StandardMaterial3D) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = 0.08
	mi.mesh = cm
	mi.material_override = mat
	add_child(mi)
	mi.global_position = c + Vector3(0, 0.03, 0)


# --- Caminos --------------------------------------------------------------------

func _build_roads(rng: RandomNumberGenerator) -> void:
	var cities: Array = Zones.cities()
	# Anillo entre ciudades.
	for i in cities.size():
		var a: Vector3 = Zones.center3(cities[i])
		var b: Vector3 = Zones.center3(cities[(i + 1) % cities.size()])
		_draw_path(a, b, rng)
	# Cada zona de combate a su ciudad mas cercana.
	for z in Zones.combat_zones():
		var zc: Vector3 = Zones.center3(z)
		var best: Vector3 = zc
		var best_d: float = INF
		for c in cities:
			var cc: Vector3 = Zones.center3(c)
			var d: float = zc.distance_to(cc)
			if d < best_d:
				best_d = d
				best = cc
		_draw_path(zc, best, rng)


func _draw_path(a: Vector3, b: Vector3, rng: RandomNumberGenerator) -> void:
	var dist: float = a.distance_to(b)
	var steps: int = maxi(int(dist / 8.0), 2)
	var perp: Vector3 = (b - a).normalized().cross(Vector3.UP)
	var freq: float = rng.randf_range(1.0, 2.4)
	var phase: float = rng.randf_range(0.0, TAU)
	var amp: float = rng.randf_range(6.0, 16.0)
	var prev: Vector3 = a
	for i in range(1, steps + 1):
		var t: float = float(i) / float(steps)
		var taper: float = 1.0 - absf(t - 0.5) * 2.0
		var off: float = sin(t * PI * freq + phase) * amp * taper
		var pt: Vector3 = a.lerp(b, t) + perp * off
		pt.y = 0.0
		_path_segment(prev, pt)
		prev = pt


func _path_segment(p0: Vector3, p1: Vector3) -> void:
	var seg_len: float = p0.distance_to(p1)
	if seg_len < 0.01:
		return
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(PATH_HALF_WIDTH * 2.0, 0.06, seg_len + 0.8)
	mi.mesh = bm
	mi.material_override = _path
	add_child(mi)
	mi.global_position = ((p0 + p1) * 0.5) + Vector3(0, 0.05, 0)
	mi.look_at(p1 + Vector3(0, 0.05, 0), Vector3.UP)
	_path_pts.append((p0 + p1) * 0.5)


func _near_road(pos: Vector3) -> bool:
	for pp in _path_pts:
		if pos.distance_to(pp) < PATH_CLEAR:
			return true
	return false


# --- Ciudades (hubs seguros) ----------------------------------------------------

func _decorate_city(z: Dictionary, rng: RandomNumberGenerator) -> void:
	var c: Vector3 = Zones.center3(z)
	# Fuente central.
	_make_building(c, Vector3(3.0, 0.5, 3.0), _stone)
	var water := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.1
	cm.bottom_radius = 1.1
	cm.height = 0.2
	water.mesh = cm
	water.material_override = _water
	add_child(water)
	water.global_position = c + Vector3(0, 0.55, 0)
	# Cartel con el nombre.
	_make_sign(c + Vector3(0, 0, -float(z["radius"]) + 4.0), String(z["name"]))
	# Edificios en anillo.
	var n := 7
	for i in n:
		var ang: float = TAU * float(i) / float(n) + rng.randf_range(-0.2, 0.2)
		var rad: float = float(z["radius"]) * rng.randf_range(0.45, 0.72)
		var pos: Vector3 = c + Vector3(cos(ang), 0, sin(ang)) * rad
		var w: float = rng.randf_range(4.0, 7.0)
		var h: float = rng.randf_range(3.0, 6.0)
		var d: float = rng.randf_range(4.0, 7.0)
		var body := _make_building(pos, Vector3(w, h, d), _wood)
		body.rotation.y = ang + PI * 0.5
		# Tejado.
		var roof := MeshInstance3D.new()
		var pm := CylinderMesh.new()
		pm.top_radius = 0.0
		pm.bottom_radius = maxf(w, d) * 0.8
		pm.height = 2.2
		roof.mesh = pm
		roof.material_override = _roof
		body.add_child(roof)
		roof.position = Vector3(0, h + 1.1, 0)


func _make_sign(pos: Vector3, txt: String) -> void:
	var post := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.15
	cm.bottom_radius = 0.15
	cm.height = 3.0
	post.mesh = cm
	post.material_override = _wood
	add_child(post)
	post.global_position = pos + Vector3(0, 1.5, 0)
	var label := Label3D.new()
	label.text = txt
	label.font_size = 64
	label.outline_size = 12
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color(1, 0.95, 0.7)
	add_child(label)
	label.global_position = pos + Vector3(0, 3.4, 0)


func _make_building(pos: Vector3, size: Vector3, mat: StandardMaterial3D) -> StaticBody3D:
	var body := StaticBody3D.new()
	add_child(body)
	body.global_position = pos
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position.y = size.y * 0.5
	body.add_child(mi)
	var col := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	col.shape = bs
	col.position.y = size.y * 0.5
	body.add_child(col)
	return body


# --- Zonas de combate -----------------------------------------------------------

func _decorate_combat(z: Dictionary, rng: RandomNumberGenerator) -> void:
	var c: Vector3 = Zones.center3(z)
	var r: float = float(z["radius"])
	# Cartel con el nombre y nivel.
	_make_sign(c + Vector3(0, 0, -r + 4.0), "%s (Nv.%d)" % [String(z["name"]), int(z["level"])])
	# Arena del jefe en el centro de la zona.
	_build_arena(c, int(z["tier"]))
	# Decorado segun el bioma.
	match String(z.get("biome", "forest")):
		"water":
			_build_water(z, rng)
		"fire":
			_build_fire(z, rng)
		"jungle":
			_build_jungle(z, rng)
		"desert":
			_build_desert(z, rng)
		"ice":
			_build_ice(z, rng)
		"swamp":
			_build_swamp(z, rng)
		_:
			_build_forest(z, rng)


func _build_forest(z: Dictionary, rng: RandomNumberGenerator) -> void:
	var c: Vector3 = Zones.center3(z)
	var r: float = float(z["radius"])
	var density: float = 0.9 + float(z["tier"]) * 0.12
	var count: int = int(r * 1.1 * density)
	var placed := 0
	var tries := 0
	while placed < count and tries < count * 8:
		tries += 1
		var ang: float = rng.randf_range(0.0, TAU)
		var dist: float = rng.randf_range(ARENA_R + 5.0, r - 2.0)
		var pos: Vector3 = c + Vector3(cos(ang), 0, sin(ang)) * dist
		if _near_road(pos):
			continue
		if rng.randf() < 0.12:
			_make_rock(pos, rng)
		else:
			_make_tree(pos, rng)
		placed += 1


# --- Bioma AGUA: lago-isla, rios, cascada, juncos, santuario, sauces ------------

func _build_water(z: Dictionary, rng: RandomNumberGenerator) -> void:
	var c: Vector3 = Zones.center3(z)
	var r: float = float(z["radius"])
	# Lago central (la arena de piedra queda como isla encima).
	_water_disc(c, r * 0.62)
	# Rios serpenteantes desde el lago hacia el borde.
	var rivers := 4
	for i in rivers:
		var ang: float = TAU * float(i) / float(rivers) + rng.randf_range(-0.3, 0.3)
		var startp: Vector3 = c + Vector3(cos(ang), 0, sin(ang)) * (r * 0.55)
		var endp: Vector3 = c + Vector3(cos(ang), 0, sin(ang)) * (r - 2.0)
		_water_river(startp, endp, rng)
	# Estanques sueltos.
	for i in 3:
		var ang2: float = rng.randf_range(0.0, TAU)
		var d2: float = rng.randf_range(r * 0.7, r - 6.0)
		_water_disc(c + Vector3(cos(ang2), 0, sin(ang2)) * d2, rng.randf_range(5.0, 9.0))
	# Cascada con risco.
	var wang: float = rng.randf_range(0.0, TAU)
	_build_waterfall(c + Vector3(cos(wang), 0, sin(wang)) * (r * 0.52))
	# Juncos alrededor del lago.
	for i in 44:
		var a: float = rng.randf_range(0.0, TAU)
		var rr: float = r * 0.62 + rng.randf_range(-2.0, 4.0)
		_make_reed(c + Vector3(cos(a), 0, sin(a)) * rr, rng)
	# Santuario acuatico (estructura unica del bioma).
	var sang: float = rng.randf_range(0.0, TAU)
	_build_water_shrine(c + Vector3(cos(sang), 0, sin(sang)) * (r * 0.8))
	# Sauces y rocas mojadas fuera del lago.
	var placed := 0
	var tries := 0
	var count := int(r * 0.7)
	while placed < count and tries < count * 8:
		tries += 1
		var ang3: float = rng.randf_range(0.0, TAU)
		var dist: float = rng.randf_range(r * 0.66, r - 2.0)
		var pos: Vector3 = c + Vector3(cos(ang3), 0, sin(ang3)) * dist
		if _near_road(pos):
			continue
		if rng.randf() < 0.25:
			_make_rock(pos, rng)
		else:
			_make_willow(pos, rng)
		placed += 1


func _water_disc(c: Vector3, radius: float) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = 0.08
	mi.mesh = cm
	mi.material_override = _water
	add_child(mi)
	mi.global_position = c + Vector3(0, 0.03, 0)


func _water_river(a: Vector3, b: Vector3, rng: RandomNumberGenerator) -> void:
	var dist: float = a.distance_to(b)
	var steps: int = maxi(int(dist / 6.0), 2)
	var perp: Vector3 = (b - a).normalized().cross(Vector3.UP)
	var freq: float = rng.randf_range(1.0, 2.5)
	var phase: float = rng.randf_range(0.0, TAU)
	var amp: float = rng.randf_range(3.0, 8.0)
	var prev: Vector3 = a
	for i in range(1, steps + 1):
		var t: float = float(i) / float(steps)
		var taper: float = 1.0 - absf(t - 0.5) * 2.0
		var off: float = sin(t * PI * freq + phase) * amp * taper
		var pt: Vector3 = a.lerp(b, t) + perp * off
		pt.y = 0.0
		_water_strip(prev, pt)
		prev = pt


func _water_strip(p0: Vector3, p1: Vector3) -> void:
	var seg: float = p0.distance_to(p1)
	if seg < 0.01:
		return
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(5.0, 0.06, seg + 0.8)
	mi.mesh = bm
	mi.material_override = _water
	add_child(mi)
	mi.global_position = ((p0 + p1) * 0.5) + Vector3(0, 0.035, 0)
	mi.look_at(p1 + Vector3(0, 0.035, 0), Vector3.UP)


func _build_waterfall(pos: Vector3) -> void:
	# Risco de roca (con colision) y una cara de agua cayendo, con espuma abajo.
	var cliff := _make_building(pos, Vector3(9.0, 9.0, 4.0), _wetrock)
	var face := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(5.5, 9.4, 0.3)
	face.mesh = bm
	face.material_override = _water
	cliff.add_child(face)
	face.position = Vector3(0, 4.6, 2.1)
	var foam := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 3.6
	cm.bottom_radius = 3.6
	cm.height = 0.1
	foam.mesh = cm
	foam.material_override = _foam
	add_child(foam)
	foam.global_position = pos + Vector3(0, 0.06, 3.4)


func _make_reed(pos: Vector3, rng: RandomNumberGenerator) -> void:
	var n := rng.randi_range(3, 6)
	for i in n:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		var h := rng.randf_range(1.2, 2.3)
		bm.size = Vector3(0.12, h, 0.12)
		mi.mesh = bm
		mi.material_override = _reed
		add_child(mi)
		mi.global_position = pos + Vector3(rng.randf_range(-0.9, 0.9), h * 0.5, rng.randf_range(-0.9, 0.9))
		mi.rotation.z = rng.randf_range(-0.2, 0.2)


func _build_water_shrine(pos: Vector3) -> void:
	var plat := _make_building(pos, Vector3(8.0, 1.0, 8.0), _stone)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_make_pillar(pos + Vector3(sx * 3.0, 1.0, sz * 3.0), 4.0, 0.4, _stone)
	var pool := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 2.0
	cm.bottom_radius = 2.0
	cm.height = 0.2
	pool.mesh = cm
	pool.material_override = _water
	plat.add_child(pool)
	pool.position = Vector3(0, 1.1, 0)
	var orb := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.8
	sm.height = 1.6
	orb.mesh = sm
	var omat := _mat(Color(0.4, 0.7, 1.0))
	omat.emission_enabled = true
	omat.emission = Color(0.3, 0.6, 1.0)
	omat.emission_energy_multiplier = 2.5
	orb.material_override = omat
	plat.add_child(orb)
	orb.position = Vector3(0, 2.6, 0)


func _make_willow(pos: Vector3, rng: RandomNumberGenerator) -> void:
	var s := rng.randf_range(0.9, 1.4)
	var body := StaticBody3D.new()
	add_child(body)
	body.global_position = pos
	body.rotation.y = rng.randf_range(0.0, TAU)
	var trunk := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 0.2
	tm.bottom_radius = 0.32
	tm.height = 3.0 * s
	trunk.mesh = tm
	trunk.material_override = _trunk
	trunk.position.y = 1.5 * s
	body.add_child(trunk)
	# Copa colgante: esferas anchas y bajas.
	for j in 3:
		var fol := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 1.4 * s
		sm.height = 1.6 * s
		fol.mesh = sm
		fol.material_override = _willow
		var ang := TAU * float(j) / 3.0
		fol.position = Vector3(cos(ang) * 1.1 * s, 3.0 * s, sin(ang) * 1.1 * s)
		body.add_child(fol)
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4 * s
	cap.height = 3.0 * s
	col.shape = cap
	col.position.y = 1.5 * s
	body.add_child(col)


func _build_arena(c: Vector3, tier: int) -> void:
	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = ARENA_R
	cm.bottom_radius = ARENA_R
	cm.height = 0.14
	disc.mesh = cm
	disc.material_override = _stone
	add_child(disc)
	disc.global_position = c + Vector3(0, 0.07, 0)
	var pmat := _mat(Color(0.34, 0.34, 0.4))
	pmat.emission_enabled = true
	# Brillo mas rojo/intenso en tiers altos.
	pmat.emission = Color(0.4 + tier * 0.1, 0.12, 0.12)
	pmat.emission_energy_multiplier = 0.2 + tier * 0.08
	var count := 12
	for i in count:
		var ang: float = TAU * float(i) / float(count)
		_make_pillar(c + Vector3(cos(ang), 0, sin(ang)) * (ARENA_R - 0.5), 5.0, 0.6, pmat)


# --- Campo abierto (bosque entre zonas) -----------------------------------------

func _scatter_wilderness(rng: RandomNumberGenerator) -> void:
	var placed := 0
	var tries := 0
	while placed < WILD_TREES and tries < WILD_TREES * 12:
		tries += 1
		var pos := Vector3(rng.randf_range(-MAP_HALF, MAP_HALF), 0, rng.randf_range(-MAP_HALF, MAP_HALF))
		if not Zones.zone_at(pos).is_empty():
			continue  # dentro de una zona ya decorada
		if _near_world_boss(pos):
			continue  # dentro de una arena de world boss
		if _near_road(pos):
			continue
		if rng.randf() < 0.15:
			_make_rock(pos, rng)
		else:
			_make_tree(pos, rng)
		placed += 1


# --- Piezas ---------------------------------------------------------------------

func _make_pillar(pos: Vector3, height: float, radius: float, mat: StandardMaterial3D) -> void:
	var body := StaticBody3D.new()
	add_child(body)
	body.global_position = pos
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius * 0.8
	cm.bottom_radius = radius
	cm.height = height
	mi.mesh = cm
	mi.material_override = mat
	mi.position.y = height * 0.5
	body.add_child(mi)
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = radius
	cap.height = height
	col.shape = cap
	col.position.y = height * 0.5
	body.add_child(col)


func _make_tree(pos: Vector3, rng: RandomNumberGenerator) -> void:
	var s: float = rng.randf_range(0.8, 1.5)
	var body := StaticBody3D.new()
	add_child(body)
	body.global_position = pos
	body.rotation.y = rng.randf_range(0.0, TAU)
	var trunk := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 0.22
	tm.bottom_radius = 0.34
	tm.height = 2.6 * s
	trunk.mesh = tm
	trunk.material_override = _trunk
	trunk.position.y = 1.3 * s
	body.add_child(trunk)
	var f1 := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.7 * s
	sm.height = 3.2 * s
	f1.mesh = sm
	f1.material_override = _leaf
	f1.position.y = 3.6 * s
	body.add_child(f1)
	var f2 := MeshInstance3D.new()
	var sm2 := SphereMesh.new()
	sm2.radius = 1.2 * s
	sm2.height = 2.2 * s
	f2.mesh = sm2
	f2.material_override = _leaf2
	f2.position = Vector3(0.4 * s, 4.6 * s, 0.2 * s)
	body.add_child(f2)
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.45 * s
	cap.height = 3.0 * s
	col.shape = cap
	col.position.y = 1.5 * s
	body.add_child(col)


func _make_rock(pos: Vector3, rng: RandomNumberGenerator) -> void:
	var s: float = rng.randf_range(0.6, 1.8)
	var body := StaticBody3D.new()
	add_child(body)
	body.global_position = pos
	body.rotation.y = rng.randf_range(0.0, TAU)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.4 * s, 0.9 * s, 1.2 * s)
	mi.mesh = bm
	mi.material_override = _rock
	mi.position.y = 0.45 * s
	body.add_child(mi)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.4 * s, 0.9 * s, 1.2 * s)
	col.shape = box
	col.position.y = 0.45 * s
	body.add_child(col)


# --- Piezas genericas reutilizables --------------------------------------------

func _disc(c: Vector3, radius: float, mat: StandardMaterial3D) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = 0.08
	mi.mesh = cm
	mi.material_override = mat
	add_child(mi)
	mi.global_position = c + Vector3(0, 0.03, 0)


func _make_cone(pos: Vector3, height: float, radius: float, mat: StandardMaterial3D, collide: bool) -> void:
	var node: Node3D
	if collide:
		node = StaticBody3D.new()
	else:
		node = Node3D.new()
	add_child(node)
	node.global_position = pos
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = radius
	cm.height = height
	mi.mesh = cm
	mi.material_override = mat
	mi.position.y = height * 0.5
	node.add_child(mi)
	if collide:
		var col := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = radius * 0.7
		cap.height = height
		col.shape = cap
		col.position.y = height * 0.5
		node.add_child(col)


func _glow_orb(pos: Vector3, radius: float, color: Color, energy: float) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	mi.mesh = sm
	mi.material_override = _glow_mat(color, energy)
	add_child(mi)
	mi.global_position = pos


func _make_mound(pos: Vector3, rng: RandomNumberGenerator, mat: StandardMaterial3D) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	var rr := rng.randf_range(3.0, 7.0)
	sm.radius = rr
	sm.height = rr * 0.5
	mi.mesh = sm
	mi.material_override = mat
	add_child(mi)
	mi.global_position = pos + Vector3(0, -rr * 0.18, 0)


func _make_dead_tree(pos: Vector3, rng: RandomNumberGenerator, mat: StandardMaterial3D) -> void:
	var s := rng.randf_range(0.9, 1.5)
	var body := StaticBody3D.new()
	add_child(body)
	body.global_position = pos
	body.rotation.y = rng.randf_range(0.0, TAU)
	var trunk := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 0.1
	tm.bottom_radius = 0.32
	tm.height = 3.4 * s
	trunk.mesh = tm
	trunk.material_override = mat
	trunk.position.y = 1.7 * s
	trunk.rotation.z = rng.randf_range(-0.12, 0.12)
	body.add_child(trunk)
	for i in 2:
		var br := MeshInstance3D.new()
		var bm := CylinderMesh.new()
		bm.top_radius = 0.05
		bm.bottom_radius = 0.12
		bm.height = 1.2 * s
		br.mesh = bm
		br.material_override = mat
		var side: float = -1.0 if i == 0 else 1.0
		br.position = Vector3(side * 0.3, rng.randf_range(2.0, 3.0) * s, 0)
		br.rotation.z = side * 0.9
		body.add_child(br)
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3 * s
	cap.height = 3.4 * s
	col.shape = cap
	col.position.y = 1.7 * s
	body.add_child(col)


func _make_cactus(pos: Vector3, rng: RandomNumberGenerator) -> void:
	var s := rng.randf_range(0.9, 1.5)
	var body := StaticBody3D.new()
	add_child(body)
	body.global_position = pos
	body.rotation.y = rng.randf_range(0.0, TAU)
	var trunk := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.4
	cm.bottom_radius = 0.45
	cm.height = 3.0 * s
	trunk.mesh = cm
	trunk.material_override = _cactus
	trunk.position.y = 1.5 * s
	body.add_child(trunk)
	for i in rng.randi_range(0, 2):
		var arm := MeshInstance3D.new()
		var am := CylinderMesh.new()
		am.top_radius = 0.25
		am.bottom_radius = 0.3
		am.height = 1.3 * s
		arm.mesh = am
		arm.material_override = _cactus
		var side: float = -1.0 if i == 0 else 1.0
		arm.position = Vector3(side * 0.5, rng.randf_range(1.4, 2.2) * s, 0)
		arm.rotation.z = side * 0.9
		body.add_child(arm)
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.45 * s
	cap.height = 3.0 * s
	col.shape = cap
	col.position.y = 1.5 * s
	body.add_child(col)


func _make_fern(pos: Vector3, rng: RandomNumberGenerator) -> void:
	var n := rng.randi_range(2, 4)
	for i in n:
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		var rr := rng.randf_range(0.5, 1.0)
		sm.radius = rr
		sm.height = rr * 1.2
		mi.mesh = sm
		mi.material_override = _jungle_leaf
		add_child(mi)
		mi.global_position = pos + Vector3(rng.randf_range(-0.8, 0.8), rr * 0.6, rng.randf_range(-0.8, 0.8))


func _make_vine(pos: Vector3, rng: RandomNumberGenerator) -> void:
	var h := rng.randf_range(2.5, 4.5)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.18, h, 0.18)
	mi.mesh = bm
	mi.material_override = _vine
	add_child(mi)
	mi.global_position = pos + Vector3(0, h * 0.5, 0)
	mi.rotation.z = rng.randf_range(-0.1, 0.1)


func _make_mushroom(pos: Vector3, rng: RandomNumberGenerator) -> void:
	var s := rng.randf_range(0.5, 1.3)
	var stem := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.12 * s
	cm.bottom_radius = 0.16 * s
	cm.height = 0.8 * s
	stem.mesh = cm
	stem.material_override = _mat(Color(0.85, 0.85, 0.78))
	add_child(stem)
	stem.global_position = pos + Vector3(0, 0.4 * s, 0)
	var cap := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.4 * s
	sm.height = 0.4 * s
	cap.mesh = sm
	var cols := [Color(0.7, 0.2, 0.2), Color(0.5, 0.3, 0.7), Color(0.3, 0.6, 0.4)]
	cap.material_override = _glow_mat(cols[rng.randi() % cols.size()], 0.4)
	add_child(cap)
	cap.global_position = pos + Vector3(0, 0.8 * s, 0)


# --- Bioma FUEGO ----------------------------------------------------------------

func _build_fire(z: Dictionary, rng: RandomNumberGenerator) -> void:
	var c: Vector3 = Zones.center3(z)
	var r: float = float(z["radius"])
	for i in 5:
		var a: float = rng.randf_range(0.0, TAU)
		var d: float = rng.randf_range(ARENA_R + 6.0, r - 6.0)
		_disc(c + Vector3(cos(a), 0, sin(a)) * d, rng.randf_range(4.0, 8.0), _lava)
	var sa: float = rng.randf_range(0.0, TAU)
	_build_fire_altar(c + Vector3(cos(sa), 0, sin(sa)) * (r * 0.75))
	var placed := 0
	var tries := 0
	var count := int(r * 1.0)
	while placed < count and tries < count * 8:
		tries += 1
		var ang: float = rng.randf_range(0.0, TAU)
		var dist: float = rng.randf_range(ARENA_R + 5.0, r - 2.0)
		var pos: Vector3 = c + Vector3(cos(ang), 0, sin(ang)) * dist
		if _near_road(pos):
			continue
		var roll: float = rng.randf()
		if roll < 0.3:
			_make_cone(pos, rng.randf_range(2.0, 5.0), rng.randf_range(0.6, 1.2), _charred, true)
		elif roll < 0.45:
			_make_rock(pos, rng)
		else:
			_make_dead_tree(pos, rng, _charred)
		if rng.randf() < 0.25:
			_glow_orb(pos + Vector3(rng.randf_range(-1.0, 1.0), 0.3, rng.randf_range(-1.0, 1.0)), 0.18, Color(1.0, 0.4, 0.1), 2.0)
		placed += 1


func _build_fire_altar(pos: Vector3) -> void:
	_make_building(pos, Vector3(7.0, 1.0, 7.0), _charred)
	_disc(pos + Vector3(0, 1.05, 0), 2.0, _lava)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_make_pillar(pos + Vector3(sx * 2.6, 1.0, sz * 2.6), 3.5, 0.35, _charred)
	_glow_orb(pos + Vector3(0, 3.2, 0), 0.7, Color(1.0, 0.45, 0.1), 2.5)


# --- Bioma JUNGLA ---------------------------------------------------------------

func _build_jungle(z: Dictionary, rng: RandomNumberGenerator) -> void:
	var c: Vector3 = Zones.center3(z)
	var r: float = float(z["radius"])
	var sa: float = rng.randf_range(0.0, TAU)
	_build_jungle_temple(c + Vector3(cos(sa), 0, sin(sa)) * (r * 0.72))
	var placed := 0
	var tries := 0
	var count := int(r * 1.5)  # jungla densa
	while placed < count and tries < count * 8:
		tries += 1
		var ang: float = rng.randf_range(0.0, TAU)
		var dist: float = rng.randf_range(ARENA_R + 5.0, r - 2.0)
		var pos: Vector3 = c + Vector3(cos(ang), 0, sin(ang)) * dist
		if _near_road(pos):
			continue
		var roll: float = rng.randf()
		if roll < 0.6:
			_make_tree(pos, rng)
		elif roll < 0.78:
			_make_fern(pos, rng)
		elif roll < 0.9:
			_make_vine(pos, rng)
		else:
			_make_rock(pos, rng)
		placed += 1


func _build_jungle_temple(pos: Vector3) -> void:
	_make_building(pos, Vector3(10.0, 1.5, 10.0), _stone)
	_make_building(pos + Vector3(0, 1.5, 0), Vector3(7.0, 1.5, 7.0), _stone)
	_make_building(pos + Vector3(0, 3.0, 0), Vector3(4.0, 1.5, 4.0), _stone)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_make_pillar(pos + Vector3(sx * 4.0, 1.5, sz * 4.0), 4.0, 0.4, _stone)
	_glow_orb(pos + Vector3(0, 5.2, 0), 0.7, Color(0.4, 0.9, 0.3), 2.0)


# --- Bioma DESIERTO -------------------------------------------------------------

func _build_desert(z: Dictionary, rng: RandomNumberGenerator) -> void:
	var c: Vector3 = Zones.center3(z)
	var r: float = float(z["radius"])
	for i in 6:
		var a: float = rng.randf_range(0.0, TAU)
		var d: float = rng.randf_range(ARENA_R + 8.0, r - 4.0)
		_make_mound(c + Vector3(cos(a), 0, sin(a)) * d, rng, _sand)
	var sa: float = rng.randf_range(0.0, TAU)
	_build_obelisk(c + Vector3(cos(sa), 0, sin(sa)) * (r * 0.7))
	var placed := 0
	var tries := 0
	var count := int(r * 0.7)
	while placed < count and tries < count * 8:
		tries += 1
		var ang: float = rng.randf_range(0.0, TAU)
		var dist: float = rng.randf_range(ARENA_R + 5.0, r - 2.0)
		var pos: Vector3 = c + Vector3(cos(ang), 0, sin(ang)) * dist
		if _near_road(pos):
			continue
		var roll: float = rng.randf()
		if roll < 0.45:
			_make_cactus(pos, rng)
		elif roll < 0.75:
			_make_rock(pos, rng)
		else:
			_make_mound(pos, rng, _sand)
		placed += 1


func _build_obelisk(pos: Vector3) -> void:
	_make_building(pos, Vector3(4.0, 0.6, 4.0), _sandstone)
	_make_building(pos, Vector3(2.0, 9.0, 2.0), _sandstone)
	_make_cone(pos + Vector3(0, 9.0, 0), 2.0, 1.3, _sandstone, false)


# --- Bioma HIELO ----------------------------------------------------------------

func _build_ice(z: Dictionary, rng: RandomNumberGenerator) -> void:
	var c: Vector3 = Zones.center3(z)
	var r: float = float(z["radius"])
	_disc(c, r * 0.5, _ice)  # lago helado (la arena queda como isla)
	var sa: float = rng.randf_range(0.0, TAU)
	_build_ice_monolith(c + Vector3(cos(sa), 0, sin(sa)) * (r * 0.74), rng)
	var placed := 0
	var tries := 0
	var count := int(r * 0.9)
	while placed < count and tries < count * 8:
		tries += 1
		var ang: float = rng.randf_range(0.0, TAU)
		var dist: float = rng.randf_range(ARENA_R + 5.0, r - 2.0)
		var pos: Vector3 = c + Vector3(cos(ang), 0, sin(ang)) * dist
		if _near_road(pos):
			continue
		var roll: float = rng.randf()
		if roll < 0.35:
			_make_cone(pos, rng.randf_range(2.5, 5.5), rng.randf_range(0.4, 0.9), _crystal, true)
		elif roll < 0.6:
			_make_mound(pos, rng, _snow)
		else:
			_make_rock(pos, rng)
		placed += 1


func _build_ice_monolith(pos: Vector3, rng: RandomNumberGenerator) -> void:
	_make_building(pos, Vector3(6.0, 0.8, 6.0), _stone)
	for i in 5:
		var a: float = TAU * float(i) / 5.0
		_make_cone(pos + Vector3(cos(a) * 2.2, 0.8, sin(a) * 2.2), rng.randf_range(3.0, 5.0), 0.5, _crystal, true)
	_glow_orb(pos + Vector3(0, 3.6, 0), 0.8, Color(0.5, 0.85, 1.0), 2.5)


# --- Bioma PANTANO --------------------------------------------------------------

func _build_swamp(z: Dictionary, rng: RandomNumberGenerator) -> void:
	var c: Vector3 = Zones.center3(z)
	var r: float = float(z["radius"])
	for i in 6:
		var a: float = rng.randf_range(0.0, TAU)
		var d: float = rng.randf_range(ARENA_R + 5.0, r - 5.0)
		_disc(c + Vector3(cos(a), 0, sin(a)) * d, rng.randf_range(4.0, 9.0), _bog)
	var sa: float = rng.randf_range(0.0, TAU)
	_build_swamp_ruin(c + Vector3(cos(sa), 0, sin(sa)) * (r * 0.74), rng)
	var placed := 0
	var tries := 0
	var count := int(r * 1.0)
	while placed < count and tries < count * 8:
		tries += 1
		var ang: float = rng.randf_range(0.0, TAU)
		var dist: float = rng.randf_range(ARENA_R + 5.0, r - 2.0)
		var pos: Vector3 = c + Vector3(cos(ang), 0, sin(ang)) * dist
		if _near_road(pos):
			continue
		var roll: float = rng.randf()
		if roll < 0.4:
			_make_dead_tree(pos, rng, _mud)
		elif roll < 0.65:
			_make_mushroom(pos, rng)
		elif roll < 0.85:
			_make_mound(pos, rng, _mud)
		else:
			_make_rock(pos, rng)
		placed += 1


func _build_swamp_ruin(pos: Vector3, rng: RandomNumberGenerator) -> void:
	_make_building(pos, Vector3(7.0, 0.6, 7.0), _mud)
	for i in 5:
		var a: float = TAU * float(i) / 5.0
		_make_pillar(pos + Vector3(cos(a) * 2.6, 0.6, sin(a) * 2.6), rng.randf_range(2.0, 4.0), 0.4, _wetrock)
	_glow_orb(pos + Vector3(0, 2.6, 0), 0.6, Color(0.4, 0.85, 0.3), 1.5)
