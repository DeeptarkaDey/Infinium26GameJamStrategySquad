class_name DialogueBox
extends CanvasLayer
## Comic speech balloon / narrator caption box. Driven by DialogueManager.

signal advanced
signal choice_selected(index: int)

const CHARS_PER_SEC := 55.0

## The box never takes more than this share of the screen height.
const MAX_HEIGHT_RATIO := 0.62
const BOTTOM_MARGIN := 16.0
## How far the name tag overlaps the box's top border.
const TAG_OVERLAP := 14.0

var _root: Control
var _stack: VBoxContainer  ## name tag above the panel, anchored to the bottom, grows upward
var _panel: PanelContainer
var _name_row: HBoxContainer
var _name_tag: PanelContainer
var _name_label: Label
var _text: RichTextLabel
var _choices: VBoxContainer
var _hint: Label
var _typing := false
var _input_grace := 0.0


func _init() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = ComicTheme.make_theme()
	add_child(_root)

	_stack = VBoxContainer.new()
	_stack.anchor_left = 0.08
	_stack.anchor_right = 0.92
	_stack.anchor_top = 1.0
	_stack.anchor_bottom = 1.0
	_stack.offset_bottom = -BOTTOM_MARGIN
	_stack.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_stack.add_theme_constant_override("separation", int(-TAG_OVERLAP))
	_root.add_child(_stack)

	# Name tag row: the tag sits on the panel's top edge, indented from the left.
	_name_row = HBoxContainer.new()
	_name_row.z_index = 1  # drawn over the panel border it overlaps
	_stack.add_child(_name_row)
	var indent := Control.new()
	indent.custom_minimum_size.x = 24
	_name_row.add_child(indent)
	_name_tag = PanelContainer.new()
	_name_row.add_child(_name_tag)
	_name_label = Label.new()
	_name_label.label_settings = ComicTheme.label_settings(20, ComicTheme.INK)
	_name_tag.add_child(_name_label)

	_panel = PanelContainer.new()
	_stack.add_child(_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	_panel.add_child(vb)

	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	# Lay out the whole line up front so the box doesn't grow while it types.
	_text.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
	_text.custom_minimum_size = Vector2(0, 30)
	_text.add_theme_font_size_override("normal_font_size", 22)
	_text.add_theme_font_size_override("bold_font_size", 22)
	_text.add_theme_font_size_override("italics_font_size", 22)
	_text.add_theme_color_override("default_color", ComicTheme.INK)
	vb.add_child(_text)

	_choices = VBoxContainer.new()
	_choices.add_theme_constant_override("separation", 6)
	vb.add_child(_choices)

	_hint = Label.new()
	_hint.text = "[E] / click to continue"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.label_settings = ComicTheme.label_settings(14, Color(0.3, 0.28, 0.25))
	vb.add_child(_hint)
	get_viewport().size_changed.connect(_layout)
	hide()


func show_line(speaker: Dictionary, text: String, choices: Array) -> void:
	show()
	_input_grace = 0.15
	var style: String = speaker.get("style", "balloon")
	var bg := ComicTheme.PAPER
	if style == "caption":
		bg = ComicTheme.CAPTION
	elif speaker.has("panel_color"):
		bg = Color.from_string(str(speaker.panel_color), bg)
	var speaker_name: String = speaker.get("name", "")
	var has_name := speaker_name != ""
	var panel_box := ComicTheme.panel(bg, 4, 7)
	panel_box.content_margin_left = 18
	panel_box.content_margin_right = 18
	# Leave room under the tag so it never covers the first line.
	panel_box.content_margin_top = TAG_OVERLAP + 12.0 if has_name else 14.0
	_panel.add_theme_stylebox_override("panel", panel_box)
	_name_row.visible = has_name
	_name_label.text = speaker_name.to_upper()
	var tag_color := Color.from_string(str(speaker.get("color", "#ffe673")), ComicTheme.CAPTION)
	var tag_box := ComicTheme.panel(tag_color, 3, 4)
	tag_box.content_margin_top = 4
	tag_box.content_margin_bottom = 4
	_name_tag.add_theme_stylebox_override("panel", tag_box)
	_text.text = "[i]%s[/i]" % text if style == "caption" else text
	_text.visible_characters = 0
	_typing = true
	for c in _choices.get_children():
		_choices.remove_child(c)
		c.queue_free()
	_hint.visible = choices.is_empty()
	for i in choices.size():
		var b := Button.new()
		b.text = str(choices[i].text)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		# Hidden but laid out, so the box is already the right size while typing.
		b.modulate.a = 0.0
		b.disabled = true
		b.pressed.connect(_on_choice.bind(i))
		_choices.add_child(b)
	_relayout()


## Rich text measures itself a frame late, so lay out on the next two frames.
func _relayout() -> void:
	for i in 2:
		await get_tree().process_frame
		_layout()


## Sizes the box to its content: anchored to the bottom, growing upward, capped
## at MAX_HEIGHT_RATIO of the screen (long text shrinks a little to fit).
func _layout() -> void:
	if not visible:
		return
	var limit := get_viewport().get_visible_rect().size.y * MAX_HEIGHT_RATIO
	var size_px := 22
	_set_text_size(size_px)
	while _stack.get_combined_minimum_size().y > limit and size_px > 15:
		size_px -= 1
		_set_text_size(size_px)
	_stack.offset_top = _stack.offset_bottom - _stack.get_combined_minimum_size().y


func _set_text_size(px: int) -> void:
	for key in ["normal_font_size", "bold_font_size", "italics_font_size"]:
		_text.add_theme_font_size_override(key, px)
	for b: Button in _choices.get_children():
		b.add_theme_font_size_override("font_size", mini(px, 20))


func close() -> void:
	hide()
	for c in _choices.get_children():
		c.queue_free()


func _process(delta: float) -> void:
	if not visible:
		return
	_input_grace = maxf(0.0, _input_grace - delta)
	if _typing:
		var before := _text.visible_characters
		_text.visible_characters += maxi(1, int(CHARS_PER_SEC * delta + 0.5))
		if before / 3 != _text.visible_characters / 3:
			Sfx.play("blip", -8.0, 0.12)
		if _text.visible_characters >= _text.get_total_character_count():
			_finish_typing()


func _finish_typing() -> void:
	_typing = false
	_text.visible_characters = -1
	var first := true
	for b: Button in _choices.get_children():
		b.modulate.a = 1.0
		b.disabled = false
		if first and not b.is_queued_for_deletion():
			b.grab_focus.call_deferred()
			first = false


func _unhandled_input(event: InputEvent) -> void:
	if not visible or _input_grace > 0.0:
		return
	var pressed := event.is_action_pressed("interact") or event.is_action_pressed("ui_accept") \
		or event.is_action_pressed("attack") or event.is_action_pressed("dash")
	if not pressed:
		return
	get_viewport().set_input_as_handled()
	if _typing:
		_finish_typing()
	elif _choices.get_child_count() == 0:
		advanced.emit()


func _on_choice(i: int) -> void:
	if _input_grace > 0.0:
		return
	choice_selected.emit(i)
