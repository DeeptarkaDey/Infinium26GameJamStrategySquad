class_name SfxWord
extends Label
## Comic onomatopoeia ("SLASH!", "KRAK!") and damage numbers: pops, drifts up
## and fades. Drawn on the world's Overlay layer, above the comic shader, so the
## posterize / outline pass can't smear the lettering.

static func spawn(parent: Node, pos: Vector2, text: String, color: Color = Color(1.0, 0.85, 0.1), size: int = 34) -> SfxWord:
	if not is_instance_valid(parent):
		return null
	var host := parent
	var world := WorldBase.of(parent)
	if world and world.overlay:
		host = world.overlay
	var w := SfxWord.new()
	w.text = text
	w.label_settings = ComicTheme.world_text(size, color)
	w.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(w)
	w.reset_size()
	w.pivot_offset = w.size * 0.5
	w.global_position = pos - w.size * 0.5
	w.rotation = randf_range(-0.12, 0.12)
	w.scale = Vector2(0.4, 0.4)
	var t := w.create_tween()
	t.tween_property(w, "scale", Vector2(1.1, 1.1), 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(w, "scale", Vector2.ONE, 0.08)
	t.parallel().tween_property(w, "position:y", w.position.y - 40.0, 0.7)
	t.tween_property(w, "modulate:a", 0.0, 0.25)
	t.tween_callback(w.queue_free)
	return w
