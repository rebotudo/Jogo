extends Node
## Session
## Autoload que guarda, durante la sesion actual, el personaje elegido en el menu
## antes de entrar a la partida. El jugador lo lee al spawnear para configurarse.

var selected_character: Dictionary = {}


func has_character() -> bool:
	return not selected_character.is_empty()
