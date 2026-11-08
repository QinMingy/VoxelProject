extends RefCounted
const Palette = preload("res://palette.gd")

# Source size controls voxel generation only. Prices and bag dimensions never depend on
# the number of cells produced by a particular burial angle.
const ITEMS := [
	{"id": "chest", "label": "冒险宝箱", "scene": "res://assets/adventure/chest.glb", "size": 1.0,
		"footprint": Vector2i(2, 2), "value": 800, "color": Palette.AMBER},
	{"id": "shield", "label": "冒险者盾牌", "scene": "res://assets/adventure/shield.glb", "size": 1.125,
		"footprint": Vector2i(2, 2), "value": 620, "color": Palette.MOON_BLUE},
	{"id": "hammer", "label": "遗落战锤", "scene": "res://assets/adventure/warhammer.glb", "size": 1.25,
		"footprint": Vector2i(1, 3), "value": 540, "color": Palette.AMBER_LIGHT},
	{"id": "spellbook", "label": "遗落魔法书", "scene": "res://assets/adventure/spellbook.glb", "size": 0.75,
		"footprint": Vector2i(1, 2), "value": 520, "color": Palette.WARNING_ROSE},
	{"id": "chest_large", "label": "大箱子", "scene": "res://assets/adventure/chest.glb", "size": 1.5,
		"footprint": Vector2i(3, 3), "value": 1200, "color": Palette.AMBER},
]

static var _scenes: Dictionary = {}

static func definition(index: int) -> Dictionary:
	return ITEMS[posmod(index, ITEMS.size())].duplicate()

static func source_scene(index: int) -> PackedScene:
	var path: String = ITEMS[posmod(index, ITEMS.size())].scene
	if not _scenes.has(path):
		_scenes[path] = load(path) as PackedScene
	return _scenes[path]
