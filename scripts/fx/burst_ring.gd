class_name BurstRing
extends Node2D
## Expanding ring of light for area powers.

var radius := 150.0
var color := Color(1.0, 0.9, 0.5)
var _p := 0.0


func _ready() -> void:
	z_index = 20
	var t := create_tween()
	t.tween_property(self, "_p", 1.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_callback(queue_free)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var r := radius * _p
	draw_circle(Vector2.ZERO, r, Color(color, 0.25 * (1.0 - _p)))
	draw_arc(Vector2.ZERO, r, 0, TAU, 48, ComicTheme.INK, 8.0 * (1.0 - _p) + 2.0)
	draw_arc(Vector2.ZERO, r, 0, TAU, 48, color, 5.0 * (1.0 - _p) + 1.0)
