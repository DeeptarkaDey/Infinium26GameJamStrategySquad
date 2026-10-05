extends Node
## Global run state: hope meter, health, gold, keys, powers, weapons, story flags.
## Autoloaded as `GameState`. Hope (0-100) is the player's inner light; it scales
## damage, luck, drops, prices and gates some dialogue choices.

signal hope_changed(value: float, delta: float, reason: String)
signal health_changed(current: float, maximum: float)
signal gold_changed(value: int)
signal keys_changed
signal powers_changed
signal weapon_changed(weapon: WeaponData)
signal flag_changed(flag: String, value: Variant)
signal toast(text: String, color: Color)
signal boss_engaged(boss: Node)
signal build_changed
signal inventory_changed
signal potions_changed(count: int)

enum Act { PROLOGUE, MISSIONS, REVEAL, VIHARA, FINALE, ENDING }

const HOPE_MAX := 100.0
const HOPE_START := 60.0
## Below this at the reveal, the monk kills you and the light side saves you.
const HOPE_DEATH_THRESHOLD := 10.0
const SAVE_PATH := "user://mirage_save.json"
const STARTING_WEAPON := "rusted_katana"
const BAG_SIZE := 20
const POTION_MAX := 5
const POTION_START := 2
const POTION_HEAL := 0.4  ## share of max HP
const POTION_PRICE := 20

var hope: float = HOPE_START
var gold: int = 0
var base_max_health: float = 100.0
var health: float = 100.0
var keys: Array[String] = []
var powers: Array[String] = []
## The bag: weapon instances (see Weapons), at most BAG_SIZE. The equipped one is kept apart.
var inventory: Array[Dictionary] = []
var equipped: Dictionary = {}
var potions: int = POTION_START
var _uid: int = 0
var _weapon_cache: WeaponData
var worlds_completed: Array[String] = []
var flags: Dictionary = {}
var current_world_id: String = "sanctum"
var act: Act = Act.PROLOGUE
## Roguelike build for the current mission (see Skills): {skill_id: level}, {slot: element}.
var run_skills: Dictionary = {}
var run_elements: Dictionary = {}

var _ui_locks: int = 0


func _ready() -> void:
	_ensure_input_actions()
	reset()


func reset() -> void:
	hope = HOPE_START
	gold = 0
	keys.clear()
	powers.clear()
	inventory.clear()
	_uid = 0
	equipped = Weapons.make(STARTING_WEAPON)
	_weapon_cache = null
	potions = POTION_START
	worlds_completed.clear()
	flags.clear()
	current_world_id = "sanctum"
	act = Act.PROLOGUE
	run_skills = {}
	run_elements = {}
	health = get_max_health()
	_ui_locks = 0


# --- Hope & multipliers -------------------------------------------------------

func change_hope(delta: float, reason: String = "") -> void:
	if is_zero_approx(delta):
		return
	var old: float = hope
	hope = clampf(hope + delta, 0.0, HOPE_MAX)
	hope_changed.emit(hope, hope - old, reason)


func hope_ratio() -> float:
	return hope / HOPE_MAX


func hope_tier() -> String:
	if hope < HOPE_DEATH_THRESHOLD: return "Extinguished"
	if hope < 35.0: return "Flickering"
	if hope < 70.0: return "Steady"
	return "Radiant"


func get_damage_multiplier() -> float:
	return (0.8 + 0.4 * hope_ratio()) * (1.0 + get_stat("damage_mult"))


func get_incoming_damage_multiplier() -> float:
	return 1.2 - 0.35 * hope_ratio()


func get_luck() -> float:
	return clampf(hope_ratio() + get_stat("luck"), 0.0, 1.5)


func get_crit_chance() -> float:
	return 0.03 + 0.12 * get_luck() + get_weapon().crit_bonus


func get_gold_multiplier() -> float:
	return 0.6 + 0.8 * hope_ratio()


func get_weapon_drop_multiplier() -> float:
	return 0.5 + get_luck()


func get_price_multiplier() -> float:
	return 1.4 - 0.5 * hope_ratio()


func get_shop_price(weapon: WeaponData) -> int:
	return maxi(1, roundi(weapon.price * get_price_multiplier()))


# --- Health -------------------------------------------------------------------

func get_max_health() -> float:
	return base_max_health + get_stat("max_health") + get_weapon().max_health_bonus


func damage_player(amount: float) -> float:
	var dealt := amount * get_incoming_damage_multiplier()
	health = maxf(0.0, health - dealt)
	health_changed.emit(health, get_max_health())
	return dealt


func heal_player(amount: float) -> void:
	health = minf(get_max_health(), health + amount)
	health_changed.emit(health, get_max_health())


func full_heal() -> void:
	heal_player(get_max_health())


# --- Gold / weapons -----------------------------------------------------------

func add_gold(amount: int) -> void:
	gold = maxi(0, gold + amount)
	gold_changed.emit(gold)


func spend_gold(amount: int) -> bool:
	if gold < amount:
		return false
	add_gold(-amount)
	return true


func get_weapon() -> WeaponData:
	if not _weapon_cache or _weapon_cache.uid != int(equipped.get("uid", -1)):
		_weapon_cache = Weapons.build(equipped)
	return _weapon_cache


func next_uid() -> int:
	_uid += 1
	return _uid


## Gives a plain (affix-free) copy of a base weapon, e.g. from dialogue.
func give_weapon(id: String, equip: bool = true) -> void:
	var inst := Weapons.make(id)
	if inst.is_empty():
		push_warning("Unknown weapon id: %s" % id)
		return
	if equip:
		_swap_equipped(inst)
	elif not add_to_bag(inst):
		toast.emit("BAG FULL", Color(0.9, 0.5, 0.5))


func bag_full() -> bool:
	return inventory.size() >= BAG_SIZE


func add_to_bag(inst: Dictionary) -> bool:
	if bag_full() or inst.is_empty():
		return false
	inventory.append(inst)
	inventory_changed.emit()
	return true


## Equips bag slot `index`; the weapon in hand takes its place in the bag.
func equip_from_bag(index: int) -> void:
	if index < 0 or index >= inventory.size():
		return
	var inst: Dictionary = inventory[index]
	inventory[index] = equipped
	_set_equipped(inst)


func remove_from_bag(index: int) -> Dictionary:
	if index < 0 or index >= inventory.size():
		return {}
	var inst: Dictionary = inventory[index]
	inventory.remove_at(index)
	inventory_changed.emit()
	return inst


## Breaks a bag weapon down into gold.
func salvage(index: int) -> int:
	var inst := remove_from_bag(index)
	var gold_gain := Weapons.salvage_value(inst)
	add_gold(gold_gain)
	return gold_gain


func _swap_equipped(inst: Dictionary) -> void:
	if not equipped.is_empty() and not add_to_bag(equipped):
		toast.emit("BAG FULL - %s left behind" % Weapons.display_name(equipped), Color(0.9, 0.5, 0.5))
	_set_equipped(inst)


func _set_equipped(inst: Dictionary) -> void:
	equipped = inst
	_weapon_cache = null
	health = minf(health, get_max_health())
	health_changed.emit(health, get_max_health())
	inventory_changed.emit()
	weapon_changed.emit(get_weapon())


# --- Potions ------------------------------------------------------------------

func add_potion(n: int = 1) -> bool:
	if potions >= POTION_MAX:
		return false
	potions = mini(POTION_MAX, potions + n)
	potions_changed.emit(potions)
	return true


func drink_potion() -> bool:
	if potions <= 0 or health >= get_max_health():
		return false
	potions -= 1
	potions_changed.emit(potions)
	heal_player(get_max_health() * POTION_HEAL)
	return true


# --- Keys / powers / worlds ---------------------------------------------------

func give_key(world_id: String) -> void:
	if keys.has(world_id):
		return
	keys.append(world_id)
	keys_changed.emit()
	Sfx.play("key")
	var w := Database.get_world(world_id)
	toast.emit("KEY OBTAINED - %s" % (w.display_name if w else world_id), Color(1.0, 0.85, 0.3))


func has_key(world_id: String) -> bool:
	return keys.has(world_id)


func grant_power(id: String) -> void:
	var p := Database.get_power(id)
	if not p or powers.has(id):
		return
	powers.append(id)
	powers_changed.emit()
	health = minf(health, get_max_health())
	health_changed.emit(health, get_max_health())
	toast.emit("POWER ABSORBED - %s" % p.display_name, p.color)


func has_power(id: String) -> bool:
	return powers.has(id)


## Sums a stat across every owned power's stat_mods.
func get_stat(stat: String) -> float:
	var total := 0.0
	for id in powers:
		var p := Database.get_power(id)
		if p and p.stat_mods.has(stat):
			total += float(p.stat_mods[stat])
	return total


func get_active_power() -> PowerData:
	# The most recently absorbed active power is the one bound to `use_power`.
	for i in range(powers.size() - 1, -1, -1):
		var p := Database.get_power(powers[i])
		if p and p.kind == PowerData.Kind.ACTIVE:
			return p
	return null


## A new mission is a new run: the skills and elements gathered room by room start over.
func start_run() -> void:
	run_skills = {}
	run_elements = {}
	build_changed.emit()


func complete_world(world_id: String) -> void:
	if not worlds_completed.has(world_id):
		worlds_completed.append(world_id)
	if worlds_completed.size() >= Database.mission_order.size():
		act = Act.REVEAL
	else:
		act = Act.MISSIONS


func next_mission_id() -> String:
	for id in Database.mission_order:
		if not worlds_completed.has(id):
			return id
	return ""


func current_world() -> WorldData:
	return Database.get_world(current_world_id)


# --- Flags & requirements -----------------------------------------------------

func set_flag(flag: String, value: Variant = true) -> void:
	flags[flag] = value
	flag_changed.emit(flag, value)


func has_flag(flag: String) -> bool:
	return bool(flags.get(flag, false))


## Evaluates a requirement dictionary used by dialogue choices and variants.
## Supported keys: hope_min, hope_max, gold_min, flag, not_flag, has_key,
## not_has_key, has_power, worlds_done_min, worlds_done_max, act.
## `flag` and `not_flag` take one flag or a list (all must / none may be set).
func check_requirements(req: Dictionary) -> bool:
	if req.has("hope_min") and hope < float(req.hope_min): return false
	if req.has("hope_max") and hope >= float(req.hope_max): return false
	if req.has("gold_min") and gold < int(req.gold_min): return false
	if req.has("flag"):
		for f in _flag_list(req.flag):
			if not has_flag(f): return false
	if req.has("not_flag"):
		for f in _flag_list(req.not_flag):
			if has_flag(f): return false
	if req.has("has_key") and not has_key(_resolve_world(str(req.has_key))): return false
	if req.has("not_has_key") and has_key(_resolve_world(str(req.not_has_key))): return false
	if req.has("has_power") and not has_power(str(req.has_power)): return false
	if req.has("worlds_done_min") and worlds_completed.size() < int(req.worlds_done_min): return false
	if req.has("worlds_done_max") and worlds_completed.size() > int(req.worlds_done_max): return false
	if req.has("act") and Act.get(str(req.act).to_upper(), -1) != act: return false
	return true


func _flag_list(v: Variant) -> Array[String]:
	var out: Array[String] = []
	if v is Array:
		for x in v:
			out.append(str(x))
	else:
		out.append(str(v))
	return out


## "current" in dialogue data means the world the player is standing in.
func _resolve_world(id: String) -> String:
	return current_world_id if id == "current" else id


# --- Locks (dialogue, shop, cutscenes freeze the player) ----------------------

func push_ui_lock() -> void:
	_ui_locks += 1


func pop_ui_lock() -> void:
	_ui_locks = maxi(0, _ui_locks - 1)


func is_player_locked() -> bool:
	return _ui_locks > 0 or DialogueManager.is_busy()


# --- Save / load --------------------------------------------------------------

func save_game() -> void:
	var data := {
		"hope": hope, "gold": gold, "health": health, "keys": keys, "powers": powers,
		"inventory": inventory, "equipped": equipped, "potions": potions, "uid": _uid,
		"worlds_completed": worlds_completed, "flags": flags,
		"current_world_id": current_world_id, "act": act,
		"run_skills": run_skills, "run_elements": run_elements,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func load_game() -> bool:
	if not has_save():
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if not parsed is Dictionary:
		return false
	var d: Dictionary = parsed
	reset()
	hope = float(d.get("hope", HOPE_START))
	gold = int(d.get("gold", 0))
	keys.assign(d.get("keys", []))
	powers.assign(d.get("powers", []))
	_uid = int(d.get("uid", 0))
	potions = int(d.get("potions", POTION_START))
	# Older saves stored plain weapon ids; turn them into instances.
	inventory.clear()
	var bag: Variant = d.get("inventory", [])
	if bag is Array:
		for item: Variant in bag:
			var inst: Dictionary = item if item is Dictionary else Weapons.make(str(item))
			if not inst.is_empty() and inventory.size() < BAG_SIZE:
				inst["uid"] = int(inst.get("uid", next_uid()))
				inst["rarity"] = int(inst.get("rarity", 0))
				inventory.append(inst)
	var eq: Variant = d.get("equipped", {})
	if eq is Dictionary and not (eq as Dictionary).is_empty():
		equipped = eq
		equipped["uid"] = int(equipped.get("uid", next_uid()))
		equipped["rarity"] = int(equipped.get("rarity", 0))
	else:
		equipped = Weapons.make(str(d.get("equipped_weapon", STARTING_WEAPON)))
		inventory = inventory.filter(func(i: Dictionary) -> bool: return i.base != equipped.base)
	_weapon_cache = null
	worlds_completed.assign(d.get("worlds_completed", []))
	flags = d.get("flags", {})
	current_world_id = str(d.get("current_world_id", "sanctum"))
	act = int(d.get("act", Act.PROLOGUE)) as Act
	var skills_data: Variant = d.get("run_skills", {})
	if skills_data is Dictionary:
		for id: String in skills_data:
			run_skills[id] = int(skills_data[id])
	var elements_data: Variant = d.get("run_elements", {})
	if elements_data is Dictionary:
		run_elements = elements_data
	health = clampf(float(d.get("health", get_max_health())), 1.0, get_max_health())
	return true


# --- Input --------------------------------------------------------------------

## Registers default bindings so the project runs without editing the Input Map.
## Bindings added in Project Settings > Input Map take precedence (actions that
## already exist are left alone).
func _ensure_input_actions() -> void:
	var bindings := {
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"move_up": [KEY_W, KEY_UP],
		"move_down": [KEY_S, KEY_DOWN],
		"attack": [KEY_J, KEY_X],
		"dash": [KEY_SHIFT, KEY_SPACE, KEY_L],
		"interact": [KEY_E, KEY_ENTER],
		"use_power": [KEY_Q, KEY_U],
		"use_potion": [KEY_R, KEY_H],
		"inventory": [KEY_I, KEY_TAB],
		"pause": [KEY_ESCAPE, KEY_P],
	}
	var pad := {
		"attack": JOY_BUTTON_X, "dash": JOY_BUTTON_A,
		"interact": JOY_BUTTON_Y, "use_power": JOY_BUTTON_LEFT_SHOULDER, "pause": JOY_BUTTON_START,
		"use_potion": JOY_BUTTON_DPAD_UP, "inventory": JOY_BUTTON_BACK,
	}
	for action: String in bindings:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for keycode: Key in bindings[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = keycode
			InputMap.action_add_event(action, ev)
		if pad.has(action):
			var jb := InputEventJoypadButton.new()
			jb.button_index = pad[action]
			InputMap.action_add_event(action, jb)
	if not InputMap.action_get_events("attack").any(func(e: InputEvent) -> bool: return e is InputEventMouseButton):
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("attack", mb)
