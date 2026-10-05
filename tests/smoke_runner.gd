extends Node
## Headless smoke test: loads every world, auto-plays dialogue (always picking
## the first visible choice), defeats bosses, and runs both reveal branches.
## Run: godot --headless --path . res://tests/smoke_test.tscn
## (smoke_test.gd adds this runner to the root so it survives scene changes.)

var _failures := 0


func _ready() -> void:
	_run.call_deferred()


func _process(_delta: float) -> void:
	# Auto-advance any open dialogue.
	if DialogueManager.is_active():
		var box: DialogueBox = DialogueManager._box
		box._finish_typing()
		if DialogueManager._visible_choices.is_empty():
			box.advanced.emit()
		else:
			box.choice_selected.emit(0)


func _run() -> void:
	await _frames(5)
	await _wait_until(func() -> bool: return Sfx.is_ready(), 600)  # sounds render in the background
	GameState.reset()
	for id: String in Database.worlds:
		await _visit(id)
	_check(Database.mission_order.size() == 3, "three missions registered")

	# Top-down movement: holding up moves the samurai north, no gravity pulls him back.
	await _visit("world_order")
	var world := get_tree().current_scene as WorldBase
	var start := world.player.global_position
	Input.action_press("move_up")
	await _physics_frames(20)
	Input.action_release("move_up")
	_check(world.player.global_position.y < start.y - 30.0, "player walks north (dy %.0f)" % (world.player.global_position.y - start.y))
	Input.action_press("move_right")
	await _physics_frames(20)
	Input.action_release("move_right")
	await _physics_frames(10)
	var y_after := world.player.global_position.y
	await _physics_frames(30)
	_check(absf(world.player.global_position.y - y_after) < 1.0, "no gravity in top-down view")

	# Rooms: walking into a room with enemies seals it; clearing it opens the
	# gates and offers a reward card.
	var fight: WorldBase.Room = null
	for room in world.rooms:
		if room.living() > 0 and not room.has_boss and not room.gates.is_empty():
			fight = room
			break
	_check(fight != null, "world_order has a combat room with gates")
	if fight:
		var tiles: Array = fight.tiles.keys()
		var centre := Vector2.ZERO
		for t: Vector2i in tiles:
			centre += Vector2(t)
		centre /= tiles.size()
		var ts := float(world.data.tile_size)
		world.player.global_position = (centre + Vector2(0.5, 0.75)) * ts
		await _physics_frames(5)
		_check(fight.sealed and world.is_gate_closed(fight.gates[0]), "entering a combat room seals its gates")
		_check(fight.enemies.any(func(e: Enemy) -> bool: return is_instance_valid(e) and e.aggro), "room enemies are aggro")
		# A dart with fire: skills fire on attack and elements stick.
		GameState.run_skills = {"spirit_dart": 1}
		GameState.run_elements = {"spirit_dart": "fire"}
		var target: Enemy = fight.enemies[0]
		world.player.global_position = target.global_position + Vector2(-90, 0)
		world.player._attack()
		await _physics_frames(2)
		var shots := world.entities.get_children().any(func(n: Node) -> bool: return n is SkillShot)
		_check(shots, "spirit dart fires with the attack")
		# The homing dart may find another mob first, so check the element on a direct strike.
		if is_instance_valid(target) and not target.is_dead():
			Skills.strike(target, 1.0, target.global_position + Vector2(-10, 0), 0.0, "spirit_dart")
		_check(not is_instance_valid(target) or target.is_dead() or target._burn_t > 0.0, "fire element burns the target")
		# Dying mid-fight: the room opens, survivors heal, and he wakes at the spawn.
		var wounded: Enemy = null
		for e in fight.enemies:
			if is_instance_valid(e) and not e.is_dead():
				wounded = e
		if wounded:
			wounded.take_hit(5.0, wounded.global_position + Vector2(-10, 0), 0.0)
		world.player.die()
		await _wait_until(func() -> bool: return not world.player.dead, 300)
		await _physics_frames(3)
		_check(not fight.sealed and not world.is_gate_closed(fight.gates[0]), "dying opens the sealed room")
		_check(world.player.global_position.distance_to(world.spawn_point) < 1.0, "player respawns at the world's start")
		_check(wounded != null and is_instance_valid(wounded) and is_equal_approx(wounded.health, wounded.max_health), "survivors heal when the player dies")
		# Walk back in to re-seal before clearing it.
		world.player.global_position = (centre + Vector2(0.5, 0.75)) * ts
		await _physics_frames(5)
		_check(fight.sealed, "room re-seals on return")
		GameState.full_heal()
		# Kill everything, including any halves a slime splits into.
		for round in 5:
			for e in fight.enemies:
				if is_instance_valid(e) and not e.is_dead():
					e.take_hit(99999.0, e.global_position + Vector2(-10, 0), 0.0)
			await _physics_frames(3)
		await _wait_until(func() -> bool: return world.reward_ui.is_open(), 200)
		_check(fight.cleared and not world.is_gate_closed(fight.gates[0]), "cleared room opens its gates")
		_check(world.reward_ui.is_open(), "cleared room offers a reward")
		GameState.run_skills = {}
		GameState.run_elements = {}
		world.reward_ui.choose(0)
		_check(not GameState.run_skills.is_empty() or not GameState.run_elements.is_empty(), "picking a reward changes the build")
		_check(not GameState.is_player_locked(), "reward pick releases the player")
	GameState.reset()

	# Labyrinths: everything that matters is reachable from the spawn.
	for id: String in Database.worlds:
		await _visit(id)
		_check_reachable(get_tree().current_scene as WorldBase)

	await _check_portal_walk_in()
	await _check_boss_mechanics()
	await _check_subquests()
	_check_sounds()
	await _check_loot_systems()
	await _check_mobs()
	await _check_weapon_kinds()
	GameState.reset()

	# Combat: kill each mission boss and confirm power + flag.
	for id in Database.mission_order:
		await _visit(id)
		var boss := _find_boss()
		_check(boss != null, "%s has a boss" % id)
		if boss:
			boss.awake = true
			boss.take_hit(99999.0, boss.global_position + Vector2(-10, 0), 0.0)
			await _wait_until(func() -> bool: return GameState.has_flag("boss_defeated_" + id), 600)
			_check(GameState.has_flag("boss_defeated_" + id), "%s boss defeated flag" % id)
		var w := Database.get_world(id)
		_check(GameState.has_power(w.boss_power), "%s grants %s" % [id, w.boss_power])
		GameState.complete_world(id)

	# Hope multipliers move in the right direction.
	GameState.hope = 90.0
	var hi := [GameState.get_damage_multiplier(), GameState.get_luck(), GameState.get_price_multiplier()]
	GameState.hope = 5.0
	var lo := [GameState.get_damage_multiplier(), GameState.get_luck(), GameState.get_price_multiplier()]
	_check(hi[0] > lo[0] and hi[1] > lo[1] and hi[2] < lo[2], "hope scales damage/luck/prices")

	# Reveal, high-hope branch -> escape to the Vihara.
	await _reveal(50.0)
	_check(GameState.current_world_id == "vihara" and GameState.has_flag("escaped_by_choice"), "high hope escapes to vihara")
	# Reveal, low-hope branch -> struck down, saved by the light.
	GameState.flags.erase("monk_revealed")
	await _reveal(5.0)
	_check(GameState.current_world_id == "vihara" and GameState.has_flag("saved_by_light"), "low hope dies and is saved")
	_check(GameState.hope >= 30.0, "being saved restores hope")

	# Vihara grants sacred light.
	DialogueManager.start("vihara_monk")
	await _wait_until(func() -> bool: return not DialogueManager.is_active(), 300)
	_check(GameState.has_power("sacred_light"), "vihara grants sacred light")

	# Finale boss -> ending.
	await _visit("finale")
	var oni := _find_boss()
	_check(oni != null and oni.is_oni, "finale has the oni")
	if oni:
		oni.awake = true
		oni.take_hit(99999.0, oni.global_position, 0.0, false, true)
		await _wait_until(func() -> bool: return get_tree().current_scene and get_tree().current_scene.scene_file_path.ends_with("ending.tscn"), 900)
		_check(get_tree().current_scene.scene_file_path.ends_with("ending.tscn"), "finale leads to ending")

	print("SMOKE TEST %s (%d failures)" % ["PASSED" if _failures == 0 else "FAILED", _failures])
	get_tree().quit(1 if _failures else 0)


## Flood fill over walkable tiles (gates count as open) from the spawn.
func _check_reachable(world: WorldBase) -> void:
	var start := world.tile_of(world.spawn_point + Vector2(0, -6))
	var seen := {start: true}
	var stack: Array[Vector2i] = [start]
	while not stack.is_empty():
		var t: Vector2i = stack.pop_back()
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var n: Vector2i = t + d
			var c := world._char(n)
			if c != " " and c != "#" and not seen.has(n):
				seen[n] = true
				stack.append(n)
	var missing: Array[String] = []
	for y in world._grid.size():
		for x in world._grid[y].length():
			var c := world._grid[y][x]
			if c != " " and c != "#" and not seen.has(Vector2i(x, y)):
				missing.append("%s@%d,%d" % [c, x, y])
	_check(missing.is_empty(), "%s: every floor tile reachable from spawn %s" % [world.data.id, "" if missing.is_empty() else str(missing.slice(0, 5))])


func _check_loot_systems() -> void:
	GameState.reset()
	await _visit("world_order")
	var world := get_tree().current_scene as WorldBase
	# Weapon variations: rolled instances carry rarity-many affixes and change stats.
	var rolled := Weapons.roll("wave_cutter", 1.0, 3)
	_check(int(rolled.rarity) == 3 and (rolled.affixes as Array).size() == 3, "legendary roll has 3 affixes")
	var keen := Weapons.make("wave_cutter", 1, [{"id": "keen", "v": 0.5}])
	_check(is_equal_approx(Weapons.build(keen).damage, Database.get_weapon("wave_cutter").damage * 1.5), "keen affix raises damage")
	_check(Weapons.display_name(keen).begins_with("Keen"), "affix names the weapon (%s)" % Weapons.display_name(keen))
	# Bag: add, equip (old one goes back in), salvage for gold.
	_check(GameState.add_to_bag(keen), "weapon goes into the bag")
	GameState.equip_from_bag(0)
	_check(GameState.get_weapon().uid == int(keen.uid) and GameState.inventory[0].base == "rusted_katana", "equip swaps with the bag")
	var gold_before := GameState.gold
	GameState.salvage(0)
	_check(GameState.gold > gold_before and GameState.inventory.is_empty(), "salvage turns a weapon into gold")
	for i in GameState.BAG_SIZE:
		GameState.add_to_bag(Weapons.make("reed_bow"))
	_check(not GameState.add_to_bag(Weapons.make("reed_bow")), "bag holds at most %d" % GameState.BAG_SIZE)
	GameState.inventory.clear()
	# Save/load keeps instances.
	GameState.add_to_bag(rolled)
	GameState.save_game()
	GameState.load_game()
	_check(GameState.inventory.size() == 1 and Weapons.display_name(GameState.inventory[0]) == Weapons.display_name(rolled), "bag survives save/load")
	GameState.inventory.clear()
	# Potions.
	GameState.potions = 2
	GameState.damage_player(50.0)
	var hp := GameState.health
	world.player.drink_potion()
	_check(GameState.health > hp and GameState.potions == 1, "drinking a potion heals and uses one")
	# Chests and pots.
	var chest: Node = world.chests[0] if not world.chests.is_empty() else null
	_check(chest != null, "world_order has a chest")
	if chest:
		var pickups_before := _count_pickups(world)
		chest.interact(world.player)
		await _physics_frames(3)
		_check(_count_pickups(world) > pickups_before, "opening a chest drops a weapon")
	var pot: Node = null
	for e in world.entities.get_children():
		if e.has_method("smash"):
			pot = e
			break
	_check(pot != null, "world_order has breakable pots")
	if pot:
		world.player.global_position = pot.global_position + Vector2(-50, 0)
		world.player.aim = Vector2.RIGHT
		var hits: Array = world.player._melee_box(pot.global_position + Vector2(-50, -15), Vector2(70, 72))
		_check(hits.has(pot), "melee reaches pots")
		pot.smash()
		await _physics_frames(20)
		_check(not is_instance_valid(pot), "pots break")
	# Inventory screen opens, pauses, closes.
	world.inventory_ui.open()
	_check(world.inventory_ui.is_open() and get_tree().paused, "inventory opens and pauses")
	world.inventory_ui.close()
	_check(not get_tree().paused, "inventory closes and unpauses")


## Walking onto a portal takes you through; a shut one only warns.
func _check_portal_walk_in() -> void:
	GameState.reset()
	await _visit("sanctum")
	await _wait_until(func() -> bool: return not GameState.is_player_locked(), 300)
	var world := get_tree().current_scene as WorldBase
	var portal: Portal = null
	for e in world.entities.get_children():
		if e is Portal:
			portal = e
	_check(portal != null, "sanctum has a portal")
	if not portal:
		return
	world.player.global_position = portal.global_position
	await _physics_frames(10)
	_check(not SceneRouter.is_busy() and GameState.current_world_id == "sanctum", "shut portal does not teleport")
	world.player.global_position = world.spawn_point
	await _physics_frames(3)
	GameState.set_flag("monk_briefed")
	world.player.global_position = portal.global_position + Vector2(0, 10)
	await _wait_until(func() -> bool: return SceneRouter.is_busy() or GameState.current_world_id != "sanctum", 60)
	_check(GameState.current_world_id == Database.mission_order[0], "walking into an open portal teleports")
	await _wait_until(func() -> bool: return not SceneRouter.is_busy(), 600)
	await _wait_until(func() -> bool: return not DialogueManager.is_active(), 300)


## Each monster boss is the right form and actually uses its signature moves.
func _check_boss_mechanics() -> void:
	var forms := {"world_order": SerpentBoss, "world_doubt": MothBoss, "world_truth": EyeBoss}
	for id: String in forms:
		GameState.reset()
		GameState.set_flag("intro_seen_" + id)
		await _visit(id)
		await _wait_until(func() -> bool: return not GameState.is_player_locked(), 300)
		var world := get_tree().current_scene as WorldBase
		var boss := _find_boss()
		_check(boss != null and is_instance_of(boss, forms[id]) and boss.figure is MonsterFigure, "%s boss is a %s monster" % [id, Database.get_world(id).boss_form])
		_check(boss != null and boss.display_name == Database.get_world(id).boss_name, "%s boss keeps its name" % id)
		if not boss:
			continue
		# Walk into the arena so the fight starts for real (intro included).
		world.player.global_position = boss.global_position + Vector2(-260, 0)
		await _wait_until(func() -> bool: return boss.awake and not GameState.is_player_locked(), 600)
		GameState.potions = 0
		if boss is SerpentBoss:
			boss._dive_t = 0.0
			await _wait_until(func() -> bool: return boss.submerged, 120)
			_check(boss.submerged and not boss.is_targetable(), "serpent dives and can't be hit")
			var hp: float = boss.health
			boss.take_hit(50.0, boss.global_position, 0.0)
			_check(is_equal_approx(boss.health, hp), "submerged serpent takes no damage")
			await _wait_until(func() -> bool: return not boss.submerged, 400)
			_check(not boss.submerged, "serpent erupts back up")
			boss._phase = 2
			boss._dives = 1
			boss._dive_t = 0.0
			await _wait_until(func() -> bool: return world.entities.get_children().any(func(n: Node) -> bool: return n is TideWave), 120)
			_check(world.entities.get_children().any(func(n: Node) -> bool: return n is TideWave), "phase 2 serpent sends a tidal wave")
			for i in 600:  # immune until she surfaces; physics frames, since headless rendering runs uncapped
				if not boss.submerged:
					break
				await get_tree().physics_frame
		elif boss is MothBoss:
			boss._cycle = -1
			boss._attack_t = 0.0
			await _physics_frames(3)
			_check(world.level.get_children().any(func(n: Node) -> bool: return n is Hazard and not n.lingering), "moth rains fire on marked circles")
			boss._cycle = 0
			boss._attack_t = 0.0
			await _physics_frames(3)
			_check(world.level.get_children().any(func(n: Node) -> bool: return n is Hazard and n.lingering), "moth leaves slowing ash")
			boss._cycle = 2
			boss._attack_t = 0.0
			await _physics_frames(3)
			_check(boss.living_minions("bat") >= 2, "moth summons a swarm")
		elif boss is EyeBoss:
			_check(boss.shielded() and boss._shards.size() == 3, "eye is shielded by three shards")
			var hp: float = boss.health
			boss.take_hit(100.0, boss.global_position, 0.0)
			_check(hp - boss.health < 100.0 * EyeBoss.SHIELDED + 1.0, "shards soak damage")
			for sh in boss._shards:
				if is_instance_valid(sh):
					sh.take_hit(99999.0, sh.global_position, 0.0)
			await _physics_frames(3)
			_check(not boss.shielded(), "breaking the shards drops the shield")
			boss._beam_t = 0.0
			boss._blink_t = 99.0
			await _wait_until(func() -> bool: return boss._beam_on, 60)
			_check(boss._beam_on, "eye fires its sweeping beam")
		boss.take_hit(99999.0, boss.global_position, 0.0)
		await _wait_until(func() -> bool: return GameState.has_flag("boss_defeated_" + id), 900)
		_check(GameState.has_flag("boss_defeated_" + id) and boss.living_minions() == 0, "%s boss dies and takes its minions with it" % id)


## Plays each NPC subquest end to end through its real dialogue files (the
## runner always picks the first visible choice, which is the helpful one).
func _check_subquests() -> void:
	var plans := [
		{"world": "world_order", "quest": "black_water", "steps": ["order_hana", "order_fisher", "ITEM", "order_hana", "BOSS", "order_hana"],
			"vow": "hana_vow", "reward": "tide_naginata"},
		{"world": "world_doubt", "quest": "walk_them_home", "steps": ["doubt_tobi", "doubt_mei", "ITEM", "doubt_tobi", "BOSS", "doubt_mei"],
			"vow": "mei_vow", "reward": "storm_rod"},
		{"world": "world_truth", "quest": "last_page", "steps": ["truth_aki", "truth_iro", "ITEM", "truth_aki", "BOSS", "truth_aki"],
			"vow": "aki_new_ending", "reward": ""},
	]
	for plan: Dictionary in plans:
		GameState.reset()
		GameState.hope = 60.0
		var wid: String = plan.world
		await _visit(wid)
		var world := get_tree().current_scene as WorldBase
		var quest: Dictionary = Quests.all().filter(func(q: Dictionary) -> bool: return q.id == plan.quest)[0]
		var item: Node = null
		for e in world.entities.get_children():
			if e.get("info") is Dictionary:
				item = e
		_check(item != null and not item.available(), "%s: quest item hidden before the quest starts" % plan.quest)
		var potions_before := GameState.potions
		for step: String in plan.steps:
			match step:
				"ITEM":
					_check(item.available(), "%s: quest item appears once needed" % plan.quest)
					item.interact(world.player)
				"BOSS":
					GameState.set_flag("boss_defeated_" + wid)
				_:
					DialogueManager.start(step)
			await _wait_until(func() -> bool: return not DialogueManager.is_active(), 600)
			await _frames(2)
		_check(Quests.complete(quest), "%s: subquest runs to its end (stuck at: %s)" % [plan.quest, Quests.current_text(quest)])
		_check(GameState.has_key(wid), "%s: still hands over the key" % plan.quest)
		_check(GameState.has_flag(str(plan.vow)), "%s: the closing promise is made" % plan.quest)
		_check(GameState.potions > potions_before, "%s: rewards potions" % plan.quest)
		if str(plan.reward) != "":
			_check(GameState.inventory.any(func(i: Dictionary) -> bool: return i.base == plan.reward), "%s: gives %s" % [plan.quest, plan.reward])
	# Kept promises are honoured at the Vihara.
	GameState.set_flag("kept_promise")
	var hope_before := GameState.hope
	DialogueManager.start("vihara_monk")
	await _wait_until(func() -> bool: return not DialogueManager.is_active(), 600)
	_check(GameState.hope >= hope_before + 10.0 and GameState.has_power("sacred_light"), "the Bhikkhu honours kept promises")


## Every synthesised sound renders: audible, not clipped, short.
func _check_sounds() -> void:
	var bad: Array[String] = []
	for sound: String in Sfx.RECIPES:
		var samples: PackedFloat32Array = Sfx.RECIPES[sound].call()
		var peak := 0.0
		for v in samples:
			peak = maxf(peak, absf(v))
		var seconds := samples.size() / float(Sfx.RATE)
		if peak < 0.03 or peak > 1.2 or seconds > 2.0:
			bad.append("%s (peak %.2f, %.2fs)" % [sound, peak, seconds])
	_check(bad.is_empty(), "all %d sounds render cleanly %s" % [Sfx.RECIPES.size(), "" if bad.is_empty() else str(bad)])
	Sfx.play("hit")
	Sfx.play_at("enemy_die", Vector2.ZERO)


func _count_pickups(world: WorldBase) -> int:
	return world.entities.get_children().filter(func(n: Node) -> bool: return n.get("item") is Dictionary).size()


func _check_mobs() -> void:
	GameState.reset()
	await _visit("world_order")
	var world := get_tree().current_scene as WorldBase
	var kinds := {}
	for e in get_tree().get_nodes_in_group("enemies"):
		kinds[(e as Enemy).archetype] = true
	_check(kinds.size() >= 5, "world_order mixes mob types %s" % str(kinds.keys()))
	var far := world.spawn_point
	# Archer shoots, slime splits, elites are tougher and always drop a weapon.
	await _wait_until(func() -> bool: return not GameState.is_player_locked(), 300)  # dialogue grace period
	var archer := world.spawn_enemy("archer", far + Vector2(300, 0), -1)
	archer.aggro = true
	archer._act_t = 0.0
	await _physics_frames(3)
	_check(world.entities.get_children().any(func(n: Node) -> bool: return n is EnemyShot), "archer fires arrows")
	archer.take_hit(99999.0, archer.global_position, 0.0)
	var slime := world.spawn_enemy("slime", far + Vector2(200, 60), 0)
	var room: WorldBase.Room = world.rooms[0]
	var before := room.enemies.size()
	slime.take_hit(99999.0, slime.global_position, 0.0)
	await _physics_frames(3)
	_check(room.enemies.size() == before + 2, "slime splits into two halves")
	for e in room.enemies:
		if is_instance_valid(e) and not e.is_dead():
			e.take_hit(99999.0, e.global_position, 0.0)
	var normal := world.spawn_enemy("chaser", far + Vector2(250, 0), -1)
	var elite := world.spawn_enemy("chaser", far + Vector2(250, 80), -1, true)
	_check(is_equal_approx(elite.max_health, normal.max_health * 2.5) and elite.display_name.begins_with("Elite"), "elites are tougher")
	var pickups_before := _count_pickups(world)
	elite.take_hit(99999.0, elite.global_position, 0.0)
	await _physics_frames(3)
	_check(_count_pickups(world) > pickups_before, "elites always drop a weapon")
	normal.take_hit(99999.0, normal.global_position, 0.0)
	await _physics_frames(30)


## Every weapon kind deals damage to an enemy in front of the samurai.
func _check_weapon_kinds() -> void:
	GameState.reset()
	await _visit("world_order")
	var world := get_tree().current_scene as WorldBase
	for id in ["rusted_katana", "tide_naginata", "noir_odachi", "lamplight_tanto", "bamboo_staff", "reed_bow"]:
		GameState.give_weapon(id)
		var w := GameState.get_weapon()
		var dummy := world.spawn_enemy("turret", world.spawn_point + Vector2(minf(w.reach * 0.6, 200.0) + 30.0, 0), -1)
		dummy.max_health = 9999.0
		dummy.health = 9999.0
		dummy.aggro = true
		await _physics_frames(2)
		world.player.global_position = world.spawn_point
		world.player.velocity = Vector2.ZERO
		world.player._attack_cd = 0.0
		world.player._attack()
		await _physics_frames(40)
		_check(dummy.health < 9999.0, "%s (%s) hits" % [id, WeaponData.kind_name(w.kind)])
		dummy.queue_free()
		await _physics_frames(2)
	# Combo: the third hit within the window is a finisher.
	world.player._combo = 2
	world.player._combo_t = 1.0
	world.player._attack_cd = 0.0
	world.player._attack()
	_check(world.player._combo == 3, "third chained hit is a finisher")


func _reveal(hope: float) -> void:
	await _visit("sanctum")
	GameState.hope = hope
	DialogueManager.start("monk")
	await _wait_until(func() -> bool: return GameState.current_world_id == "vihara" and not SceneRouter.is_busy() \
		and get_tree().current_scene is WorldBase and (get_tree().current_scene as WorldBase).data.id == "vihara", 900)
	await _wait_until(func() -> bool: return not DialogueManager.is_active(), 300)


func _visit(id: String) -> void:
	await _wait_until(func() -> bool: return not SceneRouter.is_busy(), 600)
	SceneRouter.go_to_world(id)
	await _wait_until(func() -> bool: return not SceneRouter.is_busy() and get_tree().current_scene is WorldBase, 600)
	var world := get_tree().current_scene as WorldBase
	_check(world.data != null and world.data.id == id, "loaded world %s" % id)
	_check(world.player != null, "%s spawned player" % id)
	await _frames(30)
	await _wait_until(func() -> bool: return not DialogueManager.is_active(), 300)


func _find_boss() -> Boss:
	for e in get_tree().get_nodes_in_group("enemies"):
		if e is Boss:
			return e
	return null


func _physics_frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _wait_until(cond: Callable, max_frames: int) -> void:
	for i in max_frames:
		if cond.call():
			return
		await get_tree().process_frame


func _check(ok: bool, what: String) -> void:
	if ok:
		print("  ok   ", what)
	else:
		_failures += 1
		push_error("FAIL " + what)
