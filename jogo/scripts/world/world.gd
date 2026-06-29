extends Node3D
## World
## Punto de entrada de la escena de juego. Su unica responsabilidad por ahora
## es entregarle al NetworkManager el contenedor donde deben vivir los jugadores.
##
## El NetworkManager se encarga del resto: spawnear al jugador local, replicar a
## los demas y despawnear a quien se desconecte. Cada peer ejecuta este _ready,
## asi que esto funciona igual en el host y en los clientes.
##
## Nota: si se ejecuta esta escena directamente desde el editor (sin pasar por
## el menu, es decir sin peer de red), Godot considera al juego como "servidor"
## por defecto (peer id 1), por lo que igualmente aparecera un jugador local.
## Eso permite probar el mundo en solitario sin montar una partida.

@onready var players: Node = $Players
@onready var enemies: Node = $Enemies
@onready var loot: Node = $Loot
@onready var minions: Node = $Minions


const MapDecorator = preload("res://scripts/world/map_decorator.gd")


func _ready() -> void:
	NetworkManager.register_world(players)
	EnemyManager.register_world(enemies)
	LootManager.register_world(loot)
	MinionManager.register_world(minions)
	# Decorado procedural del mapa (cesped, camino, arboles, arena del jefe).
	add_child(MapDecorator.new())
