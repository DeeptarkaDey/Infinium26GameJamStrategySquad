class_name Skills
extends RefCounted
## Run skills and element modifiers, offered as rewards after each cleared room.
## Skills fire on their own cooldowns whenever you attack. Any slot (the blade or
## a skill) can carry one element. The build lives in GameState.run_skills /
## run_elements and resets when a new mission starts.

const MAX_SKILLS := 3
const BLADE := "blade"

## damage is a multiple of the equipped weapon's damage.
const SKILLS := {
	"spirit_dart": {"name": "Spirit Dart", "desc": "Fires a homing paper charm.", "damage": 0.7, "cooldown": 0.9, "color": Color(0.75, 0.9, 1.0)},
	"crescent_wave": {"name": "Crescent Wave", "desc": "Sends a piercing ink slash forward.", "damage": 1.2, "cooldown": 2.4, "color": Color(0.95, 0.95, 1.0)},
	"whirlwind": {"name": "Whirlwind", "desc": "Spins the blade around you.", "damage": 0.9, "cooldown": 3.0, "color": Color(0.7, 1.0, 0.8)},
	"thunder_seal": {"name": "Thunder Seal", "desc": "Calls a bolt down on the nearest foe.", "damage": 1.6, "cooldown": 3.5, "color": Color(1.0, 0.95, 0.5)},
}

const ELEMENTS := {
	"fire": {"name": "Fire", "desc": "Burns for 3s.", "color": Color(1.0, 0.45, 0.15)},
	"frost": {"name": "Frost", "desc": "Slows; the third hit freezes.", "color": Color(0.55, 0.85, 1.0)},
	"shock": {"name": "Shock", "desc": "Arcs to 2 nearby foes.", "color": Color(1.0, 0.92, 0.3)},
	"poison": {"name": "Poison", "desc": "Stacking venom, up to 5.", "color": Color(0.55, 0.9, 0.3)},
}


static func skill_name(id: String) -> String:
	return str(SKILLS[id].name) if SKILLS.has(id) else id


static func slot_name(slot: String) -> String:
	return "Blade" if slot == BLADE else skill_name(slot)


static func element_color(element: String) -> Color:
	return ELEMENTS[element].color if ELEMENTS.has(element) else Color.WHITE


## Skill damage multiplier and cooldown at a given level (level 1 = base).
static func damage_mult(id: String, level: int) -> float:
	return float(SKILLS[id].damage) * (1.0 + 0.3 * (level - 1))


static func cooldown(id: String, level: int) -> float:
	return float(SKILLS[id].cooldown) * pow(0.88, level - 1)


## Three distinct reward cards. Each is {kind: "skill"|"upgrade"|"element", id, slot,
## title, desc, color}. Tries to include at least one skill card and one element card.
static func roll_rewards(count: int = 3) -> Array[Dictionary]:
	var skill_cards: Array[Dictionary] = []
	var element_cards: Array[Dictionary] = []
	var owned: Dictionary = GameState.run_skills
	for id: String in SKILLS:
		var s: Dictionary = SKILLS[id]
		if owned.has(id):
			var lvl := int(owned[id])
			skill_cards.append({"kind": "upgrade", "id": id, "slot": id, "title": "%s Lv%d" % [s.name, lvl + 1],
				"desc": "+30% damage, faster cooldown.", "color": s.color})
		elif owned.size() < MAX_SKILLS:
			skill_cards.append({"kind": "skill", "id": id, "slot": id, "title": "NEW: %s" % s.name,
				"desc": str(s.desc), "color": s.color})
	var slots: Array[String] = [BLADE]
	for id: String in owned:
		slots.append(id)
	for el: String in ELEMENTS:
		for slot in slots:
			if str(GameState.run_elements.get(slot, "")) == el:
				continue
			var e: Dictionary = ELEMENTS[el]
			element_cards.append({"kind": "element", "id": el, "slot": slot, "title": "%s %s" % [e.name, slot_name(slot)],
				"desc": "%s on your %s. %s" % [e.name, slot_name(slot), e.desc], "color": e.color})
	skill_cards.shuffle()
	element_cards.shuffle()
	var out: Array[Dictionary] = []
	if not skill_cards.is_empty():
		out.append(skill_cards.pop_back())
	if not element_cards.is_empty():
		out.append(element_cards.pop_back())
	var rest: Array[Dictionary] = skill_cards + element_cards
	rest.shuffle()
	while out.size() < count and not rest.is_empty():
		out.append(rest.pop_back())
	return out


static func apply_reward(card: Dictionary) -> void:
	match str(card.kind):
		"skill":
			GameState.run_skills[str(card.id)] = 1
		"upgrade":
			GameState.run_skills[str(card.id)] = int(GameState.run_skills.get(str(card.id), 1)) + 1
		"element":
			GameState.run_elements[str(card.slot)] = str(card.id)
	GameState.build_changed.emit()
	GameState.toast.emit(str(card.title).to_upper(), card.color)


## Every player hit goes through here: hope multiplier, crit roll (with the
## weapon's crit bonus), the element carried by the slot that dealt it, and for
## blade hits the weapon's own element and lifesteal.
static func strike(enemy: Enemy, base: float, from: Vector2, knockback: float, slot: String, is_light: bool = false, force_crit: bool = false) -> void:
	if not is_instance_valid(enemy) or enemy.is_dead():
		return
	var crit := force_crit or randf() < GameState.get_crit_chance()
	var dmg := base * GameState.get_damage_multiplier() * (1.75 if crit else 1.0)
	enemy.take_hit(dmg, from, knockback, crit, is_light)
	var elements: Array[String] = []
	var element := str(GameState.run_elements.get(slot, ""))
	if element != "":
		elements.append(element)
	if slot == BLADE:
		var w := GameState.get_weapon()
		if w.element != "" and not elements.has(w.element):
			elements.append(w.element)
		if w.lifesteal > 0.0:
			GameState.heal_player(dmg * w.lifesteal)
	for el in elements:
		if not enemy.is_dead():
			enemy.apply_element(el, dmg)
