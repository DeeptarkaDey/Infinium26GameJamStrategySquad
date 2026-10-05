extends Node
## Runs branching JSON dialogues from data/dialogue/<id>.json.
## Autoloaded as `DialogueManager`.
##
## File format:
## {
##   "variants": [ {"requires": {...}, "use": "other_id" | "start": "node_id"} ],  # first match wins
##   "start": "n1",
##   "nodes": {
##     "n1": {
##       "speaker": "monk",                  # key in speakers.json
##       "text": "...",
##       "text_low_hope": "...",             # optional, used when hope < 35
##       "text_high_hope": "...",            # optional, used when hope >= 70
##       "effects": {...},                   # applied when the line is shown
##       "next": "n2" | "choices": [ {"text": "...", "next": "n3", "requires": {...}, "effects": {...}} ]
##     }
##   }
## }
## Effects: hope, gold, set_flag, clear_flag, give_key ("current" = this world),
## give_weapon (a rolled copy goes into the bag), give_potion (count), give_power,
## heal, action ("name:arg", queued until the dialogue ends).
## Requirements: see GameState.check_requirements().

signal dialogue_started(id: String)
signal dialogue_ended(id: String)
## World-specific actions (open_shop, boss_fight, reveal_branch, ...) are emitted
## for the current scene to handle; global ones are handled here.
signal action_requested(action: String, arg: String)

const DIALOGUE_DIR := "res://data/dialogue/"
const SPEAKERS_PATH := "res://data/dialogue/speakers.json"
const BUSY_GRACE_MSEC := 250

var _box: DialogueBox
var _speakers: Dictionary = {}
var _cache: Dictionary = {}
var _data: Dictionary = {}
var _id := ""
var _node: Dictionary = {}
var _visible_choices: Array = []
var _pending_actions: Array[String] = []
var _ended_at_msec := -100000


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var parsed: Variant = _read_json(SPEAKERS_PATH)
	if parsed is Dictionary:
		_speakers = parsed
	_box = DialogueBox.new()
	add_child(_box)
	_box.advanced.connect(_on_advanced)
	_box.choice_selected.connect(_on_choice)


func is_active() -> bool:
	return _id != ""


## True while a dialogue is open and for a moment after, so the key press that
## closed the dialogue does not immediately re-trigger an interaction.
func is_busy() -> bool:
	return is_active() or Time.get_ticks_msec() - _ended_at_msec < BUSY_GRACE_MSEC


func start(id: String) -> void:
	if id == "" or is_active():
		return
	var data := _resolve(id, 0)
	if data.is_empty():
		push_warning("Dialogue not found: %s" % id)
		return
	_data = data
	_id = id
	_pending_actions.clear()
	dialogue_started.emit(id)
	_show(str(_data.get("start", "start")))


## Await this to block until the dialogue finishes.
func play(id: String) -> void:
	start(id)
	if is_active():
		await dialogue_ended


func _resolve(id: String, depth: int) -> Dictionary:
	if depth > 8:
		push_error("Dialogue variant loop at %s" % id)
		return {}
	var data := _load(id)
	for v: Dictionary in data.get("variants", []):
		if not GameState.check_requirements(v.get("requires", {})):
			continue
		if v.has("use"):
			return _resolve(str(v.use), depth + 1)
		if v.has("start"):
			# Same file, different entry node (e.g. a revisit line).
			var redirected := data.duplicate()
			redirected.start = v.start
			return redirected
	return data


func _load(id: String) -> Dictionary:
	if not _cache.has(id):
		var parsed: Variant = _read_json(DIALOGUE_DIR + id + ".json")
		_cache[id] = parsed if parsed is Dictionary else {}
	return _cache[id]


func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		push_error("%s:%d %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data


func _show(node_id: String) -> void:
	var nodes: Dictionary = _data.get("nodes", {})
	if node_id == "" or node_id == "end" or not nodes.has(node_id):
		_end()
		return
	_node = nodes[node_id]
	_apply_effects(_node.get("effects", {}))

	_visible_choices.clear()
	for c: Dictionary in _node.get("choices", []):
		if GameState.check_requirements(c.get("requires", {})):
			_visible_choices.append(c)
	_box.show_line(_speaker_info(str(_node.get("speaker", ""))), _pick_text(_node), _visible_choices)


func _pick_text(node: Dictionary) -> String:
	if node.has("text_low_hope") and GameState.hope < 35.0:
		return str(node.text_low_hope)
	if node.has("text_high_hope") and GameState.hope >= 70.0:
		return str(node.text_high_hope)
	return str(node.get("text", "..."))


func _speaker_info(key: String) -> Dictionary:
	var info: Dictionary = _speakers.get(key, {"name": key.capitalize()}).duplicate()
	# A speaker can change name once a flag is set (the monk becomes the Oni).
	if info.has("revealed_flag") and GameState.has_flag(str(info.revealed_flag)):
		info.name = info.get("revealed_name", info.get("name", ""))
		if info.has("revealed_color"):
			info.color = info.revealed_color
	return info


func _on_advanced() -> void:
	Sfx.play("ui_tick", -4.0)
	_show(str(_node.get("next", "end")))


func _on_choice(index: int) -> void:
	Sfx.play("ui_select")
	if index < 0 or index >= _visible_choices.size():
		return
	var choice: Dictionary = _visible_choices[index]
	_apply_effects(choice.get("effects", {}))
	_show(str(choice.get("next", "end")))


func _apply_effects(fx: Dictionary) -> void:
	if fx.has("hope"):
		GameState.change_hope(float(fx.hope), _id)
	if fx.has("gold"):
		GameState.add_gold(int(fx.gold))
	if fx.has("heal"):
		GameState.heal_player(float(fx.heal))
	if fx.has("set_flag"):
		for f in _as_list(fx.set_flag):
			GameState.set_flag(f)
	if fx.has("clear_flag"):
		for f in _as_list(fx.clear_flag):
			GameState.set_flag(f, false)
	if fx.has("give_key"):
		GameState.give_key(GameState._resolve_world(str(fx.give_key)))
	if fx.has("give_weapon"):
		var base := Database.get_weapon(str(fx.give_weapon))
		if base:
			var inst := Weapons.make(base.id, base.rarity, Weapons.roll_affixes(base, base.rarity))
			if GameState.add_to_bag(inst):
				GameState.toast.emit("RECEIVED - %s  (in your bag: I)" % Weapons.display_name(inst), WeaponData.rarity_color(base.rarity))
			else:
				GameState.give_weapon(base.id)  # bag full: it goes straight into your hands
	if fx.has("give_potion"):
		for i in int(fx.give_potion):
			GameState.add_potion()
		GameState.toast.emit("RECEIVED - %d healing potion%s" % [int(fx.give_potion), "s" if int(fx.give_potion) > 1 else ""], Color(1.0, 0.5, 0.55))
	if fx.has("give_power"):
		GameState.grant_power(str(fx.give_power))
	if fx.has("action"):
		for a in _as_list(fx.action):
			_pending_actions.append(a)


func _as_list(v: Variant) -> Array[String]:
	var out: Array[String] = []
	if v is Array:
		for x in v:
			out.append(str(x))
	else:
		out.append(str(v))
	return out


func _end() -> void:
	var id := _id
	_id = ""
	_node = {}
	_ended_at_msec = Time.get_ticks_msec()
	_box.close()
	dialogue_ended.emit(id)
	var actions := _pending_actions.duplicate()
	_pending_actions.clear()
	for a: String in actions:
		_run_action(a)


func _run_action(action: String) -> void:
	var parts := action.split(":", true, 1)
	var action_name := parts[0]
	var arg := parts[1] if parts.size() > 1 else ""
	match action_name:
		"teleport":
			SceneRouter.go_to_world(arg)
		"teleport_next":
			var next := GameState.next_mission_id()
			if next != "":
				SceneRouter.go_to_world(next)
		"save":
			GameState.save_game()
		_:
			action_requested.emit(action_name, arg)
