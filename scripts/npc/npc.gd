class_name NPC
extends Interactable
## A talking character. Yokai and the monk wear masks; villagers are drawn plain.
## `dialogue_id` maps to data/dialogue/<id>.json (which may redirect via variants).

@export var npc_name: String = "Stranger"
@export var dialogue_id: String = ""
@export var look: Dictionary = {}

var figure: ComicFigure


func _ready() -> void:
	prompt = "Talk to %s" % npc_name
	figure = ComicFigure.new()
	figure.apply_look(look)
	add_child(figure)
	trigger_size = Vector2(maxf(90.0, figure.width * 2.5), figure.height + 20.0)
	super._ready()


func interact(player: Player) -> void:
	figure.facing = 1 if player.global_position.x > global_position.x else -1
	DialogueManager.start(dialogue_id)


func _process(_delta: float) -> void:
	# Idle breathing.
	figure.squash = sin(Time.get_ticks_msec() * 0.002 + get_instance_id()) * 0.08
