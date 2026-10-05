extends Node
## Launches the UI check runner on the root so it outlives scene changes.

func _ready() -> void:
	get_tree().root.add_child.call_deferred(preload("res://tests/ui_check_runner.gd").new())
