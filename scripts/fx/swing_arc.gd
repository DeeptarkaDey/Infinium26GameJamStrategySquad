class_name SwingArc
extends Node2D
## The ink smear of a sword swing, drawn toward the attack direction.

var radius := 80.0
var span := 1.1  ## half-angle of the arc in radians
var color := Color.WHITE
var _p := 0.0


static func spawn(parent: Node, pos: Vector2, dir: Vector2, reach: float, col: Color, half_angle: float = 1.1) -> void:
	if not is_instance_valid(parent):
		return
	var arc := SwingArc.new()
	arc.position = pos
	arc.rotation = dir.angle()
	arc.radius = reach
	arc.color = col
	arc.span = half_angle
	parent.add_child(arc)


func _ready() -> void:
	z_index = 24
	var t := create_tween()
	t.tween_property(self, "_p", 1.0, 0.16)
	t.tween_callback(queue_free)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if span < 0.3:
		# Thrust: a stabbing line instead of an arc.
		var tip := Vector2(radius * (0.4 + 0.6 * _p), 0)
		draw_line(Vector2(10, 0), tip, ComicTheme.INK, 12.0 * (1.0 - _p) + 3.0)
		draw_line(Vector2(10, 0), tip, Color(color, 1.0 - _p * 0.6), 6.0 * (1.0 - _p) + 1.5)
		return
	var sweep := lerpf(-span, span, _p)
	var steps := maxi(12, int(span * 14.0))
	draw_arc(Vector2.ZERO, radius, -span, sweep, steps, ComicTheme.INK, 12.0 * (1.0 - _p) + 2.0)
	draw_arc(Vector2.ZERO, radius, -span, sweep, steps, Color(color, 1.0 - _p * 0.6), 7.0 * (1.0 - _p) + 1.0)
