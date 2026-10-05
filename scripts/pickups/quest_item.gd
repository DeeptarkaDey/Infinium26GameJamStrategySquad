extends Interactable
## Something an NPC asked you to find. Hidden until its quest step is reached
## (`requires` flag), gone once taken (`flag`). Taking it can play a short
## narration (`dialogue`).

var info: Dictionary = {}
var _t := 0.0


func _ready() -> void:
	prompt = "Take %s" % str(info.get("name", "it"))
	trigger_size = Vector2(60, 60)
	super._ready()


func available() -> bool:
	var req := str(info.get("requires", ""))
	return (req == "" or GameState.has_flag(req)) and not GameState.has_flag(str(info.get("flag", "")))


func can_interact() -> bool:
	return available()


func interact(_player: Player) -> void:
	if not available():
		return
	Sfx.play("quest")
	GameState.set_flag(str(info.get("flag", "")))
	SfxWord.spawn(get_parent(), global_position + Vector2(0, -70), "!", Color(0.75, 0.9, 1.0), 34)
	var d := str(info.get("dialogue", ""))
	if d != "":
		DialogueManager.start(d)
	else:
		GameState.toast.emit("FOUND - %s" % str(info.get("name", "")), Color(0.75, 0.9, 1.0))
	queue_free()


func _process(delta: float) -> void:
	_t += delta
	visible = available()
	queue_redraw()


func _draw() -> void:
	# A pale-blue glimmer with a star: quest things never look like loot.
	var c := Vector2(0, -22 + sin(_t * 3.0) * 3.0)
	draw_circle(c, 20.0 + sin(_t * 5.0) * 2.0, Color(0.6, 0.85, 1.0, 0.3))
	var pts := PackedVector2Array()
	for i in 10:
		var r := 14.0 if i % 2 == 0 else 6.0
		pts.append(c + Vector2.from_angle(-PI / 2.0 + TAU * i / 10.0) * r)
	draw_colored_polygon(pts, Color(0.85, 0.95, 1.0))
	pts.append(pts[0])
	draw_polyline(pts, ComicTheme.INK, 2.5)
