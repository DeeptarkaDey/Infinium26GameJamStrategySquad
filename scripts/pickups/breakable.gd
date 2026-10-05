extends StaticBody2D
## A clay pot / barrel. Solid until a blade breaks it (it sits on the enemy layer
## so melee finds it); sometimes hides coins or a potion.

const SHARDS := 7

var _broken := false


func _ready() -> void:
	collision_layer = 1 | 4  # blocks movement, and melee queries (mask 4) hit it
	collision_mask = 0
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(30, 16)
	shape.shape = box
	shape.position = Vector2(0, -6)
	add_child(shape)


func smash() -> void:
	if _broken:
		return
	_broken = true
	collision_layer = 0
	Sfx.play_at("pot", global_position)
	SfxWord.spawn(get_parent(), global_position + Vector2(0, -40), "KRSH!", Color(0.9, 0.8, 0.6), 20)
	var roll := randf()
	if roll < 0.12:
		Loot.spawn_potion(get_parent(), global_position)
	elif roll < 0.55:
		Loot.spawn_coin(get_parent(), global_position, randi_range(1, 4))
	var t := create_tween()
	t.tween_property(self, "scale", Vector2(1.4, 0.2), 0.12)
	t.parallel().tween_property(self, "modulate:a", 0.0, 0.2)
	t.tween_callback(queue_free)


func _draw() -> void:
	var clay := Color(0.72, 0.42, 0.26)
	var pts := PackedVector2Array()
	for i in 20:
		var a := TAU * i / 20.0
		pts.append(Vector2(cos(a) * 16.0, -16.0 + sin(a) * 15.0))
	draw_colored_polygon(pts, clay)
	pts.append(pts[0])
	draw_polyline(pts, ComicTheme.INK, 3.0)
	draw_rect(Rect2(-8, -36, 16, 7), clay.darkened(0.2))
	draw_rect(Rect2(-8, -36, 16, 7), ComicTheme.INK, false, 2.5)
	draw_line(Vector2(-12, -18), Vector2(12, -18), clay.darkened(0.35), 2.0)
