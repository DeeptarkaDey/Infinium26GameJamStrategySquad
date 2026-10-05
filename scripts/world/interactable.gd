class_name Interactable
extends Area2D
## Base for anything the player can press [interact] on: NPCs, shops, portals,
## weapon drops, key shrines. Subclasses override interact().

@export var prompt: String = "Interact"
@export var trigger_size: Vector2 = Vector2(72, 80)

var _prompt: PanelContainer
var _prompt_label: Label


func _ready() -> void:
	collision_layer = 8
	collision_mask = 2
	monitorable = false
	if get_node_or_null("CollisionShape2D") == null:
		var shape := CollisionShape2D.new()
		shape.name = "CollisionShape2D"
		var rect := RectangleShape2D.new()
		# Top-down: the zone surrounds the feet, so you can walk up from any side.
		rect.size = Vector2(trigger_size.x + 40.0, 110.0)
		shape.shape = rect
		shape.position = Vector2(0, -12)
		add_child(shape)
	# "[E] Talk to ..." chip. Lives on the world's Overlay (above the comic shader).
	_prompt = PanelContainer.new()
	var chip := ComicTheme.panel(ComicTheme.PAPER, 3, 3)
	chip.set_content_margin_all(6)
	chip.content_margin_left = 10
	chip.content_margin_right = 10
	_prompt.add_theme_stylebox_override("panel", chip)
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt.visible = false
	_prompt_label = Label.new()
	_prompt_label.label_settings = ComicTheme.label_settings(16, ComicTheme.INK)
	_prompt.add_child(_prompt_label)
	var world := WorldBase.of(self)
	if world and world.overlay:
		world.overlay.add_child.call_deferred(_prompt)
	else:
		add_child(_prompt)
	tree_exiting.connect(func() -> void:
		if is_instance_valid(_prompt) and _prompt.get_parent() != self:
			_prompt.queue_free())
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func can_interact() -> bool:
	return true


func interact(_player: Player) -> void:
	pass


func set_highlighted(on: bool) -> void:
	_prompt.visible = on and can_interact()
	if _prompt.visible:
		_prompt_label.text = "[E]  " + prompt
		_prompt.reset_size()
		_prompt.global_position = global_position + Vector2(-_prompt.size.x * 0.5, -trigger_size.y - 50)


func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		body.register_interactable(self)


func _on_body_exited(body: Node2D) -> void:
	if body is Player:
		body.unregister_interactable(self)
		set_highlighted(false)
