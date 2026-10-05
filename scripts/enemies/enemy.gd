class_name Enemy
extends CharacterBody2D
## A masked yokai, top-down. Wanders near its spawn until the player enters its
## room (the world sets `aggro`), then fights the way its archetype does
## (see ARCHETYPES): chasers rush you, archers keep their distance and shoot,
## bats swoop, slimes hop and split, brutes slam the ground, chargers rush in
## straight lines, and plant turrets spray spores. Elites are bigger, tougher,
## glow gold and always drop a weapon. Carries element statuses (burn, frost,
## shock, poison) and drops gold, weapons and potions on death.

signal defeated(enemy: Enemy)
signal health_changed(current: float, maximum: float)

@export var display_name: String = "Masked Shade"
@export var max_health: float = 30.0
@export var contact_damage: float = 10.0
@export var speed: float = 70.0
@export var chase_speed: float = 140.0
@export var gold_range: Vector2i = Vector2i(3, 8)
@export var weapon_drop_chance: float = 0.15
@export var drop_table: PackedStringArray = []
@export var sfx_on_death: String = "KRAK!"
## Radius used by skill shots and bursts to hit this body.
@export var hit_radius: float = 22.0

## Stat multipliers (on the world's enemy_health / enemy_damage), speeds, and the
## default look tweaks layered on the world's enemy_look.
const ARCHETYPES := {
	"chaser": {"hp": 1.0, "dmg": 1.0, "speed": 70.0, "chase": 140.0, "look": {}},
	"archer": {"hp": 0.8, "dmg": 0.9, "speed": 60.0, "chase": 110.0, "look": {"height": 54, "crown": "eboshi"}},
	"bat": {"hp": 0.55, "dmg": 0.7, "speed": 120.0, "chase": 210.0, "look": {"height": 30, "width": 40, "mask": "oni", "crown": "antlers"}},
	"slime": {"hp": 1.2, "dmg": 0.9, "speed": 50.0, "chase": 90.0, "look": {"height": 34, "width": 48, "mask": "none", "crown": "none"}},
	"brute": {"hp": 2.4, "dmg": 1.5, "speed": 45.0, "chase": 75.0, "look": {"height": 92, "width": 54, "mask": "oni", "crown": "spiked"}},
	"charger": {"hp": 1.2, "dmg": 1.2, "speed": 70.0, "chase": 100.0, "look": {"height": 62, "width": 38, "crown": "antlers"}},
	"turret": {"hp": 1.4, "dmg": 0.8, "speed": 0.0, "chase": 0.0, "look": {"height": 50, "width": 44, "mask": "sun", "crown": "lotus"}},
	## A boss's orbiting crystal: never moves or attacks on its own (EyeBoss places it).
	"shard": {"hp": 1.0, "dmg": 0.5, "speed": 0.0, "chase": 0.0, "look": {}},
}

@onready var figure: ComicFigure = $Figure
@onready var contact_area: Area2D = $ContactArea

var health: float
var world_id: String = ""
var room_id := -1
## True while the player stands in this enemy's room.
var aggro := false
var home: Vector2
var _stun := 0.0
var _dead := false
var _contact_cd := 0.0
var _wander_dir := Vector2.ZERO
var _wander_t := 0.0
var _knock := Vector2.ZERO
# Element statuses.
var _burn_t := 0.0
var _burn_dps := 0.0
var _poison_t := 0.0
var _poison_stacks := 0
var _poison_dps := 0.0
var _slow_t := 0.0
var _frost_hits := 0
var _status_tick := 0.0
# Archetype state.
var archetype := "chaser"
var elite := false
var mini := false  ## a slime's split-off half
var _act_t := 1.5  ## time until the next special action
var _action := ""  ## "", "windup", "dash", "hop"
var _act_dir := Vector2.ZERO
var _action_t := 0.0
var _bob := randf() * TAU


func _ready() -> void:
	add_to_group("enemies")
	health = max_health
	home = global_position
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING


func is_dead() -> bool:
	return _dead


func is_targetable() -> bool:
	return aggro


func stun(t: float) -> void:
	_stun = maxf(_stun, t)


## The room was left without clearing it: everyone heals and goes home.
func reset_to_home() -> void:
	if _dead:
		return
	health = max_health
	health_changed.emit(health, max_health)
	global_position = home
	velocity = Vector2.ZERO
	_knock = Vector2.ZERO
	_burn_t = 0.0
	_poison_t = 0.0
	_poison_stacks = 0
	_slow_t = 0.0
	_update_tint()


func _physics_process(delta: float) -> void:
	if _dead:
		return
	_contact_cd -= delta
	_tick_status(delta)
	if _dead:
		return
	_knock = _knock.move_toward(Vector2.ZERO, 1800.0 * delta)
	if _stun > 0.0:
		_stun -= delta
		velocity = _knock
	else:
		_think(delta)
		velocity = velocity * (0.5 if _slow_t > 0.0 else 1.0) + _knock
	move_and_slide()
	_deal_contact_damage()


## Sets the archetype (and elite status) before the enemy enters the tree.
func configure(kind: String, is_elite: bool = false, is_mini: bool = false) -> void:
	var a: Dictionary = ARCHETYPES.get(kind, ARCHETYPES.chaser)
	archetype = kind if ARCHETYPES.has(kind) else "chaser"
	elite = is_elite
	mini = is_mini
	max_health *= float(a.hp) * (2.5 if elite else 1.0) * (0.35 if mini else 1.0)
	contact_damage *= float(a.dmg) * (1.25 if elite else 1.0)
	speed = float(a.speed)
	chase_speed = float(a.chase) * (1.25 if mini else 1.0)
	if elite:
		gold_range *= 3
		display_name = "Elite " + display_name
	if mini:
		gold_range = Vector2i(1, 2)
		weapon_drop_chance = 0.0
	_act_t = randf_range(0.8, 2.0)


## Applies the archetype's default look over the world's, then any override.
func apply_looks(world_look: Dictionary, override: Dictionary) -> void:
	figure.apply_look(world_look)
	figure.apply_look(ARCHETYPES[archetype].look)
	figure.apply_look(override)
	var s := (1.3 if elite else 1.0) * (0.65 if mini else 1.0)
	figure.scale = Vector2(s, s)
	if elite:
		var aura := Node2D.new()
		aura.z_index = -1
		aura.draw.connect(func() -> void:
			aura.draw_circle(Vector2(0, -4), 30.0, Color(1.0, 0.8, 0.2, 0.25))
			aura.draw_arc(Vector2(0, -4), 30.0, 0, TAU, 24, Color(1.0, 0.8, 0.2, 0.8), 3.0))
		add_child(aura)


## Override for custom behaviour. Default: fight by archetype when aggro, otherwise wander.
func _think(delta: float) -> void:
	var player := _get_player()
	if archetype == "bat":
		_bob += delta * 9.0
		figure.position.y = -18.0 + sin(_bob) * 5.0
	if aggro and player and not player.dead and not GameState.is_player_locked():
		var to := player.global_position - global_position
		_face(to.x)
		_act_t -= delta
		match archetype:
			"archer": _fight_archer(to, delta)
			"bat": _fight_bat(to, delta)
			"slime": _fight_slime(to, delta)
			"brute": _fight_brute(to, delta)
			"charger": _fight_charger(to, delta)
			"turret": _fight_turret(to)
			"shard": velocity = Vector2.ZERO
			_: velocity = to.normalized() * chase_speed + _separation() * 90.0
		return
	_action = ""
	if archetype == "turret" or archetype == "shard":
		velocity = Vector2.ZERO
		return
	_wander_t -= delta
	if _wander_t <= 0.0:
		_wander_t = randf_range(1.0, 2.5)
		var back := home - global_position
		if back.length() > 110.0:
			_wander_dir = back.normalized()
		elif randf() < 0.35:
			_wander_dir = Vector2.ZERO
		else:
			_wander_dir = Vector2.from_angle(randf() * TAU)
	velocity = _wander_dir * speed
	_face(_wander_dir.x)


# --- Archetype fights -----------------------------------------------------------

## Keeps 200-320px away, strafing, and looses an arrow every ~1.8s after a short draw.
func _fight_archer(to: Vector2, delta: float) -> void:
	var d := to.length()
	var want := Vector2.ZERO
	if d < 200.0:
		want = -to.normalized()
	elif d > 320.0:
		want = to.normalized()
	else:
		want = to.normalized().orthogonal() * (1.0 if get_instance_id() % 2 == 0 else -1.0) * 0.6
	velocity = want * chase_speed + _separation() * 90.0
	if _windup(delta, 0.45, 1.8):
		EnemyShot.fire(get_parent(), global_position + Vector2(0, -32), to, contact_damage, figure.eye_glow if figure.eye_glow.a > 0.0 else Color(1, 0.4, 0.3), 380.0)


## Hovers at ~150px, then swoops through the player and pulls back out.
func _fight_bat(to: Vector2, delta: float) -> void:
	if _action == "dash":
		_action_t -= delta
		velocity = _act_dir * 430.0
		if _action_t <= 0.0:
			_action = ""
			_act_t = randf_range(1.4, 2.2)
		return
	var orbit := to.normalized().orthogonal() * 0.8 + to.normalized() * (to.length() - 150.0) / 150.0
	velocity = orbit.normalized() * chase_speed + _separation() * 60.0
	if _act_t <= 0.0:
		_action = "dash"
		_action_t = 0.45
		_act_dir = to.normalized()
		Sfx.play_at("screech", global_position, -6.0)


## Gathers itself, then hops toward the player.
func _fight_slime(to: Vector2, delta: float) -> void:
	if _action == "hop":
		_action_t -= delta
		velocity = _act_dir * 320.0
		figure.squash = -0.5
		if _action_t <= 0.0:
			_action = ""
			figure.squash = 0.4
			_act_t = randf_range(0.7, 1.2)
		return
	velocity = Vector2.ZERO
	figure.squash = lerpf(figure.squash, 0.35 if _act_t < 0.3 else 0.0, 0.2)
	if _act_t <= 0.0:
		_action = "hop"
		_action_t = 0.28
		Sfx.play_at("hop", global_position, -4.0)
		_act_dir = to.normalized()


## Lumbers in; up close it raises its club and slams the ground around it.
func _fight_brute(to: Vector2, delta: float) -> void:
	if _action == "windup":
		velocity = Vector2.ZERO
		_action_t -= delta
		if _action_t <= 0.0:
			_action = ""
			_act_t = 2.4
			_slam(120.0, contact_damage * 1.2)
		return
	velocity = to.normalized() * chase_speed + _separation() * 90.0
	if to.length() < 120.0 and _act_t <= 0.0:
		_action = "windup"
		_action_t = 0.7
		figure.modulate = Color(1.8, 0.7, 0.5)
		Sfx.play_at("warning", global_position)
		var warn := BurstRing.new()
		warn.radius = 120.0
		warn.color = Color(1.0, 0.3, 0.2)
		warn.position = position
		get_parent().add_child(warn)


## Paws the ground, then rushes in a straight line; dazed if it hits a wall.
func _fight_charger(to: Vector2, delta: float) -> void:
	if _action == "dash":
		_action_t -= delta
		velocity = _act_dir * 520.0
		if get_slide_collision_count() > 0:
			_action = ""
			stun(1.0)
			SfxWord.spawn(get_parent(), global_position + Vector2(0, -70), "BONK!", Color(1, 1, 0.6), 22)
		elif _action_t <= 0.0:
			_action = ""
		return
	if _action == "windup":
		velocity = Vector2.ZERO
		_action_t -= delta
		if _action_t <= 0.0:
			_action = "dash"
			_action_t = 0.5
			_act_dir = to.normalized()
			Sfx.play_at("charge", global_position)
			_act_t = randf_range(1.8, 2.6)
			figure.modulate = _tint()
		return
	velocity = to.normalized() * speed + _separation() * 90.0
	if _act_t <= 0.0 and to.length() < 380.0:
		_action = "windup"
		_action_t = 0.55
		Sfx.play_at("warning", global_position)
		figure.modulate = Color(1.8, 0.6, 0.6)
		SfxWord.spawn(get_parent(), global_position + Vector2(0, -80), "!", Color(1.0, 0.3, 0.3), 28)


## Rooted: fires a fan of three spores every ~2.4s.
func _fight_turret(to: Vector2) -> void:
	velocity = Vector2.ZERO
	if _act_t <= 0.0:
		_act_t = 2.4
		var col := Color(0.6, 0.95, 0.35)
		for a in [-0.3, 0.0, 0.3]:
			EnemyShot.fire(get_parent(), global_position + Vector2(0, -30), to.rotated(a), contact_damage, col, 260.0)
		_squash_pulse()


## Generic telegraph: tints during the last `windup` seconds of the cycle, then fires.
func _windup(_delta: float, windup: float, cycle: float) -> bool:
	if _act_t <= windup and _act_t + get_physics_process_delta_time() > windup:
		figure.modulate = Color(1.6, 1.3, 0.6)
	if _act_t <= 0.0:
		_act_t = cycle * randf_range(0.85, 1.15)
		figure.modulate = _tint()
		return true
	return false


func _slam(radius: float, dmg: float) -> void:
	figure.modulate = _tint()
	var ring := BurstRing.new()
	ring.radius = radius
	ring.color = Color(1.0, 0.6, 0.2)
	ring.position = position
	get_parent().add_child(ring)
	Sfx.play_at("slam", global_position)
	SfxWord.spawn(get_parent(), global_position + Vector2(0, -40), "THOOM!", Color(1.0, 0.5, 0.1), 30)
	var player := _get_player()
	if player and player.global_position.distance_to(global_position) <= radius:
		player.take_damage(dmg, global_position)


func _squash_pulse() -> void:
	var t := create_tween()
	t.tween_property(figure, "squash", 0.5, 0.08)
	t.tween_property(figure, "squash", 0.0, 0.15)


func _face(x: float) -> void:
	if absf(x) > 1.0:
		figure.facing = 1 if x > 0.0 else -1


## Gentle push away from packmates so a pack doesn't collapse into one sprite.
func _separation() -> Vector2:
	var push := Vector2.ZERO
	for e in get_tree().get_nodes_in_group("enemies"):
		if e == self or not e is Enemy or e.is_dead():
			continue
		var d: Vector2 = global_position - e.global_position
		var dist := d.length()
		if dist > 0.01 and dist < 50.0:
			push += d / dist * (1.0 - dist / 50.0)
	return push


func _deal_contact_damage() -> void:
	if _contact_cd > 0.0 or _stun > 0.0:
		return
	for body in contact_area.get_overlapping_bodies():
		if body is Player:
			body.take_damage(contact_damage * _contact_multiplier(), global_position)
			_contact_cd = 0.6
			_on_contact(body)


## Share of contact_damage dealt by touching the player right now.
func _contact_multiplier() -> float:
	match archetype:
		"archer", "turret": return 0.4
		"charger": return 1.0 if _action == "dash" else 0.5
		"brute": return 0.5
	return 1.0


func _on_contact(_player: Player) -> void:
	pass


func _get_player() -> Player:
	return get_tree().get_first_node_in_group("player") as Player


func take_hit(amount: float, from: Vector2, knockback: float, crit: bool = false, _is_light: bool = false) -> void:
	if _dead:
		return
	health -= amount
	health_changed.emit(health, max_health)
	Sfx.play_at("crit" if crit else "hit", global_position)
	var away := (global_position - from).normalized()
	_knock = away * knockback
	_stun = maxf(_stun, 0.18)
	figure.modulate = Color(3, 3, 3)
	create_tween().tween_property(figure, "modulate", _tint(), 0.15)
	if crit:
		SfxWord.spawn(get_parent(), global_position + Vector2(0, -90), "CRIT!", Color(1.0, 0.35, 0.2), 28)
	if health <= 0.0:
		_die()


# --- Elements -----------------------------------------------------------------

## `dmg` is the hit that carried the element; statuses scale from it.
func apply_element(element: String, dmg: float) -> void:
	if _dead:
		return
	Sfx.play_at({"fire": "burn", "shock": "zap", "poison": "poison"}.get(element, ""), global_position, -6.0)
	match element:
		"fire":
			_burn_dps = maxf(_burn_dps if _burn_t > 0.0 else 0.0, dmg * 0.3)
			_burn_t = 3.0
		"frost":
			_slow_t = 2.0
			_frost_hits += 1
			if _frost_hits >= 3:
				_frost_hits = 0
				stun(1.0)
				Sfx.play_at("freeze", global_position)
				SfxWord.spawn(get_parent(), global_position + Vector2(0, -80), "FROZEN!", Skills.element_color("frost"), 24)
		"shock":
			_chain_shock(dmg * 0.4)
		"poison":
			_poison_t = 5.0
			_poison_stacks = mini(_poison_stacks + 1, 5)
			_poison_dps = maxf(_poison_dps, dmg * 0.1)
	_update_tint()


func _chain_shock(dmg: float) -> void:
	var others: Array[Enemy] = []
	for e in get_tree().get_nodes_in_group("enemies"):
		if e != self and e is Enemy and not e.is_dead() and e.global_position.distance_to(global_position) < 170.0:
			others.append(e)
	others.sort_custom(func(a: Enemy, b: Enemy) -> bool:
		return a.global_position.distance_squared_to(global_position) < b.global_position.distance_squared_to(global_position))
	var col := Skills.element_color("shock")
	for e in others.slice(0, 2):
		BoltLine.spawn(get_parent(), global_position + Vector2(0, -26), e.global_position + Vector2(0, -26), col)
		e.take_hit(dmg, global_position, 60.0)


func _tick_status(delta: float) -> void:
	_burn_t -= delta
	_poison_t -= delta
	_slow_t -= delta
	if _poison_t <= 0.0:
		_poison_stacks = 0
	_status_tick -= delta
	if _status_tick > 0.0:
		return
	_status_tick = 0.5
	var dot := 0.0
	if _burn_t > 0.0:
		dot += _burn_dps * 0.5
	if _poison_stacks > 0:
		dot += _poison_dps * _poison_stacks * 0.5
	if dot > 0.0:
		health -= dot
		health_changed.emit(health, max_health)
		SfxWord.spawn(get_parent(), global_position + Vector2(randf_range(-20, 20), -70), "%d" % maxi(1, roundi(dot)),
			Skills.element_color("fire" if _burn_t > 0.0 else "poison"), 16)
		if health <= 0.0:
			_die()
			return
	_update_tint()


func _tint() -> Color:
	if _burn_t > 0.0:
		return Color(1.25, 0.8, 0.6)
	if _slow_t > 0.0:
		return Color(0.75, 0.95, 1.3)
	if _poison_stacks > 0:
		return Color(0.8, 1.2, 0.7)
	return Color.WHITE


func _update_tint() -> void:
	if figure.modulate.r < 2.0:  # don't stomp the white hit flash
		figure.modulate = _tint()


func _die() -> void:
	_dead = true
	collision_layer = 0
	Sfx.play_at("enemy_die", global_position)
	SfxWord.spawn(get_parent(), global_position + Vector2(0, -50), sfx_on_death, Color(1, 1, 1), 32)
	Loot.drop_for_enemy(get_parent(), global_position, gold_range, drop_table, world_id, weapon_drop_chance, 1 if elite else 0)
	if archetype == "slime" and not mini:
		_split()
	defeated.emit(self)
	var t := create_tween()
	t.tween_property(figure, "scale", Vector2(1.4, 0.1), 0.2)
	t.parallel().tween_property(figure, "modulate:a", 0.0, 0.25)
	t.tween_callback(queue_free)


## A slime bursts into two smaller, faster halves (registered with the room).
func _split() -> void:
	var world := get_tree().current_scene
	if not world or not world.has_method("spawn_enemy"):
		return
	for side in [-1.0, 1.0]:
		world.call_deferred("spawn_enemy", "slime", global_position + Vector2(side * 22.0, 0), room_id, false, true)
