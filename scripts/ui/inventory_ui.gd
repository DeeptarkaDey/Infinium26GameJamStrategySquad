class_name InventoryUI
extends CanvasLayer
## The bag, Labyrinth Legend style. Left: the equipped weapon, potions,
## character stats (hope's effects, gold), the quest journal, mission keys,
## absorbed powers and the run's build. Right: a 5x4 grid of weapon slots framed by rarity. Below
## the grid: the selected weapon's stats compared against the one in hand,
## its affixes, and Equip / Salvage / Drop. Pauses the game while open.
## Toggle with I / Tab; keys: Enter equip, X salvage, G drop.

const COLUMNS := 5

## A grid cell: draws the weapon icon inside a rarity frame.
class Slot extends Button:
	var item: Dictionary = {}
	var weapon: WeaponData
	var selected := false

	func _init() -> void:
		custom_minimum_size = Vector2(72, 72)
		focus_mode = Control.FOCUS_ALL
		flat = true

	func set_item(inst: Dictionary) -> void:
		item = inst
		weapon = Weapons.build(inst) if not inst.is_empty() else null
		tooltip_text = weapon.display_name if weapon else ""
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var frame := WeaponData.rarity_color(weapon.rarity) if weapon else Color(0.45, 0.42, 0.4)
		draw_rect(r, Color(0.16, 0.14, 0.16) if weapon else Color(0.22, 0.2, 0.22))
		if weapon:
			draw_rect(r.grow(-4), Color(frame, 0.18))
			WeaponIcon.draw(self, size * 0.5, size.x * 0.62, weapon)
			for i in (item.get("affixes", []) as Array).size():
				draw_circle(Vector2(10 + i * 9, size.y - 10), 3.0, frame)
		draw_rect(r, frame if weapon else Color(0.35, 0.33, 0.33), false, 3.0)
		if selected or has_focus():
			draw_rect(r.grow(-2), Color(1.0, 0.9, 0.4), false, 4.0)

var world: WorldBase  ## set by the world, for dropping items at the player's feet
var _root: Control
var _grid: GridContainer
var _bag_title: Label
var _equipped_slot: Slot
var _equipped_info: RichTextLabel
var _potion_label: Label
var _stats_label: Label
var _keys_label: RichTextLabel
var _journal_label: RichTextLabel
var _powers_label: RichTextLabel
var _build_label: RichTextLabel
var _detail_title: Label
var _detail: RichTextLabel
var _equip_btn: Button
var _salvage_btn: Button
var _drop_btn: Button
var _selected := -1


func _ready() -> void:
	layer = 18
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = ComicTheme.make_theme()
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", ComicTheme.panel(Color(0.27, 0.24, 0.26), 5, 10))
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -580
	panel.offset_right = 580
	panel.offset_top = -345
	panel.offset_bottom = 345
	_root.add_child(panel)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 22)
	panel.add_child(cols)

	# Left: the samurai (scrolls if a long build doesn't fit).
	var left_scroll := ScrollContainer.new()
	left_scroll.custom_minimum_size.x = 340
	left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cols.add_child(left_scroll)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 325
	left.add_theme_constant_override("separation", 6)
	left_scroll.add_child(left)
	left.add_child(_header("EQUIPPED"))
	var eq_row := HBoxContainer.new()
	eq_row.add_theme_constant_override("separation", 12)
	left.add_child(eq_row)
	_equipped_slot = Slot.new()
	_equipped_slot.custom_minimum_size = Vector2(110, 110)
	_equipped_slot.focus_mode = Control.FOCUS_NONE
	eq_row.add_child(_equipped_slot)
	_equipped_info = _rich(200)
	eq_row.add_child(_equipped_info)
	var pot_row := HBoxContainer.new()
	pot_row.add_theme_constant_override("separation", 12)
	left.add_child(pot_row)
	var flask := Control.new()
	flask.custom_minimum_size = Vector2(48, 48)
	flask.draw.connect(func() -> void: preload("res://scripts/pickups/potion.gd").draw_flask(flask, Vector2(24, 28), 1.6))
	pot_row.add_child(flask)
	_potion_label = Label.new()
	_potion_label.label_settings = ComicTheme.label_settings(18, ComicTheme.PAPER)
	pot_row.add_child(_potion_label)
	var drink := Button.new()
	drink.text = "Drink [R]"
	drink.focus_mode = Control.FOCUS_NONE
	drink.pressed.connect(_drink)
	pot_row.add_child(drink)
	left.add_child(_header("SAMURAI"))
	_stats_label = Label.new()
	_stats_label.label_settings = ComicTheme.label_settings(15, ComicTheme.PAPER)
	left.add_child(_stats_label)
	left.add_child(_header("JOURNAL"))
	_journal_label = _rich(0)
	left.add_child(_journal_label)
	left.add_child(_header("KEYS"))
	_keys_label = _rich(0)
	left.add_child(_keys_label)
	left.add_child(_header("POWERS"))
	_powers_label = _rich(0)
	left.add_child(_powers_label)
	left.add_child(_header("BUILD"))
	_build_label = _rich(0)
	left.add_child(_build_label)

	# Right: the bag and the selected item.
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 10)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	_bag_title = _header("BAG")
	right.add_child(_bag_title)
	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	right.add_child(_grid)
	for i in GameState.BAG_SIZE:
		var slot := Slot.new()
		slot.pressed.connect(_select.bind(i))
		slot.focus_entered.connect(_select.bind(i))
		_grid.add_child(slot)
	var detail_panel := PanelContainer.new()
	detail_panel.add_theme_stylebox_override("panel", ComicTheme.panel(ComicTheme.PAPER, 4, 6))
	detail_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(detail_panel)
	var dvb := VBoxContainer.new()
	detail_panel.add_child(dvb)
	_detail_title = Label.new()
	_detail_title.label_settings = ComicTheme.label_settings(22)
	dvb.add_child(_detail_title)
	_detail = _rich(0)
	_detail.add_theme_color_override("default_color", ComicTheme.INK)
	_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dvb.add_child(_detail)
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 10)
	dvb.add_child(btns)
	_equip_btn = _button(btns, "Equip [Enter]", _equip)
	_salvage_btn = _button(btns, "Salvage [X]", _salvage)
	_drop_btn = _button(btns, "Drop [G]", _drop)
	var hint := Label.new()
	hint.text = "I / Tab / Esc to close"
	hint.label_settings = ComicTheme.label_settings(14, Color(0.8, 0.78, 0.7))
	right.add_child(hint)

	GameState.inventory_changed.connect(_refresh)
	GameState.potions_changed.connect(func(_n: int) -> void: _refresh())
	_root.visible = false


func is_open() -> bool:
	return _root.visible


func open() -> void:
	if _root.visible or GameState.is_player_locked() or get_tree().paused:
		return
	_root.visible = true
	get_tree().paused = true
	Sfx.play("ui_open")
	_selected = 0 if not GameState.inventory.is_empty() else -1
	_refresh()
	(_grid.get_child(maxi(_selected, 0)) as Control).grab_focus.call_deferred()


func close() -> void:
	if not _root.visible:
		return
	_root.visible = false
	get_tree().paused = false
	Sfx.play("ui_close")


func _refresh() -> void:
	if not _root.visible:
		return
	var bag := GameState.inventory
	_selected = mini(_selected, bag.size() - 1)
	_bag_title.text = "BAG  %d / %d" % [bag.size(), GameState.BAG_SIZE]
	for i in _grid.get_child_count():
		var slot := _grid.get_child(i) as Slot
		slot.set_item(bag[i] if i < bag.size() else {})
		slot.selected = i == _selected
		slot.queue_redraw()
	var w := GameState.get_weapon()
	_equipped_slot.set_item(GameState.equipped)
	_equipped_info.text = _weapon_text(w, null)
	_potion_label.text = "Potions x%d / %d" % [GameState.potions, GameState.POTION_MAX]
	_stats_label.text = "HP %d / %d     Gold %d\nHope %d (%s)\nDamage x%.2f   Luck %d%%   Crit %d%%\nPrices x%.2f" % [
		roundi(GameState.health), roundi(GameState.get_max_health()), GameState.gold,
		roundi(GameState.hope), GameState.hope_tier(), GameState.get_damage_multiplier(),
		roundi(GameState.get_luck() * 100.0), roundi(GameState.get_crit_chance() * 100.0), GameState.get_price_multiplier()]
	var journal: Array[String] = []
	for q: Dictionary in Quests.all():
		if not Quests.started(q):
			continue
		if Quests.complete(q):
			journal.append("[color=#8fd18f]✓ %s[/color]" % q.title)
		else:
			var here: bool = q.world == GameState.current_world_id
			journal.append("[color=#ffd84f]%s[/color]%s\n   %s" % [q.title, "" if here else "  [color=#888888](%s)[/color]" % Database.get_world(str(q.world)).display_name,
				Quests.current_text(q)])
	_journal_label.text = "\n".join(journal) if not journal.is_empty() else "[color=#888888]Help the people you meet.[/color]"
	var keys: Array[String] = []
	for id in Database.mission_order:
		var wd := Database.get_world(id)
		var name := wd.display_name if wd else id
		keys.append("[color=#ffd84f]KEY[/color]  %s" % name if GameState.has_key(id) else "[color=#888888]---  %s[/color]" % name)
	_keys_label.text = "\n".join(keys)
	var powers: Array[String] = []
	for id in GameState.powers:
		var pw := Database.get_power(id)
		if pw:
			powers.append("[color=#%s]%s[/color]%s" % [pw.color.to_html(false), pw.display_name,
				"  [Q]" if pw.kind == PowerData.Kind.ACTIVE else ""])
	_powers_label.text = "\n".join(powers) if not powers.is_empty() else "[color=#888888]none yet[/color]"
	var build: Array[String] = []
	var blade_el := str(GameState.run_elements.get(Skills.BLADE, ""))
	if blade_el != "":
		build.append("Blade: [color=#%s]%s[/color]" % [Skills.element_color(blade_el).to_html(false), Skills.ELEMENTS[blade_el].name])
	for id: String in GameState.run_skills:
		var el := str(GameState.run_elements.get(id, ""))
		build.append("%s Lv%d%s" % [Skills.skill_name(id), int(GameState.run_skills[id]),
			"  [color=#%s]%s[/color]" % [Skills.element_color(el).to_html(false), Skills.ELEMENTS[el].name] if el != "" else ""])
	_build_label.text = "\n".join(build) if not build.is_empty() else "[color=#888888]clear rooms to earn skills[/color]"
	var has := _selected >= 0
	for b in [_equip_btn, _salvage_btn, _drop_btn]:
		b.disabled = not has
	if has:
		var sel := Weapons.build(bag[_selected])
		_detail_title.text = sel.display_name
		_detail_title.label_settings.font_color = WeaponData.rarity_color(sel.rarity).darkened(0.3)
		_detail.text = _weapon_text(sel, w)
		_salvage_btn.text = "Salvage +%dg [X]" % Weapons.salvage_value(bag[_selected])
	else:
		_detail_title.text = "Empty bag"
		_detail_title.label_settings.font_color = ComicTheme.INK
		_detail.text = "Weapons dropped by enemies and found in chests land here."
		_salvage_btn.text = "Salvage [X]"


## Stats block; with `compare`, each number shows its change against it.
func _weapon_text(w: WeaponData, compare: WeaponData) -> String:
	var lines: Array[String] = []
	lines.append("[b]%s[/b] %s" % [WeaponData.rarity_name(w.rarity), WeaponData.kind_name(w.kind)])
	lines.append("Damage %d%s" % [roundi(w.damage), _delta(w.damage, compare.damage if compare else 0.0, compare != null)])
	var aps := 1.0 / w.attack_cooldown
	lines.append("Speed %.1f/s%s" % [aps, _delta(aps, 1.0 / compare.attack_cooldown if compare else 0.0, compare != null)])
	lines.append("%s %d%s" % ["Range" if w.is_ranged() else "Reach", roundi(w.reach), _delta(w.reach, compare.reach if compare else 0.0, compare != null)])
	var dps := w.damage * aps
	lines.append("DPS ~%d%s" % [roundi(dps), _delta(dps, compare.damage / compare.attack_cooldown if compare else 0.0, compare != null)])
	for a in w.affix_lines:
		lines.append("[color=#3a7d2a]◆ %s[/color]" % a)
	return "\n".join(lines)


func _delta(v: float, other: float, show: bool) -> String:
	if not show or is_equal_approx(v, other):
		return ""
	var up := v > other
	return "  [color=%s]%s%s[/color]" % ["#2f8a2f" if up else "#b03030", "▲" if up else "▼", str(snappedf(absf(v - other), 0.1))]


func _select(i: int) -> void:
	if i >= GameState.inventory.size():
		return
	if _selected != i:
		Sfx.play("ui_tick")
	_selected = i
	_refresh()


func _equip() -> void:
	if _selected < 0:
		return
	GameState.equip_from_bag(_selected)
	Sfx.play("equip")
	var w := GameState.get_weapon()
	GameState.toast.emit("EQUIPPED - %s" % w.display_name, WeaponData.rarity_color(w.rarity))


func _salvage() -> void:
	if _selected < 0:
		return
	var g := GameState.salvage(_selected)
	Sfx.play("coin")
	GameState.toast.emit("SALVAGED  +%dg" % g, Color(1.0, 0.85, 0.3))


func _drop() -> void:
	if _selected < 0 or not world or not world.player:
		return
	var inst := GameState.remove_from_bag(_selected)
	Sfx.play("ui_close")
	Loot.spawn_weapon(world.entities, world.player.global_position + Vector2(randf_range(-30, 30), 10), inst)


func _drink() -> void:
	if world and world.player:
		world.player.drink_potion()
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory"):
		get_viewport().set_input_as_handled()
		if _root.visible:
			close()
		else:
			open()
		return
	if not _root.visible:
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
	elif event.is_action_pressed("use_potion"):
		get_viewport().set_input_as_handled()
		_drink()
	elif event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).physical_keycode:
			KEY_ENTER, KEY_KP_ENTER:
				_equip()
			KEY_X:
				_salvage()
			KEY_G:
				_drop()
			_:
				return
		get_viewport().set_input_as_handled()


func _header(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.label_settings = ComicTheme.label_settings(22, ComicTheme.CAPTION, 6, ComicTheme.INK)
	return l


func _rich(min_w: float) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.custom_minimum_size = Vector2(min_w, 0)
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_theme_color_override("default_color", ComicTheme.PAPER)
	r.add_theme_font_size_override("normal_font_size", 16)
	r.add_theme_font_size_override("bold_font_size", 16)
	return r


func _button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	parent.add_child(b)
	return b
