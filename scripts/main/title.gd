extends Control
## Comic-cover title screen.

func _ready() -> void:
	theme = ComicTheme.make_theme()
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.08, 0.1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var cover := PanelContainer.new()
	cover.add_theme_stylebox_override("panel", ComicTheme.panel(Color(0.94, 0.9, 0.8), 6, 12))
	cover.anchor_left = 0.2
	cover.anchor_right = 0.8
	cover.anchor_top = 0.1
	cover.anchor_bottom = 0.9
	add_child(cover)
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 14)
	cover.add_child(vb)

	var issue := Label.new()
	issue.text = "ISSUE #1  -  25c"
	issue.label_settings = ComicTheme.label_settings(16, Color(0.6, 0.1, 0.1))
	vb.add_child(issue)
	var title := Label.new()
	title.text = "MIRAGE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.label_settings = ComicTheme.label_settings(96, Color(1.0, 0.82, 0.25), 18, ComicTheme.INK)
	title.label_settings.shadow_color = ComicTheme.INK
	title.label_settings.shadow_offset = Vector2(8, 8)
	vb.add_child(title)
	var tagline := Label.new()
	tagline.text = "Every Light Hides a Shadow."
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tagline.label_settings = ComicTheme.label_settings(26, Color(0.0, 0.5, 0.45))
	vb.add_child(tagline)

	var monk := ComicFigure.new()
	monk.apply_look({"height": 150, "width": 70, "body": "#2a1c2e", "trim": "#d9a33a", "mask": "noh", "crown": "halo", "eyes": "#ff3b2f"})
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(0, 200)
	holder.add_child(monk)
	holder.resized.connect(func() -> void: monk.position = Vector2(holder.size.x * 0.5, 190))
	vb.add_child(holder)

	var buttons := VBoxContainer.new()
	buttons.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	buttons.custom_minimum_size.x = 280
	vb.add_child(buttons)
	var new_game := _button(buttons, "New Game", _on_new_game)
	if GameState.has_save():
		_button(buttons, "Continue", _on_continue).grab_focus.call_deferred()
	else:
		new_game.grab_focus.call_deferred()
	_button(buttons, "Quit", get_tree().quit)


func _button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(func() -> void: Sfx.play("ui_select"))
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _on_new_game() -> void:
	GameState.reset()
	SceneRouter.go_to_world("sanctum", "IN THE BEGINNING, THERE WAS ONLY SILENCE...")


func _on_continue() -> void:
	if GameState.load_game():
		SceneRouter.go_to_world(GameState.current_world_id, "PREVIOUSLY...")
