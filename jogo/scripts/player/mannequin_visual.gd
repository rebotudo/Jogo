extends Node3D
## MannequinVisual
## Cuerpo humanoide real (Quaternius "Universal Animation Library 2", CC0)
## reutilizado para TODAS las clases: un mismo maniqui tintado de color distinto
## por clase. Anima idle / andar / ataques de espada / golpe recibido leyendo el
## movimiento real del jugador padre (funciona en todos los peers).
##
## Expone la MISMA interfaz que character_visual.gd para que el jugador lo use
## sin cambios: setup(class_id, size), attack(strong), flash(), set_view(mode),
## set_dead(dead).

const MODEL: PackedScene = preload("res://assets/characters/mannequin.glb")

# El modelo Quaternius mira hacia +Z; el "frente" en Godot es -Z, asi que lo
# giramos 180º. Si se ve de espaldas al caminar, cambia esto a 0.0.
const MODEL_YAW: float = PI
const FOOT_OFFSET: float = -0.9   # origen del modelo (pies) -> base de la capsula

# Color y tamaño por clase.
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

var _model: Node3D
var _anim: AnimationPlayer
var _meshes: Array = []          # MeshInstance3D del modelo (para tintar/flash)
var _tint: Color = Color(0.7, 0.7, 0.7)

# Nombres de clips resueltos del propio archivo.
var _clip_idle: String = ""
var _clip_walk: String = ""
var _clip_hit: String = ""
var _clips_attack: Array = []
var _clip_finisher: String = ""

var _move_amount: float = 0.0
var _prev_pos: Vector3
var _has_prev: bool = false
var _state: String = "idle"      # idle / walk
var _locked: bool = false        # durante ataque/muerte no cambiamos a locomotion
var _dead: bool = false
var _view_mode: String = "normal"
var _attack_idx: int = 0

const RUN_SPEED: float = 5.0


func setup(class_id: String, size: float = 1.0) -> void:
	var look: Dictionary = CLASS_LOOK.get(class_id, {"tint": Color(0.7, 0.7, 0.7), "size": 1.0})
	_tint = look["tint"]
	var s: float = float(look["size"]) * size

	_model = MODEL.instantiate()
	add_child(_model)
	_model.position.y = FOOT_OFFSET
	_model.rotation.y = MODEL_YAW
	_model.scale = Vector3(s, s, s)

	_collect(_model)
	_resolve_clips()
	_apply_tint()
	if _anim != null:
		_set_loop(_clip_idle, true)
		_set_loop(_clip_walk, true)
		if not _anim.animation_finished.is_connected(_on_anim_finished):
			_anim.animation_finished.connect(_on_anim_finished)
	_play(_clip_idle)
	_state = "idle"


func _collect(n: Node) -> void:
	if n is MeshInstance3D:
		_meshes.append(n)
	if n is AnimationPlayer and _anim == null:
		_anim = n
	for c in n.get_children():
		_collect(c)


func _resolve_clips() -> void:
	if _anim == null:
		return
	var list: Array = Array(_anim.get_animation_list())
	_clip_idle = _pick(list, ["Idle_No", "Idle"], "")
	_clip_walk = _pick(list, ["Walk_Carry", "Walk"], _clip_idle)
	_clip_hit = _pick(list, ["Hit_Knockback", "Hit"], "")
	_clip_finisher = _pick(list, ["Sword_Heavy", "Heavy_Combo", "Sword_Regular_Combo"], "")
	for an in ["Sword_Regular_A", "Sword_Regular_B", "Sword_Regular_C"]:
		if an in list:
			_clips_attack.append(an)
	if _clips_attack.is_empty() and _clip_finisher != "":
		_clips_attack.append(_clip_finisher)


# Primer clip cuyo nombre contiene alguno de los substrings (sin mayus/minus).
func _pick(list: Array, subs: Array, fallback: String) -> String:
	for sub in subs:
		var low: String = String(sub).to_lower()
		for nm in list:
			if String(nm).to_lower().contains(low):
				return nm
	return fallback


func _set_loop(clip: String, on: bool) -> void:
	if clip == "" or not _anim.has_animation(clip):
		return
	var a: Animation = _anim.get_animation(clip)
	a.loop_mode = Animation.LOOP_LINEAR if on else Animation.LOOP_NONE


func _play(clip: String, speed: float = 1.0) -> void:
	if _anim == null or clip == "" or not _anim.has_animation(clip):
		return
	_anim.play(clip, 0.15, speed)


func _process(delta: float) -> void:
	# Velocidad y direccion reales del jugador (desplazamiento del nodo).
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

	# Orientacion del cuerpo: al moverse, gira hacia DONDE camina (asi el unico
	# clip de andar siempre se ve en la direccion correcta). Al estar quieto o
	# atacar, mira al frente (hacia donde apunta el jugador).
	var target_yaw: float = MODEL_YAW
	if not _locked and not _dead and _move_amount > 0.12 and move_dir != Vector3.ZERO:
		var fwd: Vector3 = -global_transform.basis.z
		fwd.y = 0.0
		if fwd.length() > 0.001:
			fwd = fwd.normalized()
			target_yaw = MODEL_YAW + fwd.signed_angle_to(move_dir, Vector3.UP)
	if _model != null:
		_model.rotation.y = lerp_angle(_model.rotation.y, target_yaw, clampf(delta * 12.0, 0.0, 1.0))

	if _dead or _locked or _anim == null:
		return
	# Locomotion: idle <-> andar.
	var want: String = "walk" if _move_amount > 0.12 else "idle"
	if want != _state:
		_state = want
		_play(_clip_walk if want == "walk" else _clip_idle)


func _on_anim_finished(_anim_name: String) -> void:
	if _dead:
		return
	_locked = false
	_state = ""  # forzamos re-evaluar locomotion en el proximo _process


# --- Interfaz (la llama el jugador, ya sincronizada por RPC) --------------------

func attack(_strong: bool = false) -> void:
	# Cada golpe = UN solo espadazo (A -> B -> C en bucle). No usamos los clips de
	# "combo" porque encadenan varios espadazos en uno y se ve atropellado.
	if _anim == null or _dead or _clips_attack.is_empty():
		return
	var clip: String = _clips_attack[_attack_idx % _clips_attack.size()]
	_attack_idx += 1
	_locked = true
	_play(clip, 1.2)


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
	_apply_view()  # restaura tinte / ghost segun el estado actual


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
	if _anim == null:
		return
	if dead:
		_locked = true
		if _clip_hit != "":
			_set_loop(_clip_hit, false)
			_play(_clip_hit)
	else:
		_locked = false
		_state = ""
		_play(_clip_idle)
