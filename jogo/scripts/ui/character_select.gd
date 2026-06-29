extends Control
## Menu de seleccion/creacion de personajes. Es la primera pantalla del juego.
## Al pulsar "Jugar", guarda el personaje elegido en Session y pasa al menu de
## host/join.

const MENU_SCENE := "res://scenes/ui/main_menu.tscn"

@onready var char_list: VBoxContainer = $Center/VBox/Scroll/CharList
@onready var name_input: LineEdit = $Center/VBox/CreateRow/NameInput
@onready var class_option: OptionButton = $Center/VBox/CreateRow/ClassOption
@onready var create_button: Button = $Center/VBox/CreateRow/CreateButton
@onready var class_desc: Label = $Center/VBox/ClassDesc
@onready var status: Label = $Center/VBox/Status

var _class_ids: Array = []
var _start_city_ids: Array = []
var city_option: OptionButton = null


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_class_ids = Roles.get_ids()
	for id in _class_ids:
		class_option.add_item(Roles.get_display_name(id))
	class_option.item_selected.connect(_on_class_selected)
	# Selector de ciudad de inicio (estilo Albion): se elige al crear personaje.
	city_option = OptionButton.new()
	for c in Zones.start_cities():
		city_option.add_item("Inicio: " + String(c["name"]))
		_start_city_ids.append(String(c["id"]))
	var row := create_button.get_parent()
	row.add_child(city_option)
	row.move_child(city_option, create_button.get_index())
	create_button.pressed.connect(_on_create_pressed)
	if _class_ids.size() > 0:
		_on_class_selected(0)
	_refresh_list()


func _on_class_selected(index: int) -> void:
	if index >= 0 and index < _class_ids.size():
		var cdata := Roles.get_class_data(_class_ids[index])
		class_desc.text = cdata.get("description", "")


func _on_create_pressed() -> void:
	var nm := name_input.text.strip_edges()
	if nm == "":
		status.text = "Escribe un nombre."
		return
	var idx := class_option.selected
	if idx < 0 or idx >= _class_ids.size():
		status.text = "Elige una clase."
		return
	var city_id := ""
	if city_option != null and city_option.selected >= 0 and city_option.selected < _start_city_ids.size():
		city_id = _start_city_ids[city_option.selected]
	var ch := SaveManager.create_character(nm, _class_ids[idx], city_id)
	if ch.is_empty():
		status.text = "Ese nombre ya existe o no es valido."
		return
	name_input.text = ""
	status.text = ""
	_refresh_list()


func _refresh_list() -> void:
	for c in char_list.get_children():
		char_list.remove_child(c)
		c.queue_free()
	var chars := SaveManager.list_characters()
	if chars.is_empty():
		var lbl := Label.new()
		lbl.text = "(No tienes personajes todavia. Crea uno abajo.)"
		char_list.add_child(lbl)
		return
	for ch in chars:
		var row := HBoxContainer.new()
		var lbl := Label.new()
		lbl.custom_minimum_size = Vector2(340, 0)
		lbl.text = "%s  -  %s  (Nivel %d)" % [
			ch.get("name", "?"),
			Roles.get_display_name(ch.get("class_id", "")),
			int(ch.get("level", 1)),
		]
		row.add_child(lbl)
		var play_btn := Button.new()
		play_btn.text = "Jugar"
		play_btn.pressed.connect(_on_play.bind(ch))
		row.add_child(play_btn)
		var del_btn := Button.new()
		del_btn.text = "Eliminar"
		del_btn.pressed.connect(_on_delete.bind(ch.get("name", "")))
		row.add_child(del_btn)
		char_list.add_child(row)


func _on_play(ch: Dictionary) -> void:
	Session.selected_character = ch
	get_tree().change_scene_to_file(MENU_SCENE)


func _on_delete(char_name: String) -> void:
	SaveManager.delete_character(char_name)
	_refresh_list()
