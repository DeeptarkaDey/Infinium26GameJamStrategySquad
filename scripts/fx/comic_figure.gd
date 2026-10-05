@tool
class_name ComicFigure
extends Node2D
## Placeholder character art drawn with thick comic ink lines. Origin = feet.
## Yokai and the monk always have covered faces: majestic masks and crowns, half
## holy, half wrong. Swap this node for a Sprite2D/AnimatedSprite2D when art lands.

enum Mask { NONE, NOH, ONI, KITSUNE, VEIL, KASA, SUN }
enum Crown { NONE, HALO, SPIKED, LOTUS, EBOSHI, ANTLERS }

const INK := Color(0.06, 0.05, 0.07)
const LINE := 3.0

@export var height: float = 64.0:
	set(v): height = v; queue_redraw()
@export var width: float = 30.0:
	set(v): width = v; queue_redraw()
@export var body_color: Color = Color(0.3, 0.3, 0.35):
	set(v): body_color = v; queue_redraw()
@export var trim_color: Color = Color(0.85, 0.7, 0.3):
	set(v): trim_color = v; queue_redraw()
@export var mask: Mask = Mask.NONE:
	set(v): mask = v; queue_redraw()
@export var mask_color: Color = Color(0.95, 0.93, 0.88):
	set(v): mask_color = v; queue_redraw()
@export var crown: Crown = Crown.NONE:
	set(v): crown = v; queue_redraw()
@export var crown_color: Color = Color(0.95, 0.75, 0.2):
	set(v): crown_color = v; queue_redraw()
@export var eye_glow: Color = Color(0, 0, 0, 0):  ## alpha 0 = no glowing eyes
	set(v): eye_glow = v; queue_redraw()
@export var facing: int = 1:
	set(v): facing = 1 if v >= 0 else -1; queue_redraw()
@export var weapon_color: Color = Color(0, 0, 0, 0):  ## alpha 0 = unarmed
	set(v): weapon_color = v; queue_redraw()

var swing: float = 0.0:  ## 0..1 attack pose
	set(v): swing = v; queue_redraw()
var squash: float = 0.0:  ## -1..1 stretch for dashes / hits
	set(v): squash = v; queue_redraw()


## Applies a look dictionary from world data, e.g.
## {"mask": "noh", "crown": "halo", "body": "#3a2a4a", "height": 80}
func apply_look(look: Dictionary) -> void:
	if look.has("height"): height = float(look.height)
	if look.has("width"): width = float(look.width)
	if look.has("body"): body_color = Color.from_string(str(look.body), body_color)
	if look.has("trim"): trim_color = Color.from_string(str(look.trim), trim_color)
	if look.has("mask"): mask = Mask.get(str(look.mask).to_upper(), Mask.NONE)
	if look.has("mask_color"): mask_color = Color.from_string(str(look.mask_color), mask_color)
	if look.has("crown"): crown = Crown.get(str(look.crown).to_upper(), Crown.NONE)
	if look.has("crown_color"): crown_color = Color.from_string(str(look.crown_color), crown_color)
	if look.has("eyes"): eye_glow = Color.from_string(str(look.eyes), eye_glow)


func _draw() -> void:
	var h := height * (1.0 - squash * 0.15)
	var w := width * (1.0 + squash * 0.15)
	var shoulder_y := -h * 0.7
	var head_r := h * 0.13
	var head := Vector2(0, -h * 0.82)

	# Halo sits behind everything.
	if crown == Crown.HALO:
		_ring(head + Vector2(0, -head_r * 0.2), head_r * 1.9, crown_color, 4.0)

	# Robe: a tall trapezoid, hem trimmed in gold.
	var robe := PackedVector2Array([
		Vector2(-w * 0.5, 0), Vector2(w * 0.5, 0),
		Vector2(w * 0.32, shoulder_y), Vector2(-w * 0.32, shoulder_y)])
	draw_colored_polygon(robe, body_color)
	draw_line(Vector2(-w * 0.5, -3), Vector2(w * 0.5, -3), trim_color, 5.0)
	draw_line(Vector2(0, shoulder_y), Vector2(0, -2), trim_color.darkened(0.2), 2.0)
	_outline(robe)

	# Weapon arm: angles are authored facing right, then mirrored.
	if weapon_color.a > 0.0:
		var hand := Vector2(w * 0.35 * facing, shoulder_y * 0.55)
		var angle := lerpf(-2.2, 0.4, swing)
		var dir := Vector2(cos(angle) * facing, sin(angle))
		var tip := hand + dir * h * 0.6
		draw_line(hand, tip, INK, 7.0)
		draw_line(hand, tip, weapon_color, 3.5)
		if swing > 0.2:
			# Speed lines trailing the swing.
			for i in 3:
				var a := angle - (0.3 + i * 0.25)
				var d := Vector2(cos(a) * facing, sin(a))
				draw_line(hand + d * h * 0.3, hand + d * h * 0.62, Color(INK, 0.5 * swing), 2.0)

	# Head.
	draw_circle(head, head_r, mask_color.darkened(0.4) if mask != Mask.NONE else Color(0.95, 0.8, 0.65))
	_ring(head, head_r, INK, LINE)
	_draw_mask(head, head_r)
	_draw_crown(head, head_r)


func _draw_mask(c: Vector2, r: float) -> void:
	var f := float(facing)
	match mask:
		Mask.NONE:
			draw_circle(c + Vector2(r * 0.35 * f, -r * 0.1), r * 0.12, INK)
		Mask.NOH:
			var pts := _ellipse(c + Vector2(0, r * 0.05), Vector2(r * 0.85, r * 1.1))
			draw_colored_polygon(pts, mask_color)
			_outline(pts)
			_slit_eyes(c, r)
			draw_line(c + Vector2(-r * 0.15, r * 0.6), c + Vector2(r * 0.15, r * 0.6), Color(0.7, 0.1, 0.1), 3.0)
		Mask.ONI:
			var pts := _ellipse(c, Vector2(r * 0.95, r * 1.05))
			draw_colored_polygon(pts, mask_color)
			_outline(pts)
			for s in [-1.0, 1.0]:
				var horn := PackedVector2Array([c + Vector2(s * r * 0.4, -r * 0.7), c + Vector2(s * r * 0.85, -r * 1.9), c + Vector2(s * r * 0.75, -r * 0.55)])
				draw_colored_polygon(horn, crown_color.lightened(0.3))
				_outline(horn)
				draw_line(c + Vector2(s * r * 0.3, r * 0.45), c + Vector2(s * r * 0.35, r * 0.85), Color.WHITE, 3.0)
			_slit_eyes(c, r)
			draw_line(c + Vector2(-r * 0.45, r * 0.45), c + Vector2(r * 0.45, r * 0.45), INK, 3.0)
		Mask.KITSUNE:
			var pts := _ellipse(c, Vector2(r * 0.9, r * 1.0))
			draw_colored_polygon(pts, mask_color)
			_outline(pts)
			for s in [-1.0, 1.0]:
				var ear := PackedVector2Array([c + Vector2(s * r * 0.3, -r * 0.8), c + Vector2(s * r * 0.75, -r * 1.7), c + Vector2(s * r * 0.85, -r * 0.5)])
				draw_colored_polygon(ear, mask_color)
				_outline(ear)
				draw_line(c + Vector2(s * r * 0.2, -r * 0.5), c + Vector2(s * r * 0.6, -r * 0.1), Color(0.8, 0.1, 0.15), 3.0)
			_slit_eyes(c, r)
		Mask.VEIL:
			var veil := PackedVector2Array([c + Vector2(-r * 1.1, -r * 0.9), c + Vector2(r * 1.1, -r * 0.9),
				c + Vector2(r * 1.4, r * 2.6), c + Vector2(-r * 1.4, r * 2.6)])
			draw_colored_polygon(veil, mask_color)
			_outline(veil)
			# A single all-seeing eye stitched into the cloth.
			var eye := _ellipse(c + Vector2(0, r * 0.1), Vector2(r * 0.45, r * 0.2))
			draw_colored_polygon(eye, trim_color)
			_outline(eye)
			draw_circle(c + Vector2(0, r * 0.1), r * 0.12, eye_glow if eye_glow.a > 0 else INK)
		Mask.KASA:
			# The samurai's straw hat shadows the face.
			var hat := PackedVector2Array([c + Vector2(-r * 2.0, -r * 0.1), c + Vector2(0, -r * 1.3), c + Vector2(r * 2.0, -r * 0.1)])
			draw_rect(Rect2(c + Vector2(-r, -r * 0.1), Vector2(r * 2.0, r * 0.7)), Color(INK, 0.55))
			draw_colored_polygon(hat, Color(0.82, 0.68, 0.38))
			_outline(hat)
			draw_circle(c + Vector2(r * 0.4 * f, r * 0.25), r * 0.1, eye_glow if eye_glow.a > 0 else Color(0.95, 0.9, 0.8))
		Mask.SUN:
			for i in 12:
				var a := TAU * i / 12.0
				draw_line(c + Vector2(cos(a), sin(a)) * r * 1.0, c + Vector2(cos(a), sin(a)) * r * 1.6, crown_color, 4.0)
			var pts := _ellipse(c, Vector2(r, r))
			draw_colored_polygon(pts, mask_color)
			_outline(pts)
			_slit_eyes(c, r)
	if eye_glow.a > 0.0 and mask in [Mask.NOH, Mask.ONI, Mask.KITSUNE, Mask.SUN]:
		for s in [-1.0, 1.0]:
			draw_circle(c + Vector2(s * r * 0.35, -r * 0.1), r * 0.12, eye_glow)


func _draw_crown(c: Vector2, r: float) -> void:
	var top := c + Vector2(0, -r * 0.85)
	match crown:
		Crown.SPIKED:
			var pts := PackedVector2Array([top + Vector2(-r, r * 0.2)])
			for i in 5:
				var x := -r + (i + 0.5) * (2.0 * r / 5.0)
				pts.append(top + Vector2(x, -r * (1.1 if i == 2 else 0.75)))
				pts.append(top + Vector2(x + r * 0.2, -r * 0.1))
			pts.append(top + Vector2(r, r * 0.2))
			draw_colored_polygon(pts, crown_color)
			_outline(pts)
			draw_circle(top + Vector2(0, -r * 0.1), r * 0.15, Color(0.8, 0.1, 0.2))
		Crown.LOTUS:
			for i in 5:
				var a := lerpf(-2.5, -0.64, i / 4.0)
				var petal := _ellipse(top + Vector2(cos(a), sin(a)) * r * 0.6, Vector2(r * 0.28, r * 0.6), a + PI / 2.0)
				draw_colored_polygon(petal, crown_color)
				_outline(petal)
		Crown.EBOSHI:
			var hat := PackedVector2Array([top + Vector2(-r * 0.7, r * 0.2), top + Vector2(-r * 0.4, -r * 1.8),
				top + Vector2(r * 0.5, -r * 1.5), top + Vector2(r * 0.7, r * 0.2)])
			draw_colored_polygon(hat, INK.lightened(0.15))
			_outline(hat)
			draw_line(top + Vector2(-r * 0.6, 0), top + Vector2(r * 0.6, 0), crown_color, 3.0)
		Crown.ANTLERS:
			for s in [-1.0, 1.0]:
				var base := top + Vector2(s * r * 0.4, 0)
				var mid := base + Vector2(s * r * 0.7, -r * 1.2)
				draw_line(base, mid, crown_color, 4.0)
				draw_line(mid, mid + Vector2(s * r * 0.6, -r * 0.6), crown_color, 3.0)
				draw_line(mid, mid + Vector2(-s * r * 0.1, -r * 0.9), crown_color, 3.0)
				draw_line(base.lerp(mid, 0.5), base.lerp(mid, 0.5) + Vector2(s * r * 0.6, -r * 0.1), crown_color, 3.0)


func _slit_eyes(c: Vector2, r: float) -> void:
	for s in [-1.0, 1.0]:
		var e := c + Vector2(s * r * 0.35, -r * 0.1)
		draw_line(e - Vector2(r * 0.2, -r * 0.05 * s), e + Vector2(r * 0.2, r * 0.05 * s), INK, 3.0)


func _ellipse(c: Vector2, radii: Vector2, rot: float = 0.0, steps: int = 20) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in steps:
		var a := TAU * i / steps
		pts.append(c + Vector2(cos(a) * radii.x, sin(a) * radii.y).rotated(rot))
	return pts


func _ring(c: Vector2, r: float, col: Color, w: float) -> void:
	draw_arc(c, r, 0.0, TAU, 32, col, w, true)


func _outline(pts: PackedVector2Array) -> void:
	var closed := pts.duplicate()
	closed.append(pts[0])
	draw_polyline(closed, INK, LINE, true)
