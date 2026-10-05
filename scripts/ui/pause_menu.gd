class_name PauseMenu
extends CanvasLayer
## Minimal pause: resume, sound volume, or return to the title (progress is saved).

var _root: Control


func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = ComicTheme.make_theme()
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(320, 0)
	panel.position -= Vector2(160, 90)
	_root.add_child(panel)
	var vb := VBoxContainer.new()
	panel.add_child(vb)
	var title := Label.new()
	title.text = "PAUSED"
	title.label_settings = ComicTheme.label_settings(32)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	var resume := Button.new()
	resume.text = "Resume"
	resume.pressed.connect(toggle)
	vb.add_child(resume)
	var sound_row := HBoxContainer.new()
	sound_row.add_theme_constant_override("separation", 10)
	vb.add_child(sound_row)
	var sound_label := Label.new()
	sound_label.text = "Sound"
	sound_label.label_settings = ComicTheme.label_settings(18)
	sound_row.add_child(sound_label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = Sfx.volume
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.value_changed.connect(func(v: float) -> void:
		Sfx.volume = v
		Sfx.play("ui_tick"))
	slider.drag_ended.connect(func(_changed: bool) -> void: Sfx.save_settings())
	slider.focus_exited.connect(Sfx.save_settings)
	sound_row.add_child(slider)
	var quit := Button.new()
	quit.text = "Save & return to title"
	quit.pressed.connect(func() -> void:
		toggle()
		GameState.save_game()
		SceneRouter.go_to_scene("res://scenes/main/title.tscn", "TO BE CONTINUED..."))
	vb.add_child(quit)
	_root.visible = false


func toggle() -> void:
	_root.visible = not _root.visible
	get_tree().paused = _root.visible
	Sfx.play("ui_open" if _root.visible else "ui_close")
	if _root.visible:
		(_root.find_children("*", "Button", true, false)[0] as Button).grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause") or SceneRouter.is_busy():
		return
	if not _root.visible and GameState.is_player_locked():
		return  # dialogue / shop / cutscene handle their own escape
	get_viewport().set_input_as_handled()
	toggle()
