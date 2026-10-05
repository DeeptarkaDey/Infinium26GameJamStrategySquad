extends Control
## Final comic page. The ending varies with the hope the samurai kept and the
## way he reached the Vihara.

func _ready() -> void:
	theme = ComicTheme.make_theme()
	var bg := ColorRect.new()
	bg.color = ComicTheme.INK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var page := PanelContainer.new()
	page.anchor_left = 0.12
	page.anchor_right = 0.88
	page.anchor_top = 0.08
	page.anchor_bottom = 0.92
	add_child(page)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 16)
	page.add_child(vb)

	var radiant := GameState.hope >= 70.0
	var saved := GameState.has_flag("saved_by_light")
	var heading := Label.new()
	heading.label_settings = ComicTheme.label_settings(44)
	heading.text = "DAWN" if radiant else ("EMBER" if not saved else "SECOND LIGHT")
	vb.add_child(heading)

	var text := Label.new()
	text.autowrap_mode = TextServer.AUTOWRAP_WORD
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text.label_settings = ComicTheme.label_settings(22)
	var body := "The mask fell, and beneath it there was no face at all - only hunger, and the borrowed light of three worlds.\n\n"
	if saved:
		body += "You had let your own light go out once. Someone you never met carried it back to you. You will spend the rest of your days carrying it forward.\n\n"
	if radiant:
		body += "The fragments did not return to the monk. They returned home. In every dimension at once, a lantern flickered back to life."
	else:
		body += "The worlds are quieter now. Not healed - but no longer bleeding. Some lights, once taken, only come back slowly."
	body += _promises()
	text.text = body
	vb.add_child(text)

	var stats := Label.new()
	stats.label_settings = ComicTheme.label_settings(18, Color(0.35, 0.3, 0.3))
	stats.text = "Hope kept: %d%%   Keys: %d   Powers: %d   Gold: %d" % [roundi(GameState.hope), GameState.keys.size(), GameState.powers.size(), GameState.gold]
	vb.add_child(stats)

	var back := Button.new()
	back.text = "THE END  -  back to title"
	back.pressed.connect(func() -> void:
		if FileAccess.file_exists(GameState.SAVE_PATH):
			DirAccess.remove_absolute(GameState.SAVE_PATH)
		GameState.reset()
		SceneRouter.go_to_scene("res://scenes/main/title.tscn"))
	vb.add_child(back)
	back.grab_focus.call_deferred()


## The subquest promises kept along the way, each remembered on the last page.
func _promises() -> String:
	var lines: Array[String] = []
	if GameState.has_flag("hana_vow"):
		lines.append("On Ukiyo Shore, the black water went back to blue. A girl with a charm on a string was the first to see it.")
	if GameState.has_flag("mei_vow"):
		lines.append("In Lantern City, a lamp hangs by the market stall that never needs oil. The lost follow it home.")
	if GameState.has_flag("aki_new_ending"):
		lines.append("In Prism Metro, a girl finished her sketchbook. On the last page, the hat man is standing up.")
	elif GameState.has_flag("aki_page_returned"):
		lines.append("In Prism Metro, a girl kept the true page, and drew a better one after it.")
	return "\n\n" + "\n".join(lines) if not lines.is_empty() else ""
