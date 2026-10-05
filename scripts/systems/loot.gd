class_name Loot
extends RefCounted
## Drop rolls. Gold and weapon chances scale with hope via GameState multipliers.
## Weapons drop as rolled instances (rarity + affixes, see Weapons).

const COIN_SCRIPT := preload("res://scripts/pickups/coin.gd")
const WEAPON_PICKUP_SCRIPT := preload("res://scripts/pickups/weapon_pickup.gd")
const POTION_SCRIPT := preload("res://scripts/pickups/potion.gd")
const POTION_DROP_CHANCE := 0.07


## `rarity_bonus` > 0 (elites, chests) guarantees a weapon and bumps its rarity.
static func drop_for_enemy(parent: Node, pos: Vector2, gold_range: Vector2i, table: PackedStringArray, world_id: String,
		weapon_chance: float, rarity_bonus: int = 0) -> void:
	if not is_instance_valid(parent):
		return
	var gold := roundi(randi_range(gold_range.x, gold_range.y) * GameState.get_gold_multiplier())
	if gold > 0:
		spawn_coin(parent, pos, gold)
	if rarity_bonus > 0 or randf() < weapon_chance * GameState.get_weapon_drop_multiplier():
		var inst := roll_weapon(table, world_id, rarity_bonus)
		if not inst.is_empty():
			spawn_weapon(parent, pos + Vector2(randf_range(-30, 30), randf_range(-10, 10)), inst)
	if randf() < POTION_DROP_CHANCE * (0.7 + GameState.get_luck() * 0.5):
		spawn_potion(parent, pos + Vector2(randf_range(-24, 24), 8))


static func roll_weapon(table: PackedStringArray, world_id: String, rarity_bonus: int = 0) -> Dictionary:
	var id := Database.roll_weapon(table, world_id, GameState.get_luck())
	return Weapons.roll(id, GameState.get_luck(), rarity_bonus) if id != "" else {}


static func spawn_coin(parent: Node, pos: Vector2, value: int) -> void:
	var coin: Area2D = COIN_SCRIPT.new()
	coin.value = value
	coin.position = pos
	_attach.call_deferred(parent, coin)


static func spawn_weapon(parent: Node, pos: Vector2, inst: Dictionary) -> void:
	var pickup: Area2D = WEAPON_PICKUP_SCRIPT.new()
	pickup.item = inst
	pickup.position = pos + Vector2(0, 20)
	_attach.call_deferred(parent, pickup)


static func spawn_potion(parent: Node, pos: Vector2) -> void:
	var potion: Area2D = POTION_SCRIPT.new()
	potion.position = pos
	_attach.call_deferred(parent, potion)


## Deferred because drops are spawned from physics callbacks; frees the node if
## the level was unloaded in the meantime so it doesn't leak.
static func _attach(parent: Node, node: Node) -> void:
	if is_instance_valid(parent) and parent.is_inside_tree():
		parent.add_child(node)
	else:
		node.free()
