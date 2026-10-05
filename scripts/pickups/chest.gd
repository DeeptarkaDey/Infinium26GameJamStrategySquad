extends Interactable
## A treasure chest tucked in a side room. Opens once: a weapon one rarity tier
## better than a normal drop, a pile of gold, and often a potion.

var world_id := ""
var drop_table: PackedStringArray = []
var opened := false


func _ready() -> void:
	prompt = "Open chest"
	trigger_size = Vector2(70, 60)
	super._ready()


func can_interact() -> bool:
	return not opened


func interact(_player: Player) -> void:
	opened = true
	Sfx.play("chest")
	SfxWord.spawn(get_parent(), global_position + Vector2(0, -70), "KA-CHUNK!", Color(1.0, 0.85, 0.3), 30)
	var parent := get_parent()
	var inst := Loot.roll_weapon(drop_table, world_id, 1)
	if not inst.is_empty():
		Loot.spawn_weapon(parent, global_position + Vector2(0, 30), inst)
	Loot.spawn_coin(parent, global_position + Vector2(-26, 20), roundi(randi_range(15, 35) * GameState.get_gold_multiplier()))
	if randf() < 0.5:
		Loot.spawn_potion(parent, global_position + Vector2(28, 24))
	queue_redraw()


func _draw() -> void:
	var wood := Color(0.55, 0.32, 0.16)
	var band := Color(0.9, 0.72, 0.25)
	var body := Rect2(-24, -30, 48, 30)
	draw_rect(body, wood)
	draw_rect(body, ComicTheme.INK, false, 3.0)
	if opened:
		draw_rect(Rect2(-24, -46, 48, 14), wood.darkened(0.3))
		draw_rect(Rect2(-24, -46, 48, 14), ComicTheme.INK, false, 3.0)
		draw_rect(Rect2(-18, -30, 36, 8), Color(0.12, 0.08, 0.06))
	else:
		var lid := Rect2(-26, -42, 52, 14)
		draw_rect(lid, wood.lightened(0.1))
		draw_rect(lid, ComicTheme.INK, false, 3.0)
		draw_rect(Rect2(-5, -34, 10, 12), band)
		draw_rect(Rect2(-5, -34, 10, 12), ComicTheme.INK, false, 2.0)
	for x in [-16.0, 12.0]:
		draw_rect(Rect2(x, -30, 4, 30), band)
