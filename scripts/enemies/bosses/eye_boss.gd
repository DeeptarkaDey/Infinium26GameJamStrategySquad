class_name EyeBoss
extends Boss
## The Echo: what the monk's last samurai became, an eye of broken mirrors (think
## the Beholder). Three prism shards orbit it and soak most of the damage until
## they are broken. It keeps its distance, sweeps a searing beam (pillars block
## it), and blinks across the arena. In phase 2 its shards reform and mirror
## images of the samurai step out of the glass.

const ORBIT := 140.0
const BEAM_RANGE := 900.0
## Damage taken while any shard still stands.
const SHIELDED := 0.4

var _shards: Array[Enemy] = []
var _orbit_a := 0.0
var _beam_t := 2.5
var _blink_t := 7.0
var _echo_t := 0.0
var _beam_on := false
var _beam_angle := 0.0
var _beam_end := Vector2.ZERO
var _beam_tick := 0.0
var _beam: Node2D


func _ready() -> void:
	super._ready()
	SerpentBoss._resize($CollisionShape2D, Vector2(100, 40))
	SerpentBoss._resize($ContactArea/CollisionShape2D, Vector2(110, 90))
	hit_radius = 80.0
	figure.height = 190.0
	_beam = Node2D.new()
	_beam.z_index = 40
	_beam.draw.connect(_draw_beam)
	add_child(_beam)


func reset_to_home() -> void:
	_beam_on = false
	_beam.queue_redraw()
	super.reset_to_home()
	_shards.clear()


func _awaken() -> void:
	_raise_shards()
	await super._awaken()


func _enter_phase_2() -> void:
	_raise_shards()
	_echo_t = 1.0


func shielded() -> bool:
	for s in _shards:
		if is_instance_valid(s) and not s.is_dead():
			return true
	return false


func take_hit(amount: float, from: Vector2, knockback: float, crit: bool = false, is_light: bool = false) -> void:
	if awake and shielded():
		amount *= SHIELDED
		if randf() < 0.3:
			SfxWord.spawn(get_parent(), global_position + Vector2(0, -150), "SHIELDED", Color(0.75, 0.9, 1.0), 20)
	super.take_hit(amount, from, knockback * 0.1, crit, is_light)


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_orbit_a += delta * 1.2
	# Untyped lambda param: a freed shard can't be passed as `Enemy`.
	var alive := _shards.filter(func(s: Variant) -> bool: return is_instance_valid(s) and not (s as Enemy).is_dead())
	for i in alive.size():
		var s: Enemy = alive[i]
		s.global_position = global_position + Vector2.from_angle(_orbit_a + TAU * i / alive.size()) * ORBIT
	var player := _get_player()
	if player:
		(figure as MonsterFigure).look_dir = (player.global_position + Vector2(0, -30) - (global_position + Vector2(0, -100))).normalized()


func _fight(delta: float, player: Player, to: Vector2) -> void:
	if _beam_on:
		velocity = Vector2.ZERO
		return
	# Keep its distance.
	var d := to.length()
	velocity = -to.normalized() * speed if d < 240.0 else (to.normalized() * speed * 0.6 if d > 380.0 else to.normalized().orthogonal() * speed * 0.5)
	_beam_t -= delta
	_blink_t -= delta
	if _phase == 2:
		_echo_t -= delta
		if _echo_t <= 0.0:
			_echo_t = 9.0
			_echoes()
	if _beam_t <= 0.0:
		_beam_t = 4.0 if _phase == 2 else 5.0
		_sweep(player)
	elif _blink_t <= 0.0:
		_blink_t = randf_range(6.0, 8.0)
		_blink(player)


func _raise_shards() -> void:
	var look := {"crown_color": "#bfe8ff", "eyes": "#ff2e63"}
	for i in 3:
		var s := summon("shard", global_position + Vector2.from_angle(TAU * i / 3.0) * ORBIT, look, "shard")
		if s:
			s.max_health *= 0.9
			s.health = s.max_health
			_shards.append(s)


## Narrows its eye on you, then rakes the beam across the arena.
func _sweep(player: Player) -> void:
	var to := player.global_position - global_position
	var mf := figure as MonsterFigure
	var t := create_tween()
	t.tween_property(mf, "squash", 0.6, 0.7)
	_beam_angle = to.angle()
	_beam_on = true
	Sfx.play("laser")
	var warm := 0.7
	var swing := 1.8 if _phase == 2 else 1.3
	var dir := 1.0 if randf() < 0.5 else -1.0
	var start := _beam_angle - swing * 0.5 * dir
	var elapsed := 0.0
	while elapsed < warm + 1.8 and not _dead and _beam_on:
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		elapsed += dt
		if elapsed < warm:
			_beam_angle = (player.global_position - global_position).angle()
			start = _beam_angle - swing * 0.5 * dir
		else:
			_beam_angle = start + dir * swing * clampf((elapsed - warm) / 1.8, 0.0, 1.0)
		_trace_beam(elapsed >= warm, dt)
	_beam_on = false
	mf.squash = 0.0
	_beam.queue_redraw()


func _eye_pos() -> Vector2:
	return global_position + Vector2(0, -100)


## Raycasts the beam (walls and pillars stop it) and burns the player it touches.
func _trace_beam(live: bool, dt: float) -> void:
	var from := _eye_pos()
	var to := from + Vector2.from_angle(_beam_angle) * BEAM_RANGE
	var q := PhysicsRayQueryParameters2D.create(from + Vector2(0, 100), to + Vector2(0, 100), 1)
	var hit := get_world_2d().direct_space_state.intersect_ray(q)
	_beam_end = (hit.position - Vector2(0, 100)) if not hit.is_empty() else to
	_beam.set_meta("live", live)
	_beam.queue_redraw()
	if not live:
		return
	_beam_tick -= dt
	var player := _get_player()
	if player and _beam_tick <= 0.0:
		var chest := player.global_position + Player.CHEST
		var closest := Geometry2D.get_closest_point_to_segment(chest, from, _beam_end)
		if closest.distance_to(chest) < 28.0:
			_beam_tick = 0.35
			player.take_damage(contact_damage * 0.3, closest)


func _draw_beam() -> void:
	if not _beam_on:
		return
	var a := _eye_pos() - global_position
	var b := _beam_end - global_position
	if _beam.get_meta("live", false):
		_beam.draw_line(a, b, ComicTheme.INK, 26.0)
		_beam.draw_line(a, b, Color(1.0, 0.3, 0.45), 18.0)
		_beam.draw_line(a, b, Color(1.0, 0.95, 0.95), 7.0)
		_beam.draw_circle(b, 16.0, Color(1.0, 0.6, 0.6))
	else:
		_beam.draw_line(a, b, Color(1.0, 0.3, 0.4, 0.6), 3.0)


## Shatters and reforms somewhere else in the arena.
func _blink(player: Player) -> void:
	var ring := BurstRing.new()
	ring.radius = 90.0
	ring.color = Color(0.75, 0.9, 1.0)
	ring.position = position
	get_parent().add_child(ring)
	global_position = arena_spot(player.global_position, 280.0)
	Sfx.play("shimmer")
	SfxWord.spawn(get_parent(), global_position + Vector2(0, -160), "SHING!", Color(0.75, 0.9, 1.0), 30)


## Phase 2: mirror images of the samurai it was step out of the glass.
func _echoes() -> void:
	if living_minions("chaser") >= 2:
		return
	var look := {"height": 66, "width": 30, "body": "#18203a", "trim": "#d32f2f", "mask": "kasa", "crown": "none", "eyes": "#4fd1ff"}
	for i in 2:
		var e := summon("chaser", global_position + Vector2((i * 2 - 1) * 110.0, 60), look)
		if e:
			e.display_name = "Mirror Samurai"
			e.figure.modulate = Color(0.75, 0.9, 1.2, 0.85)
