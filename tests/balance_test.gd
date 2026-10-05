extends Node
## Launches the balance runner on the root so it outlives scene changes.

func _ready() -> void:
	get_tree().root.add_child.call_deferred(preload("res://tests/balance_runner.gd").new())
