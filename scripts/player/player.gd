class_name Player
extends CharacterBody2D
## The samurai. Top-down movement in eight directions (Endless Wander style), a
## dash, and attacks shaped by the equipped weapon's kind (Labyrinth Legend
## style): sword arcs, spear thrusts, greatblade sweeps, dagger flurries, staff
## bolts and arrows, with soft auto-aim and a 3-hit combo whose last hit is a
## finisher. Also fires the run's skills, drinks potions, and uses powers
## absorbed from fallen worlds.

signal died

@export var run_speed: float = 260.0
@export var acceleration: float = 2400.0
@export var friction: float = 2800.0
@export var dash_speed: float = 760.0
@export var dash_time: float = 0.16
@export var dash_cooldown: float = 0.55
@export var hurt_invuln: float = 0.8
## Melee attacks snap toward the nearest enemy within this range (ranged ones use their reach).
@export var auto_aim_range: float = 190.0
## Hits landing within this window chain into a combo; the 3rd is a finisher.
@export var combo_window: float = 0.7

## Swing sound per weapon kind.
const SWING_SOUNDS := {
	WeaponData.Kind.SWORD: "swing", WeaponData.Kind.SPEAR: "thrust", WeaponData.Kind.HEAVY: "swing_heavy",
	WeaponData.Kind.DAGGER: "swing_light", WeaponData.Kind.STAFF: "staff", WeaponData.Kind.BOW: "bow",
}

## Chest height above the feet: where swings and skills originate.
const CHEST := Vector2(0, -30)

@onready var figure: ComicFigure = $Figure
@onready var camera: Camera2D = $Camera2D

var facing := 1
var aim := Vector2.RIGHT  ## last move / attack direction (unit vector)
var dead := false
var _dash_t := 0.0
var _dash_dir := Vector2.RIGHT
var _dash_cd := 0.0
var _dash_charges := 1
var _attack_cd := 0.0
var _power_cd := 0.0
var _invuln := 0.0
var _skill_cd: Dictionary = {}  ## skill id -> seconds left
var _combo := 0
var _combo_t := 0.0
var _potion_cd := 0.0
var _slow_t := 0.0
var _slow_factor := 1.0
var _interactables: Array[Interactable] = []
var _focused: Interactable


func _ready() -> void:
	add_to_group("player")
	GameState.weapon_changed.connect(func(_w: WeaponData) -> void: _refresh_weapon())
	_refresh_weapon()


func _refresh_weapon() -> void:
	figure.weapon_color = GameState.get_weapon().blade_color
	_combo = 0


func _physics_process(delta: float) -> void:
	_tick_timers(delta)
	if dead:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
		move_and_slide()
		return

	if _dash_t > 0.0:
		velocity = _dash_dir * dash_speed
		move_and_slide()
		return

	var locked := GameState.is_player_locked()
	var input := Vector2.ZERO if locked else Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if input != Vector2.ZERO:
		var spd := run_speed * (_slow_factor if _slow_t > 0.0 else 1.0)
		velocity = velocity.move_toward(input * spd, acceleration * delta)
		aim = input.normalized()
		if absf(input.x) > 0.1:
			_set_facing(1 if input.x > 0.0 else -1)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
	# Walking bob.
	figure.squash = sin(Time.get_ticks_msec() * 0.02) * 0.08 * (velocity.length() / run_speed)

	if not locked:
		if Input.is_action_just_pressed("dash") and _dash_charges > 0:
			_dash(input)
		if Input.is_action_just_pressed("attack") and _attack_cd <= 0.0:
			_attack()
		if Input.is_action_just_pressed("use_potion"):
			drink_potion()
		if Input.is_action_just_pressed("use_power"):
			_use_active_power()
		if Input.is_action_just_pressed("interact") and _focused and _focused.can_interact():
			_focused.interact(self)

	move_and_slide()
	_update_focus()


func _tick_timers(delta: float) -> void:
	_dash_t -= delta
	_attack_cd -= delta
	_combo_t -= delta
	_potion_cd -= delta
	_slow_t -= delta
	_power_cd -= delta
	_invuln -= delta
	for id: String in _skill_cd:
		_skill_cd[id] = float(_skill_cd[id]) - delta
	# Dash charges refill one at a time.
	var max_charges := 1 + int(GameState.get_stat("dash_charges"))
	if _dash_charges < max_charges:
		_dash_cd -= delta
		if _dash_cd <= 0.0:
			_dash_charges += 1
			_dash_cd = dash_cooldown
	figure.modulate.a = 0.4 if _invuln > 0.0 and int(_invuln * 20.0) % 2 == 0 else 1.0


## Webs, ash and mud: walk at `factor` speed for `t` seconds.
func apply_slow(factor: float, t: float) -> void:
	_slow_factor = factor if _slow_t <= 0.0 else minf(_slow_factor, factor)
	_slow_t = maxf(_slow_t, t)


func _set_facing(dir: int) -> void:
	if dir == facing:
		return
	facing = dir
	figure.facing = dir


func _dash(input: Vector2) -> void:
	_dash_dir = input.normalized() if input != Vector2.ZERO else aim
	_dash_t = dash_time * (1.0 + GameState.get_stat("dash_length"))
	if _dash_charges == 1 + int(GameState.get_stat("dash_charges")):
		_dash_cd = dash_cooldown
	_dash_charges -= 1
	if GameState.get_stat("dash_invuln") > 0.0:
		_invuln = maxf(_invuln, _dash_t + 0.05)
	_squash(0.6)
	Sfx.play("dash")
	SfxWord.spawn(get_parent(), global_position + CHEST - _dash_dir * 30.0, "ZIP!", Color(0.9, 0.9, 1.0), 22)


func _squash(amount: float) -> void:
	var t := create_tween()
	t.tween_property(figure, "squash", amount, 0.06)
	t.tween_property(figure, "squash", 0.0, 0.12)


# --- Combat -------------------------------------------------------------------

func nearest_enemy(max_dist: float) -> Enemy:
	var best: Enemy = null
	var best_d := max_dist
	for e in get_tree().get_nodes_in_group("enemies"):
		var enemy := e as Enemy
		if enemy and not enemy.is_dead() and enemy.is_targetable():
			var d := global_position.distance_to(enemy.global_position)
			if d < best_d:
				best_d = d
				best = enemy
	return best


func _attack() -> void:
	var w := GameState.get_weapon()
	_attack_cd = w.attack_cooldown
	var target := nearest_enemy(minf(w.reach, 460.0) if w.is_ranged() else auto_aim_range)
	if target:
		aim = (target.global_position - global_position).normalized()
		if absf(aim.x) > 0.05:
			_set_facing(1 if aim.x > 0.0 else -1)
	_combo = _combo + 1 if _combo_t > 0.0 and _combo < 3 else 1
	_combo_t = combo_window + w.attack_cooldown
	var finisher := _combo == 3
	var t := create_tween()
	t.tween_property(figure, "swing", 1.0, 0.06)
	t.tween_property(figure, "swing", 0.0, 0.14)
	Sfx.play(SWING_SOUNDS.get(w.kind, "swing"), 2.0 if finisher else 0.0)
	var dmg := w.damage * (1.6 if finisher else 1.0)
	var kb := w.knockback * (1.5 if finisher else 1.0)
	var origin := global_position + CHEST * 0.5
	var hits: Array = []
	match w.kind:
		WeaponData.Kind.STAFF:
			var spread := [-0.22, 0.0, 0.22] if finisher else [0.0]
			for a: float in spread:
				_shoot(Skills.BLADE, dmg, 560.0, 16.0, false, false, w.reach / 560.0, w.blade_color, aim.rotated(a), true)
		WeaponData.Kind.BOW:
			_shoot(Skills.BLADE, dmg, 900.0, 10.0, finisher, false, w.reach / 900.0, w.blade_color, aim, false)
		WeaponData.Kind.SPEAR:
			# A long, narrow thrust; the finisher lunges forward with it.
			if finisher:
				velocity = aim * 520.0
			SwingArc.spawn(get_parent(), origin, aim, w.reach + 20.0, w.blade_color, 0.18)
			hits = _melee_box(origin, Vector2(w.reach * (1.25 if finisher else 1.0), 34.0))
		WeaponData.Kind.HEAVY:
			# Wide sweeps; the finisher is a full spin.
			if finisher:
				SwingArc.spawn(get_parent(), origin, aim, w.reach, w.blade_color, PI)
				hits = _melee_circle(origin, w.reach + 10.0)
			else:
				SwingArc.spawn(get_parent(), origin, aim, w.reach + 20.0, w.blade_color, 1.6)
				hits = _melee_box(origin, Vector2(w.reach, 130.0))
		WeaponData.Kind.DAGGER:
			# Quick stabs that step in; the finisher always crits.
			velocity += aim * 180.0
			SwingArc.spawn(get_parent(), origin, aim, w.reach + 24.0, w.blade_color, 0.7)
			hits = _melee_box(origin, Vector2(w.reach, 52.0))
		_:
			SwingArc.spawn(get_parent(), origin, aim, w.reach + 30.0, w.blade_color, 1.4 if finisher else 1.1)
			hits = _melee_box(origin, Vector2(w.reach, 100.0 if finisher else 72.0))
	var hit_any := false
	for body: Node in hits:
		if body is Enemy and not body.is_dead():
			Skills.strike(body, dmg, global_position, kb, Skills.BLADE, false, finisher and w.kind == WeaponData.Kind.DAGGER)
			hit_any = true
		elif body.has_method("smash"):
			body.smash()
	if finisher:
		SfxWord.spawn(get_parent(), global_position + Vector2(0, -100), "FINISHER!", Color(1.0, 0.6, 0.2), 26)
	if hit_any:
		SfxWord.spawn(get_parent(), global_position + CHEST + aim * 50.0 + Vector2(0, -20), w.sfx_word, Color(1.0, 0.85, 0.1))
		_hitstop()
	_fire_skills(w)


## Bodies on the enemy layer inside a box reaching out along `aim`.
func _melee_box(origin: Vector2, size: Vector2) -> Array:
	var rect := RectangleShape2D.new()
	rect.size = size
	var xf := Transform2D(aim.angle(), origin + aim * (size.x * 0.5 + 6.0) + Vector2(0, 12))
	return _query(rect, xf)


func _melee_circle(origin: Vector2, radius: float) -> Array:
	var circle := CircleShape2D.new()
	circle.radius = radius
	return _query(circle, Transform2D(0.0, origin + Vector2(0, 12)))


## Enemy bodies are foot boxes, so queries are nudged toward the feet.
func _query(shape: Shape2D, xf: Transform2D) -> Array:
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = shape
	q.transform = xf
	q.collision_mask = 4
	var out: Array = []
	for hit in get_world_2d().direct_space_state.intersect_shape(q, 32):
		if not out.has(hit.collider):
			out.append(hit.collider)
	return out


func drink_potion() -> void:
	if _potion_cd > 0.0 or dead:
		return
	if GameState.potions <= 0:
		Sfx.play("error")
		SfxWord.spawn(get_parent(), global_position + Vector2(0, -90), "NO POTIONS", Color(0.8, 0.6, 0.6), 18)
		return
	if GameState.drink_potion():
		_potion_cd = 0.6
		Sfx.play("drink")
		SfxWord.spawn(get_parent(), global_position + Vector2(0, -90), "GLUG!", Color(1.0, 0.4, 0.45), 28)
		var ring := BurstRing.new()
		ring.radius = 60.0
		ring.color = Color(1.0, 0.45, 0.5)
		ring.position = position + CHEST * 0.5
		get_parent().add_child(ring)


## Every equipped skill that is off cooldown fires alongside the swing.
func _fire_skills(w: WeaponData) -> void:
	for id: String in GameState.run_skills:
		if float(_skill_cd.get(id, 0.0)) > 0.0:
			continue
		var lvl := int(GameState.run_skills[id])
		_skill_cd[id] = Skills.cooldown(id, lvl)
		var dmg := w.damage * Skills.damage_mult(id, lvl)
		var el := str(GameState.run_elements.get(id, ""))
		var col: Color = Skills.element_color(el) if el != "" else Skills.SKILLS[id].color
		Sfx.play({"spirit_dart": "dart", "crescent_wave": "swing_heavy", "whirlwind": "whirl", "thunder_seal": "thunder"}.get(id, "dart"), -3.0)
		match id:
			"spirit_dart":
				_shoot(id, dmg, 640.0, 14.0, false, true, 1.0, col)
			"crescent_wave":
				_shoot(id, dmg, 520.0, 46.0, true, false, 0.55, col)
			"whirlwind":
				var ring := BurstRing.new()
				ring.radius = 120.0
				ring.color = col
				ring.position = position + CHEST * 0.5
				get_parent().add_child(ring)
				for e in get_tree().get_nodes_in_group("enemies"):
					if e is Enemy and not e.is_dead() and e.global_position.distance_to(global_position) <= 130.0:
						Skills.strike(e, dmg, global_position, 260.0, id)
			"thunder_seal":
				var target := nearest_enemy(340.0)
				if target:
					BoltLine.spawn(get_parent(), target.global_position + Vector2(0, -420), target.global_position + Vector2(0, -20), col, 7.0)
					SfxWord.spawn(get_parent(), target.global_position + Vector2(0, -90), "KRA-KOOM!", col, 30)
					Skills.strike(target, dmg, target.global_position + Vector2(0, -1), 60.0, id)
				else:
					_skill_cd[id] = 0.0  # no target in range: keep it ready


func _shoot(id: String, dmg: float, spd: float, rad: float, pierce: bool, homing: bool, life: float, col: Color,
		dir: Vector2 = Vector2.ZERO, orb: bool = false) -> void:
	var shot := SkillShot.new()
	shot.slot = id
	shot.damage = dmg
	shot.direction = aim if dir == Vector2.ZERO else dir
	shot.orb = orb
	shot.speed = spd
	shot.radius = rad
	shot.pierce = pierce
	shot.homing = homing
	shot.lifetime = life
	shot.color = col
	shot.position = position + CHEST + aim * 20.0
	get_parent().add_child(shot)


func _hitstop() -> void:
	Engine.time_scale = 0.05
	await get_tree().create_timer(0.045, true, false, true).timeout
	Engine.time_scale = 1.0


func _use_active_power() -> void:
	var p := GameState.get_active_power()
	if not p or _power_cd > 0.0:
		return
	_power_cd = p.cooldown
	Sfx.play("sacred" if p.id == "sacred_light" else "flare")
	match p.id:
		"lantern_flare":
			_burst(160.0, 30.0, p.color, "FWOOSH!")
		"sacred_light":
			# Sacred light grows with hope: the light you kept is the light you wield.
			_burst(240.0, 45.0 * (0.6 + GameState.hope_ratio()), p.color, "LIGHT!")
		_:
			_burst(120.0, 20.0, p.color, "POW!")


func _burst(radius: float, damage: float, color: Color, word: String) -> void:
	var ring := BurstRing.new()
	ring.radius = radius
	ring.color = color
	ring.position = position + CHEST * 0.5
	get_parent().add_child(ring)
	SfxWord.spawn(get_parent(), global_position + Vector2(0, -90), word, color, 40)
	for e in get_tree().get_nodes_in_group("enemies"):
		if e is Enemy and not e.is_dead() and e.global_position.distance_to(global_position) <= radius:
			e.take_hit(damage * GameState.get_damage_multiplier(), global_position, 380.0, false, true)
			e.stun(0.8)


func take_damage(amount: float, from: Vector2) -> void:
	if dead or _invuln > 0.0:
		return
	var dealt := GameState.damage_player(amount)
	Sfx.play("hurt")
	_invuln = hurt_invuln
	var away := (global_position - from).normalized()
	velocity = (away if away != Vector2.ZERO else Vector2(-facing, 0)) * 380.0
	SfxWord.spawn(get_parent(), global_position + Vector2(0, -70), "-%d" % roundi(dealt), Color(1.0, 0.3, 0.3), 24)
	var world := get_tree().current_scene
	if world and world.has_method("shake"):
		world.shake(8.0)
	if GameState.health <= 0.0:
		die()


func die() -> void:
	if dead:
		return
	dead = true
	Sfx.play("player_die")
	var t := create_tween()
	t.tween_property(figure, "rotation", -PI / 2.0 * facing, 0.35).set_trans(Tween.TRANS_BOUNCE)
	died.emit()


func revive(at: Vector2) -> void:
	dead = false
	figure.rotation = 0.0
	global_position = at
	velocity = Vector2.ZERO
	_invuln = 1.0


# --- Interaction --------------------------------------------------------------

func register_interactable(i: Interactable) -> void:
	if not _interactables.has(i):
		_interactables.append(i)


func unregister_interactable(i: Interactable) -> void:
	_interactables.erase(i)
	if _focused == i:
		_focused = null


func _update_focus() -> void:
	var best: Interactable = null
	var best_d := INF
	for i in _interactables:
		if not is_instance_valid(i):
			continue
		var d := global_position.distance_squared_to(i.global_position)
		if d < best_d:
			best_d = d
			best = i
	if best != _focused:
		if is_instance_valid(_focused):
			_focused.set_highlighted(false)
		_focused = best
	if _focused:
		_focused.set_highlighted(not GameState.is_player_locked())
