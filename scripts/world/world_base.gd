class_name WorldBase
extends Node2D
## Generic world scene, seen top-down. Builds whatever GameState.current_world()
## describes: floor and raised walls from the ASCII layout in the world's comic
## style, the entities, and the rooms. Rooms run like Endless Wander: step into a
## room with enemies and its gates seal; clear it and they open, and you pick a
## reward (a skill, an upgrade or an element). Also runs the story beats tied
## to the world.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const ENEMY_SCENE := preload("res://scenes/enemies/enemy.tscn")
const BOSS_SCENE := preload("res://scenes/enemies/boss.tscn")
## WorldData.boss_form -> Boss subclass (the base Boss is the humanoid fighter).
const BOSS_FORMS := {
	"serpent": preload("res://scripts/enemies/bosses/serpent_boss.gd"),
	"moth": preload("res://scripts/enemies/bosses/moth_boss.gd"),
	"eye": preload("res://scripts/enemies/bosses/eye_boss.gd"),
}
const KEY_SHRINE := preload("res://scripts/pickups/key_shrine.gd")
const COIN := preload("res://scripts/pickups/coin.gd")
const CHEST := preload("res://scripts/pickups/chest.gd")
const BREAKABLE := preload("res://scripts/pickups/breakable.gd")
const QUEST_ITEM := preload("res://scripts/pickups/quest_item.gd")
## Every Nth wall tile facing a room carries a torch.
const TORCH_SPACING := 4
const ENDING_SCENE := "res://scenes/main/ending.tscn"
## How tall walls are drawn above their footprint (the 3/4 view).
const WALL_RISE := 40.0
const GATE_LAYER := 16  ## physics layer 5: blocks enemies always, the player only while sealed

## One room: floor tiles connected without crossing a wall or gate.
class Room:
	var id := 0
	var tiles: Dictionary = {}  ## Vector2i -> true
	var gates: Array[Vector2i] = []
	var enemies: Array[Enemy] = []
	var has_boss := false
	var sealed := false
	var cleared := false
	var visited := false

	func living() -> int:
		var n := 0
		for e in enemies:
			if is_instance_valid(e) and not e.is_dead():
				n += 1
		return n

@onready var sky_layer: CanvasLayer = $Sky
@onready var level: Node2D = $Level
@onready var entities: Node2D = $Entities
@onready var comic_filter: ComicFilter = $ComicFilter
@onready var hud: HUD = $HUD
@onready var shop_ui: ShopUI = $ShopUI
@onready var reward_ui: RewardUI = $RewardUI
@onready var inventory_ui: InventoryUI = $InventoryUI

var data: WorldData
var player: Player
var spawn_point := Vector2(128, 128)
var level_size := Vector2.ZERO
var rooms: Array[Room] = []
var _grid: Array[String] = []
var _room_of: Dictionary = {}  ## Vector2i tile -> room id
var _gate_bodies: Dictionary = {}  ## Vector2i -> StaticBody2D
var _gate_art: Array[Node2D] = []
var _npc_index := 0
var _quest_item_index := 0
var _cutscene_death := false
var _shake := 0.0
var torches: Array[Vector2] = []  ## world positions of wall torches
var chests: Array[Node2D] = []
var minimap: Minimap
## Above the comic shader but moving with the camera: in-world lettering (SFX
## words, damage numbers, interact prompts) lives here so it stays readable.
var overlay: CanvasLayer


func _ready() -> void:
	data = GameState.current_world()
	if not data:
		push_error("No WorldData for '%s'" % GameState.current_world_id)
		return
	overlay = CanvasLayer.new()
	overlay.name = "Overlay"
	overlay.layer = 6
	overlay.follow_viewport_enabled = true
	add_child(overlay)
	_build_sky()
	_build_level()
	comic_filter.apply_style(data.style)
	inventory_ui.world = self
	DialogueManager.action_requested.connect(_on_dialogue_action)
	if data.kind == WorldData.Kind.MISSION:
		GameState.act = GameState.Act.MISSIONS
		# Each mission is a fresh run: the build gathered room by room starts over.
		if not GameState.has_flag("run_started_" + data.id):
			GameState.set_flag("run_started_" + data.id)
			GameState.start_run()
	elif data.kind == WorldData.Kind.SANCTUARY:
		GameState.act = GameState.Act.VIHARA
	elif data.kind == WorldData.Kind.FINALE:
		GameState.act = GameState.Act.FINALE
	_start_world.call_deferred()


## The WorldBase a node belongs to (walks up its ancestors), or null.
static func of(node: Node) -> WorldBase:
	var n := node
	while n:
		if n is WorldBase:
			return n
		n = n.get_parent()
	return null


func _exit_tree() -> void:
	if DialogueManager.action_requested.is_connected(_on_dialogue_action):
		DialogueManager.action_requested.disconnect(_on_dialogue_action)


func _start_world() -> void:
	if SceneRouter.is_busy():
		await SceneRouter.transition_finished
	hud.show_caption("%s\n%s" % [data.display_name.to_upper(), data.subtitle] if data.subtitle != "" else data.display_name.to_upper())
	var seen := "intro_seen_" + data.id
	if data.intro_dialogue != "" and not GameState.has_flag(seen):
		GameState.set_flag(seen)
		DialogueManager.start(data.intro_dialogue)


func _process(delta: float) -> void:
	if _shake > 0.0 and player:
		_shake = move_toward(_shake, 0.0, 40.0 * delta)
		player.camera.offset = Vector2(randf_range(-_shake, _shake), randf_range(-_shake, _shake))


func _physics_process(_delta: float) -> void:
	if player:
		_update_rooms()


func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


# --- Rooms --------------------------------------------------------------------

func tile_of(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / data.tile_size), floori(pos.y / data.tile_size))


## The room the player's feet are in, or null on a gate / outside.
func player_room() -> Room:
	var id: Variant = _room_of.get(tile_of(player.global_position + Vector2(0, -6)))
	return rooms[int(id)] if id != null else null


func _update_rooms() -> void:
	var here := player_room() if not player.dead else null
	if here and not here.visited:
		here.visited = true
		if minimap:
			minimap.queue_redraw()
	for room in rooms:
		var aggro := room == here
		for e in room.enemies:
			if is_instance_valid(e):
				e.aggro = aggro
	if not here:
		return
	if here.sealed:
		if here.living() == 0:
			_clear_room(here)
	elif not here.cleared and here.living() > 0 and _clear_of_gates(here):
		_seal_room(here)


## Only seal once the player is fully through the gate, so it never closes on them.
func _clear_of_gates(room: Room) -> bool:
	var ts := float(data.tile_size)
	for g in room.gates:
		var r := Rect2(Vector2(g) * ts, Vector2(ts, ts)).grow(22.0)
		if r.has_point(player.global_position):
			return false
	return true


func _seal_room(room: Room) -> void:
	if room.gates.is_empty():
		return
	room.sealed = true
	_set_gates(room, true)
	Sfx.play("seal")
	SfxWord.spawn(entities, player.global_position + Vector2(0, -110), "SEALED!", data.style.accent_color, 34)
	shake(5.0)


func _clear_room(room: Room) -> void:
	room.sealed = false
	room.cleared = true
	_set_gates(room, false)
	Sfx.play("clear")
	SfxWord.spawn(entities, player.global_position + Vector2(0, -110), "CLEAR!", Color(1.0, 0.9, 0.4), 44)
	if not room.has_boss:
		await get_tree().create_timer(0.6).timeout
		if is_inside_tree():
			reward_ui.open()


## A death inside a sealed room: the gates open and survivors heal and go home.
func _abandon_rooms() -> void:
	for room in rooms:
		if room.sealed:
			room.sealed = false
			_set_gates(room, false)
			for e in room.enemies:
				if is_instance_valid(e):
					e.reset_to_home()


func _set_gates(room: Room, closed: bool) -> void:
	for g in room.gates:
		var body: StaticBody2D = _gate_bodies.get(g)
		if body:
			body.collision_layer = GATE_LAYER | (1 if closed else 0)
	for art in _gate_art:
		art.queue_redraw()


func is_gate_closed(tile: Vector2i) -> bool:
	var body: StaticBody2D = _gate_bodies.get(tile)
	return body != null and body.collision_layer & 1 != 0


func _find_rooms() -> void:
	for y in _grid.size():
		for x in _grid[y].length():
			var t := Vector2i(x, y)
			if _is_floor(t) and not _room_of.has(t):
				var room := Room.new()
				room.id = rooms.size()
				rooms.append(room)
				var stack: Array[Vector2i] = [t]
				_room_of[t] = room.id
				while not stack.is_empty():
					var c: Vector2i = stack.pop_back()
					room.tiles[c] = true
					for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
						var n: Vector2i = c + d
						if _char(n) == "D" and not room.gates.has(n):
							room.gates.append(n)
						elif _is_floor(n) and not _room_of.has(n):
							_room_of[n] = room.id
							stack.append(n)


func _char(t: Vector2i) -> String:
	if t.y < 0 or t.y >= _grid.size() or t.x < 0 or t.x >= _grid[t.y].length():
		return " "
	return _grid[t.y][t.x]


func _is_floor(t: Vector2i) -> bool:
	var c := _char(t)
	return c != " " and c != "#" and c != "D"


# --- Building -----------------------------------------------------------------

func _build_sky() -> void:
	# Outside the map: one flat, dark colour from the world's palette. (A gradient
	# gets posterized into bands that sit still while the map scrolls, which reads
	# as the background moving; light colours get tinted odd hues by the shader.)
	var rect := ColorRect.new()
	rect.color = data.style.ground_color.lerp(data.style.ink_color, 0.75)
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sky_layer.add_child(rect)


func _build_level() -> void:
	var ts := data.tile_size
	var rows := Array(data.layout.split("\n"))
	while not rows.is_empty() and str(rows.front()).strip_edges() == "":
		rows.pop_front()
	while not rows.is_empty() and str(rows.back()).strip_edges() == "":
		rows.pop_back()
	var cols := 0
	for r in rows:
		cols = maxi(cols, str(r).length())
	for r in rows:
		_grid.append(str(r).rpad(cols))
	level_size = Vector2(cols * ts, rows.size() * ts)
	_find_rooms()

	# Wall collision: horizontal runs, stacked into slabs where they line up.
	var wall_runs: Array[Rect2] = []
	for y in _grid.size():
		var row := _grid[y]
		var x := 0
		while x < row.length():
			if row[x] == "#":
				var start := x
				while x < row.length() and row[x] == "#":
					x += 1
				_merge_down(wall_runs, Rect2(start * ts, y * ts, (x - start) * ts, ts))
				continue
			x += 1
	for rect in wall_runs:
		_add_body(rect, 1)

	var floor_art := Node2D.new()
	floor_art.z_index = -5
	floor_art.draw.connect(_draw_floor.bind(floor_art))
	level.add_child(floor_art)

	# Each wall row is its own y-sorted drawer, so characters walk behind walls
	# to their south and in front of walls to their north.
	entities.y_sort_enabled = true
	for y in _grid.size():
		if _grid[y].contains("#") or _grid[y].contains("D"):
			var row_art := Node2D.new()
			row_art.position = Vector2(0, (y + 1) * ts)
			row_art.draw.connect(_draw_wall_row.bind(row_art, y))
			entities.add_child(row_art)
			if _grid[y].contains("D"):
				_gate_art.append(row_art)

	for y in _grid.size():
		for x in _grid[y].length():
			var ch := _grid[y][x]
			if ch == "D":
				_gate_bodies[Vector2i(x, y)] = _add_body(Rect2(x * ts, y * ts, ts, ts), GATE_LAYER)
			elif ch != " " and ch != "#" and ch != ".":
				_spawn_entity(ch, Vector2(x * ts + ts * 0.5, y * ts + ts * 0.75), Vector2i(x, y))

	_promote_elites()
	_place_torches()
	player = PLAYER_SCENE.instantiate()
	player.position = spawn_point
	entities.add_child(player)
	minimap = Minimap.new()
	minimap.world = self
	hud.add_child(minimap)
	player.died.connect(_on_player_died)
	var cam := player.camera
	cam.limit_left = -ts
	cam.limit_top = -ts * 2
	cam.limit_right = int(level_size.x) + ts
	cam.limit_bottom = int(level_size.y) + ts


## Stacks a run onto the run directly above it when they line up, so a thick
## wall collides as one slab instead of a pile of bricks.
func _merge_down(runs: Array[Rect2], rect: Rect2) -> void:
	for i in runs.size():
		var r := runs[i]
		if is_equal_approx(r.position.x, rect.position.x) and is_equal_approx(r.size.x, rect.size.x) \
				and is_equal_approx(r.end.y, rect.position.y):
			runs[i] = r.merge(rect)
			return
	runs.append(rect)


func _add_body(rect: Rect2, layer: int) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = rect.size
	shape.shape = box
	shape.position = rect.get_center()
	body.add_child(shape)
	level.add_child(body)
	return body


## Missions and the finale are dungeons: darker stone, wall shadows, torches.
func _is_dungeon() -> bool:
	return data.kind == WorldData.Kind.MISSION or data.kind == WorldData.Kind.FINALE


func _floor_color() -> Color:
	return data.style.paper_color.lerp(data.style.backdrop_color, 0.35)


func _draw_floor(art: Node2D) -> void:
	var s := data.style
	var ts := float(data.tile_size)
	var base := _floor_color()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(data.id)
	for y in _grid.size():
		for x in _grid[y].length():
			var c := _grid[y][x]
			if c == " " or c == "#":
				continue
			var r := Rect2(x * ts, y * ts, ts, ts)
			art.draw_rect(r, base.darkened(0.015) if (x + y) % 2 == 0 else base)
			_draw_floor_pattern(art, r, rng)
			if c == "D":
				art.draw_rect(r.grow(-6), s.ground_color.lerp(base, 0.6))
	# Dungeons: walls cast flat ink shadows onto the floor, and torches pool warm
	# light below them. Flat shapes (not gradients) so the comic shader keeps
	# them crisp.
	if _is_dungeon():
		var shade := base.lerp(s.ink_color, 0.22)  # opaque: alpha blends posterize into odd tints
		for y in _grid.size():
			for x in _grid[y].length():
				if not _is_floor(Vector2i(x, y)) and _grid[y][x] != "D":
					continue
				var r := Rect2(x * ts, y * ts, ts, ts)
				if _char(Vector2i(x, y - 1)) == "#":
					art.draw_rect(Rect2(r.position, Vector2(ts, 22)), shade)
				if _char(Vector2i(x - 1, y)) == "#":
					art.draw_rect(Rect2(r.position, Vector2(12, ts)), shade)
				if _char(Vector2i(x + 1, y)) == "#":
					art.draw_rect(Rect2(r.position + Vector2(ts - 12, 0), Vector2(12, ts)), shade)
		for t in torches:
			art.draw_circle(t + Vector2(0, 76), 80.0, base.lerp(Color(1.0, 0.82, 0.45), 0.22))
			art.draw_circle(t + Vector2(0, 66), 46.0, base.lerp(Color(1.0, 0.88, 0.55), 0.4))
	# Ink lines where floor meets the void or a wall's foot.
	for y in _grid.size():
		for x in _grid[y].length():
			if _grid[y][x] == "#" and _is_floor(Vector2i(x, y - 1)):
				art.draw_rect(Rect2(x * ts, y * ts - 10, ts, 10), Color(s.ink_color, 0.25))


## Per-style floor texture: tatami, boards, cobbles, Ben-Day dots, flagstones, cracks.
## Kept faint on purpose: the comic shader's ink-outline pass turns any strong
## edge into a heavy black line.
func _draw_floor_pattern(art: Node2D, r: Rect2, rng: RandomNumberGenerator) -> void:
	var s := data.style
	var ink := Color(s.ink_color, 0.06)
	match s.backdrop:
		ComicStyle.BackdropKind.TEMPLE:
			art.draw_rect(r.grow(-3), ink, false, 2.0)
			art.draw_line(r.position + Vector2(r.size.x * 0.5, 4), r.position + Vector2(r.size.x * 0.5, r.size.y - 4), ink, 1.5)
		ComicStyle.BackdropKind.WAVES:
			for i in 3:
				var yy := r.position.y + (i + 1) * r.size.y / 4.0
				art.draw_line(Vector2(r.position.x, yy), Vector2(r.end.x, yy), ink, 2.0)
		ComicStyle.BackdropKind.CITY:
			art.draw_rect(Rect2(r.position + Vector2(4, 4), r.size * 0.5 - Vector2(6, 6)), ink, false, 2.0)
			art.draw_rect(Rect2(r.position + r.size * 0.5 + Vector2(2, 2), r.size * 0.5 - Vector2(6, 6)), ink, false, 2.0)
		ComicStyle.BackdropKind.POP:
			for dy in range(8, int(r.size.y), 16):
				for dx in range(8, int(r.size.x), 16):
					art.draw_circle(r.position + Vector2(dx, dy), 2.5, Color(s.accent_color, 0.07))
		ComicStyle.BackdropKind.VIHARA:
			art.draw_rect(r.grow(-2), Color(s.accent_color, 0.08), false, 2.0)
		ComicStyle.BackdropKind.SHATTERED:
			if rng.randf() < 0.3:
				var a := r.position + Vector2(rng.randf_range(8, 56), rng.randf_range(8, 56))
				art.draw_line(a, a + Vector2(rng.randf_range(-30, 30), rng.randf_range(-30, 30)), Color(s.accent_color, 0.25), 2.0)
	if rng.randf() < 0.03:
		# A stray ink blot / tuft so the floor doesn't read as a spreadsheet.
		art.draw_circle(r.get_center() + Vector2(rng.randf_range(-20, 20), rng.randf_range(-20, 20)), rng.randf_range(3, 6), Color(s.ink_color, 0.12))


## Draws row `y`'s walls (and gates) relative to the row's bottom edge.
func _draw_wall_row(art: Node2D, y: int) -> void:
	var s := data.style
	var ts := float(data.tile_size)
	var top := s.ground_color.lightened(0.18)
	var face := s.ground_color.darkened(0.25)
	if _is_dungeon():
		# Heavier, darker stone with mortar lines on the face.
		top = s.ground_color.lerp(s.ink_color, 0.25)
		face = s.ground_color.lerp(s.ink_color, 0.55)
	for x in _grid[y].length():
		var c := _grid[y][x]
		var px := x * ts
		if c == "#":
			var below_open := _char(Vector2i(x, y + 1)) != "#"
			if below_open:
				var fr := Rect2(px, -WALL_RISE, ts, WALL_RISE)
				art.draw_rect(fr, face)
				art.draw_line(Vector2(px, -WALL_RISE * 0.5), Vector2(px + ts, -WALL_RISE * 0.5), Color(s.ink_color, 0.3), 2.0)
				art.draw_rect(fr, s.ink_color, false, 3.0)
			var tr := Rect2(px, -ts - WALL_RISE, ts, ts)
			art.draw_rect(tr, top)
			# Ink only on edges that face open space, so walls read as one mass.
			if _char(Vector2i(x, y - 1)) != "#":
				art.draw_line(tr.position, tr.position + Vector2(ts, 0), s.ink_color, 4.0)
			if _char(Vector2i(x - 1, y)) != "#":
				art.draw_line(tr.position, Vector2(px, 0 if below_open else -WALL_RISE), s.ink_color, 4.0)
			if _char(Vector2i(x + 1, y)) != "#":
				art.draw_line(tr.position + Vector2(ts, 0), Vector2(px + ts, 0 if below_open else -WALL_RISE), s.ink_color, 4.0)
			if below_open:
				art.draw_line(Vector2(px, -WALL_RISE), Vector2(px + ts, -WALL_RISE), s.ink_color, 3.0)
				if torches.has(_torch_pos(x, y)):
					_draw_torch(art, Vector2(px + ts * 0.5, -WALL_RISE * 0.55))
		elif c == "D" and is_gate_closed(Vector2i(x, y)):
			# Sealed gate: red-lacquered bars rising from the floor.
			var bar_col := s.accent_color
			for i in 4:
				var bx := px + 8.0 + i * (ts - 16.0) / 3.0
				art.draw_line(Vector2(bx, -4), Vector2(bx, -ts - 10), s.ink_color, 10.0)
				art.draw_line(Vector2(bx, -4), Vector2(bx, -ts - 10), bar_col, 5.0)
			art.draw_line(Vector2(px + 4, -ts * 0.6), Vector2(px + ts - 4, -ts * 0.6), s.ink_color, 8.0)


# --- Torches & light ------------------------------------------------------------

func _torch_pos(x: int, y: int) -> Vector2:
	var ts := float(data.tile_size)
	return Vector2(x * ts + ts * 0.5, (y + 1) * ts - WALL_RISE * 0.55)


## Torches on wall faces that look into rooms (not corridors), evenly spaced.
func _place_torches() -> void:
	for y in _grid.size():
		var run := 0
		for x in _grid[y].length():
			var below := Vector2i(x, y + 1)
			# Outer walls only (void behind them), never pillars.
			var faces_room := _grid[y][x] == "#" and _char(Vector2i(x, y - 1)) == " " \
				and _room_of.has(below) and rooms[int(_room_of[below])].tiles.size() > 30
			run = run + 1 if faces_room else 0
			if faces_room and run % TORCH_SPACING == 2:
				torches.append(_torch_pos(x, y))


func _draw_torch(art: Node2D, p: Vector2) -> void:
	art.draw_line(p + Vector2(0, 10), p + Vector2(0, -4), ComicTheme.INK, 6.0)
	art.draw_line(p + Vector2(0, 10), p + Vector2(0, -4), Color(0.45, 0.28, 0.15), 3.0)
	var flame := PackedVector2Array([p + Vector2(-6, -4), p + Vector2(0, -20), p + Vector2(6, -4)])
	art.draw_colored_polygon(flame, Color(1.0, 0.6, 0.15))
	art.draw_colored_polygon(PackedVector2Array([p + Vector2(-3, -4), p + Vector2(0, -13), p + Vector2(3, -4)]), Color(1.0, 0.92, 0.5))
	flame.append(flame[0])
	art.draw_polyline(flame, ComicTheme.INK, 2.0)


func _spawn_entity(ch: String, pos: Vector2, tile: Vector2i) -> void:
	match ch:
		"S":
			spawn_point = pos
		"E", "A", "F", "H", "U", "R", "T":
			var id: Variant = _room_of.get(tile)
			spawn_enemy(WorldData.ENEMY_LETTERS[ch], pos, int(id) if id != null else -1)
		"B":
			_spawn_boss(pos, tile)
		"N":
			if _npc_index < data.npcs.size():
				var d: Dictionary = data.npcs[_npc_index]
				_spawn_npc(str(d.get("name", "Stranger")), str(d.get("dialogue", "")), d.get("look", {}), pos)
			_npc_index += 1
		"$":
			var sk := data.shopkeeper
			_spawn_npc(str(sk.get("name", "Merchant")), str(sk.get("dialogue", "shop_generic")), sk.get("look", {}), pos)
		"K":
			var shrine: Interactable = KEY_SHRINE.new()
			shrine.set("world_id", data.id)
			shrine.position = pos
			entities.add_child(shrine)
		"P":
			_spawn_portal(pos)
		"C":
			var chest: Interactable = CHEST.new()
			chest.set("world_id", data.id)
			chest.set("drop_table", data.drop_table)
			chest.position = pos
			entities.add_child(chest)
			chests.append(chest)
		"q":
			if _quest_item_index < data.quest_items.size():
				var qi: Interactable = QUEST_ITEM.new()
				qi.set("info", data.quest_items[_quest_item_index])
				qi.position = pos
				entities.add_child(qi)
			_quest_item_index += 1
		"o":
			var pot: StaticBody2D = BREAKABLE.new()
			pot.position = pos
			entities.add_child(pot)
		"c":
			var coin: Area2D = COIN.new()
			coin.set("value", 3)
			coin.position = pos
			entities.add_child(coin)


## Builds one enemy of `kind` from this world's stats and looks and registers it
## with room `room_id` (slimes call this to split mid-fight).
func spawn_enemy(kind: String, pos: Vector2, room_id: int, elite: bool = false, mini: bool = false,
		look: Dictionary = {}, form: String = "") -> Enemy:
	var e: Enemy = ENEMY_SCENE.instantiate()
	if form != "":
		_swap_figure(e, form)
	var variant: Dictionary = data.enemy_variants.get(kind, {})
	e.display_name = str(variant.get("name", data.enemy_name if kind == "chaser" else "%s %s" % [data.enemy_name, kind.capitalize()]))
	e.max_health = data.enemy_health
	e.contact_damage = data.enemy_damage
	e.gold_range = data.gold_per_enemy
	e.drop_table = data.drop_table
	e.weapon_drop_chance = data.weapon_drop_chance
	e.world_id = data.id
	e.position = pos
	e.configure(kind, elite, mini)
	entities.add_child(e)
	e.apply_looks(data.enemy_look, look if not look.is_empty() else variant.get("look", {}))
	if room_id >= 0 and room_id < rooms.size():
		e.room_id = room_id
		rooms[room_id].enemies.append(e)
		e.aggro = player != null and player_room() == rooms[room_id]
	return e


## Some combat rooms get an elite: one random non-turret enemy, promoted.
func _promote_elites() -> void:
	if data.kind != WorldData.Kind.MISSION:
		return
	for room in rooms:
		if room.has_boss or room.enemies.is_empty() or randf() >= data.elite_chance:
			continue
		var pick: Enemy = room.enemies.pick_random()
		var pos := pick.position
		var kind := pick.archetype
		room.enemies.erase(pick)
		pick.free()
		spawn_enemy(kind, pos, room.id, true)


func _add_to_room(e: Enemy, tile: Vector2i) -> void:
	var id: Variant = _room_of.get(tile)
	if id == null:
		return
	e.room_id = int(id)
	rooms[e.room_id].enemies.append(e)


func _spawn_npc(npc_name: String, dialogue: String, look: Dictionary, pos: Vector2) -> void:
	var npc := NPC.new()
	npc.npc_name = npc_name
	npc.dialogue_id = dialogue
	npc.look = look
	npc.position = pos
	entities.add_child(npc)


func _spawn_boss(pos: Vector2, tile: Vector2i) -> void:
	if data.boss_name == "" or GameState.has_flag("boss_defeated_" + data.id):
		return
	var b: Boss = BOSS_SCENE.instantiate()
	if BOSS_FORMS.has(data.boss_form):
		b.set_script(BOSS_FORMS[data.boss_form])
		_swap_figure(b, data.boss_form)
		b.speed = 70.0
		b.chase_speed = 160.0
		b.hit_radius = 80.0
		b.figure_scale = 1.2
	else:
		b.figure_scale = 1.3
	b.display_name = data.boss_name
	b.max_health = data.boss_health
	b.contact_damage = data.boss_damage
	b.intro_dialogue = data.boss_intro_dialogue
	b.defeat_dialogue = data.boss_defeat_dialogue
	b.power_id = data.boss_power
	b.hope_on_kill = data.boss_hope_on_kill
	b.is_oni = data.boss_is_oni
	b.drop_table = data.drop_table
	b.world_id = data.id
	b.position = pos
	entities.add_child(b)
	b.figure.apply_look(data.boss_look)
	b.figure.scale = Vector2.ONE * b.figure_scale
	b.defeated.connect(_on_boss_defeated)
	_add_to_room(b, tile)
	if b.room_id >= 0:
		rooms[b.room_id].has_boss = true


## Replaces a not-yet-added body's ComicFigure with a MonsterFigure of `form`.
func _swap_figure(body: Node, form: String) -> void:
	var old := body.get_node("Figure")
	var mf := MonsterFigure.new()
	mf.form = form
	mf.name = "Figure"
	body.remove_child(old)
	old.free()
	body.add_child(mf)


func _spawn_portal(pos: Vector2) -> void:
	# The monk's gate always opens onto the next world he wants harvested;
	# once every world is done, it stays shut.
	var next := GameState.next_mission_id()
	if data.kind == WorldData.Kind.HUB and next == "":
		return
	var p := Portal.new()
	p.position = pos
	match data.kind:
		WorldData.Kind.HUB:
			p.target_world = next
			p.prompt = "Enter the next page"
			p.requires_flag = "monk_briefed"
			p.flag_hint = "Speak with the Master first."
		_:
			p.target_world = data.portal_target
			if data.portal_requires_key:
				p.requires_key = data.id
			if data.portal_requires_boss and data.boss_name != "":
				p.requires_flag = "boss_defeated_" + data.id
			elif data.portal_requires_flag != "":
				p.requires_flag = data.portal_requires_flag
				p.flag_hint = "Something here is still waiting for you."
			if data.kind == WorldData.Kind.MISSION:
				p.on_enter = func() -> void:
					GameState.complete_world(data.id)
					SceneRouter.go_to_world(data.portal_target, "AND SO, THE SAMURAI RETURNED...")
	entities.add_child(p)


# --- Events -------------------------------------------------------------------

func _on_player_died() -> void:
	if _cutscene_death:
		return
	shake(14.0)
	comic_filter.flash(0.5, 0.4)
	hud.show_toast("YOU FELL...  (-20% gold, hope -3)", Color(0.8, 0.4, 0.4))
	await get_tree().create_timer(1.4).timeout
	_abandon_rooms()
	GameState.add_gold(-roundi(GameState.gold * 0.2))
	GameState.change_hope(-3.0, "fell")
	GameState.full_heal()
	player.revive(spawn_point)


func _on_boss_defeated(_boss: Enemy) -> void:
	if data.kind == WorldData.Kind.FINALE:
		GameState.act = GameState.Act.ENDING
		GameState.save_game()
		SceneRouter.go_to_scene(ENDING_SCENE, "THE LAST PAGE")


func _on_dialogue_action(action: String, arg: String) -> void:
	match action:
		"open_shop":
			shop_ui.open(str(data.shopkeeper.get("name", "Shop")), data.shop_stock)
		"reveal_branch":
			_reveal_branch()
		"heal":
			GameState.full_heal()
		"flash":
			comic_filter.flash(0.8, 0.5)
			shake(10.0)
		"ending":
			SceneRouter.go_to_scene(ENDING_SCENE, arg if arg != "" else "THE LAST PAGE")
		_:
			push_warning("Unhandled dialogue action: %s:%s" % [action, arg])


## After the third world, the mask slips. If the samurai's light is nearly gone
## (hope < 10%), the monk cuts him down and the other side must save him;
## otherwise he sees the truth in time and flees.
func _reveal_branch() -> void:
	GameState.set_flag("monk_revealed")
	GameState.act = GameState.Act.REVEAL
	if GameState.hope < GameState.HOPE_DEATH_THRESHOLD:
		await _struck_down_by_master()
	else:
		GameState.set_flag("escaped_by_choice")
		await DialogueManager.play("reveal_escape")
		SceneRouter.go_to_world("vihara", "THE SAMURAI RAN UNTIL THE INK RAN OUT...")


func _struck_down_by_master() -> void:
	_cutscene_death = true
	GameState.push_ui_lock()
	await get_tree().create_timer(0.4).timeout
	comic_filter.flash(1.0, 0.6)
	shake(20.0)
	SfxWord.spawn(entities, player.global_position + Vector2(0, -80), "SHHNK!", Color(0.9, 0.1, 0.1), 64)
	player.die()
	await get_tree().create_timer(1.2).timeout
	GameState.pop_ui_lock()
	await DialogueManager.play("reveal_death")
	GameState.set_flag("saved_by_light")
	GameState.full_heal()
	SceneRouter.go_to_world("vihara", "...BUT ANOTHER LIGHT REFUSED TO LET HIM GO.")
