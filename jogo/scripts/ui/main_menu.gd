extends Control
## Menu principal: hostear o unirse a una partida.

const WORLD_SCENE := "res://scenes/world/world.tscn"

@onready var ip_input: LineEdit = $Center/VBox/IPInput
@onready var status: Label = $Center/VBox/Status
@onready var host_button: Button = $Center/VBox/HostButton
@onready var join_button: Button = $Center/VBox/JoinButton

func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)

func _on_host_pressed():
	if NetworkManager.host_game():
		get_tree().change_scene_to_file(WORLD_SCENE)
	else:
		status.text = "No se pudo crear el servidor."

func _on_join_pressed():
	var ip := ip_input.text.strip_edges()
	if ip == "":
		ip = "127.0.0.1"
	status.text = "Conectando a %s..." % ip
	# Esperamos a estar conectados ANTES de cargar el mundo.
	multiplayer.connected_to_server.connect(_on_connected, CONNECT_ONE_SHOT)
	multiplayer.connection_failed.connect(_on_failed, CONNECT_ONE_SHOT)
	if not NetworkManager.join_game(ip):
		status.text = "No se pudo iniciar el cliente."

func _on_connected():
	get_tree().change_scene_to_file(WORLD_SCENE)

func _on_failed():
	status.text = "Conexion fallida. Esta el host activo?"
