extends RefCounted

const MAX_LEVEL := 3
const MAX_WAREHOUSE := 1024
const MAX_UID := 2_000_000_000
const MAX_COUNT := 1_000_000
const MAX_WEAR := 65
const INCOME_PERIOD := 65.0
const MIN_INCOME_SECONDS := 10.0
const EXHIBIT_VALUE_RATE := 0.06
const EXHIBIT_LEVEL_MULTIPLIERS := [1.0, 1.5, 2.0]
const CATEGORIES := [
	{"key": "crystal_small", "item_type": "crystal", "size_tier": 0, "label": "小型晶石", "item_name": "小型晶石", "base_value": 180, "footprint": Vector2i(1, 1), "icon_color": Color("#b875ed")},
	{"key": "crystal_medium", "item_type": "crystal", "size_tier": 1, "label": "中型晶石", "item_name": "中型晶石", "base_value": 400, "footprint": Vector2i(1, 2), "icon_color": Color("#b875ed")},
	{"key": "crystal_large", "item_type": "crystal", "size_tier": 2, "label": "大型晶石", "item_name": "大型晶石", "base_value": 760, "footprint": Vector2i(2, 2), "icon_color": Color("#b875ed")},
	{"key": "chest", "item_type": "chest", "size_tier": 0, "label": "冒险宝箱", "item_name": "冒险宝箱", "base_value": 800, "footprint": Vector2i(2, 2), "icon_color": Color("#dcad51")},
	{"key": "shield", "item_type": "shield", "size_tier": 0, "label": "冒险者盾牌", "item_name": "冒险者盾牌", "base_value": 620, "footprint": Vector2i(2, 2), "icon_color": Color("#639ee0")},
	{"key": "hammer", "item_type": "hammer", "size_tier": 0, "label": "遗落战锤", "item_name": "遗落战锤", "base_value": 540, "footprint": Vector2i(1, 3), "icon_color": Color("#dab069")},
]

static func initial_state() -> Dictionary:
	return {"warehouse": [], "exhibits": {}, "slots": ["", "", "", "", "", ""], "next_uid": 1, "identified_types": []}

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
		return kind if kind in ["chest", "shield", "hammer"] else ""
	var footprint: Variant = record.get("footprint", Vector2i.ZERO)
	if not footprint is Vector2i:
		return ""
	for row: Dictionary in CATEGORIES:
		if row.item_type == "crystal" and row.footprint == footprint:
			return str(row.key)
	return ""

static func sanitize_item(record: Dictionary, uid: int) -> Dictionary:
	var key := key_for_item(record)
	var row := definition(key)
	if row.is_empty() or uid < 1 or uid > MAX_UID:
		return {}
	var wear: Variant = record.get("wear", -1)
	var base_value: Variant = record.get("base_value", -1)
	if not wear is int or wear < 0 or wear > MAX_WEAR or not base_value is int or base_value != row.base_value:
		return {}
	if record.get("footprint", Vector2i.ZERO) != row.footprint:
		return {}
	row["uid"] = uid
	row["wear"] = wear
	return row

static func item_value(record: Dictionary) -> int:
	return roundi(float(record.get("base_value", 0)) * float(100 - int(record.get("wear", 0))) / 100.0)

static func _valid_item(record: Variant) -> bool:
	if not record is Dictionary or record.size() != 10:
		return false
	for key: String in ["key", "item_type", "size_tier", "label", "item_name", "base_value", "footprint", "icon_color", "uid", "wear"]:
		if not record.has(key):
			return false
	if not record.uid is int:
		return false
	var clean := sanitize_item(record, int(record.uid))
	if clean.is_empty():
		return false
	for key: String in ["key", "item_type", "size_tier", "label", "item_name", "base_value", "footprint", "uid", "wear"]:
		if clean[key] != record[key]:
			return false
	return record.icon_color is Color and is_finite(record.icon_color.r) and is_finite(record.icon_color.g) and is_finite(record.icon_color.b) and is_finite(record.icon_color.a)

static func is_valid_state(value: Variant, capacity: int = 6) -> bool:
	if not value is Dictionary or value.size() != 5:
		return false
	for key: String in ["warehouse", "exhibits", "slots", "next_uid", "identified_types"]:
		if not value.has(key):
			return false
	if not value.warehouse is Array or value.warehouse.size() > MAX_WAREHOUSE or not value.exhibits is Dictionary or value.exhibits.size() > CATEGORIES.size():
		return false
	if not value.slots is Array or value.slots.size() != 6 or not value.next_uid is int or value.next_uid < 1 or value.next_uid > MAX_UID:
		return false
	if not value.identified_types is Array or value.identified_types.size() > 4:
		return false
	var identifiers := {}
	for kind: Variant in value.identified_types:
		if not kind is String or kind not in ["crystal", "chest", "shield", "hammer"] or identifiers.has(kind):
			return false
		identifiers[kind] = true
	var uids := {}
	for record: Variant in value.warehouse:
		if not _valid_item(record) or uids.has(record.uid) or int(record.uid) >= int(value.next_uid):
			return false
		uids[record.uid] = true
	for key: Variant in value.exhibits:
		var entry: Variant = value.exhibits[key]
		if not key is String or definition(key).is_empty() or not entry is Dictionary or entry.size() != 6:
			return false
		for field: String in ["key", "label", "item", "bestwear", "level", "count"]:
			if not entry.has(field):
				return false
		if not _valid_item(entry.item) or entry.item.key != key or entry.key != key or entry.label != entry.item.label:
			return false
		if uids.has(entry.item.uid) or int(entry.item.uid) >= int(value.next_uid):
			return false
		uids[entry.item.uid] = true
		if not entry.level is int or entry.level < 1 or entry.level > MAX_LEVEL or not entry.count is int or entry.count < entry.level or entry.count > MAX_COUNT:
			return false
		if not entry.bestwear is int or entry.bestwear != entry.item.wear:
			return false
	var placed := {}
	for index in range(6):
		var key: Variant = value.slots[index]
		if not key is String:
			return false
		if key.is_empty():
			continue
		if index >= capacity or not value.exhibits.has(key) or placed.has(key):
			return false
		placed[key] = true
	return true

static func append_cargo(state: Dictionary, records: Array) -> Dictionary:
	if state.warehouse.size() + records.size() > MAX_WAREHOUSE:
		return {"ok": false, "message": "仓库待整理区已满，请先处理物品", "error": ERR_OUT_OF_MEMORY}
	var next := state.duplicate(true)
	var added: Array[int] = []
	for raw: Variant in records:
		if not raw is Dictionary or int(next.next_uid) >= MAX_UID:
			return {"ok": false, "message": "物品记录无效，物品仍留在背包", "error": ERR_INVALID_PARAMETER}
		var clean := sanitize_item(raw, int(next.next_uid))
		if clean.is_empty():
			return {"ok": false, "message": "无法识别物品记录，物品仍留在背包", "error": ERR_INVALID_PARAMETER}
		next.warehouse.append(clean)
		added.append(int(next.next_uid))
		next.next_uid += 1
	return {"ok": true, "state": next, "uids": added}

static func find_item(state: Dictionary, uid: int) -> Dictionary:
	for record: Dictionary in state.warehouse:
		if int(record.uid) == uid:
			return record.duplicate(true)
	return {}

static func _warehouse_index(state: Dictionary, uid: int) -> int:
	for index in range(state.warehouse.size()):
		if int(state.warehouse[index].uid) == uid:
			return index
	return -1

static func _identify(state: Dictionary, kind: String) -> void:
	if not state.identified_types.has(kind):
		state.identified_types.append(kind)

static func plan_donation(state: Dictionary, uid: int, capacity: int) -> Dictionary:
	var index := _warehouse_index(state, uid)
	if index < 0:
		return {"ok": false, "message": "这件物品已不在仓库", "error": ERR_DOES_NOT_EXIST}
	var next := state.duplicate(true)
	var item: Dictionary = next.warehouse[index].duplicate(true)
	var key := str(item.key)
	var entry: Dictionary = next.exhibits.get(key, {}).duplicate(true)
	var research := 0
	var replaced := false
	if entry.is_empty():
		entry = {"key": key, "label": item.label, "item": item, "bestwear": item.wear, "level": 1, "count": 1}
		research = 1
		for slot in range(capacity):
			if str(next.slots[slot]).is_empty():
				next.slots[slot] = key
				break
	elif int(entry.level) < MAX_LEVEL:
		entry.level += 1
		entry.count += 1
		research = 1
		if int(item.wear) < int(entry.bestwear):
			entry.item = item
			entry.bestwear = item.wear
	elif int(item.wear) < int(entry.bestwear):
		# Fully researched better-condition replacements return the former display
		# specimen to the warehouse. Its original stable UID is retained.
		next.warehouse.append(entry.item.duplicate(true))
		entry.item = item
		entry.bestwear = item.wear
		entry.count = mini(MAX_COUNT, int(entry.count) + 1)
		replaced = true
	else:
		return {"ok": false, "message": "展品已满级，且现有展品品相更好；可以保留或出售", "error": ERR_ALREADY_EXISTS}
	next.warehouse.remove_at(index)
	next.exhibits[key] = entry
	_identify(next, str(item.item_type))
	return {"ok": true, "state": next, "research": research, "key": key, "replaced": replaced,
		"message": "%s已替换，原展品已退回待整理区" % item.label if replaced else "%s · 展品 Lv.%d · 研究点 +%d" % [item.label, entry.level, research]}

static func plan_sale(state: Dictionary, uid: int) -> Dictionary:
	var index := _warehouse_index(state, uid)
	if index < 0:
		return {"ok": false, "message": "这件物品已不在仓库", "error": ERR_DOES_NOT_EXIST}
	var next := state.duplicate(true)
	var item: Dictionary = next.warehouse[index].duplicate(true)
	next.warehouse.remove_at(index)
	_identify(next, str(item.item_type))
	var value := item_value(item)
	return {"ok": true, "state": next, "income": value, "item": item,
		"message": "%s出售 +%d · 磨损 %d%%" % [item.label, value, item.wear]}

static func plan_placement(state: Dictionary, key: String, slot: int, capacity: int) -> Dictionary:
	if slot < 0 or slot >= capacity or (not key.is_empty() and not state.exhibits.has(key)):
		return {"ok": false, "message": "展台尚未解锁或展品尚未登记", "error": ERR_INVALID_PARAMETER}
	var next := state.duplicate(true)
	var former_slot: int = next.slots.find(key) if not key.is_empty() else -1
	var displaced := str(next.slots[slot])
	if former_slot >= 0 and former_slot != slot:
		next.slots[former_slot] = displaced
	next.slots[slot] = key
	return {"ok": true, "state": next, "message": "展台已收起" if key.is_empty() else "%s已摆入 %d 号展台" % [state.exhibits[key].label, slot + 1]}

static func exhibit_income(entry: Dictionary, appeal: float) -> int:
	var specimen: Dictionary = entry.item
	var condition := float(100 - int(entry.bestwear)) / 100.0
	return roundi(float(specimen.base_value) * condition * EXHIBIT_VALUE_RATE * EXHIBIT_LEVEL_MULTIPLIERS[int(entry.level) - 1] * appeal)

static func summary(state: Dictionary, capacity: int, appeal: float, research_points: int) -> Dictionary:
	var result := state.duplicate(true)
	result["capacity"] = capacity
	result["appeal"] = appeal
	result["research_points"] = research_points
	result["max_level"] = MAX_LEVEL
	result["registered_count"] = state.exhibits.size()
	result["total_level"] = 0
	result["displayed_count"] = 0
	result["income"] = 0
	result["income_period"] = INCOME_PERIOD
	result["income_min_seconds"] = MIN_INCOME_SECONDS
	var rows: Array[Dictionary] = []
	for definition_row: Dictionary in CATEGORIES:
		var key := str(definition_row.key)
		var entry: Dictionary = state.exhibits.get(key, {})
		var slot: int = state.slots.find(key)
		var shown := slot >= 0 and slot < capacity
		var income := exhibit_income(entry, appeal) if not entry.is_empty() else 0
		var row := definition_row.duplicate(true)
		row.merge({"registered": not entry.is_empty(), "level": int(entry.get("level", 0)), "count": int(entry.get("count", 0)), "wear": int(entry.get("bestwear", 0)), "item": entry.get("item", {}).duplicate(true), "slot": slot, "displayed": shown, "income": income}, true)
		rows.append(row)
		if not entry.is_empty():
			result.total_level += int(entry.level)
		if shown:
			result.displayed_count += 1
			result.income += income
	result["catalogue_rows"] = rows
	return result
