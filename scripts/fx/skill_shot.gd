class_name SkillShot
extends Node2D
## A travelling skill hit: Spirit Dart (homes, hits once) or Crescent Wave
## (wide, pierces). Hit tests are plain distance checks against enemies.

var slot := ""
var damage := 10.0
var direction := Vector2.RIGHT
var speed := 620.0
var radius := 14.0
var pierce := false
var homing := false
var orb := false  ## staff bolt: drawn as a glowing ball
var lifetime := 0.9
var color := Color.WHITE
var _hit: Array[Enemy] = []
var _t := 0.0


func _ready() -> void:
	z_index = 25
	rotation = direction.angle()


func _physics_process(delta: float) -> void:
	_t += delta
	if _t >= lifetime:
		queue_free()
		return
	if homing:
		var target := _nearest(260.0)
		if target:
			var want := (target.global_position + Vector2(0, -26) - global_position).normalized()
			direction = direction.slerp(want, minf(1.0, 7.0 * delta)).normalized()
			rotation = direction.angle()
	global_position += direction * speed * delta
	if _blocked():
		queue_free()
		return
	for e in get_tree().get_nodes_in_group("enemies"):
		var enemy := e as Enemy
		if not enemy or enemy.is_dead() or _hit.has(enemy):
			continue
		if global_position.distance_to(enemy.global_position + Vector2(0, -26)) <= radius + enemy.hit_radius:
			_hit.append(enemy)
			Skills.strike(enemy, damage, global_position - direction * 40.0, 160.0, slot)
			if not pierce:
				queue_free()
				return
	queue_redraw()


func _blocked() -> bool:
	var q := PhysicsPointQueryParameters2D.new()
	q.position = global_position + Vector2(0, 26)  # shots fly at chest height; walls live at feet height
	q.collision_mask = 1
	return not get_world_2d().direct_space_state.intersect_point(q, 1).is_empty()


func _nearest(max_d: float) -> Enemy:
	var best: Enemy = null
	var best_d := max_d
	for e in get_tree().get_nodes_in_group("enemies"):
		var enemy := e as Enemy
		if enemy and not enemy.is_dead() and not _hit.has(enemy):
			var d := global_position.distance_to(enemy.global_position)
			if d < best_d:
				best_d = d
				best = enemy
	return best


func _draw() -> void:
	var fade := 1.0 - _t / lifetime * 0.5
	if orb:
		draw_circle(Vector2.ZERO, radius + 4.0, Color(color, 0.3 * fade))
		draw_circle(Vector2.ZERO, radius * 0.7, Color(color, fade))
		draw_arc(Vector2.ZERO, radius * 0.7, 0, TAU, 16, ComicTheme.INK, 3.0)
	elif pierce and radius > 20.0:
		# Crescent: a thick ink arc facing the travel direction.
		draw_arc(Vector2.ZERO, radius, -1.2, 1.2, 16, ComicTheme.INK, 14.0)
		draw_arc(Vector2.ZERO, radius, -1.2, 1.2, 16, Color(color, fade), 8.0)
	else:
		var pts := PackedVector2Array([Vector2(12, 0), Vector2(-8, -7), Vector2(-4, 0), Vector2(-8, 7)])
		draw_colored_polygon(pts, Color(color, fade))
		pts.append(pts[0])
		draw_polyline(pts, ComicTheme.INK, 3.0)
