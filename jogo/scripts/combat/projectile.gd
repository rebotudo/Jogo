extends Area3D
## Projectile
## Proyectil de ataque a distancia (flecha / bola mágica). Cada peer lo crea de
## forma local con los mismos parametros (origen, direccion, velocidad), asi se
## mueve igual en todas las pantallas sin sincronizar posicion.
##
## Solo el "dueño" (el cliente del atacante) comprueba los impactos y aplica el
## daño a traves del Hurtbox -> CombatManager (modelo autoritativo, igual que el
## golpe melé). En los demas peers el proyectil es solo visual.

@export var speed: float = 22.0
@export var lifetime: float = 3.0
var max_range: float = 30.0   # alcance maximo: al recorrerlo, explota/desaparece
var _traveled: float = 0.0    # distancia recorrida

var direction: Vector3 = Vector3.ZERO
var damage: int = 10
var attacker_id: int = 0
var is_owner: bool = false
var explode_radius: float = 0.0  # > 0 = explota en area al impactar
var pierce: bool = false         # true = atraviesa varios enemigos
var _life: float = 0.0
var _hit: bool = false
var _hit_set: Array = []         # enemigos ya golpeados (para perforar)


func setup(dir: Vector3, dmg: int, aid: int, kind: String = "magic") -> void:
	direction = dir.normalized()
	damage = dmg
	attacker_id = aid
	is_owner = (aid == multiplayer.get_unique_id())
	_life = lifetime
	# Alcance maximo segun el tipo (las flechas llegan algo mas lejos).
	max_range = 40.0 if kind == "arrow" else 30.0
	# Tambien detectamos el entorno (capa 1 = mundo): suelo y paredes estaticas,
	# para explotar/desaparecer al chocar con ellos.
	collision_mask = collision_mask | 1
	_apply_visual(kind)
	# Orientar la flecha a lo largo de su trayectoria (la magia es esferica).
	if kind == "arrow" and absf(direction.dot(Vector3.UP)) < 0.98:
		look_at(global_position + direction, Vector3.UP)


func _apply_visual(kind: String) -> void:
	var mesh_node := $Mesh as MeshInstance3D
	if mesh_node == null:
		return
	var mat := StandardMaterial3D.new()
	mat.emission_enabled = true
	if kind == "arrow":
		var bm := BoxMesh.new()
		bm.size = Vector3(0.06, 0.06, 0.55)  # alargada (eje Z), como una flecha
		mesh_node.mesh = bm
		mat.albedo_color = Color(0.55, 0.4, 0.22, 1)
		mat.emission = Color(0.35, 0.25, 0.12, 1)
		mat.emission_energy_multiplier = 0.4
	else:
		# Bola elemental: el color depende del tipo.
		var col := Color(0.55, 0.45, 1.0)  # magia (por defecto)
		match kind:
			"water": col = Color(0.3, 0.6, 0.95)
			"fire": col = Color(1.0, 0.45, 0.12)
			"ice": col = Color(0.6, 0.9, 1.0)
			"poison": col = Color(0.5, 0.9, 0.3)
			"sand": col = Color(0.85, 0.72, 0.4)
		var sm := SphereMesh.new()
		sm.radius = 0.17
		sm.height = 0.34
		mesh_node.mesh = sm
		mat.albedo_color = col
		mat.emission = col
		mat.emission_energy_multiplier = 2.0
	mesh_node.material_override = mat


func _physics_process(delta: float) -> void:
	var step: float = speed * delta
	global_position += direction * step
	_traveled += step
	_life -= delta
	# Fin de vida o de alcance: explota (si tiene radio) o desaparece.
	if _life <= 0.0 or _traveled >= max_range:
		_expire()
		return
	# Choque con el ENTORNO (suelo/paredes estaticas): mismo final que el alcance.
	for body in get_overlapping_bodies():
		if body is StaticBody3D:
			_expire()
			return
	# Solo el atacante decide el impacto (evita aplicar el daño varias veces).
	if not is_owner:
		return
	if pierce:
		# Atraviesa: golpea a cada enemigo una vez y sigue su camino.
		for area in get_overlapping_areas():
			if area.has_method("receive_hit") and not (area in _hit_set):
				_hit_set.append(area)
				area.receive_hit(damage, attacker_id)
		return
	if not _hit:
		for area in get_overlapping_areas():
			if area.has_method("receive_hit"):
				_hit = true
				if explode_radius > 0.0:
					# Explosion: daño en area alrededor del impacto.
					CombatManager.report_explosion(global_position, explode_radius, damage, attacker_id)
				else:
					area.receive_hit(damage, attacker_id)
				queue_free()
				return


# Fin del proyectil (alcance agotado o choque con el entorno). Todos los peers lo
# despawnean; solo el dueño reporta la explosion (daño + efecto en area).
func _expire() -> void:
	if is_owner and explode_radius > 0.0 and not _hit:
		_hit = true
		CombatManager.report_explosion(global_position, explode_radius, damage, attacker_id)
	queue_free()
