extends Area2D
## A healing potion on the floor. Walk over it to pocket it (up to
## GameState.POTION_MAX); press R / H to drink one.

var _t := randf() * TAU


func _ready() -> void:
	collision_layer = 8
	collision_mask = 2
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 16
	shape.shape = circle
	add_child(shape)
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _on_body_entered(body: Node2D) -> void:
	if not body is Player:
		return
	if GameState.add_potion():
		Sfx.play("potion_pickup")
		SfxWord.spawn(get_parent(), global_position + Vector2(0, -30), "+POTION", Color(1.0, 0.45, 0.5), 18)
		queue_free()


func _draw() -> void:
	draw_flask(self, Vector2(0, -14 + sin(_t * 3.0) * 2.0), 1.0)


## Shared flask art (also used by the HUD and the inventory).
static func draw_flask(ci: CanvasItem, c: Vector2, scale: float) -> void:
	var ink := ComicTheme.INK
	ci.draw_circle(c + Vector2(0, 4) * scale, 10.0 * scale, ink)
	ci.draw_circle(c + Vector2(0, 4) * scale, 7.5 * scale, Color(0.9, 0.2, 0.3))
	ci.draw_circle(c + Vector2(-2.5, 1.5) * scale, 2.2 * scale, Color(1, 0.8, 0.8))
	ci.draw_rect(Rect2(c + Vector2(-3.5, -10) * scale, Vector2(7, 8) * scale), ink)
	ci.draw_rect(Rect2(c + Vector2(-2, -9) * scale, Vector2(4, 6) * scale), Color(0.85, 0.85, 0.9))
	ci.draw_rect(Rect2(c + Vector2(-4, -13) * scale, Vector2(8, 4) * scale), Color(0.55, 0.35, 0.2))
