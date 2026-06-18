extends CharacterBody3D

@export var speed: float = 5.0
@export var jump_force: float = 5.0

@onready var spring_arm = $SpringArm3D
@onready var camera = $SpringArm3D/Camera3D

var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
var mouse_sensitivity = 0.003

func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event):
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * mouse_sensitivity)
		spring_arm.rotate_x(-event.relative.y * mouse_sensitivity)
		spring_arm.rotation.x = clamp(spring_arm.rotation.x, -0.8, 0.5)
	if event.is_action_pressed("open_menu"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _physics_process(delta):
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

	move_and_slide()
