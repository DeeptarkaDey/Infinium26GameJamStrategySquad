class_name BoltLine
extends Node2D
## A jagged lightning stroke between two points that flickers out.

var from := Vector2.ZERO
var to := Vector2.ZERO
var color := Color(1.0, 0.92, 0.3)
var width := 5.0
var _pts := PackedVector2Array()


static func spawn(parent: Node, a: Vector2, b: Vector2, col: Color, w: float = 5.0) -> void:
	if not is_instance_valid(parent):
		return
	var bolt := BoltLine.new()
	bolt.from = a
	bolt.to = b
	bolt.color = col
	bolt.width = w
	parent.add_child(bolt)


func _ready() -> void:
	z_index = 45
	_pts.append(from)
	var n := 7
	var side := (to - from).orthogonal().normalized()
	for i in range(1, n):
		_pts.append(from.lerp(to, float(i) / n) + side * randf_range(-14.0, 14.0))
	_pts.append(to)
	var t := create_tween()
	t.tween_property(self, "modulate:a", 0.0, 0.25)
	t.tween_callback(queue_free)


func _draw() -> void:
	draw_polyline(_pts, ComicTheme.INK, width + 4.0)
	draw_polyline(_pts, color, width)
