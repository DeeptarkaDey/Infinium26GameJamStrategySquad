class_name PowerData
extends Resource
## A power/perk absorbed from a defeated boss (the light of a fallen world).
## Passive effects are expressed as stat_mods and summed by GameState.get_stat().
## Active powers are dispatched by `id` in Player._use_active_power().

enum Kind { PASSIVE, ACTIVE }

@export var id: String = ""
@export var display_name: String = "Power"
@export_multiline var description: String = ""
@export var source_world: String = ""
@export var kind: Kind = Kind.PASSIVE
@export var cooldown: float = 4.0
## e.g. {"dash_charges": 1, "max_health": 20, "damage_mult": 0.1, "luck": 0.1, "dash_invuln": 1}
@export var stat_mods: Dictionary = {}
@export var color: Color = Color(1.0, 0.9, 0.5)
