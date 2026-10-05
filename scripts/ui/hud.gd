class_name HUD
extends CanvasLayer
## Health and the Hope Meter (top left), boss bar, zone caption and toasts, all
## as comic panels. Everything else (weapon, gold, keys, powers, build, potions)
## lives in the inventory screen.

var _health_bar: ProgressBar
var _hope_bar: ProgressBar
var _hope_fill: StyleBoxFlat
var _boss_panel: PanelContainer
var _boss_bar: ProgressBar
var _boss_name: Label
var _caption: PanelContainer
var _caption_label: Label
var _toasts: VBoxContainer
var _hint: Label
var _quest_states: Dictionary = {}  ## quest id -> Quests.state(), to announce progress


func _ready() -> void:
	layer = 10
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = ComicTheme.make_theme()
	add_child(root)

	# Top-left status panel.
	var status := PanelContainer.new()
	status.position = Vector2(16, 16)
	root.add_child(status)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	status.add_child(vb)
	_health_bar = _bar(Color(0.85, 0.2, 0.2), 220)
	vb.add_child(_row("HP", _health_bar))
	_hope_bar = _bar(Color(1.0, 0.82, 0.3), 220)
	_hope_fill = _hope_bar.get_theme_stylebox("fill") as StyleBoxFlat
	vb.add_child(_row("HOPE", _hope_bar))

	# Boss bar.
	_boss_panel = PanelContainer.new()
	_boss_panel.anchor_left = 0.25
	_boss_panel.anchor_right = 0.75
	_boss_panel.anchor_top = 1.0
	_boss_panel.anchor_bottom = 1.0
	_boss_panel.offset_top = -112
	_boss_panel.offset_bottom = -44  # clears the control hint along the bottom edge
	_boss_panel.visible = false
	root.add_child(_boss_panel)
	var bvb := VBoxContainer.new()
	_boss_panel.add_child(bvb)
	_boss_name = Label.new()
	_boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bvb.add_child(_boss_name)
	_boss_bar = _bar(Color(0.55, 0.1, 0.25), 0)
	_boss_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bvb.add_child(_boss_bar)

	# Zone caption (top-right, like a comic narration box).
	_caption = PanelContainer.new()
	_caption.add_theme_stylebox_override("panel", ComicTheme.panel(ComicTheme.CAPTION, 4, 6))
	_caption.anchor_left = 1.0
	_caption.anchor_right = 1.0
	_caption.offset_left = -440
	_caption.offset_right = -16
	_caption.offset_top = 16
	root.add_child(_caption)
	_caption_label = Label.new()
	_caption_label.label_settings = ComicTheme.label_settings(20)
	_caption_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_caption.add_child(_caption_label)
	_caption.visible = false

	_toasts = VBoxContainer.new()
	_toasts.anchor_left = 0.5
	_toasts.anchor_right = 0.5
	_toasts.offset_left = -300
	_toasts.offset_right = 300
	_toasts.offset_top = 150
	_toasts.alignment = BoxContainer.ALIGNMENT_BEGIN
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_toasts)

	var hint := _small_label()
	_hint = hint
	hint.text = "WASD move  J attack  SHIFT/SPACE dash  Q power  R potion  I bag  E interact"
	hint.anchor_top = 1.0
	hint.anchor_bottom = 1.0
	hint.offset_left = 16
	hint.offset_top = -30
	hint.label_settings = ComicTheme.label_settings(14, ComicTheme.PAPER, 4, ComicTheme.INK)
	root.add_child(hint)

	GameState.health_changed.connect(_on_health)
	GameState.hope_changed.connect(_on_hope)
	GameState.toast.connect(show_toast)
	# The dialogue box covers the bottom of the screen; tuck the corner widgets away.
	DialogueManager.dialogue_started.connect(func(_id: String) -> void: _set_corners_visible(false))
	DialogueManager.dialogue_ended.connect(func(_id: String) -> void: _set_corners_visible(true))
	GameState.boss_engaged.connect(_on_boss)
	for q: Dictionary in Quests.all():
		_quest_states[q.id] = Quests.state(q)
	GameState.flag_changed.connect(func(_f: String, _v: Variant) -> void: _check_quests())
	_on_health(GameState.health, GameState.get_max_health())
	_on_hope(GameState.hope, 0.0, "")


func show_caption(text: String, seconds: float = 4.0) -> void:
	_caption_label.text = text
	_caption.visible = true
	_caption.modulate.a = 0.0
	var t := create_tween()
	t.tween_property(_caption, "modulate:a", 1.0, 0.25)
	t.tween_interval(seconds)
	t.tween_property(_caption, "modulate:a", 0.0, 0.5)
	t.tween_callback(func() -> void: _caption.visible = false)


func show_toast(text: String, color: Color = ComicTheme.CAPTION) -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", ComicTheme.panel(color, 3, 5))
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.label_settings = ComicTheme.label_settings(20)
	p.add_child(l)
	_toasts.add_child(p)
	p.pivot_offset = Vector2(300, 20)
	p.scale = Vector2(0.7, 0.7)
	var t := create_tween()
	t.tween_property(p, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_interval(2.6)
	t.tween_property(p, "modulate:a", 0.0, 0.4)
	t.tween_callback(p.queue_free)


func _set_corners_visible(on: bool) -> void:
	_hint.visible = on
	for c in get_children():
		if c is Minimap:
			c.visible = on


## Announces quests starting, advancing and finishing.
func _check_quests() -> void:
	for q: Dictionary in Quests.all():
		var now := Quests.state(q)
		var before := str(_quest_states.get(q.id, ""))
		if now == before:
			continue
		_quest_states[q.id] = now
		Sfx.play("quest_done" if now == "done" else "quest")
		if now == "done":
			show_toast("QUEST COMPLETE - %s" % q.title, Color(1.0, 0.85, 0.3))
		elif before == "":
			show_toast("NEW QUEST - %s\n%s" % [q.title, Quests.current_text(q)], Color(0.75, 0.9, 1.0))
		else:
			show_toast("QUEST - %s" % Quests.current_text(q), Color(0.75, 0.9, 1.0))


func _on_health(current: float, maximum: float) -> void:
	_health_bar.max_value = maximum
	_health_bar.value = current


func _on_hope(value: float, delta: float, _reason: String) -> void:
	var t := create_tween()
	t.tween_property(_hope_bar, "value", value, 0.4)
	# The lantern burns gold when radiant and sinks to violet ash near despair.
	_hope_fill.bg_color = Color(0.35, 0.2, 0.45).lerp(Color(1.0, 0.82, 0.3), value / GameState.HOPE_MAX)
	if not is_zero_approx(delta):
		var up := delta > 0.0
		Sfx.play("hope_up" if up else "hope_down")
		show_toast("HOPE %s%d" % ["+" if up else "", roundi(delta)], Color(1.0, 0.9, 0.5) if up else Color(0.6, 0.5, 0.75))


func _on_boss(boss: Node) -> void:
	if not boss is Enemy:
		return
	var e := boss as Enemy
	_boss_name.text = e.display_name.to_upper()
	_boss_bar.max_value = e.max_health
	_boss_bar.value = e.health
	_boss_panel.visible = true
	e.health_changed.connect(func(c: float, _m: float) -> void: _boss_bar.value = c)
	e.defeated.connect(func(_x: Enemy) -> void: _boss_panel.visible = false)
	e.tree_exiting.connect(func() -> void: if is_instance_valid(_boss_panel): _boss_panel.visible = false)


## One-line summary of the run build, e.g. "BLADE (Fire) | Spirit Dart Lv2 (Shock)".
static func build_text() -> String:
	var parts: Array[String] = []
	var blade_el := str(GameState.run_elements.get(Skills.BLADE, ""))
	parts.append("BLADE" + (" (%s)" % Skills.ELEMENTS[blade_el].name if blade_el != "" else ""))
	for id: String in GameState.run_skills:
		var el := str(GameState.run_elements.get(id, ""))
		parts.append("%s Lv%d%s" % [Skills.skill_name(id), int(GameState.run_skills[id]),
			" (%s)" % Skills.ELEMENTS[el].name if el != "" else ""])
	return "BUILD: " + " | ".join(parts)


func _bar(color: Color, width: float) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(width, 18)
	bar.show_percentage = false
	var bg := ComicTheme.panel(Color(0.2, 0.18, 0.2), 3, 0)
	bg.set_content_margin_all(0)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.border_color = ComicTheme.INK
	fill.set_border_width_all(3)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)
	return bar


func _row(label: String, bar: ProgressBar) -> HBoxContainer:
	var h := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size.x = 56
	l.label_settings = ComicTheme.label_settings(16)
	h.add_child(l)
	h.add_child(bar)
	return h


func _small_label() -> Label:
	var l := Label.new()
	l.label_settings = ComicTheme.label_settings(14)
	return l
