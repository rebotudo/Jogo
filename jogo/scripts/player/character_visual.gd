extends Node3D
## CharacterVisual
## Muñeco 3D procedural (construido con primitivas) para cada clase. No usa
## modelos externos: torso, cabeza, brazos y piernas son MeshInstance3D, y las
## extremidades cuelgan de pivotes (Node3D) que rotamos para animar.
##
## Animaciones (en _process, en TODOS los peers, leyendo el movimiento real del
## jugador padre):
##   - idle: leve balanceo de respiracion.
##   - andar/correr: piernas y brazos oscilan; amplitud segun la velocidad.
##   - atacar: golpe rapido del brazo derecho + embestida del torso.
##   - morir: el muñeco se desploma.
## Tambien gestiona el flash blanco al recibir daño y los modos de visibilidad
## (normal / difuminado / oculto) para la invisibilidad del asesino.

# Aspecto por clase: silueta (ancho/alto), colores y "prop" (sombrero/capucha).
const LOOK := {
	"guerrero":   {"w": 1.05, "h": 1.0,  "body": Color(0.45, 0.48, 0.55), "limb": Color(0.7, 0.2, 0.2),  "head": Color(0.9, 0.75, 0.62), "prop": "none"},
	"tanque":     {"w": 1.35, "h": 0.95, "body": Color(0.32, 0.35, 0.4),  "limb": Color(0.5, 0.52, 0.55), "head": Color(0.9, 0.75, 0.62), "prop": "none"},
	"paladin":    {"w": 1.12, "h": 1.02, "body": Color(0.82, 0.82, 0.86), "limb": Color(0.85, 0.7, 0.25), "head": Color(0.9, 0.75, 0.62), "prop": "none"},
	"asesino":    {"w": 0.82, "h": 1.0,  "body": Color(0.12, 0.12, 0.16), "limb": Color(0.45, 0.2, 0.55), "head": Color(0.85, 0.7, 0.58), "prop": "hood"},
	"arquero":    {"w": 0.9,  "h": 1.0,  "body": Color(0.2, 0.42, 0.24),  "limb": Color(0.45, 0.32, 0.18),"head": Color(0.9, 0.75, 0.62), "prop": "hood"},
	"mago":       {"w": 0.92, "h": 1.0,  "body": Color(0.2, 0.28, 0.7),   "limb": Color(0.3, 0.5, 0.85),  "head": Color(0.9, 0.78, 0.66), "prop": "hat"},
	"curandero":  {"w": 0.95, "h": 1.0,  "body": Color(0.92, 0.92, 0.95), "limb": Color(0.85, 0.75, 0.35),"head": Color(0.9, 0.78, 0.66), "prop": "hood"},
	"nigromante": {"w": 0.9,  "h": 1.0,  "body": Color(0.22, 0.14, 0.3),  "limb": Color(0.3, 0.65, 0.35), "head": Color(0.8, 0.82, 0.72), "prop": "hood"},
	# No jugables: invocaciones y enemigos.
	"skeleton":   {"w": 0.8,  "h": 0.95, "body": Color(0.86, 0.85, 0.78), "limb": Color(0.8, 0.79, 0.72), "head": Color(0.93, 0.92, 0.86),"prop": "none", "glow": Color(0.5, 0.55, 0.4)},
	"enemy":      {"w": 1.1,  "h": 1.0,  "body": Color(0.5, 0.13, 0.13),  "limb": Color(0.32, 0.08, 0.08),"head": Color(0.55, 0.5, 0.32), "prop": "none", "glow": Color(0.3, 0.02, 0.02)},
}

var _rig: Node3D            # contenedor que balanceamos/embestimos
var _left_leg: Node3D
var _right_leg: Node3D
var _left_arm: Node3D
var _right_arm: Node3D
var _parts: Array = []      # todas las MeshInstance3D (para flash/ghost)

var _phase: float = 0.0     # ciclo de paso
var _move_amount: float = 0.0
var _prev_pos: Vector3
var _has_prev: bool = false
var _time: float = 0.0

var _attacking: bool = false
var _dead: bool = false
var _view_mode: String = "normal"

const RUN_SPEED: float = 5.0  # velocidad a la que la animacion va a tope


var _glow = null  # Color opcional de emision (esqueletos/enemigos)


func setup(class_id: String, size: float = 1.0) -> void:
	var look: Dictionary = LOOK.get(class_id, LOOK["guerrero"])
	_build(look)
	scale = Vector3(look["w"], look["h"], look["w"]) * size


func _build(look: Dictionary) -> void:
	_glow = look.get("glow", null)
	_rig = Node3D.new()
	add_child(_rig)

	var body_col: Color = look["body"]
	var limb_col: Color = look["limb"]
	var head_col: Color = look["head"]

	# Torso (caja) centrado entre cadera y hombros.
	var torso := _box(Vector3(0.5, 0.7, 0.32), body_col, Vector3(0, 0.12, 0))
	_rig.add_child(torso)
	# Cadera/cinturon.
	var hips := _box(Vector3(0.46, 0.18, 0.3), limb_col, Vector3(0, -0.22, 0))
	_rig.add_child(hips)

	# Cabeza (esfera).
	var head := _sphere(0.18, head_col, Vector3(0, 0.66, 0))
	_rig.add_child(head)

	# Prop por clase (sombrero de mago, capucha...).
	_add_prop(String(look.get("prop", "none")), body_col)

	# Brazos: pivote en el hombro, brazo colgando.
	_left_arm = _limb(Vector3(-0.34, 0.42, 0), 0.55, 0.13, limb_col)
	_right_arm = _limb(Vector3(0.34, 0.42, 0), 0.55, 0.13, limb_col)
	# Piernas: pivote en la cadera.
	_left_leg = _limb(Vector3(-0.14, -0.28, 0), 0.62, 0.16, body_col.darkened(0.2))
	_right_leg = _limb(Vector3(0.14, -0.28, 0), 0.62, 0.16, body_col.darkened(0.2))


# Crea una extremidad: un pivote (Node3D) en pos con una caja que cuelga hacia
# abajo. Rotar el pivote en X balancea la extremidad.
func _limb(pos: Vector3, length: float, thick: float, col: Color) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = pos
	_rig.add_child(pivot)
	var mi := _box(Vector3(thick, length, thick), col, Vector3(0, -length * 0.5, 0))
	pivot.add_child(mi)
	return pivot


func _add_prop(prop: String, accent: Color) -> void:
	match prop:
		"hat":
			# Sombrero puntiagudo de mago (cono).
			var cone := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.0
			cyl.bottom_radius = 0.22
			cyl.height = 0.4
			cone.mesh = cyl
			cone.position = Vector3(0, 0.95, 0)
			_apply_color(cone, accent.darkened(0.1))
			_rig.add_child(cone)
		"hood":
			# Capucha: media esfera algo mayor sobre la cabeza.
			var hood := _sphere(0.21, accent.darkened(0.15), Vector3(0, 0.7, -0.02))
			_rig.add_child(hood)
		_:
			pass


func _box(size: Vector3, col: Color, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	_apply_color(mi, col)
	return mi


func _sphere(radius: float, col: Color, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	mi.mesh = sm
	mi.position = pos
	_apply_color(mi, col)
	return mi


func _apply_color(mi: MeshInstance3D, col: Color) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	if _glow != null:
		mat.emission_enabled = true
		mat.emission = _glow
		mat.emission_energy_multiplier = 0.4
	mi.set_surface_override_material(0, mat)
	_parts.append(mi)


func _process(delta: float) -> void:
	_time += delta
	if _dead:
		return

	# Velocidad real del jugador a partir del desplazamiento del nodo.
	var cur := global_position
	if _has_prev:
		var d := cur - _prev_pos
		d.y = 0.0
		var spd: float = d.length() / maxf(delta, 0.0001)
		var target: float = clampf(spd / RUN_SPEED, 0.0, 1.0)
		_move_amount = lerpf(_move_amount, target, clampf(delta * 10.0, 0.0, 1.0))
	_prev_pos = cur
	_has_prev = true

	if _rig == null:
		return

	# Avance del ciclo de paso (mas rapido al correr).
	_phase += delta * (6.0 + _move_amount * 6.0)
	var amp: float = _move_amount * 0.7

	var swing: float = sin(_phase) * amp
	if _left_leg: _left_leg.rotation.x = swing
	if _right_leg: _right_leg.rotation.x = -swing
	if not _attacking:
		if _left_arm: _left_arm.rotation.x = -swing * 0.8
		if _right_arm: _right_arm.rotation.x = swing * 0.8

	# Respiracion/rebote del torso.
	var bob: float = sin(_time * 2.0) * 0.012 + abs(sin(_phase)) * _move_amount * 0.04
	_rig.position.y = bob


# --- Eventos (los llama el jugador, ya sincronizados por RPC) -------------------

func attack(strong: bool = false) -> void:
	if _rig == null or _right_arm == null or _dead:
		return
	_attacking = true
	var windup: float = -2.4 if strong else -1.8
	var chop: float = 0.8 if strong else 0.5
	var lunge: float = -0.4 if strong else -0.25
	var t := create_tween()
	# Brazo: levantar y descargar el golpe.
	t.tween_property(_right_arm, "rotation:x", windup, 0.08)
	t.parallel().tween_property(_rig, "position:z", lunge, 0.08)
	t.tween_property(_right_arm, "rotation:x", chop, 0.07)
	t.tween_property(_right_arm, "rotation:x", 0.0, 0.14)
	t.parallel().tween_property(_rig, "position:z", 0.0, 0.14)
	t.tween_callback(func(): _attacking = false)


func flash() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 1, 1)
	mat.emission_enabled = true
	mat.emission = Color(1, 1, 1)
	mat.emission_energy_multiplier = 2.0
	for mi in _parts:
		if is_instance_valid(mi):
			mi.material_override = mat
	await get_tree().create_timer(0.12).timeout
	_apply_view()  # volver al estado visual actual (normal/ghost)


# Modos: "normal" (visible), "ghost" (difuminado), "hidden" (invisible).
func set_view(mode: String) -> void:
	_view_mode = mode
	_apply_view()


func _apply_view() -> void:
	if _view_mode == "hidden":
		visible = false
		return
	visible = true
	if _view_mode == "ghost":
		var gm := StandardMaterial3D.new()
		gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		gm.albedo_color = Color(0.45, 0.5, 0.65, 0.25)
		for mi in _parts:
			if is_instance_valid(mi):
				mi.material_override = gm
	else:
		for mi in _parts:
			if is_instance_valid(mi):
				mi.material_override = null


func set_dead(dead: bool) -> void:
	_dead = dead
	if _rig == null:
		return
	var t := create_tween()
	if dead:
		# Se desploma de espaldas.
		t.tween_property(_rig, "rotation:x", -1.4, 0.35)
		t.parallel().tween_property(_rig, "position:y", -0.55, 0.35)
	else:
		t.tween_property(_rig, "rotation:x", 0.0, 0.2)
		t.parallel().tween_property(_rig, "position:y", 0.0, 0.2)
