extends RefCounted

# Source size controls voxel generation only. Prices and bag dimensions never depend on
# the number of cells produced by a particular burial angle.
const ITEMS := [
	{"id": "chest", "label": "冒险宝箱", "scene": "res://assets/adventure/chest.glb", "size": 1.0,
		"footprint": Vector2i(2, 2), "value": 800, "color": Color("#dcad51")},
	{"id": "shield", "label": "冒险者盾牌", "scene": "res://assets/adventure/shield.glb", "size": 1.125,
		"footprint": Vector2i(2, 2), "value": 620, "color": Color("#639ee0")},
	{"id": "hammer", "label": "遗落战锤", "scene": "res://assets/adventure/warhammer.glb", "size": 1.25,
		"footprint": Vector2i(1, 3), "value": 540, "color": Color("#dab069")},
]

static var _scenes: Dictionary = {}

static func definition(index: int) -> Dictionary:
	return ITEMS[posmod(index, ITEMS.size())].duplicate()

static func source_scene(index: int) -> PackedScene:
	var path: String = ITEMS[posmod(index, ITEMS.size())].scene
	if not _scenes.has(path):
		_scenes[path] = load(path) as PackedScene
	return _scenes[path]
