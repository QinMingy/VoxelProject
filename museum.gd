extends RefCounted
const Palette = preload("res://palette.gd")

# One owned specimen per category. A collection's only stored fact is how many
# copies it has ever taken in; level and experience are derived from that count.
const MAX_LEVEL := 10
const MAX_COPIES := 1_000_000
# Four exhibition zones of twelve stands each. Zone grouping is presentation only
# today; zone buffs are reserved for a later pass.
const ZONE_SIZE := 12
const ZONE_COUNT := 4
const STAND_COUNT := ZONE_SIZE * ZONE_COUNT
const ZONES := [
	{"id": "a", "label": "A 区"},
	{"id": "b", "label": "B 区"},
	{"id": "c", "label": "C 区"},
	{"id": "d", "label": "D 区"},
]
const INCOME_PERIOD := 65.0
const MIN_INCOME_SECONDS := 10.0
const EXHIBIT_VALUE_RATE := 0.06
const LEVEL_INCOME_STEP := 0.15
# Minimum copies held for each level: Lv1 on the first find, then 2,3,4,…,10 more.
const LEVEL_THRESHOLDS := [1, 3, 6, 10, 15, 21, 28, 36, 45, 55]
const CATEGORIES := [
	{"key": "crystal_small", "item_type": "crystal", "size_tier": 0, "label": "小型晶石", "item_name": "小型晶石", "base_value": 180, "footprint": Vector2i(1, 1), "icon_color": Palette.CRYSTAL},
	{"key": "crystal_medium", "item_type": "crystal", "size_tier": 1, "label": "中型晶石", "item_name": "中型晶石", "base_value": 400, "footprint": Vector2i(1, 2), "icon_color": Palette.CRYSTAL},
	{"key": "crystal_large", "item_type": "crystal", "size_tier": 2, "label": "大型晶石", "item_name": "大型晶石", "base_value": 760, "footprint": Vector2i(2, 2), "icon_color": Palette.CRYSTAL},
	{"key": "chest", "item_type": "chest", "size_tier": 0, "label": "冒险宝箱", "item_name": "冒险宝箱", "base_value": 800, "footprint": Vector2i(2, 2), "icon_color": Palette.AMBER},
	{"key": "shield", "item_type": "shield", "size_tier": 0, "label": "冒险者盾牌", "item_name": "冒险者盾牌", "base_value": 620, "footprint": Vector2i(2, 2), "icon_color": Palette.MOON_BLUE},
	{"key": "hammer", "item_type": "hammer", "size_tier": 0, "label": "遗落战锤", "item_name": "遗落战锤", "base_value": 540, "footprint": Vector2i(1, 3), "icon_color": Palette.AMBER_LIGHT},
	{"key": "spellbook", "item_type": "spellbook", "size_tier": 0, "label": "遗落魔法书", "item_name": "遗落魔法书", "base_value": 520, "footprint": Vector2i(1, 2), "icon_color": Palette.WARNING_ROSE},
	{"key": "chest_large", "item_type": "chest_large", "size_tier": 0, "label": "大箱子", "item_name": "大箱子", "base_value": 1200, "footprint": Vector2i(3, 3), "icon_color": Palette.AMBER},
]

static func initial_state() -> Dictionary:
	return {"items": {}, "slots": empty_slots()}

static func empty_slots() -> Array:
	var slots: Array = []
	slots.resize(STAND_COUNT)
	slots.fill("")
	return slots

static func zone_for_slot(slot: int) -> int:
	return clampi(slot / ZONE_SIZE, 0, ZONE_COUNT - 1)

static func zone_label(zone: int) -> String:
	return str(ZONES[clampi(zone, 0, ZONE_COUNT - 1)].label)

static func definition(key: String) -> Dictionary:
	for row: Dictionary in CATEGORIES:
		if row.key == key:
			return row.duplicate(true)
	return {}

static func key_for_item(record: Dictionary) -> String:
	var kind: Variant = record.get("item_type", "crystal")
	if not kind is String:
		return ""
	if kind != "crystal":
		var relic := definition(kind)
		return kind if not relic.is_empty() and str(relic.item_type) == kind else ""
	var footprint: Variant = record.get("footprint", Vector2i.ZERO)
	if not footprint is Vector2i:
		return ""
	for row: Dictionary in CATEGORIES:
		if row.item_type == "crystal" and row.footprint == footprint:
			return str(row.key)
	return ""

static func level_for(copies: int) -> int:
	if copies <= 0:
		return 0
	var level := 1
	for index in range(1, LEVEL_THRESHOLDS.size()):
		if copies >= int(LEVEL_THRESHOLDS[index]):
			level = index + 1
	return level

static func xp_for(copies: int) -> int:
	var level := level_for(copies)
	if level <= 0 or level >= MAX_LEVEL:
		return 0
	return copies - int(LEVEL_THRESHOLDS[level - 1])

static func need_for(level: int) -> int:
	if level < 1 or level >= MAX_LEVEL:
		return 0
	return int(LEVEL_THRESHOLDS[level]) - int(LEVEL_THRESHOLDS[level - 1])

static func copies_for_level(level: int) -> int:
	if level <= 0:
		return 0
	return int(LEVEL_THRESHOLDS[clampi(level, 1, MAX_LEVEL) - 1])

static func is_valid_state(value: Variant, capacity: int = STAND_COUNT) -> bool:
	if not value is Dictionary or value.size() != 2:
		return false
	if not value.has("items") or not value.has("slots"):
		return false
	if not value.items is Dictionary or value.items.size() > CATEGORIES.size():
		return false
	for key: Variant in value.items:
		var entry: Variant = value.items[key]
		if not key is String or definition(key).is_empty():
			return false
		if not entry is Dictionary or entry.size() != 2 or not entry.has("key") or not entry.has("copies"):
			return false
		if entry.key != key or not entry.copies is int:
			return false
		if int(entry.copies) < 1 or int(entry.copies) > MAX_COPIES:
			return false
	if not value.slots is Array or value.slots.size() != STAND_COUNT:
		return false
	var placed := {}
	for index in range(STAND_COUNT):
		var key: Variant = value.slots[index]
		if not key is String:
			return false
		if key.is_empty():
			continue
		if index >= capacity or not value.items.has(key) or placed.has(key):
			return false
		placed[key] = true
	return true

static func plan_collect(state: Dictionary, records: Array, capacity: int) -> Dictionary:
	var next := state.duplicate(true)
	var changes := {}
	var research := 0
	for raw: Variant in records:
		if not raw is Dictionary:
			return {"ok": false, "message": "物品记录无效，物品仍留在背包", "error": ERR_INVALID_PARAMETER}
		var key := key_for_item(raw)
		if key.is_empty():
			return {"ok": false, "message": "无法识别物品记录，物品仍留在背包", "error": ERR_INVALID_PARAMETER}
		var before := 0
		if next.items.has(key):
			before = int(next.items[key].copies)
		var copies := mini(MAX_COPIES, before + 1)
		var level_before := level_for(before)
		var level_after := level_for(copies)
		if not next.items.has(key):
			next.items[key] = {"key": key, "copies": 0}
			research += 1
			_auto_place(next, key, capacity)
		next.items[key].copies = copies
		research += maxi(0, level_after - maxi(level_before, 1))
		var change: Dictionary = changes.get(key, {
			"key": key, "label": str(definition(key).label), "count": 0,
			"copies_before": before, "copies_after": before,
			"level_before": level_before, "level_after": level_before,
		})
		change.count = int(change.count) + 1
		change.copies_after = copies
		change.level_after = level_after
		changes[key] = change
	return {"ok": true, "state": next, "changes": changes.values(), "research": research, "stored": records.size()}

static func _auto_place(state: Dictionary, key: String, capacity: int) -> void:
	for slot in range(mini(capacity, state.slots.size())):
		if str(state.slots[slot]).is_empty():
			state.slots[slot] = key
			return

static func plan_placement(state: Dictionary, key: String, slot: int, capacity: int) -> Dictionary:
	if slot < 0 or slot >= capacity or (not key.is_empty() and not state.items.has(key)):
		return {"ok": false, "message": "展台尚未解锁或物品尚未获得", "error": ERR_INVALID_PARAMETER}
	var next := state.duplicate(true)
	var former_slot: int = next.slots.find(key) if not key.is_empty() else -1
	var displaced := str(next.slots[slot])
	if former_slot >= 0 and former_slot != slot:
		next.slots[former_slot] = displaced
	next.slots[slot] = key
	return {"ok": true, "state": next, "message": "展台已收起" if key.is_empty() else "%s已摆入展台" % definition(key).label}

static func exhibit_income(level: int, base_value: int, appeal: float) -> int:
	if level <= 0:
		return 0
	var multiplier := 1.0 + LEVEL_INCOME_STEP * float(level - 1)
	return roundi(float(base_value) * EXHIBIT_VALUE_RATE * multiplier * appeal)

static func summary(state: Dictionary, capacity: int, appeal: float, research_points: int) -> Dictionary:
	var result := state.duplicate(true)
	result["capacity"] = capacity
	result["appeal"] = appeal
	result["research_points"] = research_points
	result["max_level"] = MAX_LEVEL
	result["registered_count"] = state.items.size()
	result["total_level"] = 0
	result["displayed_count"] = 0
	result["income"] = 0
	result["income_period"] = INCOME_PERIOD
	result["income_min_seconds"] = MIN_INCOME_SECONDS
	var exhibits := {}
	var rows: Array[Dictionary] = []
	for definition_row: Dictionary in CATEGORIES:
		var key := str(definition_row.key)
		var entry: Dictionary = state.items.get(key, {})
		var copies := int(entry.get("copies", 0))
		var level := level_for(copies)
		var slot: int = state.slots.find(key)
		var shown := copies > 0 and slot >= 0 and slot < capacity
		var income := exhibit_income(level, int(definition_row.base_value), appeal) if copies > 0 else 0
		var row := definition_row.duplicate(true)
		row.merge({"owned": copies > 0, "copies": copies, "level": level, "xp": xp_for(copies),
			"need": need_for(level), "count": copies, "slot": slot, "displayed": shown, "income": income}, true)
		rows.append(row)
		if copies > 0:
			result.total_level += level
			exhibits[key] = {"key": key, "label": str(definition_row.label), "level": level,
				"count": copies, "copies": copies, "item": definition_row.duplicate(true)}
		if shown:
			result.displayed_count += 1
			result.income += income
	result["exhibits"] = exhibits
	result["catalogue_rows"] = rows
	return result
