extends Node
## UI check captures (needs a real window): a long dialogue line with a speaker
## name, a choice list, an interact prompt and combat SFX words, plus two frames
## while walking to compare the background.
## Run: godot --path . --quit-after 6000 res://tests/ui_check.tscn -- <output_dir>

func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else OS.get_user_data_dir()
	GameState.reset()
	GameState.set_flag("intro_seen_world_order")
	SceneRouter.go_to_world("world_order")
	while SceneRouter.is_busy() or not get_tree().current_scene is WorldBase:
		await get_tree().process_frame
	var world := get_tree().current_scene as WorldBase
	await _frames(30)
	# Stand by the first NPC so its prompt shows, and pop some combat words.
	for e in world.entities.get_children():
		if e is NPC:
			world.player.global_position = e.global_position + Vector2(-50, 10)
			break
	await _frames(20)
	SfxWord.spawn(world.entities, world.player.global_position + Vector2(80, -80), "SHHHA!", Color(1.0, 0.85, 0.1))
	SfxWord.spawn(world.entities, world.player.global_position + Vector2(-60, -120), "CRIT!", Color(1.0, 0.35, 0.2), 28)
	SfxWord.spawn(world.entities, world.player.global_position + Vector2(10, -150), "-12", Color(1.0, 0.3, 0.3), 24)
	await _frames(6)
	await _shot(out.path_join("ui_prompt_sfx.png"))
	# A long line from a named speaker.
	DialogueManager.start("order_fisher")
	await _frames(4)
	DialogueManager._show("f3")
	DialogueManager._box._finish_typing()
	await _frames(6)
	await _shot(out.path_join("ui_dialogue_choices.png"))
	DialogueManager._show("jun")
	DialogueManager._box._finish_typing()
	await _frames(6)
	await _shot(out.path_join("ui_dialogue_long.png"))
	DialogueManager._end()
	await _frames(20)
	# Two frames while walking right: the background should hold still.
	world.player.global_position = world.spawn_point
	Input.action_press("move_right")
	await _frames(20)
	await _shot(out.path_join("ui_walk_a.png"))
	await _frames(12)
	await _shot(out.path_join("ui_walk_b.png"))
	Input.action_release("move_right")
	get_tree().quit()


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
