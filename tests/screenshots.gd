extends Node

func _ready() -> void:
	get_tree().root.add_child.call_deferred(preload("res://tests/screenshot_runner.gd").new())
