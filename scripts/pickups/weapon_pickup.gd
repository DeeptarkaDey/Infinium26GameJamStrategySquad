extends Interactable
## A dropped weapon instance lying on the floor, with a rarity-coloured beam so
## good loot is spotted across a room. Press interact to put it in the bag.

var item: Dictionary = {}
var _weapon: WeaponData
var _t := 0.0


func _ready() -> void:
	trigger_size = Vector2(60, 60)
	_weapon = Weapons.build(item)
	prompt = "Take %s (%s)" % [_weapon.display_name, WeaponData.rarity_name(_weapon.rarity)]
	super._ready()


func interact(_player: Player) -> void:
	if not GameState.add_to_bag(item):
		Sfx.play("error")
		GameState.toast.emit("BAG FULL - press I to make room", Color(0.9, 0.5, 0.5))
		return
	Sfx.play("pickup")
	GameState.toast.emit("%s  ->  BAG" % _weapon.display_name.to_upper(), WeaponData.rarity_color(_weapon.rarity))
	queue_free()


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var rc := WeaponData.rarity_color(_weapon.rarity)
	if _weapon.rarity >= WeaponData.Rarity.UNCOMMON:
		var h := 60.0 + 40.0 * _weapon.rarity
		draw_rect(Rect2(-6, -h, 12, h), Color(rc, 0.25 + 0.1 * sin(_t * 4.0)))
	draw_circle(Vector2(0, -2), 18.0, Color(rc, 0.3))
	WeaponIcon.draw(self, Vector2(0, -20 + sin(_t * 3.0) * 3.0), 34.0, _weapon)
