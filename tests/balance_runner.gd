extends Node
## Economy + boss balance check.
## Economy: every shop item must be affordable with the gold a player can earn
## up to the end of that mission, and each later shop must have something
## affordable on arrival.
## Bosses: A deliberately dumb bot (walk at the boss, swing whenever
## the blade is ready, never dodge) fights each boss with the build a player
## would realistically have by then. If the bot wins, a player will.
## Run: godot --headless --path . --quit-after 60000 res://tests/balance_test.tscn

## Expected state on reaching each boss: rooms cleared so far give one reward
## card each, and the gold from those rooms buys roughly one shop weapon.
const CASES := [
	{"world": "world_order", "weapon": "rusted_katana", "hope": 60.0, "powers": [],
		"skills": {"spirit_dart": 1}, "elements": {"blade": "fire"}},
	{"world": "world_doubt", "weapon": "wave_cutter", "hope": 55.0, "powers": ["tide_step"],
		"skills": {"spirit_dart": 1, "whirlwind": 1}, "elements": {"blade": "poison"}},
	{"world": "world_truth", "weapon": "wave_cutter", "hope": 50.0, "powers": ["tide_step", "lantern_flare"],
		"skills": {"spirit_dart": 2, "crescent_wave": 1}, "elements": {"blade": "fire", "spirit_dart": "shock"}},
	{"world": "finale", "weapon": "wave_cutter", "hope": 45.0, "powers": ["tide_step", "lantern_flare", "panel_skip", "sacred_light"],
		"skills": {"spirit_dart": 2, "crescent_wave": 1}, "elements": {"blade": "fire", "spirit_dart": "shock"}},
	# Worst case: no skills, no elements, starting blade. Reported, never failed.
	{"world": "world_order", "weapon": "rusted_katana", "hope": 60.0, "powers": [], "skills": {}, "elements": {}, "info": true},
	{"world": "world_truth", "weapon": "rusted_katana", "hope": 30.0, "powers": ["tide_step", "lantern_flare"], "skills": {}, "elements": {}, "info": true},
	{"world": "finale", "weapon": "rusted_katana", "hope": 20.0, "powers": ["sacred_light"], "skills": {}, "elements": {}, "info": true},
]
## A boss is "easy" when the dumb bot kills it this fast and keeps this much HP.
## Expected hope while in each mission (boss kills drain a little light).
const MISSION_HOPE := {"world_order": 60.0, "world_doubt": 55.0, "world_truth": 50.0}
const COIN_VALUE := 3  ## the `c` pickups in layouts
const BOSS_GOLD := 50.0  ## midpoint of Boss._die's Vector2i(40, 60) drop
const MAX_SECONDS := 40.0
## Fights run on real-time timers next to fixed physics steps, so no two runs are
## identical; each boss is fought this many times and judged on the median.
const TRIES := 3
const MIN_HP_LEFT := 0.25

var _failures := 0


func _process(_delta: float) -> void:
	if DialogueManager.is_active():
		var box: DialogueBox = DialogueManager._box
		box._finish_typing()
		if DialogueManager._visible_choices.is_empty():
			box.advanced.emit()
		else:
			box.choice_selected.emit(0)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	await _frames(5)
	await _wait_until(func() -> bool: return Sfx.is_ready(), 600)  # sounds render in the background
	_check_economy()
	for c: Dictionary in CASES:
		var results: Array[Dictionary] = []
		for i in (1 if c.get("info", false) else TRIES):
			results.append(await _fight(c, i))
		if not c.get("info", false):
			_judge(str(c.world), results)
	print("BALANCE TEST %s (%d failures)" % ["PASSED" if _failures == 0 else "FAILED", _failures])
	get_tree().quit(1 if _failures else 0)


## Median of each measure across tries decides pass/fail.
func _judge(id: String, results: Array[Dictionary]) -> void:
	var wins := results.filter(func(r: Dictionary) -> bool: return r.won).size()
	var times: Array = results.map(func(r: Dictionary) -> float: return r.t)
	var hps: Array = results.map(func(r: Dictionary) -> float: return r.hp_left)
	times.sort()
	hps.sort()
	var t: float = times[times.size() / 2]
	var hp: float = hps[hps.size() / 2]
	print("  %-12s median of %d: won %d/%d, %.1fs, lowest HP %d%%" % [id, results.size(), wins, results.size(), t, roundi(hp * 100.0)])
	if wins * 2 <= results.size():
		_fail("%s: bot lost most fights" % id)
	elif t > MAX_SECONDS:
		_fail("%s: median fight %.0fs (> %.0fs)" % [id, t, MAX_SECONDS])
	elif hp < MIN_HP_LEFT:
		_fail("%s: median lowest HP %d%%" % [id, roundi(hp * 100.0)])


func _fight(c: Dictionary, attempt: int = 0) -> Dictionary:
	seed(hash(str(c.world) + str(c.weapon)) + attempt)
	GameState.reset()
	var id: String = c.world
	GameState.set_flag("intro_seen_" + id)
	GameState.set_flag("run_started_" + id)
	for p: String in c.powers:
		GameState.grant_power(p)
	GameState.give_weapon(str(c.weapon))
	GameState.hope = float(c.hope)
	GameState.run_skills = c.skills.duplicate()
	GameState.run_elements = c.elements.duplicate()
	GameState.full_heal()
	SceneRouter.go_to_world(id)
	await _wait_until(func() -> bool: return not SceneRouter.is_busy() and get_tree().current_scene is WorldBase, 600)
	var world := get_tree().current_scene as WorldBase
	await _frames(10)
	var boss: Boss = null
	for e in get_tree().get_nodes_in_group("enemies"):
		if e is Boss:
			boss = e
	if not boss:
		_fail("%s: no boss" % id)
		return {"won": false, "t": 999.0, "hp_left": 0.0}
	var player := world.player
	# Stand at the arena's edge, facing in.
	player.global_position = boss.global_position + Vector2(-320, 0)
	var t := 0.0
	var lowest := GameState.health
	var taken := [0.0]  # array: lambdas capture locals by value
	var hp_seen := [GameState.health]
	var on_hp := func(cur: float, _m: float) -> void:
		taken[0] += maxf(0.0, hp_seen[0] - cur)
		hp_seen[0] = cur
	GameState.health_changed.connect(on_hp)
	while t < 120.0 and is_instance_valid(boss) and not boss.is_dead() and not player.dead:
		await get_tree().physics_frame
		if DialogueManager.is_active() or GameState.is_player_locked():
			continue
		t += 1.0 / Engine.physics_ticks_per_second  # real seconds, hit-stop included
		var to := boss.global_position - player.global_position
		var dir := to.normalized() if to.length() > 70.0 else Vector2.ZERO
		player.velocity = dir * player.run_speed
		if dir != Vector2.ZERO:
			player.aim = dir
		if player._attack_cd <= 0.0:
			player._attack()
		if player._power_cd <= 0.0 and to.length() < 160.0:
			player._use_active_power()
		lowest = minf(lowest, GameState.health)
	GameState.health_changed.disconnect(on_hp)
	var won := not is_instance_valid(boss) or boss.is_dead()
	var hp_left := lowest / GameState.get_max_health()
	var hp_text := "%d / %d" % [roundi(lowest), roundi(GameState.get_max_health())]
	var boss_left := 0.0 if won else boss.health / boss.max_health
	print("  %-12s %-14s %s%s in %5.1fs, lowest HP %s (%d%%), took %d dmg = %.1f/s, boss left at %d%%" % [id, c.weapon,
		"(bare) " if c.get("info", false) else "", "WON " if won else "LOST", t, hp_text, roundi(hp_left * 100.0), roundi(taken[0]), taken[0] / maxf(t, 0.1), roundi(boss_left * 100.0)])
	await _wait_until(func() -> bool: return not DialogueManager.is_active() and not SceneRouter.is_busy(), 900)
	return {"won": won, "t": t, "hp_left": hp_left}


func _check_economy() -> void:
	GameState.reset()
	var before := 0.0  # gold earned before entering the mission
	for id in Database.mission_order:
		var w := Database.get_world(id)
		GameState.hope = float(MISSION_HOPE.get(id, 50.0))
		var mult := GameState.get_gold_multiplier()
		var avg_drop := (w.gold_per_enemy.x + w.gold_per_enemy.y) * 0.5
		var enemies := 0
		for letter: String in WorldData.ENEMY_LETTERS:
			enemies += w.layout.count(letter)
		var earned := enemies * avg_drop * mult + w.layout.count("c") * COIN_VALUE \
			+ (BOSS_GOLD * mult if w.boss_name != "" else 0.0)
		if id == Database.mission_order[0]:
			earned += 3 * Database.get_world("sanctum").layout.count("c")
		var by_end := before + earned
		var cheapest := INF
		var parts: Array[String] = []
		for item in w.shop_stock:
			var weapon := Database.get_weapon(item)
			var price := GameState.get_shop_price(weapon)
			cheapest = minf(cheapest, price)
			parts.append("%s %dg" % [item, price])
			if price > by_end:
				_fail("%s: %s costs %dg but only ~%dg is earnable by the end of the mission" % [id, item, price, roundi(by_end)])
		print("  %-12s arrive ~%3dg, earn ~%3dg, ~%3dg by end | %s" % [id, roundi(before), roundi(earned), roundi(by_end), ", ".join(parts)])
		if before > 0.0 and cheapest > before:
			_fail("%s: nothing in the shop is affordable on arrival (~%dg, cheapest %dg)" % [id, roundi(before), cheapest])
		before = by_end
	GameState.reset()


func _fail(what: String) -> void:
	_failures += 1
	push_error("FAIL " + what)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _wait_until(cond: Callable, max_frames: int) -> void:
	for i in max_frames:
		if cond.call():
			return
		await get_tree().process_frame
