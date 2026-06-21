extends Node3D

@onready var hp_text = $HPText

var stats: CharacterStats

func setup(character_stats: CharacterStats):
	stats = character_stats
	stats.ensure_initialized()
	_update_text(stats.current_hp, stats.max_hp)
	stats.hp_changed.connect(_on_hp_changed)

func _on_hp_changed(new_hp: int, max_hp: int):
	_update_text(new_hp, max_hp)

func _update_text(current: int, max_hp: int):
	hp_text.text = str(current) + " / " + str(max_hp)
