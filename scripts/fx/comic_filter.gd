class_name ComicFilter
extends CanvasLayer
## Screen-space comic print filter. Sits above the world and below the UI so
## lettering stays crisp. Reacts to hope: low hope drains the colour.

const SHADER := preload("res://shaders/comic_post.gdshader")

var material: ShaderMaterial
var _rect: ColorRect


func _ready() -> void:
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	material = ShaderMaterial.new()
	material.shader = SHADER
	_rect.material = material
	add_child(_rect)
	GameState.hope_changed.connect(func(_v: float, _d: float, _r: String) -> void: _update_hope())
	_update_hope()


func apply_style(style: ComicStyle) -> void:
	if style:
		style.apply_to(material)


func flash(strength: float = 0.6, duration: float = 0.15) -> void:
	material.set_shader_parameter("impact_flash", strength)
	var t := create_tween()
	t.tween_method(func(v: float) -> void: material.set_shader_parameter("impact_flash", v), strength, 0.0, duration)


func _update_hope() -> void:
	var desat := clampf((40.0 - GameState.hope) / 40.0, 0.0, 1.0) * 0.75
	material.set_shader_parameter("hope_desaturation", desat)
