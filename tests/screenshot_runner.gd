extends Node
## Captures one screenshot per world (needs a real window, not --headless).
## Run: godot --path . res://tests/screenshots.tscn -- <output_dir>

func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else OS.get_user_data_dir()
	GameState.reset()
	GameState.give_key("world_order")
	for id: String in ["sanctum", "world_order", "world_doubt", "world_truth", "vihara", "finale"]:
		SceneRouter.go_to_world(id)
		while SceneRouter.is_busy() or not get_tree().current_scene is WorldBase:
			await get_tree().process_frame
		var world := get_tree().current_scene as WorldBase
		for i in 20:
			await get_tree().process_frame
		var keep_dialogue := id == "world_order"
		while DialogueManager.is_active() and not keep_dialogue:
			DialogueManager._end()
		# Walk the camera toward the first NPC so characters are in frame.
		for e in world.entities.get_children():
			if e is NPC:
				world.player.global_position = e.global_position + Vector2(-140, 0)
				break
		for i in 60:
			await get_tree().process_frame
		if DialogueManager.is_active():
			DialogueManager._box._finish_typing()
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out.path_join(id + ".png"))
		if id == "world_order":
			await _shoot_fight(world, out.path_join("world_order_fight.png"))
			await _shoot_inventory(world, out.path_join("inventory.png"))
		while DialogueManager.is_active():
			DialogueManager._end()
	for id: String in ["world_order", "world_doubt", "world_truth", "finale"]:
		await _shoot_boss(id, out.path_join(id + "_boss.png"))
	get_tree().quit()


## Walks into the first combat room (it seals) and swings with a couple of skills.
func _shoot_fight(world: WorldBase, path: String) -> void:
	while DialogueManager.is_active():
		DialogueManager._end()
	for room in world.rooms:
		if room.living() > 0 and not room.has_boss and not room.gates.is_empty():
			var e: Enemy = room.enemies[0]
			world.player.global_position = e.global_position + Vector2(-100, 40)
			break
	for room in world.rooms:
		room.visited = room.visited or room.living() > 0 or room.id < 6
	GameState.run_skills = {"spirit_dart": 1, "whirlwind": 1}
	GameState.run_elements = {"blade": "fire", "spirit_dart": "shock"}
	for i in 30:
		await get_tree().physics_frame
	world.player._attack()
	for i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)


## Fills the bag with rolled loot and captures the inventory screen.
func _shoot_inventory(world: WorldBase, path: String) -> void:
	GameState.inventory.clear()
	for id in ["wave_cutter", "tide_naginata", "noir_odachi", "lamplight_tanto", "storm_rod", "reed_bow", "dawn_edge", "ink_kama"]:
		GameState.add_to_bag(Weapons.roll(id, 1.0, randi_range(0, 2)))
	GameState.potions = 3
	for f in ["hana_helped", "sabu_told_jun", "tobi_helped", "mei_told_lantern", "found_apprentice_lantern", "suzu_home"]:
		GameState.set_flag(f)
	world.inventory_ui.open()
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	world.inventory_ui.close()


## Walks into each boss arena, lets the fight start, and triggers a signature move.
func _shoot_boss(id: String, path: String) -> void:
	GameState.reset()
	GameState.set_flag("intro_seen_" + id)
	GameState.give_weapon("wave_cutter")
	SceneRouter.go_to_world(id)
	while SceneRouter.is_busy() or not get_tree().current_scene is WorldBase:
		await get_tree().process_frame
	var world := get_tree().current_scene as WorldBase
	var boss: Boss = null
	for e in get_tree().get_nodes_in_group("enemies"):
		if e is Boss:
			boss = e
	if not boss:
		return
	world.player.global_position = boss.global_position + Vector2(-300, 60)
	for i in 600:
		if boss.awake:
			break
		await get_tree().physics_frame
	while DialogueManager.is_active():
		DialogueManager._end()
	for i in 40:
		await get_tree().physics_frame
	if boss is MothBoss:
		boss._cycle = -1
		boss._attack_t = 0.0
	elif boss is EyeBoss:
		boss._beam_t = 0.0
	for i in 70:
		await get_tree().physics_frame
	world.player.velocity = Vector2.ZERO
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
