extends Node
## Launches the smoke test runner on the root so it outlives scene changes.

func _ready() -> void:
	get_tree().root.add_child.call_deferred(preload("res://tests/smoke_runner.gd").new())
