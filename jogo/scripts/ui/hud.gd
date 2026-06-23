extends Control

@onready var hp_bar = $HPBar
@onready var hp_label = $HPBar/HPLabel
@onready var death_label = $DeathLabel
@onready var pickup_label = $PickupLabel
@onready var inventory_panel = $InventoryPanel
@onready var stats_label = $InventoryPanel/Margin/VBox/StatsLabel
@onready var equipped_list = $InventoryPanel/Margin/VBox/EquippedList
@onready var items_list = $InventoryPanel/Margin/VBox/Scroll/ItemsList

var player_stats: CharacterStats
var local_player: Node = null
var _pickup_token: int = 0

func setup(stats: CharacterStats, player: Node = null):
	if hp_bar == null:
		push_error("hp_bar es null, revisa el nombre del nodo HPBar")
		return
	player_stats = stats
	local_player = player
	hp_bar.max_value = player_stats.max_hp
	hp_bar.value = player_stats.current_hp
	hp_label.text = str(player_stats.current_hp) + " / " + str(player_stats.max_hp)
	player_stats.hp_changed.connect(_on_hp_changed)

func _on_hp_changed(new_hp: int, max_hp: int):
	hp_bar.max_value = max_hp
	hp_bar.value = new_hp
	hp_label.text = str(new_hp) + " / " + str(max_hp)

func show_death(seconds: float):
	if death_label:
		death_label.text = "HAS MUERTO\nReapareciendo en %d..." % int(ceil(seconds))
		death_label.visible = true

func hide_death():
	if death_label:
		death_label.visible = false

func show_pickup(text: String):
	if pickup_label == null:
		return
	pickup_label.text = text
	pickup_label.visible = true
	_pickup_token += 1
	var my := _pickup_token
	await get_tree().create_timer(2.5).timeout
	# Solo ocultamos si no llego otra recogida mas nueva mientras tanto.
	if my == _pickup_token and pickup_label:
		pickup_label.visible = false


# --- Inventario -----------------------------------------------------------------

func is_inventory_open() -> bool:
	return inventory_panel != null and inventory_panel.visible


# Abre/cierra el panel. Devuelve true si queda abierto.
func toggle_inventory() -> bool:
	if inventory_panel == null:
		return false
	inventory_panel.visible = not inventory_panel.visible
	if inventory_panel.visible and local_player:
		update_inventory(local_player.inventory, local_player.equipment)
	return inventory_panel.visible


# Reconstruye las listas del inventario y el equipo.
func update_inventory(inv: Array, equip: Dictionary):
	if items_list == null:
		return
	if stats_label and player_stats:
		stats_label.text = "Ataque: %d    Defensa: %d" % [player_stats.attack, player_stats.defense]

	# Equipo
	_clear(equipped_list)
	for slot in ["weapon", "armor"]:
		var row := HBoxContainer.new()
		var lbl := Label.new()
		lbl.custom_minimum_size = Vector2(280, 0)
		var path: String = equip.get(slot, "")
		if path != "":
			var item := load(path) as ItemData
			lbl.text = "%s: %s" % [_slot_name(slot), item.name if item else "?"]
			row.add_child(lbl)
			var btn := Button.new()
			btn.text = "Quitar"
			if local_player:
				btn.pressed.connect(local_player.request_unequip.bind(slot))
			row.add_child(btn)
		else:
			lbl.text = "%s: (vacio)" % _slot_name(slot)
			row.add_child(lbl)
		equipped_list.add_child(row)

	# Mochila
	_clear(items_list)
	for entry in inv:
		var path: String = entry["path"]
		var amount: int = entry["amount"]
		var item := load(path) as ItemData
		var row := HBoxContainer.new()
		var lbl := Label.new()
		lbl.custom_minimum_size = Vector2(280, 0)
		lbl.text = "%s x%d" % [item.name if item else path, amount]
		row.add_child(lbl)
		if item and (item.type == ItemData.ItemType.WEAPON or item.type == ItemData.ItemType.ARMOR):
			var btn := Button.new()
			btn.text = "Equipar"
			if local_player:
				btn.pressed.connect(local_player.request_equip.bind(path))
			row.add_child(btn)
		items_list.add_child(row)


func _clear(node: Node):
	if node == null:
		return
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


func _slot_name(slot: String) -> String:
	return "Arma" if slot == "weapon" else "Armadura"
