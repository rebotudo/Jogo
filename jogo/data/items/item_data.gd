class_name ItemData
extends Resource

enum ItemType { MATERIAL, WEAPON, ARMOR, CONSUMABLE }
enum Rarity { COMMON, RARE, EPIC, LEGENDARY }
# Slot de equipo. NONE = no se puede equipar (materiales, consumibles).
enum EquipSlot { NONE, WEAPON, HEAD, TORSO, LEGS, FEET }
# Tipo de arma (para restringir que clases pueden usarla). NONE = no es arma.
enum WeaponType { NONE, SWORD, DAGGER, AXE, GREATSWORD, MACE, BOW, STAFF }

@export var id: String = ""
@export var name: String = "Item sin nombre"
@export var description: String = ""
@export var type: ItemType = ItemType.MATERIAL
@export var rarity: Rarity = Rarity.COMMON
@export var icon: Texture2D
@export var stack_max: int = 99

@export_group("Equipo")
@export var equip_slot: EquipSlot = EquipSlot.NONE
@export var weapon_type: WeaponType = WeaponType.NONE
@export var attack_bonus: int = 0
@export var defense_bonus: int = 0
