extends CharacterBody3D

@onready var hurtbox = $Hurtbox
@onready var nav_agent = $NavigationAgent3D
@onready var hitbox = $Hitbox

@export var speed: float = 3.0
@export var detection_range: float = 8.0
@export var attack_range: float = 1.5
@export var attack_cooldown: float = 1.5

var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
var player: Node3D = null
var is_attacking: bool = false
var attack_timer: float = 0.0

enum State { IDLE, CHASE, ATTACK }
var state: State = State.IDLE

func _ready():
	if hurtbox.stats == null:
		push_warning("Enemy sin stats asignado en el Hurtbox")
	else:
		hurtbox.stats.died.connect(_on_died)

	player = get_tree().get_first_node_in_group("player")

func _physics_process(delta):
	if not is_on_floor():
		velocity.y -= gravity * delta

	if attack_timer > 0:
		attack_timer -= delta

	if player == null:
		move_and_slide()
		return

	var distance_to_player = global_position.distance_to(player.global_position)

	match state:
		State.IDLE:
			velocity.x = 0
			velocity.z = 0
			if distance_to_player <= detection_range:
				state = State.CHASE

		State.CHASE:
			if distance_to_player > detection_range * 1.5:
				state = State.IDLE
			elif distance_to_player <= attack_range:
				state = State.ATTACK
			else:
				_move_towards_player(delta)

		State.ATTACK:
			velocity.x = 0
			velocity.z = 0
			if distance_to_player > attack_range * 1.3:
				state = State.CHASE
			elif attack_timer <= 0:
				_attack()

	move_and_slide()

func _move_towards_player(delta):
	nav_agent.target_position = player.global_position

	if nav_agent.is_navigation_finished():
		velocity.x = 0
		velocity.z = 0
		return

	var next_pos = nav_agent.get_next_path_position()
	var direction = (next_pos - global_position)
	direction.y = 0

	if direction.length() < 0.15:
		velocity.x = 0
		velocity.z = 0
		return

	direction = direction.normalized()
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed

	var look_target = global_position + direction
	look_target.y = global_position.y
	look_at(look_target, Vector3.UP)

func _attack():
	is_attacking = true
	attack_timer = attack_cooldown
	hitbox.activate()
	await get_tree().create_timer(0.2).timeout
	hitbox.deactivate()
	is_attacking = false

func _on_died():
	queue_free()
