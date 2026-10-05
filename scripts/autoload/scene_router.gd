extends CanvasLayer
## Moves between worlds with a comic "page turn" transition and a caption box
## ("MEANWHILE, IN ANOTHER DIMENSION..."). Autoloaded as `SceneRouter`.

signal transition_finished

const WORLD_SCENE := "res://scenes/world/world.tscn"

var _slabs: Array[ColorRect] = []
var _caption: PanelContainer
var _caption_label: Label
var _busy := false


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 3:
		var slab := ColorRect.new()
		slab.color = ComicTheme.INK
		slab.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slab.visible = false
		add_child(slab)
		_slabs.append(slab)
	_caption = PanelContainer.new()
	_caption.add_theme_stylebox_override("panel", ComicTheme.panel(ComicTheme.CAPTION, 4, 8))
	_caption.visible = false
	add_child(_caption)
	_caption_label = Label.new()
	_caption_label.label_settings = ComicTheme.label_settings(30, ComicTheme.INK)
	_caption.add_child(_caption_label)


func is_busy() -> bool:
	return _busy


func go_to_world(world_id: String, caption: String = "") -> void:
	var w := Database.get_world(world_id)
	if not w:
		push_error("Unknown world: %s" % world_id)
		return
	GameState.current_world_id = world_id
	if caption == "" and w.style:
		caption = w.style.transition_caption
	await go_to_scene(WORLD_SCENE, caption)
	GameState.save_game()


func go_to_scene(path: String, caption: String = "") -> void:
	if _busy:
		return
	_busy = true
	GameState.push_ui_lock()
	await _cover(caption)
	get_tree().paused = false
	get_tree().change_scene_to_file(path)
	await get_tree().process_frame
	await get_tree().process_frame
	await _uncover()
	GameState.pop_ui_lock()
	_busy = false
	transition_finished.emit()


## Three ink panels slam in like gutters closing on a comic page.
func _cover(caption: String) -> void:
	Sfx.play("page_turn")
	var size := get_viewport().get_visible_rect().size
	var h := size.y / 3.0
	var tween := create_tween().set_parallel(true)
	for i in _slabs.size():
		var slab := _slabs[i]
		slab.visible = true
		slab.size = Vector2(size.x + 80, h + 4)
		slab.rotation = 0.0
		var from_left := i % 2 == 0
		slab.position = Vector2(-size.x - 120 if from_left else size.x + 40, h * i)
		tween.tween_property(slab, "position:x", -40.0, 0.28).set_delay(i * 0.07) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tween.finished
	if caption != "":
		_caption_label.text = caption
		_caption.visible = true
		_caption.reset_size()
		_caption.position = Vector2(48, size.y * 0.5 - 30)
		_caption.scale = Vector2(0.6, 0.6)
		_caption.rotation = -0.04
		var t2 := create_tween()
		t2.tween_property(_caption, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t2.tween_interval(0.9)
		await t2.finished


func _uncover() -> void:
	var size := get_viewport().get_visible_rect().size
	_caption.visible = false
	var tween := create_tween().set_parallel(true)
	for i in _slabs.size():
		var to_left := i % 2 == 1
		tween.tween_property(_slabs[i], "position:x", -size.x - 160 if to_left else size.x + 80, 0.3) \
			.set_delay(i * 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tween.finished
	for slab in _slabs:
		slab.visible = false
