class_name TideWave
extends Node2D
## A wall of water that sweeps across a boss arena with one gap in it. Stand in
## the gap (or dash through it) or get hit.

var arena := Rect2()
var from_left := true
var gap_center := 0.0
var gap_half := 80.0
var damage := 15.0
var travel_time := 2.4
var _t := 0.0
var _hit := false

const THICK := 46.0


func _ready() -> void:
	z_index = 30


func _physics_process(delta: float) -> void:
	_t += delta
	if _t >= travel_time:
		queue_free()
		return
	queue_redraw()
	var player := get_tree().get_first_node_in_group("player") as Player
	if _hit or not player or player.dead:
		return
	var p := player.global_position
	if absf(p.x - _x()) < THICK * 0.5 + 10.0 and absf(p.y - gap_center) > gap_half:
		_hit = true
		player.take_damage(damage, Vector2(_x() - (40.0 if from_left else -40.0), p.y))


func _x() -> float:
	var k := _t / travel_time
	return lerpf(arena.position.x, arena.end.x, k) if from_left else lerpf(arena.end.x, arena.position.x, k)


func _draw() -> void:
	var x := _x()
	var water := Color(0.3, 0.6, 0.85)
	var foam := Color(0.92, 0.97, 1.0)
	for seg: Vector2 in [Vector2(arena.position.y, gap_center - gap_half), Vector2(gap_center + gap_half, arena.end.y)]:
		if seg.y <= seg.x:
			continue
		var r := Rect2(x - THICK * 0.5, seg.x, THICK, seg.y - seg.x)
		draw_rect(r, water)
		var lead := r.end.x if from_left else r.position.x
		var y: float = seg.x
		while y < seg.y:
			draw_circle(Vector2(lead, y + 10.0), 11.0, foam)
			y += 18.0
		draw_rect(r, ComicTheme.INK, false, 4.0)
