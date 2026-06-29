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
var _recheck_timer: float = 0.5


func _ready() -> void:
	if item_path != "":
		var item := load(item_path) as ItemData
		if item and label:
			label.text = "%s x%d" % [item.name, amount]
	area.area_entered.connect(_on_area_entered)


func _process(delta: float) -> void:
	rotate_y(delta * 2.0)
	# El servidor reintenta la recogida EN SILENCIO (sin avisos) para cubrir casos
	# en los que area_entered no salta: el dueño ya esta encima, o el botin se
	# libero tras expirar. Si algun jugador encima puede cogerlo, lo coge.
	if not multiplayer.is_server() or _collected:
		return
	_recheck_timer -= delta
	if _recheck_timer <= 0.0:
		_recheck_timer = 0.5
		for a in area.get_overlapping_areas():
			var ent := a.get_parent()
			if ent and ent.is_in_group("player"):
				if LootManager.server_collect(name.to_int(), ent, false):
					_collected = true
					return


func _on_area_entered(other: Area3D) -> void:
	if _collected or not multiplayer.is_server():
		return
	var entity := other.get_parent()
	if entity and entity.is_in_group("player"):
		# Intento "con aviso": si no es tuyo, te avisa. Solo se marca recogido
		# cuando la recogida tiene exito de verdad.
		if LootManager.server_collect(name.to_int(), entity, true):
			_collected = true
