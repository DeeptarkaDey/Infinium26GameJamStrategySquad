class_name SerpentBoss
extends Boss
## Kagami, Weaver of Tides: a great sea serpent (think Leviathan). Surfaced, she
## slides after you trailing her coils and spits fans of water. Then she dives:
## only a ripple shows, hunting your shadow, until she erupts beneath you
## (watch the circle). In phase 2 she also drowns the arena under a tidal wave
## with one gap to slip through. She can only be hurt while surfaced.

const TRAIL_LEN := 7
const SEGMENT_GAP := 26.0

var submerged := false
var _spit_t := 1.5
var _dive_t := 4.5
var _dives := 0
var _hunt_t := 0.0
var _trail: Array[Vector2] = []


func _ready() -> void:
	super._ready()
	_resize($CollisionShape2D, Vector2(110, 40))
	_resize($ContactArea/CollisionShape2D, Vector2(130, 90))
	hit_radius = 80.0
	figure.height = 170.0


func is_targetable() -> bool:
	return awake and not submerged


func reset_to_home() -> void:
	_surface()
	super.reset_to_home()


func _contact_multiplier() -> float:
	return 0.0 if submerged else touch_damage_share


func take_hit(amount: float, from: Vector2, knockback: float, crit: bool = false, is_light: bool = false) -> void:
	if submerged:
		if randf() < 0.3:
			SfxWord.spawn(get_parent(), global_position + Vector2(0, -30), "SPLSH", Color(0.7, 0.9, 1.0), 18)
		return
	super.take_hit(amount, from, knockback * 0.2, crit, is_light)


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_update_trail()


func _fight(delta: float, player: Player, to: Vector2) -> void:
	if submerged:
		# The ripple hunts the player's shadow, then she erupts.
		_hunt_t -= delta
		velocity = to.normalized() * minf(to.length() * 4.0, 300.0) if _hunt_t > 0.0 else Vector2.ZERO
		return
	_face(to.x)
	velocity = to.normalized() * speed * (1.3 if _phase == 2 else 1.0)
	_spit_t -= delta
	_dive_t -= delta
	if _spit_t <= 0.0:
		_spit_t = 1.6 if _phase == 2 else 2.3
		_spit(to)
	if _dive_t <= 0.0:
		_dive_t = 6.0 if _phase == 2 else 7.5
		_dives += 1
		if _phase == 2 and _dives % 2 == 0:
			_tidal_wave(player)
		else:
			_dive()


func _spit(to: Vector2) -> void:
	figure.squash = 1.0
	create_tween().tween_property(figure, "squash", 0.0, 0.4)
	var mouth := global_position + Vector2(40.0 * figure.facing, -120)
	var n := 5 if _phase == 2 else 3
	for i in n:
		var a := (i - (n - 1) * 0.5) * 0.22
		EnemyShot.fire(get_parent(), mouth, to.rotated(a), contact_damage * 0.6, Color(0.5, 0.8, 1.0), 300.0)
	Sfx.play("splash", -3.0)
	SfxWord.spawn(get_parent(), mouth + Vector2(0, -30), "SPLOOSH", Color(0.6, 0.85, 1.0), 24)


func _dive() -> void:
	_go_under()
	_hunt_t = 1.4
	await get_tree().create_timer(1.4).timeout
	if _dead or not submerged:
		return
	var w := _world()
	var spot := global_position
	var h := Hazard.blast(w.level if w else get_parent(), spot, 115.0, 0.8, contact_damage * 1.1, Color(0.35, 0.7, 1.0), "ERUPT!")
	Sfx.play("warning")
	await h.burst
	if _dead or not submerged:
		return
	global_position = spot
	_surface()
	_world().shake(10.0)


## Phase 2: she sinks at the arena's edge and sends a wall of water across it.
func _tidal_wave(player: Player) -> void:
	_go_under()
	_hunt_t = 0.0
	var arena := arena_rect(8.0)
	var wave := TideWave.new()
	wave.arena = arena
	wave.from_left = player.global_position.x > arena.get_center().x
	wave.gap_center = clampf(player.global_position.y + randf_range(-120, 120), arena.position.y + 90.0, arena.end.y - 90.0)
	wave.damage = contact_damage * 1.2
	get_parent().add_child(wave)
	Sfx.play("wave")
	SfxWord.spawn(get_parent(), player.global_position + Vector2(0, -110), "TIDE!", Color(0.5, 0.8, 1.0), 40)
	await get_tree().create_timer(wave.travel_time + 0.3).timeout
	if _dead or not submerged:
		return
	_hunt_t = 1.0
	await get_tree().create_timer(1.0).timeout
	if _dead or not submerged:
		return
	var spot := global_position
	var h := Hazard.blast(_world().level, spot, 115.0, 0.8, contact_damage * 1.1, Color(0.35, 0.7, 1.0), "ERUPT!")
	await h.burst
	if _dead or not submerged:
		return
	_surface()


func _go_under() -> void:
	submerged = true
	(figure as MonsterFigure).submerged = true
	_trail.clear()
	Sfx.play("dive")
	SfxWord.spawn(get_parent(), global_position + Vector2(0, -60), "BLOOP", Color(0.6, 0.85, 1.0), 26)


func _surface() -> void:
	if submerged:
		Sfx.play("splash")
	submerged = false
	(figure as MonsterFigure).submerged = false
	_contact_cd = 0.8  # don't punish the player for standing where she rises... twice


## Coils follow the head's path.
func _update_trail() -> void:
	if submerged:
		return
	if _trail.is_empty() or _trail[0].distance_to(global_position) >= SEGMENT_GAP:
		_trail.push_front(global_position)
		if _trail.size() > TRAIL_LEN:
			_trail.pop_back()
	var mf := figure as MonsterFigure
	var segs := PackedVector2Array()
	for i in range(1, _trail.size()):
		segs.append(_trail[i] - global_position)
	# At rest the coils curl up behind her.
	while segs.size() < TRAIL_LEN - 1:
		var k := segs.size() + 1
		segs.append(Vector2(-figure.facing * k * 22.0, sin(k * 1.3) * 18.0))
	mf.segments = segs


static func _resize(shape_node: CollisionShape2D, size: Vector2) -> void:
	var box := RectangleShape2D.new()
	box.size = size
	shape_node.shape = box
	shape_node.position = Vector2(0, -size.y * 0.3)
