extends Interactable
## A hidden shrine holding this world's key: the path for players who did not
## earn the key through kindness. Lights up when found.

var world_id := ""
var _opened := false


func _ready() -> void:
	prompt = "Pray at the shrine"
	super._ready()


func can_interact() -> bool:
	return not _opened


func interact(_player: Player) -> void:
	_opened = true
	if GameState.has_key(world_id):
		GameState.add_gold(25)
		GameState.toast.emit("The shrine is empty... someone left an offering. (+25g)", Color(1, 0.85, 0.3))
	else:
		GameState.give_key(world_id)
		SfxWord.spawn(get_parent(), global_position + Vector2(0, -100), "SHINGG!", Color(1.0, 0.9, 0.4), 36)
	queue_redraw()


func _draw() -> void:
	var gate := Color(0.75, 0.15, 0.1) if not _opened else Color(0.45, 0.35, 0.3)
	# A tiny torii gate.
	draw_rect(Rect2(-26, -64, 7, 64), gate)
	draw_rect(Rect2(19, -64, 7, 64), gate)
	draw_rect(Rect2(-36, -72, 72, 9), gate)
	draw_rect(Rect2(-30, -58, 60, 6), gate)
	for r in [Rect2(-26, -64, 7, 64), Rect2(19, -64, 7, 64), Rect2(-36, -72, 72, 9), Rect2(-30, -58, 60, 6)]:
		draw_rect(r, ComicTheme.INK, false, 2.5)
	if not _opened:
		draw_circle(Vector2(0, -30), 9, Color(1.0, 0.85, 0.3))
		draw_arc(Vector2(0, -30), 9, 0, TAU, 16, ComicTheme.INK, 2.5)
