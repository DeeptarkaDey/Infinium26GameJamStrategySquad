class_name Weapons
extends RefCounted
## Weapon instances, Labyrinth Legend style: the same base weapon drops in many
## variations. An instance is a plain Dictionary (so it saves as JSON):
##   {"uid": int, "base": "wave_cutter", "rarity": 2, "affixes": [{"id": "keen", "v": 0.18}, ...]}
## Rarity sets the number of affixes (common 0 ... legendary 3).

## v is rolled uniformly in [min, max]. "element" affixes carry no number.
const AFFIXES := {
	"keen": {"prefix": "Keen", "suffix": "of Edges", "min": 0.12, "max": 0.3, "line": "+%d%% damage"},
	"swift": {"prefix": "Swift", "suffix": "of Haste", "min": 0.08, "max": 0.2, "line": "%d%% faster attacks"},
	"long": {"prefix": "Long", "suffix": "of Reach", "min": 0.15, "max": 0.3, "line": "+%d%% reach"},
	"heavy": {"prefix": "Heavy", "suffix": "of Force", "min": 0.3, "max": 0.7, "line": "+%d%% knockback"},
	"lucky": {"prefix": "Lucky", "suffix": "of Fortune", "min": 0.04, "max": 0.1, "line": "+%d%% crit chance"},
	"vampiric": {"prefix": "Vampiric", "suffix": "of Thirst", "min": 0.03, "max": 0.07, "line": "Heals %d%% of damage dealt"},
	"stalwart": {"prefix": "Stalwart", "suffix": "of the Ox", "min": 10.0, "max": 25.0, "line": "+%d max HP"},
	"burning": {"prefix": "Burning", "suffix": "of Embers", "element": "fire", "line": "Hits burn"},
	"freezing": {"prefix": "Freezing", "suffix": "of Frost", "element": "frost", "line": "Hits chill and freeze"},
	"shocking": {"prefix": "Shocking", "suffix": "of Storms", "element": "shock", "line": "Hits arc to nearby foes"},
	"venomous": {"prefix": "Venomous", "suffix": "of Venom", "element": "poison", "line": "Hits poison (stacks)"},
}
const ELEMENT_AFFIXES := ["burning", "freezing", "shocking", "venomous"]
## Rarity roll weights before luck: common, uncommon, rare, legendary.
const RARITY_WEIGHTS := [62.0, 27.0, 9.0, 2.0]


static func make(base_id: String, rarity: int = -1, affixes: Array = []) -> Dictionary:
	var base := Database.get_weapon(base_id)
	if not base:
		return {}
	if rarity < 0:
		rarity = base.rarity
	return {"uid": GameState.next_uid(), "base": base_id, "rarity": maxi(rarity, base.rarity), "affixes": affixes}


## A random instance of `base_id`: rarity rolled with luck (plus `bonus` tiers,
## e.g. elites and chests), then one affix per rarity tier.
static func roll(base_id: String, luck: float, bonus: int = 0) -> Dictionary:
	var base := Database.get_weapon(base_id)
	if not base:
		return {}
	var weights: Array[float] = []
	for i in RARITY_WEIGHTS.size():
		weights.append(RARITY_WEIGHTS[i] * (1.0 + luck * i * 0.6))
	var rarity := _pick_index(weights)
	rarity = clampi(maxi(rarity + bonus, base.rarity), 0, 3)
	return make(base_id, rarity, roll_affixes(base, rarity))


static func roll_affixes(base: WeaponData, count: int) -> Array:
	var pool: Array = AFFIXES.keys()
	if base.element != "":
		pool = pool.filter(func(a: String) -> bool: return not ELEMENT_AFFIXES.has(a))
	pool.shuffle()
	var out: Array = []
	var has_element := false
	for id: String in pool:
		if out.size() >= count:
			break
		var a: Dictionary = AFFIXES[id]
		if a.has("element"):
			if has_element:
				continue
			has_element = true
			out.append({"id": id, "v": 0.0})
		else:
			out.append({"id": id, "v": snappedf(randf_range(a.min, a.max), 0.01)})
	return out


## A deterministic instance for a shop shelf, so a stall's stock doesn't
## reshuffle every time it's opened.
static func shop_item(base_id: String, seed_text: String) -> Dictionary:
	var base := Database.get_weapon(base_id)
	if not base:
		return {}
	seed(hash(seed_text + base_id))
	var affixes := roll_affixes(base, base.rarity)
	randomize()
	return make(base_id, base.rarity, affixes)


## The runtime WeaponData for an instance: a copy of the base with affixes applied.
static func build(inst: Dictionary) -> WeaponData:
	var base := Database.get_weapon(str(inst.get("base", "")))
	if not base:
		base = Database.get_weapon(GameState.STARTING_WEAPON)
	var w: WeaponData = base.duplicate()
	w.uid = int(inst.get("uid", 0))
	w.rarity = int(inst.get("rarity", base.rarity)) as WeaponData.Rarity
	w.affix_lines = []
	if base.element != "":
		w.affix_lines.append("Innate %s" % Skills.ELEMENTS[base.element].name.to_lower())
	var affixes: Array = inst.get("affixes", [])
	for a: Dictionary in affixes:
		var id := str(a.get("id", ""))
		if not AFFIXES.has(id):
			continue
		var def: Dictionary = AFFIXES[id]
		var v := float(a.get("v", 0.0))
		match id:
			"keen": w.damage *= 1.0 + v
			"swift": w.attack_cooldown *= 1.0 - v
			"long": w.reach *= 1.0 + v
			"heavy": w.knockback *= 1.0 + v
			"lucky": w.crit_bonus += v
			"vampiric": w.lifesteal += v
			"stalwart": w.max_health_bonus += v
		if def.has("element"):
			w.element = str(def.element)
			w.affix_lines.append(str(def.line))
		elif id == "stalwart":
			w.affix_lines.append(str(def.line) % roundi(v))
		else:
			w.affix_lines.append(str(def.line) % roundi(v * 100.0))
	w.display_name = display_name(inst)
	return w


## "Burning Wave Cutter of Haste": first affix as prefix, second as suffix.
static func display_name(inst: Dictionary) -> String:
	var base := Database.get_weapon(str(inst.get("base", "")))
	var name := base.display_name if base else "Weapon"
	var affixes: Array = inst.get("affixes", [])
	if affixes.size() >= 1 and AFFIXES.has(str(affixes[0].id)):
		name = "%s %s" % [AFFIXES[str(affixes[0].id)].prefix, name]
	if affixes.size() >= 2 and AFFIXES.has(str(affixes[1].id)):
		name = "%s %s" % [name, AFFIXES[str(affixes[1].id)].suffix]
	return name


## Gold for salvaging an instance: a third of its worth, more for more affixes.
static func salvage_value(inst: Dictionary) -> int:
	var base := Database.get_weapon(str(inst.get("base", "")))
	if not base:
		return 0
	var worth := float(maxi(base.price, 40)) * (1.0 + 0.4 * (inst.get("affixes", []) as Array).size())
	return maxi(5, roundi(worth * 0.3))


static func _pick_index(weights: Array[float]) -> int:
	var total := 0.0
	for w in weights:
		total += w
	var r := randf() * total
	for i in weights.size():
		r -= weights[i]
		if r <= 0.0:
			return i
	return weights.size() - 1
