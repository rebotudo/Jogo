extends Node
## SaveManager
## Autoload que guarda los personajes en disco (user://characters.json).
## Cada personaje: { name, class_id, level, exp, inventory, equipment }.
## Los personajes son locales a la maquina del jugador.

const PATH := "user://characters.json"


func _load_all() -> Dictionary:
	if not FileAccess.file_exists(PATH):
		return {}
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return {}
	var txt := f.get_as_text()
	f.close()
	var data: Variant = JSON.parse_string(txt)
	if typeof(data) == TYPE_DICTIONARY:
		return data
	return {}


func _save_all(all: Dictionary) -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		push_error("No se pudo escribir el guardado de personajes")
		return
	f.store_string(JSON.stringify(all, "\t"))
	f.close()


# Devuelve la lista de personajes (diccionarios).
func list_characters() -> Array:
	return _load_all().values()


func has_character(char_name: String) -> bool:
	return _load_all().has(char_name)


func get_character(char_name: String) -> Dictionary:
	return _load_all().get(char_name, {})


# Crea un personaje nuevo con el arma inicial de su clase. Devuelve {} si el
# nombre ya existe o la clase no es valida.
func create_character(char_name: String, class_id: String, start_city: String = "") -> Dictionary:
	char_name = char_name.strip_edges()
	if char_name == "" or not Roles.has_class(class_id):
		return {}
	var all := _load_all()
	if all.has(char_name):
		return {}
	var cdata := Roles.get_class_data(class_id)
	var equipment := {"weapon": "", "head": "", "torso": "", "legs": "", "feet": ""}
	var start_weapon: String = cdata.get("starting_weapon", "")
	if start_weapon != "":
		equipment["weapon"] = start_weapon  # nace con su arma ya equipada
	var ch := {
		"name": char_name,
		"class_id": class_id,
		"start_city": start_city,
		"level": 1,
		"exp": 0,
		"inventory": [],
		"equipment": equipment,
	}
	all[char_name] = ch
	_save_all(all)
	return ch


# Inserta o actualiza un personaje (por nombre).
func save_character(ch: Dictionary) -> void:
	if not ch.has("name"):
		return
	var all := _load_all()
	all[ch["name"]] = ch
	_save_all(all)


func delete_character(char_name: String) -> void:
	var all := _load_all()
	all.erase(char_name)
	_save_all(all)
