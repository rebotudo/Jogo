extends Node3D
## LootPickup
## Objeto de botin tirado en el mundo. Lo crea el SERVIDOR al morir un enemigo.
## Gira para llamar la atencion y muestra el nombre del item. Cuando un jugador
## lo toca, es el SERVIDOR quien decide la recogida (modelo autoritativo).

var item_path: String = ""   # ruta del recurso ItemData (.tres)
var amount: int = 1

@onready var area: Area3D = $Area3D
@onready var label: Label3D = $Label3D

var _collected: bool = false


func _ready() -> void:
	if item_path != "":
		var item := load(item_path) as ItemData
		if item and label:
			label.text = "%s x%d" % [item.name, amount]
	area.area_entered.connect(_on_area_entered)


func _process(delta: float) -> void:
	rotate_y(delta * 2.0)


func _on_area_entered(other: Area3D) -> void:
	if _collected:
		return
	# La recogida solo la valida el servidor.
	if not multiplayer.is_server():
		return
	var entity := other.get_parent()
	if entity and entity.is_in_group("player"):
		_collected = true
		LootManager.server_collect(name.to_int(), entity)
