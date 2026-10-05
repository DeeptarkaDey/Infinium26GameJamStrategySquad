class_name Hazard
extends Node2D
## Floor hazards for boss fights, drawn under the characters.
## - blast: a warning circle fills up, then bursts and hurts the player inside.
## - zone: a lingering cloud that slows (and optionally burns) whoever stands in it.

signal burst

var radius := 80.0
var color := Color(1.0, 0.4, 0.2)
var damage := 10.0
var delay := 1.0
var word := ""
var lingering := false
var duration := 4.0
var slow := 0.5
## Played when a blast lands ("" for none).
var sound := "boom"
var _t := 0.0
var _tick := 0.0


static func blast(parent: Node, pos: Vector2, r: float, wait: float, dmg: float, col: Color, sfx: String = "") -> Hazard:
	var h := Hazard.new()
	h.position = pos
	h.radius = r
	h.delay = wait
	h.damage = dmg
	h.color = col
	h.word = sfx
	parent.add_child(h)
	return h


static func zone(parent: Node, pos: Vector2, r: float, time: float, slow_factor: float, dps: float, col: Color) -> Hazard:
	var h := Hazard.new()
	h.position = pos
	h.radius = r
	h.lingering = true
	h.duration = time
	h.slow = slow_factor
	h.damage = dps
	h.color = col
	parent.add_child(h)
	Sfx.play_at("puff", pos)
	return h


func _ready() -> void:
	z_index = -4  # above the floor art, below everything standing on it


func _physics_process(delta: float) -> void:
	_t += delta
	queue_redraw()
	var player := get_tree().get_first_node_in_group("player") as Player
	var inside := player != null and not player.dead and player.global_position.distance_to(global_position) <= radius
	if lingering:
		if inside:
			player.apply_slow(slow, 0.15)
			_tick -= delta
			if damage > 0.0 and _tick <= 0.0:
				_tick = 0.5
				player.take_damage(damage * 0.5, global_position)
		if _t >= duration:
			queue_free()
		return
	if _t >= delay:
		if inside:
			player.take_damage(damage, global_position)
		var ring := BurstRing.new()
		ring.radius = radius
		ring.color = color
		ring.position = position
		get_parent().add_child(ring)
		if word != "":
			SfxWord.spawn(get_parent(), global_position + Vector2(0, -30), word, color, 26)
		if sound != "":
			Sfx.play_at(sound, global_position, -2.0)
		burst.emit()
		queue_free()


func _draw() -> void:
	if lingering:
		var fade := clampf(minf(_t * 3.0, (duration - _t) * 2.0), 0.0, 1.0)
		draw_circle(Vector2.ZERO, radius, Color(color, 0.45 * fade))
		for i in 5:
			var a := TAU * i / 5.0 + _t * 0.6
			draw_circle(Vector2.from_angle(a) * radius * 0.55, radius * 0.35, Color(color.lightened(0.2), 0.35 * fade))
		draw_arc(Vector2.ZERO, radius, 0, TAU, 32, Color(ComicTheme.INK, 0.6 * fade), 2.0)
		return
	var p := clampf(_t / delay, 0.0, 1.0)
	draw_circle(Vector2.ZERO, radius, Color(color, 0.18))
	draw_circle(Vector2.ZERO, radius * p, Color(color, 0.35))
	draw_arc(Vector2.ZERO, radius, 0, TAU, 32, ComicTheme.INK, 4.0)
	draw_arc(Vector2.ZERO, radius, 0, TAU, 32, color, 2.0)
