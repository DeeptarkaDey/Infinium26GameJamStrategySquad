class_name EnemyShot
extends Node2D
## A hostile projectile (arrows, spit, spores). Hurts the player on touch and
## breaks on walls. Drawn as an ink-outlined dart in the shooter's colour.

var damage := 10.0
var direction := Vector2.RIGHT
var speed := 330.0
var color := Color(1.0, 0.4, 0.3)
var lifetime := 2.5
var radius := 9.0
var _t := 0.0


static func fire(parent: Node, pos: Vector2, dir: Vector2, dmg: float, col: Color, spd: float = 330.0) -> void:
	if not is_instance_valid(parent):
		return
	var s := EnemyShot.new()
	s.position = pos
	s.direction = dir.normalized()
	s.damage = dmg
	s.color = col
	s.speed = spd
	parent.add_child(s)
	Sfx.play_at("shoot", pos, -4.0)


func _ready() -> void:
	z_index = 26
	rotation = direction.angle()


func _physics_process(delta: float) -> void:
	_t += delta
	global_position += direction * speed * delta
	if _t > lifetime or _blocked():
		queue_free()
		return
	var player := get_tree().get_first_node_in_group("player") as Player
	if player and not player.dead and global_position.distance_to(player.global_position + Player.CHEST) < radius + 16.0:
		player.take_damage(damage, global_position - direction * 20.0)
		queue_free()
		return
	queue_redraw()


func _blocked() -> bool:
	var q := PhysicsPointQueryParameters2D.new()
	q.position = global_position + Vector2(0, 26)
	q.collision_mask = 1
	return not get_world_2d().direct_space_state.intersect_point(q, 1).is_empty()


func _draw() -> void:
	var pts := PackedVector2Array([Vector2(radius + 4, 0), Vector2(-radius, -radius * 0.7), Vector2(-radius * 0.4, 0), Vector2(-radius, radius * 0.7)])
	draw_colored_polygon(pts, color)
	pts.append(pts[0])
	draw_polyline(pts, ComicTheme.INK, 2.5)
