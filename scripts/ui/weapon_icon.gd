class_name WeaponIcon
extends RefCounted
## Placeholder item art: draws a weapon by kind, in its blade colour, onto any
## CanvasItem. Shared by floor pickups and the inventory grid.

static func draw(ci: CanvasItem, c: Vector2, size: float, w: WeaponData) -> void:
	var ink := ComicTheme.INK
	var col := w.blade_color
	var s := size * 0.5
	match w.kind:
		WeaponData.Kind.BOW:
			ci.draw_arc(c + Vector2(-s * 0.3, 0), s * 0.9, -1.2, 1.2, 14, ink, 6.0)
			ci.draw_arc(c + Vector2(-s * 0.3, 0), s * 0.9, -1.2, 1.2, 14, col, 3.0)
			var top := c + Vector2(-s * 0.3, 0) + Vector2.from_angle(-1.2) * s * 0.9
			var bot := c + Vector2(-s * 0.3, 0) + Vector2.from_angle(1.2) * s * 0.9
			ci.draw_line(top, bot, Color(0.9, 0.9, 0.85), 1.5)
			ci.draw_line(c + Vector2(-s * 0.4, 0), c + Vector2(s * 0.9, 0), ink, 4.0)
			ci.draw_line(c + Vector2(-s * 0.4, 0), c + Vector2(s * 0.9, 0), Color(0.85, 0.75, 0.55), 2.0)
		WeaponData.Kind.STAFF:
			var a := c + Vector2(-s * 0.7, s * 0.8)
			var b := c + Vector2(s * 0.5, -s * 0.6)
			ci.draw_line(a, b, ink, 7.0)
			ci.draw_line(a, b, Color(0.6, 0.45, 0.3), 4.0)
			ci.draw_circle(b, s * 0.32, ink)
			ci.draw_circle(b, s * 0.24, col)
		_:
			# Blades: length and guard depend on the kind.
			var length := {WeaponData.Kind.SPEAR: 1.0, WeaponData.Kind.HEAVY: 0.95, WeaponData.Kind.DAGGER: 0.55}.get(w.kind, 0.8) as float
			var width := {WeaponData.Kind.HEAVY: 9.0, WeaponData.Kind.DAGGER: 5.0, WeaponData.Kind.SPEAR: 3.0}.get(w.kind, 6.0) as float
			var hilt := c + Vector2(-s * 0.75, s * 0.75)
			var dir := Vector2(1, -1).normalized()
			var guard := hilt + dir * s * (0.9 if w.kind == WeaponData.Kind.SPEAR else 0.35)
			var tip := guard + dir * s * 2.2 * length * (0.55 if w.kind == WeaponData.Kind.SPEAR else 1.0)
			ci.draw_line(hilt, guard, ink, 6.0)
			ci.draw_line(hilt, guard, Color(0.35, 0.2, 0.15), 3.0)
			ci.draw_line(guard, tip, ink, width + 4.0)
			ci.draw_line(guard, tip, col, width)
			if w.kind == WeaponData.Kind.SPEAR:
				var head := PackedVector2Array([tip + dir * 10.0, tip + dir.orthogonal() * 5.0, tip - dir.orthogonal() * 5.0])
				ci.draw_colored_polygon(head, col)
			else:
				var o := dir.orthogonal() * s * 0.28
				ci.draw_line(guard - o, guard + o, ink, 5.0)
				ci.draw_line(guard - o, guard + o, Color(0.85, 0.7, 0.3), 2.5)
	if w.element != "":
		ci.draw_circle(c + Vector2(s * 0.7, s * 0.7), s * 0.2, ink)
		ci.draw_circle(c + Vector2(s * 0.7, s * 0.7), s * 0.14, Skills.element_color(w.element))
