class_name MothBoss
extends Boss
## The Lamplighter: a colossal lantern moth carrying the lamps of lost souls
## (think the great moths of Hollow Knight and Dark Souls). Circles the player
## and cycles its attacks: lantern fire rains on marked circles, ash clouds slow
## you, and a swarm of ash moths answers its call. In phase 2 it also
## dive-bombs straight through you.

var _attack_t := 1.2
var _cycle := 0
var _diving := 0.0
var _dive_dir := Vector2.ZERO
var _orbit_sign := 1.0


func _ready() -> void:
	super._ready()
	SerpentBoss._resize($CollisionShape2D, Vector2(110, 40))
	SerpentBoss._resize($ContactArea/CollisionShape2D, Vector2(150, 100))
	hit_radius = 85.0
	figure.height = 190.0


func reset_to_home() -> void:
	_diving = 0.0
	super.reset_to_home()


func _contact_multiplier() -> float:
	return 1.0 if _diving > 0.0 else touch_damage_share


func _fight(delta: float, _player: Player, to: Vector2) -> void:
	if _diving > 0.0:
		_diving -= delta
		velocity = _dive_dir * 640.0
		figure.squash = 0.6
		if _diving <= 0.0 or get_slide_collision_count() > 0:
			_diving = 0.0
			figure.squash = 0.0
		return
	_face(to.x)
	# Hover in a wide circle around the player, drifting in and out.
	var d := to.length()
	var radial := to.normalized() * (d - 200.0) / 200.0
	var tangent := to.normalized().orthogonal() * _orbit_sign
	velocity = (radial + tangent).normalized() * speed * 1.6
	if get_slide_collision_count() > 0:
		_orbit_sign = -_orbit_sign
	_attack_t -= delta
	if _attack_t > 0.0:
		return
	_attack_t = 1.8 if _phase == 2 else 2.5
	_cycle += 1
	var attacks := ["fire", "ash", "fire", "swarm"]
	if _phase == 2:
		attacks = ["fire", "dive", "ash", "swarm", "fire", "dive"]
	match attacks[_cycle % attacks.size()]:
		"fire": _fire_rain()
		"ash": _ash_cloud()
		"swarm": _swarm()
		"dive": _telegraph_dive()


## Lanterns drop flame on marked circles: one on you, the rest around you.
func _fire_rain() -> void:
	var player := _get_player()
	if not player:
		return
	_flash(Color(1.8, 1.3, 0.6))
	var count := 6 if _phase == 2 else 4
	var spots: Array[Vector2] = [player.global_position]
	for i in count - 1:
		spots.append(player.global_position + Vector2.from_angle(randf() * TAU) * randf_range(90, 200))
	for p in spots:
		var h := Hazard.blast(_world().level, p, 62.0, 1.1, contact_damage * 0.75, Color(1.0, 0.55, 0.15), "FWOOM")
		h.sound = "fwoom"


## Wing-beats shed a cloud of ash where you stand; it slows you for a while.
func _ash_cloud() -> void:
	var player := _get_player()
	if not player:
		return
	SfxWord.spawn(get_parent(), global_position + Vector2(0, -200), "FWUMP", Color(0.75, 0.75, 0.8), 30)
	Hazard.zone(_world().level, player.global_position, 110.0, 4.5, 0.5, 0.0, Color(0.55, 0.55, 0.6))


## Calls ash moths (the world's bats) out of the dark, up to four at a time.
func _swarm() -> void:
	if living_minions() >= 4:
		_fire_rain()
		return
	Sfx.play("screech")
	for i in 2:
		summon("bat", global_position + Vector2((i * 2 - 1) * 90.0, 20))


## Phase 2: rears back, then dives through the player in a straight line.
func _telegraph_dive() -> void:
	var player := _get_player()
	if not player:
		return
	_flash(Color(1.8, 0.6, 0.5))
	SfxWord.spawn(get_parent(), global_position + Vector2(0, -210), "!!", Color(1.0, 0.3, 0.3), 36)
	Sfx.play("screech", 2.0)
	figure.squash = -0.6
	_stun = 0.6
	await get_tree().create_timer(0.6).timeout
	if _dead or not player:
		return
	_dive_dir = (player.global_position - global_position).normalized()
	_diving = 0.65
