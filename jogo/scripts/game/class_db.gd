extends Node
## ClassDB
## Autoload con la definicion de las clases jugables. Cada clase define sus stats
## base (nivel 1), que tipos de arma puede equipar y su arma inicial. El campo
## "abilities" queda preparado para el futuro arbol de habilidades.
##
## Tipos de arma (ItemData.WeaponType):
##   SWORD=1 DAGGER=2 AXE=3 GREATSWORD=4 MACE=5 BOW=6 STAFF=7

const CLASSES := {
	"guerrero": {
		"name": "Guerrero",
		"description": "Cuerpo a cuerpo equilibrado: buen daño y aguante.",
		"max_hp": 120, "max_mp": 20, "attack": 12, "defense": 8, "speed": 5.0,
		"allowed_weapons": [1, 3, 4],
		"starting_weapon": "res://data/items/iron_sword.tres",
		"combo": [{"mult": 1.0, "cd": 0.45}, {"mult": 1.0, "cd": 0.45}, {"mult": 1.7, "cd": 0.85}],
		"abilities": [
			{"name": "Furia Berserker", "type": "buff", "mana": 12, "cooldown": 12.0, "duration": 6.0, "atk_pct": 0.6, "def_pct": -0.4},
			{"name": "Sed de Sangre", "type": "buff", "mana": 10, "cooldown": 14.0, "duration": 8.0, "lifesteal": 0.25},
			{"name": "Pisotón Sísmico", "type": "aoe_stun", "mana": 14, "cooldown": 10.0, "radius": 4.0, "damage_mult": 0.8, "stun": 2.0},
			{"name": "Apocalipsis Berserker", "type": "buff", "mana": 30, "cooldown": 60.0, "duration": 10.0, "atk_pct": 1.0, "cc_immune": true, "apocalipsis": true},
		],
	},
	"tanque": {
		"name": "Tanque",
		"description": "Muralla del equipo: mucha vida y defensa, poco daño.",
		"max_hp": 180, "max_mp": 10, "attack": 8, "defense": 14, "speed": 4.5,
		"allowed_weapons": [1, 5],
		"starting_weapon": "res://data/items/weapons/iron_mace.tres",
		"combo": [{"mult": 1.0, "cd": 0.7}, {"mult": 1.5, "cd": 0.95}],
		"abilities": [
			{"name": "Muro de Acero", "type": "buff", "mana": 12, "cooldown": 14.0, "duration": 5.0, "dmg_taken_mult": 0.5},
			{"name": "Guardia Protectora", "type": "guard", "mana": 10, "cooldown": 16.0, "duration": 6.0, "fraction": 0.4},
			{"name": "Provocación", "type": "taunt", "mana": 8, "cooldown": 10.0, "radius": 8.0, "duration": 3.0},
			{"name": "Bastión Imperecedero", "type": "bastion", "mana": 35, "cooldown": 70.0, "duration": 8.0, "radius": 7.0, "self_dmg_mult": 0.25, "ally_dmg_mult": 0.6, "regen": 12},
		],
	},
	"paladin": {
		"name": "Paladín",
		"description": "Híbrido defensa/soporte: resiste y apoya.",
		"max_hp": 150, "max_mp": 40, "attack": 10, "defense": 11, "speed": 4.8,
		"allowed_weapons": [1, 5],
		"starting_weapon": "res://data/items/weapons/iron_mace.tres",
		"combo": [{"mult": 1.0, "cd": 0.55}, {"mult": 1.0, "cd": 0.55}, {"mult": 1.6, "cd": 0.9}],
		"abilities": [
			{"name": "Luz Consagrada", "type": "smite_heal", "mana": 12, "cooldown": 5.0, "range": 6.0, "damage_mult": 1.5, "heal_radius": 10.0, "heal_amount": 25},
			{"name": "Escudo Divino", "type": "buff", "mana": 14, "cooldown": 14.0, "duration": 6.0, "shield": 120},
			{"name": "Martillo del Juicio", "type": "hammer", "mana": 16, "cooldown": 9.0, "range": 14.0, "damage_mult": 1.6, "stun": 2.0},
			{"name": "Ascensión Sagrada", "type": "ascension", "mana": 40, "cooldown": 80.0, "duration": 10.0, "atk_pct": 0.4, "def_pct": 0.5, "heal_radius": 12.0, "heal_amount": 15},
		],
	},
	"asesino": {
		"name": "Asesino",
		"description": "Daño explosivo y movilidad, pero frágil.",
		"max_hp": 90, "max_mp": 20, "attack": 16, "defense": 4, "speed": 6.0,
		"allowed_weapons": [2, 1],
		"starting_weapon": "res://data/items/weapons/rusty_dagger.tres",
		"combo": [{"mult": 0.75, "cd": 0.25}, {"mult": 0.75, "cd": 0.25}, {"mult": 0.75, "cd": 0.25}, {"mult": 1.4, "cd": 0.5}],
		"abilities": [
			{"name": "Dash Sombrío", "type": "dash", "mana": 8, "cooldown": 5.0, "distance": 7.0},
			{"name": "Desvanecerse", "type": "buff", "mana": 14, "cooldown": 16.0, "duration": 5.0, "invis": true},
			{"name": "Veneno Paralizante", "type": "buff", "mana": 10, "cooldown": 14.0, "duration": 8.0, "poison_attacks": true},
			{"name": "Danza de las Sombras", "type": "shadow_dance", "mana": 30, "cooldown": 45.0, "radius": 8.0, "hit_mult": 1.2, "final_mult": 3.5},
		],
	},
	"arquero": {
		"name": "Arquero",
		"description": "Daño físico a distancia.",
		"max_hp": 100, "max_mp": 25, "attack": 13, "defense": 5, "speed": 5.5,
		"allowed_weapons": [6, 2],
		"starting_weapon": "res://data/items/weapons/hunting_bow.tres",
		"combo": [{"mult": 0.85, "cd": 0.3}, {"mult": 0.85, "cd": 0.3}, {"mult": 1.3, "cd": 0.55}],
		"abilities": [
			{"name": "Flecha Perforante", "type": "pierce_arrow", "mana": 12, "cooldown": 5.0, "damage_mult": 1.8, "speed": 36.0},
			{"name": "Disparo Rápido", "type": "burst", "mana": 14, "cooldown": 8.0, "count": 5, "damage_mult": 0.7, "speed": 34.0, "spread": 0.12},
			{"name": "Trampa de Caza", "type": "trap", "mana": 12, "cooldown": 12.0, "radius": 2.0, "stun": 3.0, "lifetime": 12.0, "damage_mult": 1.0},
			{"name": "Lluvia de Flechas", "type": "storm", "mana": 38, "cooldown": 50.0, "duration": 4.0, "radius": 9.0, "tick_mult": 0.7, "color": [0.85, 0.72, 0.4, 0.22]},
		],
	},
	"mago": {
		"name": "Mago",
		"description": "Gran daño mágico a distancia, muy frágil.",
		"max_hp": 80, "max_mp": 80, "attack": 14, "defense": 3, "speed": 4.8,
		"allowed_weapons": [7],
		"starting_weapon": "res://data/items/weapons/apprentice_staff.tres",
		"combo": [{"mult": 1.0, "cd": 0.5}, {"mult": 1.0, "cd": 0.5}, {"mult": 1.5, "cd": 0.75}],
		"abilities": [
			{"name": "Bola de Fuego", "type": "projectile_strong", "mana": 15, "cooldown": 5.0, "damage_mult": 1.8, "visual": "magic", "speed": 24.0, "explode_radius": 3.5},
			{"name": "Nova de Hielo", "type": "aoe_stun", "mana": 16, "cooldown": 10.0, "radius": 6.0, "damage_mult": 0.6, "stun": 1.8, "color": [0.4, 0.7, 1.0, 0.35]},
			{"name": "Rayo Arcano", "type": "beam", "mana": 18, "cooldown": 6.0, "range": 18.0, "damage_mult": 2.2},
			{"name": "Tormenta Elemental", "type": "storm", "mana": 35, "cooldown": 45.0, "duration": 6.0, "radius": 8.0, "tick_mult": 0.6},
		],
	},
	"curandero": {
		"name": "Curandero",
		"description": "Soporte y curación. Mantiene vivo al equipo.",
		"max_hp": 95, "max_mp": 70, "attack": 8, "defense": 5, "speed": 4.8,
		"allowed_weapons": [7, 5],
		"starting_weapon": "res://data/items/weapons/apprentice_staff.tres",
		"combo": [{"mult": 1.0, "cd": 0.6}, {"mult": 1.4, "cd": 0.85}],
		"abilities": [
			{"name": "Sanación Rápida", "type": "heal_single", "mana": 12, "cooldown": 4.0, "radius": 14.0, "amount": 70},
			{"name": "Renovación", "type": "hot_party", "mana": 16, "cooldown": 10.0, "radius": 12.0, "per_sec": 12, "duration": 6.0},
			{"name": "Purificación", "type": "purify", "mana": 14, "cooldown": 9.0, "radius": 12.0, "amount": 25},
			{"name": "Milagro Celestial", "type": "miracle", "mana": 40, "cooldown": 80.0, "radius": 12.0, "immune_duration": 4.0},
		],
	},
	"nigromante": {
		"name": "Nigromante",
		"description": "Daño mágico sostenido y control.",
		"max_hp": 90, "max_mp": 75, "attack": 12, "defense": 4, "speed": 4.8,
		"allowed_weapons": [7, 2],
		"starting_weapon": "res://data/items/weapons/apprentice_staff.tres",
		"combo": [{"mult": 1.0, "cd": 0.5}, {"mult": 1.4, "cd": 0.7}],
		"abilities": [
			{"name": "Drenar Vida", "type": "drain", "mana": 12, "cooldown": 5.0, "range": 16.0, "damage_mult": 1.8, "drain": 0.5},
			{"name": "Invocar Esqueleto", "type": "summon", "mana": 18, "cooldown": 12.0, "single": true, "dmg_mult": 0.8, "lifetime": 30.0, "minion_hp": 110},
			{"name": "Maldición de Debilidad", "type": "curse", "mana": 14, "cooldown": 10.0, "radius": 7.0, "duration": 6.0, "def_reduction": 6},
			{"name": "Ejército de los Condenados", "type": "summon", "mana": 40, "cooldown": 90.0, "count": 4, "dmg_mult": 0.6, "lifetime": 18.0, "minion_hp": 50},
		],
	},
}


func get_ids() -> Array:
	return CLASSES.keys()


func has_class(id: String) -> bool:
	return CLASSES.has(id)


func get_class_data(id: String) -> Dictionary:
	return CLASSES.get(id, {})


func get_display_name(id: String) -> String:
	var c: Dictionary = CLASSES.get(id, {})
	return c.get("name", id)


# Devuelve true si la clase puede equipar ese tipo de arma.
func allows_weapon(id: String, weapon_type: int) -> bool:
	var c: Dictionary = CLASSES.get(id, {})
	var allowed: Array = c.get("allowed_weapons", [])
	return weapon_type in allowed
