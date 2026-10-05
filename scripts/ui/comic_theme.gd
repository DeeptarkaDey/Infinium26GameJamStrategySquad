class_name ComicTheme
extends RefCounted
## Shared comic-book UI look: paper panels with thick ink borders, slightly
## rounded corners and hard drop shadows.

const PAPER := Color(0.98, 0.95, 0.86)
const INK := Color(0.06, 0.05, 0.07)
const CAPTION := Color(1.0, 0.9, 0.45)
## Panels and buttons get just a hint of rounding.
const CORNER := 6

static var _sfx_font: SystemFont


static func panel(bg: Color = PAPER, border: int = 4, shadow: int = 6) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = INK
	sb.set_border_width_all(border)
	sb.set_corner_radius_all(CORNER)
	sb.anti_aliasing = true
	sb.shadow_color = INK
	sb.shadow_size = 0
	sb.shadow_offset = Vector2(shadow, shadow)
	sb.set_content_margin_all(14)
	return sb


static func label_settings(size: int = 22, color: Color = INK, outline: int = 0, outline_color: Color = INK) -> LabelSettings:
	var ls := LabelSettings.new()
	ls.font_size = size
	ls.font_color = color
	ls.outline_size = outline
	ls.outline_color = outline_color
	return ls


## Heavy display face for in-world words (SFX, damage numbers, prompts): falls
## back through common bold system fonts.
static func sfx_font() -> Font:
	if not _sfx_font:
		_sfx_font = SystemFont.new()
		_sfx_font.font_names = PackedStringArray(["Impact", "Arial Black", "Helvetica Neue", "Arial", "sans-serif"])
		_sfx_font.font_weight = 800
	return _sfx_font


## Readable in-world lettering: bold face, solid colour, thick ink outline.
static func world_text(size: int, color: Color) -> LabelSettings:
	var ls := LabelSettings.new()
	ls.font = sfx_font()
	ls.font_size = size
	ls.font_color = color
	ls.outline_size = maxi(6, size / 4)
	ls.outline_color = INK
	return ls


static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 20
	t.set_stylebox("panel", "PanelContainer", panel())
	t.set_stylebox("panel", "Panel", panel())
	var normal := panel(PAPER, 3, 4)
	normal.set_content_margin_all(8)
	var hover := panel(CAPTION, 3, 4)
	hover.set_content_margin_all(8)
	var pressed := panel(CAPTION.darkened(0.2), 3, 2)
	pressed.set_content_margin_all(8)
	var disabled := panel(Color(0.75, 0.73, 0.68), 3, 2)
	disabled.set_content_margin_all(8)
	for state in ["normal", "focus"]:
		t.set_stylebox(state, "Button", normal if state == "normal" else hover)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("disabled", "Button", disabled)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		t.set_color(c, "Button", INK)
	t.set_color("font_disabled_color", "Button", Color(0.35, 0.33, 0.3))
	t.set_color("font_color", "Label", INK)
	t.set_color("default_color", "RichTextLabel", INK)
	return t
