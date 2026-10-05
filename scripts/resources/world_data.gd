class_name WorldData
extends Resource
## One zone / dimension. Each world is a counterpart of the monk's world, printed
## in its own comic style. Levels are authored as top-down ASCII maps (see LEGEND).

enum Kind { HUB, MISSION, SANCTUARY, FINALE }

const LEGEND := """
#  wall                .  floor               D  gate (2 wide, between rooms)
S  player spawn        N  next NPC in `npcs`  $  shopkeeper
B  boss                K  hidden key shrine   P  exit portal
C  treasure chest      o  breakable pot       c  coin
q  next quest item in `quest_items`
Enemies (see Enemy.ARCHETYPES):  E chaser  A archer  F bat  H slime
                                 U brute   R charger T turret plant
(space) outside the map
Rooms are floor areas bounded by walls and gates. A room with enemies seals
its gates while the player is inside, and rewards a skill/element when cleared.
"""
## Layout letter -> Enemy archetype.
const ENEMY_LETTERS := {"E": "chaser", "A": "archer", "F": "bat", "H": "slime", "U": "brute", "R": "charger", "T": "turret"}

@export var id: String = ""
@export var display_name: String = "Unnamed World"
@export var subtitle: String = ""  ## e.g. "Mission 1 - The Order"
@export var kind: Kind = Kind.MISSION
@export var mission_index: int = 0  ## 1..n for missions; order the monk sends you
@export var style: ComicStyle

@export_group("Layout")
@export_multiline var layout: String = ""
@export var tile_size: int = 64
@export var intro_dialogue: String = ""  ## played the first time the world is entered

@export_group("NPCs")
## In order of 'N' in the layout. Keys: name, dialogue, look (ComicFigure.apply_look dict)
@export var npcs: Array = []
@export var shopkeeper: Dictionary = {}
## In order of 'q' in the layout. Keys: name, flag (set when picked up),
## requires (flag that makes it appear), dialogue (optional narration on pickup).
@export var quest_items: Array = []
@export var shop_stock: PackedStringArray = []

@export_group("Enemies & Loot")
@export var enemy_name: String = "Shade"
@export var enemy_health: float = 30.0
@export var enemy_damage: float = 10.0
@export var enemy_look: Dictionary = {}
## Per archetype overrides, e.g. {"archer": {"name": "Drowned Archer", "look": {...}}}.
## Unnamed archetypes are called "<enemy_name> <Archetype>".
@export var enemy_variants: Dictionary = {}
## Chance that each combat room promotes one of its enemies to an elite.
@export var elite_chance: float = 0.3
@export var gold_per_enemy: Vector2i = Vector2i(3, 8)
@export var weapon_drop_chance: float = 0.15
@export var drop_table: PackedStringArray = []  ## weapon ids; empty = any tagged for this world

@export_group("Boss")
@export var boss_name: String = ""
@export var boss_health: float = 300.0
@export var boss_damage: float = 18.0
@export var boss_look: Dictionary = {}
@export var boss_intro_dialogue: String = ""
@export var boss_defeat_dialogue: String = ""
@export var boss_power: String = ""  ## PowerData id granted on defeat
@export var boss_hope_on_kill: float = -5.0  ## the light escaping takes a little of yours
@export var boss_is_oni: bool = false  ## only truly harmed by sacred light
## "humanoid" (the Oni's fighting style), or a monster: "serpent", "moth", "eye".
@export var boss_form: String = "humanoid"

@export_group("Exit")
@export var portal_target: String = "sanctum"
@export var portal_requires_key: bool = true
@export var portal_requires_boss: bool = true
@export var portal_requires_flag: String = ""
