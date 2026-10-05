class_name LightFragment
extends Node2D
## The strange light that escapes a fallen target and drifts away toward the
## monk's waiting hands.

signal absorbed

var color := Color(1.0, 0.92, 0.6)
var _t := 0.0


func _ready() -> void:
	z_index = 40
	var t := create_tween()
	t.tween_property(self, "position:y", position.y - 120.0, 1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_interval(0.6)
	t.tween_property(self, "position", position + Vector2(-900, -700), 1.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(self, "scale", Vector2(0.2, 0.2), 1.4)
	t.tween_callback(func() -> void: absorbed.emit(); queue_free())


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var pulse := 1.0 + sin(_t * 8.0) * 0.12
	for i in 4:
		draw_circle(Vector2.ZERO, (40.0 - i * 9.0) * pulse, Color(color, 0.15 + i * 0.2))
	for i in 8:
		var a := TAU * i / 8.0 + _t
		draw_line(Vector2(cos(a), sin(a)) * 22.0, Vector2(cos(a), sin(a)) * 46.0 * pulse, Color(color, 0.6), 3.0)
