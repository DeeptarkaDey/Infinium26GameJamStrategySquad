class_name MonsterFigure
extends ComicFigure
## Placeholder art for the non-human bosses (and their crystal shards), drawn in
## the same thick-ink comic style as ComicFigure. Origin = the point on the
## floor below the creature. Colours come from the world's boss_look:
## body_color, trim_color (fins / wing spots), eye_glow, crown_color (horns /
## lanterns / mirror shards).

## "serpent", "moth", "eye" or "shard".
var form := "serpent"
## Serpent only: body segment positions relative to the head, nearest first.
var segments := PackedVector2Array()
## Serpent only: under the floor, only a ripple shows.
var submerged := false
## Eye only: where the pupil looks (unit vector).
var look_dir := Vector2.DOWN
var _t := 0.0


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	match form:
		"serpent": _draw_serpent()
		"moth": _draw_moth()
		"eye": _draw_eye()
		"shard": _draw_shard()
		_: super._draw()


func _shadow(w: float) -> void:
	draw_set_transform(Vector2(0, -4), 0.0, Vector2(1.0, 0.35))
	draw_circle(Vector2.ZERO, w, Color(0, 0, 0, 0.25))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _blob(c: Vector2, r: float, col: Color) -> void:
	draw_circle(c, r + 3.5, INK)
	draw_circle(c, r, col)


# --- Great sea serpent -----------------------------------------------------------

func _draw_serpent() -> void:
	if submerged:
		for i in 3:
			var r := fposmod(_t * 50.0 + i * 25.0, 75.0) + 15.0
			draw_arc(Vector2.ZERO, r, 0, TAU, 28, Color(0.85, 0.95, 1.0, 1.0 - r / 90.0), 3.0)
		return
	# Coils trail behind, rising out of the floor (back to front so the head is on top).
	var n := segments.size()
	for i in range(n - 1, -1, -1):
		var k := float(i) / maxf(1.0, n)
		var r := lerpf(40.0, 16.0, k)
		var p := segments[i] + Vector2(0, -r - 6.0)
		_blob(p, r, body_color.lerp(body_color.darkened(0.3), k))
		# Dorsal fin on every other coil.
		if i % 2 == 0:
			var fin := PackedVector2Array([p + Vector2(-r * 0.5, -r * 0.6), p + Vector2(0, -r * 1.7), p + Vector2(r * 0.5, -r * 0.6)])
			draw_colored_polygon(fin, trim_color)
			fin.append(fin[0])
			draw_polyline(fin, INK, 3.0)
	_shadow(70.0)
	# Neck rising to the head.
	var neck := Vector2(0, -60)
	_blob(neck, 38.0, body_color)
	var head := Vector2(18.0 * facing, -120.0 - squash * 20.0)
	draw_line(neck, head, INK, 58.0)
	draw_line(neck, head, body_color, 50.0)
	# Head: a long wedge with a frilled crest and horns.
	var f := float(facing)
	var skull := PackedVector2Array([head + Vector2(-34 * f, -26), head + Vector2(60 * f, -8), head + Vector2(66 * f, 14),
		head + Vector2(10 * f, 30), head + Vector2(-38 * f, 18)])
	draw_colored_polygon(skull, body_color.lightened(0.08))
	skull.append(skull[0])
	draw_polyline(skull, INK, LINE)
	for i in 4:
		var base := head + Vector2((-30 + i * 9) * f, -20)
		var spike := PackedVector2Array([base, base + Vector2(-16 * f, -40 + i * 6), base + Vector2(8 * f, -6)])
		draw_colored_polygon(spike, trim_color)
		spike.append(spike[0])
		draw_polyline(spike, INK, 2.5)
	for s: float in [-1.0, 1.0]:
		var hb := head + Vector2((-6 + s * 10) * f, -24)
		draw_line(hb, hb + Vector2(-34 * f, -46 + s * 8), INK, 9.0)
		draw_line(hb, hb + Vector2(-34 * f, -46 + s * 8), crown_color, 5.0)
	var eye := head + Vector2(26 * f, -6)
	draw_circle(eye, 9.0, INK)
	draw_circle(eye, 6.5, eye_glow if eye_glow.a > 0.0 else Color.WHITE)
	draw_line(eye + Vector2(0, -5), eye + Vector2(0, 5), INK, 2.5)
	# Jaw line, opening when about to spit.
	var gape := 10.0 + squash * 22.0
	draw_line(head + Vector2(66 * f, 14), head + Vector2(14 * f, 14 + gape), INK, 4.0)


# --- Lantern moth ----------------------------------------------------------------

func _draw_moth() -> void:
	_shadow(90.0)
	var lift := -110.0 + sin(_t * 2.4) * 8.0 + squash * 30.0
	var body := Vector2(0, lift)
	var flap := sin(_t * 9.0) * 0.35
	# Four wings, upper pair larger, eye-spots in trim colour.
	for s: float in [-1.0, 1.0]:
		for upper: bool in [true, false]:
			var span := 120.0 if upper else 82.0
			var ang: float = (-0.55 if upper else 0.45) + flap * s * (1.0 if upper else 0.6)
			var tip := body + Vector2(s * span * cos(ang), span * sin(ang) * (0.9 if upper else 1.1))
			var wing := PackedVector2Array([body + Vector2(s * 8, -10), tip + Vector2(0, -24 if upper else 0),
				tip + Vector2(s * 14, 18), body + Vector2(s * 10, 18 if upper else 30)])
			draw_colored_polygon(wing, body_color.lightened(0.15 if upper else 0.05))
			wing.append(wing[0])
			draw_polyline(wing, INK, LINE)
			var spot := body.lerp(tip, 0.62)
			_blob(spot, 14.0 if upper else 9.0, trim_color)
			draw_circle(spot, 5.0 if upper else 3.0, INK)
	# Fuzzy segmented body.
	for i in 4:
		_blob(body + Vector2(0, -18 + i * 16), 22.0 - i * 3.0, body_color.darkened(0.1 * i))
	var head := body + Vector2(0, -38)
	_blob(head, 20.0, body_color.lightened(0.2))
	for s: float in [-1.0, 1.0]:
		draw_circle(head + Vector2(s * 9, -2), 6.0, eye_glow if eye_glow.a > 0.0 else Color(1, 0.9, 0.4))
		# Feathery antennae.
		var a0 := head + Vector2(s * 8, -16)
		var a1 := a0 + Vector2(s * 34, -40)
		draw_line(a0, a1, INK, 3.0)
		for k in 5:
			var p := a0.lerp(a1, 0.3 + k * 0.15)
			draw_line(p, p + Vector2(s * 9, 5), INK, 2.0)
	# Lanterns of the souls it walks home, hanging on silk threads.
	for s: float in [-1.0, 0.0, 1.0]:
		var top := body + Vector2(s * 26, 34)
		var lamp := top + Vector2(sin(_t * 2.0 + s) * 4.0, 34.0 + absf(s) * 10.0)
		draw_line(top, lamp, INK, 1.5)
		draw_circle(lamp, 16.0, Color(crown_color, 0.25))
		var box := Rect2(lamp - Vector2(8, 10), Vector2(16, 20))
		draw_rect(box, crown_color)
		draw_rect(box, INK, false, 2.5)


# --- Eye of broken mirrors ----------------------------------------------------------

func _draw_eye() -> void:
	_shadow(70.0)
	var c := Vector2(0, -100 + sin(_t * 1.8) * 6.0)
	# Mirror shards drift in a halo behind it.
	for i in 9:
		var a := TAU * i / 9.0 + _t * 0.4
		var p := c + Vector2.from_angle(a) * (92.0 + sin(_t * 2.0 + i) * 6.0)
		var shard := PackedVector2Array([p + Vector2.from_angle(a) * 16.0, p + Vector2.from_angle(a + 2.2) * 9.0, p + Vector2.from_angle(a - 2.2) * 9.0])
		draw_colored_polygon(shard, crown_color)
		shard.append(shard[0])
		draw_polyline(shard, INK, 2.0)
	# Stalks with smaller eyes, beholder style.
	for i in 5:
		var a := -PI * 0.5 + (i - 2) * 0.5
		var tip := c + Vector2.from_angle(a) * 92.0 + Vector2(0, sin(_t * 3.0 + i) * 5.0)
		draw_line(c + Vector2.from_angle(a) * 50.0, tip, INK, 8.0)
		draw_line(c + Vector2.from_angle(a) * 50.0, tip, body_color.darkened(0.2), 4.0)
		_blob(tip, 9.0, Color.WHITE)
		draw_circle(tip + look_dir * 3.0, 4.0, trim_color)
	# The great eye.
	_blob(c, 64.0, body_color)
	var lid := clampf(squash, 0.0, 1.0)
	draw_circle(c, 48.0, Color(0.98, 0.96, 0.92))
	var iris := c + look_dir * 16.0
	draw_circle(iris, 26.0, eye_glow if eye_glow.a > 0.0 else Color(0.3, 0.8, 1.0))
	draw_circle(iris, 26.0 * 0.45, INK)
	draw_circle(iris + Vector2(-8, -8), 5.0, Color.WHITE)
	# Lids narrow while it charges the beam.
	if lid > 0.0:
		draw_rect(Rect2(c + Vector2(-50, -50), Vector2(100, 50.0 * lid)), body_color)
		draw_rect(Rect2(c + Vector2(-50, 50.0 - 50.0 * lid), Vector2(100, 50.0 * lid)), body_color)
	draw_arc(c, 48.0, 0, TAU, 32, INK, LINE)
	# Halftone cracks across the lens.
	draw_line(c + Vector2(-30, -30), c + Vector2(-8, -6), Color(INK, 0.5), 2.0)
	draw_line(c + Vector2(20, 26), c + Vector2(34, 8), Color(INK, 0.5), 2.0)


func _draw_shard() -> void:
	var c := Vector2(0, -50 + sin(_t * 3.0) * 5.0)
	var pts := PackedVector2Array([c + Vector2(0, -34), c + Vector2(16, -4), c + Vector2(0, 30), c + Vector2(-16, -4)])
	draw_colored_polygon(pts, crown_color)
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -34), c + Vector2(16, -4), c]), crown_color.lightened(0.4))
	pts.append(pts[0])
	draw_polyline(pts, INK, LINE)
	draw_circle(c, 5.0, eye_glow if eye_glow.a > 0.0 else Color.WHITE)
