class_name Minimap
extends Control
## Corner map of the labyrinth, revealed room by room as you walk in. The
## current room is highlighted, sealed fights glow red, uncleared fights are
## dim red, and visited rooms show the shop, chests, boss and exit.

const MAX_SIZE := Vector2(240, 170)
const PAD := 8.0

var world: WorldBase
var _scale := 3.0
var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cols := 0
	for row in world._grid:
		cols = maxi(cols, row.length())
	var rows := world._grid.size()
	_scale = minf(MAX_SIZE.x / cols, MAX_SIZE.y / rows)
	var sz := Vector2(cols, rows) * _scale + Vector2(PAD, PAD) * 2.0
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = -sz.x - 16.0
	offset_right = -16.0
	offset_top = -sz.y - 40.0
	offset_bottom = -40.0


func _process(delta: float) -> void:
	_t += delta
	if _t > 0.15:
		_t = 0.0
		queue_redraw()


func _draw() -> void:
	if not world or not world.player:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.08, 0.07, 0.09, 0.78))
	draw_rect(Rect2(Vector2.ZERO, size), ComicTheme.INK, false, 3.0)
	var here := world.player_room()
	for room in world.rooms:
		if not room.visited:
			continue
		var col := Color(0.85, 0.82, 0.74)
		if room == here:
			col = ComicTheme.CAPTION
		if room.sealed:
			col = Color(0.95, 0.3, 0.25)
		elif not room.cleared and room.living() > 0:
			col = Color(0.75, 0.45, 0.42)
		for t: Vector2i in room.tiles:
			draw_rect(Rect2(_map(Vector2(t)), Vector2(_scale, _scale)), col)
		for g in room.gates:
			draw_rect(Rect2(_map(Vector2(g)), Vector2(_scale, _scale)), Color(0.55, 0.5, 0.45))
	var ts := float(world.data.tile_size)
	for e in world.entities.get_children():
		if not e is Node2D:
			continue  # floating SFX words are Labels
		var t := world.tile_of(e.global_position + Vector2(0, -6))
		var id: Variant = world._room_of.get(t)
		if id == null or not world.rooms[int(id)].visited:
			continue
		var p := _map(e.global_position / ts)
		if e is Portal:
			draw_circle(p, 4.0, Color(0.6, 0.45, 1.0))
		elif e is Boss:
			draw_circle(p, 4.5, Color(0.9, 0.1, 0.2))
		elif e is NPC and e.dialogue_id.begins_with("shop"):
			draw_circle(p, 3.5, Color(1.0, 0.85, 0.2))
		elif world.chests.has(e) and not e.get("opened"):
			draw_rect(Rect2(p - Vector2(3, 3), Vector2(6, 6)), Color(0.9, 0.6, 0.2))
	var pp := _map(world.player.global_position / ts)
	draw_circle(pp, 4.0, ComicTheme.INK)
	draw_circle(pp, 2.8, Color.WHITE)


func _map(tile_pos: Vector2) -> Vector2:
	return Vector2(PAD, PAD) + tile_pos * _scale
