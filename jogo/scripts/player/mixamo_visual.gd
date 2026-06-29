extends Node3D
## MixamoVisual
## Cuerpo humanoide real (Mixamo "Y Bot") + animaciones Mixamo (CC, uso libre),
## reutilizado para TODAS las clases, tintado por clase. Todas las animaciones
## comparten el mismo esqueleto (mixamorig), asi que las fusionamos en el
## AnimationPlayer del cuerpo y las reproducimos por nombre.
##
## Locomotion DIRECCIONAL real: el cuerpo mira al frente (hacia donde apunta el
## jugador) y elegimos el clip segun la direccion del movimiento (correr / andar
## hacia atras / strafe izq / strafe der).
##
## Misma interfaz que los demas visuales: setup(class_id, size), attack(strong),
## flash(), set_view(mode), set_dead(dead).

const BODY_PATH: String = "res://assets/characters/ybot.glb"

# Mixamo mira a +Z; el "frente" en Godot es -Z, asi que giramos 180º. Si se ve
# de espaldas, cambia esto a 0.0.
const BODY_YAW: float = PI
const FOOT_OFFSET: float = -0.9

# clip_key -> archivo .glb de la animacion.
const ANIM_FILES := {
	"idle": "res://assets/characters/anim/Neutral Idle.glb",
	"run": "res://assets/characters/anim/Running.glb",
	"back": "res://assets/characters/anim/Walking Backwards.glb",
	"strafe_l": "res://assets/characters/anim/Left Strafe Walking.glb",
	"strafe_r": "res://assets/characters/anim/Right Strafe Walking.glb",
	"atk1": "res://assets/characters/anim/Sword And Shield Slash.glb",
	"atk2": "res://assets/characters/anim/Stable Sword Outward Slash.glb",
	"atk3": "res://assets/characters/anim/Great Sword Slash.glb",
}
const LOOP_CLIPS := ["idle", "run", "back", "strafe_l", "strafe_r"]
const ATTACK_CLIPS := ["atk1", "atk2", "atk3"]

const CLASS_LOOK := {
	"guerrero":   {"tint": Color(0.72, 0.22, 0.20), "size": 1.0},
	"tanque":     {"tint": Color(0.40, 0.45, 0.55), "size": 1.18},
	"paladin":    {"tint": Color(0.86, 0.78, 0.42), "size": 1.05},
	"asesino":    {"tint": Color(0.24, 0.20, 0.34), "size": 0.93},
	"arquero":    {"tint": Color(0.24, 0.50, 0.30), "size": 0.97},
	"mago":       {"tint": Color(0.28, 0.40, 0.85), "size": 0.97},
	"curandero":  {"tint": Color(0.90, 0.90, 0.95), "size": 0.98},
	"nigromante": {"tint": Color(0.34, 0.24, 0.46), "size": 0.97},
}

var _body: Node3D
var _anim: AnimationPlayer
var _meshes: Array = []
var _tint: Color = Color(0.7, 0.7, 0.7)
var _available: Array = []     # claves de clips que SI se cargaron

var _move_amount: float = 0.0
var _prev_pos: Vector3
var _has_prev: bool = false
var _state: String = ""
var _locked: bool = false
var _dead: bool = false
var _view_mode: String = "normal"
var _attack_idx: int = 0

const RUN_SPEED: float = 5.0


func setup(class_id: String, size: float = 1.0) -> void:
	var look: Dictionary = CLASS_LOOK.get(class_id, {"tint": Color(0.7, 0.7, 0.7), "size": 1.0})
	_tint = look["tint"]
	var s: float = float(look["size"]) * size

	var packed = load(BODY_PATH)
	if packed == null:
		push_warning("MixamoVisual: no se pudo cargar " + BODY_PATH)
		return
	_body = packed.instantiate()
	add_child(_body)
	_body.position.y = FOOT_OFFSET
	_body.rotation.y = BODY_YAW
	_body.scale = Vector3(s, s, s)

	_collect(_body)
	_merge_animations()
	_apply_tint()
	if _anim != null:
		if not _anim.animation_finished.is_connected(_on_anim_finished):
			_anim.animation_finished.connect(_on_anim_finished)
		_play("idle")
		_state = "idle"


func _collect(n: Node) -> void:
	if n is MeshInstance3D:
		_meshes.append(n)
	if n is AnimationPlayer and _anim == null:
		_anim = n
	for c in n.get_children():
		_collect(c)


# Fusiona cada animacion (de su propio glb) en el AnimationPlayer del cuerpo.
func _merge_animations() -> void:
	if _anim == null:
		return
	var lib: AnimationLibrary = _anim.get_animation_library("")
	if lib == null:
		lib = AnimationLibrary.new()
		_anim.add_animation_library("", lib)
	for key in ANIM_FILES.keys():
		var p = load(ANIM_FILES[key])
		if p == null:
			continue
		var tmp = p.instantiate()
		var ap: AnimationPlayer = _find_anim_player(tmp)
		if ap != null:
			var names: Array = Array(ap.get_animation_list())
			if not names.is_empty():
				var src: Animation = ap.get_animation(names[0])
				if src != null:
					var dup: Animation = src.duplicate()
					_strip_travel(dup)  # quita el root motion (desplazamiento del clip)
					dup.loop_mode = Animation.LOOP_LINEAR if key in LOOP_CLIPS else Animation.LOOP_NONE
					if lib.has_animation(key):
						lib.remove_animation(key)
					lib.add_animation(key, dup)
					_available.append(key)
		tmp.queue_free()


# Anula el "root motion": congela el desplazamiento horizontal (X,Z) de la
# cadera para que la animacion se reproduzca EN EL SITIO (el juego ya mueve al
# personaje). Conserva la Y para mantener el rebote natural.
func _strip_travel(anim: Animation) -> void:
	for i in anim.get_track_count():
		if anim.track_get_type(i) != Animation.TYPE_POSITION_3D:
			continue
		var path: String = String(anim.track_get_path(i))
		if not path.ends_with("Hips"):
			continue
		var kc: int = anim.track_get_key_count(i)
		if kc == 0:
			continue
		var base: Vector3 = anim.track_get_key_value(i, 0)
		for k in kc:
			var v: Vector3 = anim.track_get_key_value(i, k)
			anim.track_set_key_value(i, k, Vector3(base.x, v.y, base.z))


func _find_anim_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_anim_player(c)
		if r != null:
			return r
	return null


func _play(key: String, speed: float = 1.0) -> void:
	if _anim == null or not (key in _available):
		return
	_anim.play(key, 0.15, speed)


func _process(delta: float) -> void:
	var cur: Vector3 = global_position
	var move_dir: Vector3 = Vector3.ZERO
	if _has_prev:
		var d: Vector3 = cur - _prev_pos
		d.y = 0.0
		var spd: float = d.length() / maxf(delta, 0.0001)
		_move_amount = lerpf(_move_amount, clampf(spd / RUN_SPEED, 0.0, 1.0), clampf(delta * 10.0, 0.0, 1.0))
		if d.length() > 0.0005:
			move_dir = d.normalized()
	_prev_pos = cur
	_has_prev = true

	if _dead or _locked or _anim == null:
		return

	# Locomotion direccional: el cuerpo mira al frente; elegimos clip segun hacia
	# donde se mueve respecto a esa orientacion.
	var want: String = "idle"
	if _move_amount > 0.12 and move_dir != Vector3.ZERO:
		var fwd: Vector3 = -global_transform.basis.z
		var right: Vector3 = global_transform.basis.x
		fwd.y = 0.0
		right.y = 0.0
		var f: float = move_dir.dot(fwd.normalized())
		var r: float = move_dir.dot(right.normalized())
		if absf(f) >= absf(r):
			want = "run" if f > 0.0 else "back"
		else:
			want = "strafe_r" if r > 0.0 else "strafe_l"
		want = _best(want, "run", "idle")
	if want != _state:
		_state = want
		_play(want)


# Devuelve la 1ª clave disponible entre las dadas (fallback si falta el clip).
func _best(a: String, b: String, c: String) -> String:
	if a in _available: return a
	if b in _available: return b
	return c


func _on_anim_finished(_n: String) -> void:
	if _dead:
		return
	_locked = false
	_state = ""  # re-evaluar locomotion


# --- Interfaz --------------------------------------------------------------------

func attack(_strong: bool = false) -> void:
	if _anim == null or _dead:
		return
	var avail: Array = []
	for k in ATTACK_CLIPS:
		if k in _available:
			avail.append(k)
	if avail.is_empty():
		return
	var clip: String = avail[_attack_idx % avail.size()]
	_attack_idx += 1
	_locked = true
	_play(clip, 1.3)


func flash() -> void:
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(1, 1, 1)
	fm.emission_enabled = true
	fm.emission = Color(1, 1, 1)
	fm.emission_energy_multiplier = 2.0
	for mi in _meshes:
		if is_instance_valid(mi):
			mi.material_override = fm
	await get_tree().create_timer(0.12).timeout
	_apply_view()


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
		gm.albedo_color = Color(_tint.r, _tint.g, _tint.b, 0.25)
		for mi in _meshes:
			if is_instance_valid(mi):
				mi.material_override = gm
	else:
		_apply_tint()


func _apply_tint() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _tint
	for mi in _meshes:
		if is_instance_valid(mi):
			mi.material_override = mat


func set_dead(dead: bool) -> void:
	_dead = dead
	if _body == null:
		return
	# No tenemos clip de muerte aun: desplome simple del cuerpo.
	var t := create_tween()
	if dead:
		_locked = true
		t.tween_property(_body, "rotation:x", -1.4, 0.35)
		t.parallel().tween_property(_body, "position:y", FOOT_OFFSET - 0.4, 0.35)
	else:
		_locked = false
		_state = ""
		t.tween_property(_body, "rotation:x", 0.0, 0.2)
		t.parallel().tween_property(_body, "position:y", FOOT_OFFSET, 0.2)
		_play("idle")
