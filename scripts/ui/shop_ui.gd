class_name ShopUI
extends CanvasLayer
## Weapon shop. Each stall's weapons are fixed rolls (Weapons.shop_item) that
## go into the bag when bought; it also sells healing potions. Prices scale with
## hope (GameState.get_price_multiplier()).

signal closed

var _panel: PanelContainer
var _list: VBoxContainer
var _title: Label
var _gold: Label
var _stock: PackedStringArray = []
var _items: Array[Dictionary] = []  ## rolled instances on the shelf
var _shelf_key := ""


func _ready() -> void:
	layer = 15
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = ComicTheme.make_theme()
	add_child(root)
	_panel = PanelContainer.new()
	_panel.anchor_left = 0.25
	_panel.anchor_right = 0.75
	_panel.anchor_top = 0.15
	_panel.anchor_bottom = 0.85
	root.add_child(_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	_panel.add_child(vb)
	_title = Label.new()
	_title.label_settings = ComicTheme.label_settings(28)
	vb.add_child(_title)
	_gold = Label.new()
	vb.add_child(_gold)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	var close_btn := Button.new()
	close_btn.text = "Leave"
	close_btn.pressed.connect(close)
	vb.add_child(close_btn)
	hide()


func open(shop_name: String, stock: PackedStringArray) -> void:
	if visible:
		return
	var key := GameState.current_world_id + ":" + ",".join(stock)
	if key != _shelf_key:
		_shelf_key = key
		_stock = stock
		_items.clear()
		for id in stock:
			var inst := Weapons.shop_item(id, key)
			if not inst.is_empty():
				_items.append(inst)
	_title.text = shop_name.to_upper()
	GameState.push_ui_lock()
	Sfx.play("ui_open")
	show()
	_rebuild()


func close() -> void:
	if not visible:
		return
	hide()
	Sfx.play("ui_close")
	GameState.pop_ui_lock()
	closed.emit()


func _rebuild() -> void:
	_gold.text = "Your gold: %d     Bag %d/%d     (Hope %s - prices x%.2f)" % [GameState.gold, GameState.inventory.size(),
		GameState.BAG_SIZE, GameState.hope_tier(), GameState.get_price_multiplier()]
	for c in _list.get_children():
		c.queue_free()
	var first: Button = null
	var potion_price := potion_cost()
	var pb := Button.new()
	pb.text = "Healing Potion  (heals %d%%)  x%d/%d  -  %dg" % [roundi(GameState.POTION_HEAL * 100.0), GameState.potions,
		GameState.POTION_MAX, potion_price]
	pb.alignment = HORIZONTAL_ALIGNMENT_LEFT
	pb.disabled = GameState.gold < potion_price or GameState.potions >= GameState.POTION_MAX
	pb.pressed.connect(_buy_potion)
	_list.add_child(pb)
	if not pb.disabled:
		first = pb
	for i in _items.size():
		var w := Weapons.build(_items[i])
		var price := GameState.get_shop_price(w)
		var b := Button.new()
		b.text = "%s  [%s %s]  DMG %d  SPD %.1f/s  -  %dg" % [w.display_name, WeaponData.rarity_name(w.rarity),
			WeaponData.kind_name(w.kind), roundi(w.damage), 1.0 / w.attack_cooldown, price]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.tooltip_text = w.description + ("\n" + "\n".join(w.affix_lines) if not w.affix_lines.is_empty() else "")
		b.add_theme_color_override("font_color", WeaponData.rarity_color(w.rarity).darkened(0.45))
		b.disabled = GameState.gold < price or GameState.bag_full()
		b.pressed.connect(_buy.bind(i))
		_list.add_child(b)
		if not first and not b.disabled:
			first = b
	if first:
		first.grab_focus.call_deferred()


static func potion_cost() -> int:
	return maxi(1, roundi(GameState.POTION_PRICE * GameState.get_price_multiplier()))


func _buy_potion() -> void:
	if GameState.potions >= GameState.POTION_MAX or not GameState.spend_gold(potion_cost()):
		return
	GameState.add_potion()
	Sfx.play("buy")
	GameState.toast.emit("BOUGHT - Healing Potion", Color(1.0, 0.5, 0.55))
	_rebuild()


func _buy(index: int) -> void:
	if index < 0 or index >= _items.size() or GameState.bag_full():
		return
	var inst := _items[index]
	var w := Weapons.build(inst)
	if not GameState.spend_gold(GameState.get_shop_price(w)):
		return
	_items.remove_at(index)
	GameState.add_to_bag(inst)
	Sfx.play("buy")
	GameState.toast.emit("BOUGHT - %s  (in your bag: I)" % w.display_name, WeaponData.rarity_color(w.rarity))
	_rebuild()


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel")):
		get_viewport().set_input_as_handled()
		close()
