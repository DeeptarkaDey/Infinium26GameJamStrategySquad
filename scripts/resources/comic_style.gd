@tool
class_name ComicStyle
extends Resource
## The visual "issue" a zone is printed in. Every world gets its own ComicStyle,
## which drives the full-screen comic post-process (shaders/comic_post.gdshader),
## the procedural backdrop palette and the lettering colours.

enum BackdropKind { TEMPLE, WAVES, CITY, POP, VIHARA, SHATTERED }

@export var style_name: String = "Sumi Ink"

@export_group("Palette")
@export var paper_color: Color = Color(0.96, 0.93, 0.85)
@export var ink_color: Color = Color(0.06, 0.05, 0.07)
@export var sky_top: Color = Color(0.85, 0.82, 0.75)
@export var sky_bottom: Color = Color(0.95, 0.92, 0.85)
@export var ground_color: Color = Color(0.25, 0.22, 0.2)
@export var backdrop_color: Color = Color(0.55, 0.5, 0.45)
@export var accent_color: Color = Color(0.75, 0.1, 0.1)
@export var backdrop: BackdropKind = BackdropKind.TEMPLE

@export_group("Post Process")
@export_range(2, 16) var posterize_levels: int = 6
@export_range(0.0, 1.0) var halftone_strength: float = 0.4
@export_range(2.0, 24.0) var halftone_scale: float = 6.0
@export var halftone_angle: float = 0.785
@export_range(0.0, 1.0) var hatching: float = 0.0
@export_range(0.0, 3.0) var outline_strength: float = 1.0
@export_range(0.01, 1.0) var outline_threshold: float = 0.2
@export_range(0.0, 8.0) var misregistration: float = 0.0
@export_range(0.0, 1.0) var paper_grain: float = 0.2
@export_range(0.0, 1.0) var paper_tint: float = 0.5
@export_range(0.0, 2.0) var saturation: float = 1.0
@export_range(0.0, 1.0) var monochrome: float = 0.0
@export_range(0.0, 1.0) var accent_keep: float = 0.0  ## keeps accent_color saturated in monochrome styles (noir red)

@export_group("Lettering")
@export var sfx_color: Color = Color(1.0, 0.85, 0.1)
@export var caption_color: Color = Color(1.0, 0.93, 0.55)
@export var transition_caption: String = "MEANWHILE..."


func apply_to(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("paper_color", paper_color)
	mat.set_shader_parameter("ink_color", ink_color)
	mat.set_shader_parameter("accent_color", accent_color)
	mat.set_shader_parameter("posterize_levels", float(posterize_levels))
	mat.set_shader_parameter("halftone_strength", halftone_strength)
	mat.set_shader_parameter("halftone_scale", halftone_scale)
	mat.set_shader_parameter("halftone_angle", halftone_angle)
	mat.set_shader_parameter("hatching", hatching)
	mat.set_shader_parameter("outline_strength", outline_strength)
	mat.set_shader_parameter("outline_threshold", outline_threshold)
	mat.set_shader_parameter("misregistration", misregistration)
	mat.set_shader_parameter("paper_grain", paper_grain)
	mat.set_shader_parameter("paper_tint", paper_tint)
	mat.set_shader_parameter("saturation", saturation)
	mat.set_shader_parameter("monochrome", monochrome)
	mat.set_shader_parameter("accent_keep", accent_keep)
