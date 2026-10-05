class_name Boss
extends Enemy
## A world's "target": the protector of its light. Sleeps until the player walks
## into its arena (the room seals behind them), speaks, then fights in two
## phases (phase 2 below half health). On defeat its light escapes to the monk
## and the player absorbs the world's power.
##
## This base class is the humanoid fighter (the Oni): telegraphed charges, plus
## a ground slam in phase 2. Monster bosses (scripts/enemies/bosses/) override
## _fight() and draw with a MonsterFigure.

signal fight_started
signal light_released

@export var intro_dialogue: String = ""
@export var defeat_dialogue: String = ""
@export var power_id: String = ""
@export var hope_on_kill: float = -5.0
## Oni bosses shrug off ordinary steel (25%) unless sacred light has exposed them.
@export var is_oni: bool = false
@export var slam_radius: float = 170.0
## Walking into the player only deals this share of contact_damage; charges deal it all.
@export var touch_damage_share: float = 0.5
## How long Sacred Light leaves an oni open to ordinary steel.
@export var exposed_time: float = 3.0
## The humanoid Oni towers over everyone else.
var figure_scale := 1.0

var awake := false
var _pattern_t := 2.0
var _charging := 0.0
var _charge_dir := Vector2.ZERO
var _phase := 1
var _next_slam := false
var _exposed_t := 0.0
var _minions: Array[Enemy] = []


func is_targetable() -> bool:
	return awake


func reset_to_home() -> void:
	super.reset_to_home()
	_charging = 0.0
	_pattern_t = 2.0
	for m in _minions:
		if is_instance_valid(m) and not m.is_dead():
			m.queue_free()
	_minions.clear()


func _contact_multiplier() -> float:
	return 1.0 if _charging > 0.0 else touch_damage_share


## After landing a touch the boss steps back for a beat: an opening to hit back.
func _on_contact(player: Player) -> void:
	_contact_cd = 1.0
	if _charging > 0.0:
		_charging = 0.0
	_knock = (global_position - player.global_position).normalized() * 260.0
	_stun = maxf(_stun, 0.5)


func _physics_process(delta: float) -> void:
	_exposed_t -= delta  # here, not in _think: hits stun the boss and skip _think
	super._physics_process(delta)


func _think(delta: float) -> void:
	var player := _get_player()
	if not awake:
		velocity = Vector2.ZERO
		if aggro and player and not player.dead and not GameState.is_player_locked():
			_awaken()
		return
	if GameState.is_player_locked() or not player or player.dead or not aggro:
		velocity = velocity.move_toward(Vector2.ZERO, 1200.0 * delta)
		return
	_fight(delta, player, player.global_position - global_position)


## One tick of the fight while awake and the player is in the arena. Override per boss.
func _fight(delta: float, _player: Player, to: Vector2) -> void:
	if _charging > 0.0:
		_charging -= delta
		velocity = _charge_dir * chase_speed * 2.8
		if get_slide_collision_count() > 0:
			_charging = 0.0
			get_tree().current_scene.call("shake", 6.0)
		return
	_face(to.x)
	velocity = to.normalized() * speed * (1.4 if _phase == 2 else 1.0)
	_pattern_t -= delta
	if _pattern_t <= 0.0:
		_pattern_t = 2.0 if _phase == 2 else 3.0
		if _phase == 2 and _next_slam:
			_telegraph_slam()
		else:
			_telegraph_charge()
		_next_slam = not _next_slam


func _telegraph_charge() -> void:
	figure.modulate = Color(1.8, 0.6, 0.6)
	Sfx.play("warning")
	SfxWord.spawn(get_parent(), global_position + Vector2(0, -figure.height - 20), "!!", Color(1.0, 0.3, 0.3), 36)
	_stun = 0.45
	await get_tree().create_timer(0.45).timeout
	if _dead:
		return
	figure.modulate = Color.WHITE
	var player := _get_player()
	if player:
		_charge_dir = (player.global_position - global_position).normalized()
		_charging = 0.55


## Phase 2: crouch, then a shockwave around the boss.
func _telegraph_slam() -> void:
	figure.modulate = Color(1.8, 1.2, 0.4)
	_stun = 0.7
	var warn := BurstRing.new()
	warn.radius = slam_radius
	warn.color = Color(1.0, 0.3, 0.2)
	warn.position = position
	get_parent().add_child(warn)
	await get_tree().create_timer(0.6).timeout
	if _dead:
		return
	figure.modulate = Color.WHITE
	var ring := BurstRing.new()
	ring.radius = slam_radius
	ring.color = Color(1.0, 0.6, 0.2)
	ring.position = position
	get_parent().add_child(ring)
	Sfx.play("boom")
	SfxWord.spawn(get_parent(), global_position + Vector2(0, -40), "BOOM!", Color(1.0, 0.5, 0.1), 44)
	get_tree().current_scene.call("shake", 10.0)
	var player := _get_player()
	if player and player.global_position.distance_to(global_position) <= slam_radius:
		player.take_damage(contact_damage * 1.2, global_position)


func _awaken() -> void:
	awake = true
	Sfx.play("roar")
	GameState.boss_engaged.emit(self)
	if intro_dialogue != "":
		await DialogueManager.play(intro_dialogue)
	fight_started.emit()


func take_hit(amount: float, from: Vector2, knockback: float, crit: bool = false, is_light: bool = false) -> void:
	if not awake:
		return
	if is_oni and is_light and GameState.has_power("sacred_light"):
		if _exposed_t <= 0.0:
			SfxWord.spawn(get_parent(), global_position + Vector2(0, -figure.height - 10), "EXPOSED!", Color(1.0, 0.95, 0.6), 34)
		_exposed_t = exposed_time
	if is_oni and _exposed_t <= 0.0:
		amount *= 0.25
		if randf() < 0.3:
			SfxWord.spawn(get_parent(), global_position + Vector2(0, -figure.height), "TINK", Color(0.7, 0.7, 0.8), 22)
	super.take_hit(amount, from, knockback * 0.35, crit, is_light)
	_stun = minf(_stun, 0.05) if _charging > 0.0 else _stun
	if _phase == 1 and health <= max_health * 0.5 and not _dead:
		_phase = 2
		Sfx.play("roar", 2.0)
		SfxWord.spawn(get_parent(), global_position + Vector2(0, -figure.height - 30), "RAAAH!", Color(1.0, 0.5, 0.1), 44)
		_enter_phase_2()


## Hook for monster bosses (new attacks, summons) when health drops below half.
func _enter_phase_2() -> void:
	pass


func _world() -> WorldBase:
	return get_tree().current_scene as WorldBase


## The boss room's floor in world pixels (shrunk by `margin`).
func arena_rect(margin: float = 0.0) -> Rect2:
	var w := _world()
	if not w or room_id < 0:
		return Rect2(home - Vector2(400, 300), Vector2(800, 600)).grow(-margin)
	var r := Rect2()
	var first := true
	for t: Vector2i in w.rooms[room_id].tiles:
		var tile := Rect2(Vector2(t) * w.data.tile_size, Vector2.ONE * w.data.tile_size)
		r = tile if first else r.merge(tile)
		first = false
	return r.grow(-margin)


## A random open floor spot in the arena at least `min_dist` from `away_from`.
func arena_spot(away_from: Vector2, min_dist: float) -> Vector2:
	var w := _world()
	if not w or room_id < 0:
		return home
	var tiles: Array = w.rooms[room_id].tiles.keys()
	tiles.shuffle()
	for t: Vector2i in tiles:
		var p := (Vector2(t) + Vector2(0.5, 0.75)) * w.data.tile_size
		var inner := w.rooms[room_id].tiles
		var open := inner.has(t + Vector2i.LEFT) and inner.has(t + Vector2i.RIGHT) and inner.has(t + Vector2i.UP) and inner.has(t + Vector2i.DOWN)
		if open and p.distance_to(away_from) >= min_dist:
			return p
	return home


## Calls in an enemy of `kind` (drawn as MonsterFigure `form` if given) to fight in this arena.
func summon(kind: String, pos: Vector2, look: Dictionary = {}, form: String = "") -> Enemy:
	var w := _world()
	if not w:
		return null
	var e := w.spawn_enemy(kind, pos, room_id, false, false, look, form)
	e.weapon_drop_chance = 0.0
	e.gold_range = Vector2i(0, 1)
	_minions.append(e)
	Sfx.play_at("puff", pos, -4.0)
	SfxWord.spawn(get_parent(), pos + Vector2(0, -60), "!", Color(1, 0.8, 0.3), 24)
	return e


func living_minions(kind: String = "") -> int:
	var n := 0
	for m in _minions:
		if is_instance_valid(m) and not m.is_dead() and (kind == "" or m.archetype == kind):
			n += 1
	return n


## Shared telegraph tint.
func _flash(col: Color) -> void:
	figure.modulate = col
	create_tween().tween_property(figure, "modulate", Color.WHITE, 0.5)


func apply_element(element: String, dmg: float) -> void:
	if awake:
		super.apply_element(element, dmg * 0.6)  # bosses shrug off some of it


func _die() -> void:
	_dead = true
	collision_layer = 0
	for m in _minions:
		if is_instance_valid(m) and not m.is_dead():
			m.take_hit(99999.0, m.global_position, 0.0)
	SfxWord.spawn(get_parent(), global_position + Vector2(0, -figure.height), "...", Color.WHITE, 40)
	Sfx.play("boss_die")
	GameState.full_heal()
	var light := LightFragment.new()
	light.position = position + Vector2(0, -figure.height * 0.6)
	get_parent().add_child(light)
	create_tween().tween_property(figure, "modulate:a", 0.15, 1.5)
	await light.absorbed
	light_released.emit()
	GameState.change_hope(hope_on_kill, "light_taken")
	if power_id != "":
		GameState.grant_power(power_id)
	if world_id != "":
		GameState.set_flag("boss_defeated_" + world_id)
	Loot.drop_for_enemy(get_parent(), global_position, Vector2i(40, 60), drop_table, world_id, 1.0)
	if defeat_dialogue != "":
		await DialogueManager.play(defeat_dialogue)
	defeated.emit(self)
	queue_free()
