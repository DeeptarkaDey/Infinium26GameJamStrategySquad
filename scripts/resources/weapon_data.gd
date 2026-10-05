class_name WeaponData
extends Resource
## A base weapon: drops from enemies and chests, or is bought in shops. What you
## actually carry is an *instance* of one (see Weapons): a rolled rarity plus up
## to three affixes. GameState.get_weapon() returns a runtime copy of this
## resource with the equipped instance's affixes applied.

enum Rarity { COMMON, UNCOMMON, RARE, LEGENDARY }
## Each kind attacks differently (see Player._attack).
enum Kind { SWORD, SPEAR, HEAVY, DAGGER, STAFF, BOW }

@export var id: String = ""
@export var display_name: String = "Weapon"
@export_multiline var description: String = ""
@export var kind: Kind = Kind.SWORD
@export var rarity: Rarity = Rarity.COMMON  ## minimum rarity of any instance
@export var damage: float = 10.0
@export var attack_cooldown: float = 0.4
@export var reach: float = 56.0  ## swing length in pixels (projectile range for STAFF/BOW)
@export var knockback: float = 220.0
@export var price: int = 50  ## base shop price, scaled by hope
@export var drop_weight: float = 1.0
@export var sfx_word: String = "SLASH!"
@export var blade_color: Color = Color(0.85, 0.88, 0.95)
## Built-in element ("fire", "frost", "shock", "poison"), or "" for none.
@export var element: String = ""
## World ids this weapon can drop in. Empty = any world.
@export var world_tags: PackedStringArray = []

# Runtime only (set on the copy GameState.get_weapon() builds; never saved in .tres).
var uid := 0
var lifesteal := 0.0  ## share of blade damage healed
var crit_bonus := 0.0
var max_health_bonus := 0.0
var affix_lines: PackedStringArray = []


func is_ranged() -> bool:
	return kind == Kind.STAFF or kind == Kind.BOW


static func rarity_color(r: Rarity) -> Color:
	match r:
		Rarity.UNCOMMON: return Color(0.3, 0.8, 0.35)
		Rarity.RARE: return Color(0.3, 0.55, 1.0)
		Rarity.LEGENDARY: return Color(1.0, 0.65, 0.1)
	return Color(0.9, 0.9, 0.9)


static func rarity_name(r: Rarity) -> String:
	return ["Common", "Uncommon", "Rare", "Legendary"][r]


static func kind_name(k: Kind) -> String:
	return ["Sword", "Spear", "Greatblade", "Dagger", "Staff", "Bow"][k]
