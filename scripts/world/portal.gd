class_name Portal
extends Interactable
## A tear between comic pages. Walk into it to cross to another world, once the
## world's key is found and its target has fallen. A shut portal says why once
## per approach.

var target_world := "sanctum"
var requires_key := ""
var requires_flag := ""
var key_hint := "This world's key is still hidden."
var flag_hint := "Your target still stands."
var on_enter: Callable  ## optional override (hub portal picks the next mission)
## Stepping inside this box around the portal's foot takes you through.
const STEP_ZONE := Vector2(40, 30)
var _t := 0.0
var _used := false
var _warned := false


func _ready() -> void:
	prompt = "Walk through"
	trigger_size = Vector2(80, 130)
	super._ready()


func is_open() -> bool:
	if requires_key != "" and not GameState.has_key(requires_key):
		return false
	if requires_flag != "" and not GameState.has_flag(requires_flag):
		return false
	return true


func interact(_player: Player) -> void:
	if _used or SceneRouter.is_busy():
		return
	if not is_open():
		Sfx.play("error")
		var flag_missing := requires_flag != "" and not GameState.has_flag(requires_flag)
		GameState.toast.emit("The page will not turn. " + (flag_hint if flag_missing else key_hint), Color(0.9, 0.5, 0.5))
		return
	_used = true
	Sfx.play("portal")
	if on_enter.is_valid():
		on_enter.call()
	else:
		SceneRouter.go_to_world(target_world)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _physics_process(_delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player") as Player
	if not player or player.dead:
		return
	var d := player.global_position - global_position
	var inside := absf(d.x) < STEP_ZONE.x and absf(d.y) < STEP_ZONE.y
	if not inside:
		_warned = false
		return
	if GameState.is_player_locked() or (_warned and not is_open()):
		return
	_warned = true
	interact(player)


func _draw() -> void:
	var open := is_open()
	var rect := Rect2(-36, -128, 72, 124)
	draw_rect(rect, Color(0.08, 0.06, 0.12))
	# Swirling panel lines inside the tear.
	for i in 6:
		var y := fposmod(_t * 60.0 + i * 22.0, 120.0)
		draw_line(Vector2(-30, -8 - y), Vector2(30, -8 - y + 10), Color(1.0, 0.85, 0.4, 0.6) if open else Color(0.4, 0.4, 0.5, 0.4), 3.0)
	draw_rect(rect, ComicTheme.INK, false, 6.0)
	draw_rect(rect.grow(-6), Color(1.0, 0.85, 0.3) if open else Color(0.5, 0.45, 0.45), false, 3.0)
