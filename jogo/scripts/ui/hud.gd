extends Control

@onready var hp_bar = $HPBar
@onready var hp_label = $HPBar/HPLabel

var player_stats: CharacterStats

func setup(stats: CharacterStats):
	if hp_bar == null:
		push_error("hp_bar es null, revisa el nombre del nodo HPBar")
		return
	player_stats = stats
	hp_bar.max_value = player_stats.max_hp
	hp_bar.value = player_stats.current_hp
	hp_label.text = str(player_stats.current_hp) + " / " + str(player_stats.max_hp)
	player_stats.hp_changed.connect(_on_hp_changed)

func _on_hp_changed(new_hp: int, max_hp: int):
	hp_bar.max_value = max_hp
	hp_bar.value = new_hp
	hp_label.text = str(new_hp) + " / " + str(max_hp)
