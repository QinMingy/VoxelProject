extends RefCounted

const COLUMNS := 6
const ROWS := 4

var columns := COLUMNS
var rows := ROWS
var items: Array[Dictionary] = []
var _next_id := 1

func _init(width: int = COLUMNS, height: int = ROWS) -> void:
	columns = maxi(1, width)
	rows = maxi(1, height)

static func footprint(item: Dictionary, rotated: bool = false) -> Vector2i:
	var original: Vector2i = item.get("footprint", Vector2i.ONE)
	return Vector2i(original.y, original.x) if rotated else original

func can_place(item: Dictionary, at: Vector2i, rotated: bool = false, ignore_id: int = -1) -> bool:
	var size := footprint(item, rotated)
	if size.x < 1 or size.y < 1 or at.x < 0 or at.y < 0:
		return false
	if at.x + size.x > columns or at.y + size.y > rows:
		return false
	var area := Rect2i(at, size)
	for stored in items:
		if int(stored.id) == ignore_id:
			continue
		var occupied := Rect2i(stored.pos, footprint(stored, stored.rotated))
		if area.intersects(occupied):
			return false
	return true

func try_add(item: Dictionary) -> bool:
	var copy := item.duplicate(true)
	var item_id := int(copy.get("id", -1))
	if item_id < 0:
		item_id = _next_id
	if not get_item(item_id).is_empty():
		return false
	copy.id = item_id
	for rotated: bool in [false, true]:
		for y in range(rows):
			for x in range(columns):
				var at := Vector2i(x, y)
				if can_place(copy, at, rotated):
					copy.pos = at
					copy.rotated = rotated
					items.append(copy)
					_next_id = maxi(_next_id, item_id + 1)
					return true
	return false

func move_item(item_id: int, at: Vector2i, rotated: bool) -> bool:
	for index in range(items.size()):
		if int(items[index].id) != item_id:
			continue
		if not can_place(items[index], at, rotated, item_id):
			return false
		items[index].pos = at
		items[index].rotated = rotated
		return true
	return false

func get_item(item_id: int) -> Dictionary:
	for item in items:
		if int(item.id) == item_id:
			return item.duplicate(true)
	return {}

func item_at(cell: Vector2i) -> Dictionary:
	for item in items:
		if Rect2i(item.pos, footprint(item, item.rotated)).has_point(cell):
			return item.duplicate(true)
	return {}

func remove_item(item_id: int) -> Dictionary:
	for index in range(items.size()):
		if int(items[index].id) == item_id:
			var removed := items[index].duplicate(true)
			items.remove_at(index)
			return removed
	return {}

func used_cells() -> int:
	var result := 0
	for item in items:
		var size := footprint(item)
		result += size.x * size.y
	return result

func clear() -> void:
	items.clear()
	_next_id = 1
