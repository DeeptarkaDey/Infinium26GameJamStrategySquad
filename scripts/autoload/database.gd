extends Node
## Loads every WeaponData / PowerData / WorldData resource from data/ at startup.
## Autoloaded as `Database`.

const WEAPON_DIR := "res://data/weapons/"
const POWER_DIR := "res://data/powers/"
const WORLD_DIR := "res://data/worlds/"

var weapons: Dictionary = {}  # id -> WeaponData
var powers: Dictionary = {}   # id -> PowerData
var worlds: Dictionary = {}   # id -> WorldData
var mission_order: Array[String] = []


func _ready() -> void:
	for res in _load_dir(WEAPON_DIR):
		if res is WeaponData:
			weapons[res.id] = res
	for res in _load_dir(POWER_DIR):
		if res is PowerData:
			powers[res.id] = res
	var missions: Array[WorldData] = []
	for res in _load_dir(WORLD_DIR):
		if res is WorldData:
			worlds[res.id] = res
			if res.kind == WorldData.Kind.MISSION:
				missions.append(res)
	missions.sort_custom(func(a: WorldData, b: WorldData) -> bool: return a.mission_index < b.mission_index)
	for w in missions:
		mission_order.append(w.id)


func _load_dir(dir: String) -> Array:
	var out := []
	for file in ResourceLoader.list_directory(dir):
		if file.ends_with(".tres") or file.ends_with(".res"):
			var res := load(dir + file)
			if res:
				out.append(res)
	return out


func get_weapon(id: String) -> WeaponData:
	return weapons.get(id)


func get_power(id: String) -> PowerData:
	return powers.get(id)


func get_world(id: String) -> WorldData:
	return worlds.get(id)


## Picks a weapon id from `table` (or every weapon tagged for `world_id`), weighting
## rarer weapons up as luck (driven by hope) increases.
func roll_weapon(table: PackedStringArray, world_id: String, luck: float) -> String:
	var candidates: Array[WeaponData] = []
	if table.is_empty():
		for w: WeaponData in weapons.values():
			if w.world_tags.is_empty() or w.world_tags.has(world_id):
				candidates.append(w)
	else:
		for id in table:
			if weapons.has(id):
				candidates.append(weapons[id])
	if candidates.is_empty():
		return ""
	var total := 0.0
	var weights: Array[float] = []
	for w in candidates:
		var weight := w.drop_weight * _rarity_weight(w.rarity, luck)
		weights.append(weight)
		total += weight
	var roll := randf() * total
	for i in candidates.size():
		roll -= weights[i]
		if roll <= 0.0:
			return candidates[i].id
	return candidates.back().id


func _rarity_weight(r: WeaponData.Rarity, luck: float) -> float:
	match r:
		WeaponData.Rarity.UNCOMMON: return 0.45 + luck * 0.5
		WeaponData.Rarity.RARE: return 0.1 + luck * 0.45
		WeaponData.Rarity.LEGENDARY: return 0.01 + luck * 0.2
	return 1.0
