class_name RewardUI
extends CanvasLayer
## "Room cleared" reward: pick one of three cards (a new skill, a skill upgrade,
## or an element for one of your slots). Built from Skills.roll_rewards().

signal chosen(card: Dictionary)

var _row: HBoxContainer
var _build_label: Label
var _cards: Array[Dictionary] = []


func _ready() -> void:
	layer = 16
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = ComicTheme.make_theme()
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 18)
	root.add_child(vb)
	var title := Label.new()
	title.text = "ROOM CLEARED!  CHOOSE ONE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.label_settings = ComicTheme.label_settings(40, ComicTheme.CAPTION, 12, ComicTheme.INK)
	vb.add_child(title)
	_row = HBoxContainer.new()
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.add_theme_constant_override("separation", 24)
	vb.add_child(_row)
	_build_label = Label.new()
	_build_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_build_label.label_settings = ComicTheme.label_settings(16, ComicTheme.PAPER, 6, ComicTheme.INK)
	vb.add_child(_build_label)
	hide()


func is_open() -> bool:
	return visible


func open() -> void:
	if visible:
		return
	_cards = Skills.roll_rewards()
	if _cards.is_empty():
		return
	GameState.push_ui_lock()
	Sfx.play("ui_open")
	for c in _row.get_children():
		c.queue_free()
	for i in _cards.size():
		_row.add_child(_make_card(_cards[i], i))
	_build_label.text = HUD.build_text()
	show()
	(_row.get_child(0) as Button).grab_focus.call_deferred()


func choose(index: int) -> void:
	if not visible or index < 0 or index >= _cards.size():
		return
	var card := _cards[index]
	Sfx.play("reward")
	hide()
	GameState.pop_ui_lock()
	Skills.apply_reward(card)
	chosen.emit(card)


func _make_card(card: Dictionary, index: int) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(250, 300)
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(choose.bind(index))
	var col: Color = card.color
	var normal := ComicTheme.panel(ComicTheme.PAPER, 5, 8)
	var hover := ComicTheme.panel(col.lerp(Color.WHITE, 0.55), 6, 10)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("focus", hover)
	b.add_theme_stylebox_override("pressed", hover)
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.offset_left = 16
	vb.offset_right = -16
	vb.offset_top = 16
	vb.offset_bottom = -16
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_theme_constant_override("separation", 12)
	b.add_child(vb)
	var kind := Label.new()
	kind.text = {"skill": "SKILL", "upgrade": "UPGRADE", "element": "ELEMENT"}.get(str(card.kind), "")
	kind.label_settings = ComicTheme.label_settings(16, col.darkened(0.35))
	vb.add_child(kind)
	var icon := ColorRect.new()
	icon.color = col
	icon.custom_minimum_size = Vector2(0, 70)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(icon)
	var title := Label.new()
	title.text = str(card.title)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD
	title.label_settings = ComicTheme.label_settings(24)
	vb.add_child(title)
	var desc := Label.new()
	desc.text = str(card.desc)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc.label_settings = ComicTheme.label_settings(16)
	vb.add_child(desc)
	var key := Label.new()
	key.text = "[%d]" % (index + 1)
	key.label_settings = ComicTheme.label_settings(16, Color(0.4, 0.4, 0.4))
	vb.add_child(key)
	return b


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey or not event.pressed:
		return
	var k := (event as InputEventKey).physical_keycode
	if k >= KEY_1 and k <= KEY_3:
		get_viewport().set_input_as_handled()
		choose(k - KEY_1)
