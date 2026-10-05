extends Area2D
## Gold. Hops out onto the floor, then is pulled toward the player when close.

var value := 5
var _t := randf() * TAU


func _ready() -> void:
	collision_layer = 8
	collision_mask = 2
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 14
	shape.shape = circle
	add_child(shape)
	body_entered.connect(_on_body_entered)
	_ready_hop()


func _ready_hop() -> void:
	# Scatter a little across the floor.
	var to := position + Vector2.from_angle(randf() * TAU) * randf_range(10.0, 50.0)
	var t := create_tween()
	t.tween_property(self, "position", to, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _physics_process(delta: float) -> void:
	_t += delta
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player and global_position.distance_to(player.global_position) < 110.0:
		global_position = global_position.move_toward(player.global_position, 520.0 * delta)
	queue_redraw()


func _draw() -> void:
	var squish := absf(cos(_t * 3.0))
	var r := Vector2(10.0 * maxf(squish, 0.2), 10.0)
	var pts := PackedVector2Array()
	for i in 16:
		var a := TAU * i / 16.0
		pts.append(Vector2(cos(a) * r.x, sin(a) * r.y - 12.0))
	draw_colored_polygon(pts, Color(1.0, 0.8, 0.15))
	pts.append(pts[0])
	draw_polyline(pts, ComicTheme.INK, 3.0, true)


func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		GameState.add_gold(value)
		Sfx.play("coin")
		SfxWord.spawn(get_parent(), global_position + Vector2(0, -20), "+%dg" % value, Color(1.0, 0.85, 0.2), 18)
		queue_free()
