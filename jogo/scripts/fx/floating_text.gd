class_name FloatingText
extends Label3D
## Texto flotante (numeros de daño/curación). Aparece sobre el objetivo, sube y
## se desvanece. Se usa desde cualquier sitio con FloatingText.spawn(...).

# Ajustes activables desde el menu de opciones.
static var enabled: bool = true        # mostrar/ocultar numeros de daño
static var shake_enabled: bool = true  # temblor de pantalla

# Crea un texto flotante en el mundo en la posicion dada.
static func spawn(host: Node, pos: Vector3, txt: String, color: Color = Color.WHITE, big: bool = false) -> void:
	if host == null or not enabled:
		return
	var n := FloatingText.new()
	n.text = txt
	n.modulate = color
	n.font_size = 44 if big else 30
	n.outline_size = 8
	n.outline_modulate = Color(0, 0, 0, 0.9)
	n.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	n.no_depth_test = true
	n.fixed_size = true
	n.pixel_size = 0.006
	host.add_child(n)
	n.global_position = pos
	# Pequeño desplazamiento horizontal aleatorio para que no se solapen.
	n.global_position += Vector3(randf_range(-0.4, 0.4), 0.0, randf_range(-0.4, 0.4))
	n._animate(big)


func _animate(big: bool) -> void:
	var rise: float = 1.6 if big else 1.1
	var dur: float = 0.85 if big else 0.7
	# Pequeño "pop" de escala al aparecer.
	scale = Vector3.ONE * (0.4 if big else 0.6)
	var t := create_tween()
	t.tween_property(self, "scale", Vector3.ONE * (1.3 if big else 1.0), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(self, "global_position:y", global_position.y + rise, dur)
	t.tween_property(self, "modulate:a", 0.0, dur * 0.5)
	t.tween_callback(queue_free)
