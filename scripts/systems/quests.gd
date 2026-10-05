class_name Quests
extends RefCounted
## NPC subquests (data/quests/quests.json). A quest starts when its start_flag
## is set and is a list of steps, each finished by a flag; the current step is
## the first unfinished one, so steps done out of order still count. Dialogue
## effects, quest items (`q` in layouts) and boss kills all advance quests
## simply by setting flags.

const PATH := "res://data/quests/quests.json"

static var _quests: Array = []


static func all() -> Array:
	if _quests.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if parsed is Dictionary:
			_quests = (parsed as Dictionary).get("quests", [])
	return _quests


static func started(q: Dictionary) -> bool:
	return GameState.has_flag(str(q.start_flag))


## Index of the first unfinished step, or steps.size() when complete.
static func step_index(q: Dictionary) -> int:
	var steps: Array = q.steps
	for i in steps.size():
		if not GameState.has_flag(str(steps[i].done)):
			return i
	return steps.size()


static func complete(q: Dictionary) -> bool:
	return started(q) and step_index(q) >= (q.steps as Array).size()


## "" (not started), "step:<i>", or "done": used to notice progress.
static func state(q: Dictionary) -> String:
	if not started(q):
		return ""
	return "done" if complete(q) else "step:%d" % step_index(q)


static func current_text(q: Dictionary) -> String:
	var i := step_index(q)
	var steps: Array = q.steps
	return str(steps[i].text) if i < steps.size() else "Complete."
