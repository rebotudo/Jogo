class_name LootEntry
extends Resource

@export var item: ItemData
@export var drop_chance: float = 1.0  # 1.0 = 100%, 0.5 = 50%, etc.
@export var min_amount: int = 1
@export var max_amount: int = 1
