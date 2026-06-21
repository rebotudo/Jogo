class_name CharacterStats
extends Resource

@export var max_hp: int = 100
@export var max_mp: int = 50
@export var attack: int = 10
@export var defense: int = 5
@export var speed: float = 5.0
@export var level: int = 1
@export var experience: int = 0
@export var exp_to_next_level: int = 100

var current_hp: int = -1
var current_mp: int = -1

signal hp_changed(new_hp: int, max_hp: int)
signal mp_changed(new_mp: int, max_mp: int)
signal died
signal leveled_up(new_level: int)

func ensure_initialized():
	if current_hp == -1:
		current_hp = max_hp
	if current_mp == -1:
		current_mp = max_mp

func take_damage(amount: int):
	ensure_initialized()
	var real_damage = max(amount - defense, 1)
	current_hp = max(current_hp - real_damage, 0)
	hp_changed.emit(current_hp, max_hp)
	if current_hp == 0:
		died.emit()

func heal(amount: int):
	ensure_initialized()
	current_hp = min(current_hp + amount, max_hp)
	hp_changed.emit(current_hp, max_hp)

func use_mp(amount: int) -> bool:
	ensure_initialized()
	if current_mp < amount:
		return false
	current_mp -= amount
	mp_changed.emit(current_mp, max_mp)
	return true

func gain_experience(amount: int):
	experience += amount
	if experience >= exp_to_next_level:
		_level_up()

func _level_up():
	level += 1
	experience -= exp_to_next_level
	exp_to_next_level = int(exp_to_next_level * 1.5)
	max_hp += 20
	max_mp += 10
	attack += 3
	defense += 2
	current_hp = max_hp
	current_mp = max_mp
	leveled_up.emit(level)
