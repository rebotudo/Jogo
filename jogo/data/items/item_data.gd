class_name ItemData
extends Resource

enum ItemType { MATERIAL, WEAPON, ARMOR, CONSUMABLE }
enum Rarity { COMMON, RARE, EPIC, LEGENDARY }

@export var id: String = ""
@export var name: String = "Item sin nombre"
@export var description: String = ""
@export var type: ItemType = ItemType.MATERIAL
@export var rarity: Rarity = Rarity.COMMON
@export var icon: Texture2D
@export var stack_max: int = 99

@export_group("Bonos de equipo (solo si type es WEAPON o ARMOR)")
@export var attack_bonus: int = 0
@export var defense_bonus: int = 0
