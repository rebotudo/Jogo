extends Control

@onready var hp_bar = $BottomBar/HBox/Bars/HPBar
@onready var hp_label = $BottomBar/HBox/Bars/HPBar/HPLabel
@onready var mp_bar = $BottomBar/HBox/Bars/MPBar
@onready var mp_label = $BottomBar/HBox/Bars/MPBar/MPLabel
@onready var death_label = $DeathLabel
@onready var pickup_label = $PickupLabel
@onready var charge_bar = $ChargeBar
@onready var level_label = $BottomBar/HBox/Portrait/LevelLabel
@onready var exp_bar = $BottomBar/HBox/Bars/ExpBar
@onready var exp_label = $BottomBar/HBox/Bars/ExpBar/ExpLabel
@onready var inventory_panel = $InventoryPanel
@onready var stats_label = $InventoryPanel/Margin/VBox/StatsLabel
@onready var equipped_list = $InventoryPanel/Margin/VBox/EquippedList
@onready var items_list = $InventoryPanel/Margin/VBox/Scroll/ItemsList
@onready var party_panel = $PartyPanel
@onready var party_members_list = $PartyPanel/Margin/VBox/MembersList
@onready var party_others_list = $PartyPanel/Margin/VBox/Scroll/OthersList
@onready var party_leave_button = $PartyPanel/Margin/VBox/LeaveButton
@onready var party_invite_box = $PartyPanel/Margin/VBox/InviteBox
@onready var party_invite_label = $PartyPanel/Margin/VBox/InviteBox/InviteLabel
@onready var party_accept_button = $PartyPanel/Margin/VBox/InviteBox/AcceptButton
@onready var party_decline_button = $PartyPanel/Margin/VBox/InviteBox/DeclineButton
@onready var party_frames = $PartyFrames
@onready var buff_list = $BuffList

var _buff_widgets: Array = []  # [{time_left, total, bar}]

# Menu de pausa (construido por codigo).
var pause_menu: Control = null
var options_panel: Control = null
var dmg_check: CheckButton = null
var shake_check: CheckButton = null

var player_stats: CharacterStats
var local_player: Node = null
var _pickup_token: int = 0

# Slots de habilidad (Q/E/R/F = indices 0..3): etiquetas, overlays y textos de cooldown.
var _slot_keys: Array = []
var _slot_overlays: Array = []
var _slot_cds: Array = []

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

func set_level(level: int, exp: int, exp_to_next: int):
	if level_label:
		level_label.text = str(level)
		level_label.tooltip_text = "Nivel %d" % level
	if exp_bar:
		if level >= 200:
			exp_bar.max_value = 1
			exp_bar.value = 1
		else:
			exp_bar.max_value = max(exp_to_next, 1)
			exp_bar.value = exp
	if exp_label:
		exp_label.text = "MÁX" if level >= 200 else "%d / %d" % [exp, exp_to_next]

func set_mp(current: int, max_mp: int):
	if mp_bar:
		mp_bar.max_value = max(max_mp, 1)
		mp_bar.value = current
	if mp_label:
		mp_label.text = "%d / %d" % [current, max_mp]

# Marca que slots tienen habilidad (dorado) y cuales estan vacios (gris).
func set_abilities(abilities: Array):
	for i in _slot_keys.size():
		var lbl: Label = _slot_keys[i]
		if i < abilities.size():
			lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
		else:
			lbl.add_theme_color_override("font_color", Color(0.45, 0.45, 0.45))


# Muestra el cooldown de un slot (overlay oscuro + segundos). remaining<=0 lo limpia.
func set_cooldown(slot: int, remaining: float, _total: float):
	if slot < 0 or slot >= _slot_overlays.size():
		return
	var ov: ColorRect = _slot_overlays[slot]
	var cd: Label = _slot_cds[slot]
	if remaining <= 0.05:
		ov.visible = false
	else:
		ov.visible = true
		cd.text = str(int(ceil(remaining)))


# Indicador de carga del arco. ratio < 0 lo oculta.
func set_charge(ratio: float):
	if charge_bar == null:
		return
	if ratio < 0.0:
		charge_bar.visible = false
	else:
		charge_bar.visible = true
		charge_bar.value = clampf(ratio, 0.0, 1.0)

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
	for slot in ["weapon", "head", "torso", "legs", "feet"]:
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
		if item and item.equip_slot != ItemData.EquipSlot.NONE:
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
	match slot:
		"weapon": return "Arma"
		"head": return "Cabeza"
		"torso": return "Tronco"
		"legs": return "Piernas"
		"feet": return "Pies"
	return slot


# --- Barras de buffs activos ----------------------------------------------------

func set_buffs(buffs: Array):
	if buff_list == null:
		return
	_clear(buff_list)
	_buff_widgets = []
	for b in buffs:
		var box := VBoxContainer.new()
		box.custom_minimum_size = Vector2(120, 0)
		var lbl := Label.new()
		lbl.text = String(b.get("name", ""))
		lbl.add_theme_font_size_override("font_size", 12)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(lbl)
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(0, 8)
		bar.show_percentage = false
		bar.max_value = 1.0
		var total := float(b.get("total", 1.0))
		var tl := float(b.get("time_left", 0.0))
		bar.value = clampf(tl / maxf(total, 0.01), 0.0, 1.0)
		box.add_child(bar)
		buff_list.add_child(box)
		_buff_widgets.append({"time_left": tl, "total": total, "bar": bar})


func _process(delta: float) -> void:
	# Cuenta atras local de las barras de buff (entre sincronizaciones del servidor).
	if _buff_widgets.is_empty():
		return
	for w in _buff_widgets:
		w["time_left"] = w["time_left"] - delta
		if is_instance_valid(w["bar"]):
			w["bar"].value = clampf(w["time_left"] / maxf(w["total"], 0.01), 0.0, 1.0)


# --- Grupo (party) --------------------------------------------------------------

func _ready() -> void:
	# Referencias de los slots de habilidad (Q/E/R/F).
	for n in ["SlotQ", "SlotW", "SlotE", "SlotR"]:
		var base: String = "BottomBar/HBox/Abilities/" + str(n)
		_slot_keys.append(get_node(base + "/Label"))
		_slot_overlays.append(get_node(base + "/CDOverlay"))
		_slot_cds.append(get_node(base + "/CDOverlay/CDLabel"))
	PartyManager.party_changed.connect(_on_party_changed)
	PartyManager.invite_received.connect(_on_invite_received)
	PartyManager.player_list_received.connect(_on_player_list)
	party_leave_button.pressed.connect(func(): PartyManager.leave_party())
	party_accept_button.pressed.connect(_on_accept_invite)
	party_decline_button.pressed.connect(_on_decline_invite)
	_on_party_changed()
	_build_pause_menu()


# --- Menu de pausa (Escape) -----------------------------------------------------

func _build_pause_menu() -> void:
	pause_menu = Control.new()
	pause_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_menu.mouse_filter = Control.MOUSE_FILTER_STOP
	pause_menu.visible = false
	add_child(pause_menu)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_menu.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_menu.add_child(center)

	var vb := VBoxContainer.new()
	vb.custom_minimum_size = Vector2(300, 0)
	vb.add_theme_constant_override("separation", 14)
	center.add_child(vb)

	var title := Label.new()
	title.text = "PAUSA"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	vb.add_child(title)

	var b_play := Button.new()
	b_play.text = "Jugar"
	b_play.custom_minimum_size = Vector2(0, 46)
	vb.add_child(b_play)
	b_play.pressed.connect(func(): toggle_pause())

	var b_opt := Button.new()
	b_opt.text = "Opciones"
	b_opt.custom_minimum_size = Vector2(0, 46)
	vb.add_child(b_opt)
	b_opt.pressed.connect(_open_options)

	var b_exit := Button.new()
	b_exit.text = "Salir"
	b_exit.custom_minimum_size = Vector2(0, 46)
	vb.add_child(b_exit)
	b_exit.pressed.connect(_exit_to_select)

	# --- Sub-panel de opciones ---
	options_panel = Control.new()
	options_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	options_panel.visible = false
	pause_menu.add_child(options_panel)

	var odim := ColorRect.new()
	odim.color = Color(0, 0, 0, 0.85)
	odim.set_anchors_preset(Control.PRESET_FULL_RECT)
	options_panel.add_child(odim)

	var ocenter := CenterContainer.new()
	ocenter.set_anchors_preset(Control.PRESET_FULL_RECT)
	options_panel.add_child(ocenter)

	var ovb := VBoxContainer.new()
	ovb.custom_minimum_size = Vector2(380, 0)
	ovb.add_theme_constant_override("separation", 18)
	ocenter.add_child(ovb)

	var otitle := Label.new()
	otitle.text = "OPCIONES"
	otitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	otitle.add_theme_font_size_override("font_size", 32)
	ovb.add_child(otitle)

	var row := HBoxContainer.new()
	var clbl := Label.new()
	clbl.text = "Mostrar números de daño"
	clbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(clbl)
	dmg_check = CheckButton.new()
	dmg_check.button_pressed = FloatingText.enabled
	row.add_child(dmg_check)
	dmg_check.toggled.connect(func(on): FloatingText.enabled = on)
	ovb.add_child(row)

	var srow := HBoxContainer.new()
	var slbl := Label.new()
	slbl.text = "Temblor de pantalla"
	slbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	srow.add_child(slbl)
	shake_check = CheckButton.new()
	shake_check.button_pressed = FloatingText.shake_enabled
	srow.add_child(shake_check)
	shake_check.toggled.connect(func(on): FloatingText.shake_enabled = on)
	ovb.add_child(srow)

	var b_back := Button.new()
	b_back.text = "Volver"
	b_back.custom_minimum_size = Vector2(0, 42)
	ovb.add_child(b_back)
	b_back.pressed.connect(_close_options)


func is_pause_open() -> bool:
	return pause_menu != null and pause_menu.visible


func toggle_pause() -> bool:
	if pause_menu == null:
		return false
	pause_menu.visible = not pause_menu.visible
	if not pause_menu.visible and options_panel != null:
		options_panel.visible = false
	_refresh_player_mouse()
	return pause_menu.visible


func _refresh_player_mouse() -> void:
	if local_player != null and local_player.has_method("refresh_mouse_mode"):
		local_player.refresh_mouse_mode()


func _open_options() -> void:
	if options_panel != null:
		if dmg_check != null:
			dmg_check.button_pressed = FloatingText.enabled
		if shake_check != null:
			shake_check.button_pressed = FloatingText.shake_enabled
		options_panel.visible = true


func _close_options() -> void:
	if options_panel != null:
		options_panel.visible = false


func _exit_to_select() -> void:
	# Cortamos la conexion multijugador y volvemos a la eleccion de personajes.
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer = null
	get_tree().change_scene_to_file("res://scenes/ui/character_select.tscn")


func is_party_open() -> bool:
	return party_panel != null and party_panel.visible


func toggle_party() -> bool:
	if party_panel == null:
		return false
	party_panel.visible = not party_panel.visible
	if party_panel.visible:
		_on_party_changed()
		PartyManager.request_player_list()
	return party_panel.visible


func _on_party_changed() -> void:
	if party_members_list == null:
		return
	_clear(party_members_list)
	var members: Array = PartyManager.my_members
	if members.is_empty():
		var lbl := Label.new()
		lbl.text = "(Vas solo)"
		party_members_list.add_child(lbl)
		party_leave_button.visible = false
	else:
		for m in members:
			var lbl := Label.new()
			lbl.text = "- %s" % m.get("name", "?")
			party_members_list.add_child(lbl)
		party_leave_button.visible = true
	if party_panel.visible:
		PartyManager.request_player_list()
	_update_party_frames()


# Marcos de grupo (siempre visibles cuando estas en grupo): nombre + barra de vida.
func _update_party_frames() -> void:
	if party_frames == null:
		return
	_clear(party_frames)
	var my_id := multiplayer.get_unique_id()
	var shown := 0
	for m in PartyManager.my_members:
		if int(m.get("id", -1)) == my_id:
			continue  # tu propia vida ya esta abajo; aqui solo los compañeros
		var row := VBoxContainer.new()
		var lbl := Label.new()
		lbl.text = String(m.get("name", "?"))
		row.add_child(lbl)
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(190, 14)
		bar.show_percentage = false
		bar.max_value = maxi(int(m.get("max", 1)), 1)
		bar.value = int(m.get("current", 0))
		row.add_child(bar)
		party_frames.add_child(row)
		shown += 1
	party_frames.visible = shown > 0


func _on_player_list(list: Array) -> void:
	if party_others_list == null:
		return
	_clear(party_others_list)
	var my_id := multiplayer.get_unique_id()
	var member_ids: Array = []
	for m in PartyManager.my_members:
		member_ids.append(int(m.get("id", -1)))
	for p in list:
		var pid := int(p.get("id", -1))
		if pid == my_id or pid in member_ids:
			continue
		var row := HBoxContainer.new()
		var lbl := Label.new()
		lbl.custom_minimum_size = Vector2(280, 0)
		lbl.text = String(p.get("name", "?"))
		row.add_child(lbl)
		var btn := Button.new()
		btn.text = "Invitar"
		btn.pressed.connect(PartyManager.invite_player.bind(pid))
		row.add_child(btn)
		party_others_list.add_child(row)
	if party_others_list.get_child_count() == 0:
		var lbl := Label.new()
		lbl.text = "(No hay otros jugadores)"
		party_others_list.add_child(lbl)


func _on_invite_received(from_name: String) -> void:
	party_invite_label.text = "%s te invita a su grupo" % from_name
	party_invite_box.visible = true
	show_pickup("%s te invita (pulsa P para responder)" % from_name)


func _on_accept_invite() -> void:
	PartyManager.accept_invite()
	party_invite_box.visible = false


func _on_decline_invite() -> void:
	PartyManager.decline_invite()
	party_invite_box.visible = false
