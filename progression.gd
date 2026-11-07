extends RefCounted

const Museum = preload("res://museum.gd")
const PROFILE_VERSION := 5
const DEFAULT_BANK := 150
const MAX_BANK := 10_000_000
const DEFAULT_ZONE := "meadow"
const MAX_ACTIVITY_RADIUS := 26.0
const OXYGEN_RECOVERY_LIMITS := [6.0, 10.0, 16.0, 24.0]

const UPGRADES := {
	"drill": {
		"name": "电镐", "description": "缩短每次开采的蓄力时间。",
		"values": [0.9, 0.65, 0.45, 0.30], "costs": [120, 700, 2200],
	},
	"mining_radius": {
		"name": "开采范围", "description": "扩大每次开采的直径，不改变笔刷形状；与开采速度共同生效。",
		"values": [0.45, 0.50, 0.55, 0.60], "costs": [180, 850, 2600],
	},
	"oxygen": {
		"name": "氧气瓶", "description": "提高每次出舱的氧气上限。",
		"values": [65, 75, 85, 95], "costs": [160, 650, 1900],
	},
	"oxygen_supply": {
		"name": "氧矿补给", "description": "提高下一趟氧矿密度与单趟补氧总额度；每粒仍回复 0.02 秒。",
		"values": [0.25, 0.40, 0.60, 0.85], "costs": [180, 750, 2200],
	},
	"boots": {
		"name": "推进靴", "description": "提高步行速度，缩短返舱路程耗时。",
		"values": [3.35, 3.7, 4.05, 4.4], "costs": [140, 600, 1800],
	},
	"backpack": {
		"name": "标本背包", "description": "扩大格子面积，容纳更多完整标本。",
		"values": [Vector2i(4, 4), Vector2i(5, 4), Vector2i(5, 5)], "costs": [300, 1400],
	},
	"detector": {
		"name": "探测仪", "description": "扩大多目标探测范围，后续解锁埋深区间与体积回波。",
		"values": [10, 16, 22, 28], "costs": [100, 500, 1500],
	},
	"excavation_range": {
		"name": "勘探范围", "description": "扩大下一趟的可开采区域，矿点随面积增加。",
		"values": [14.0, 18.0, 22.0, 26.0], "costs": [140, 450, 1100],
	},
	"museum_capacity": {
		"name": "展台扩建", "description": "增加可同时展示的藏品数量。",
		"values": [3, 4, 6], "costs": [600, 1800],
	},
	"museum_appeal": {
		"name": "展馆吸引力", "description": "用展品研究成果提高展览收益，下一趟出发时生效。",
		"values": [1.0, 1.35, 1.75, 2.25], "costs": [0, 0, 0], "research_costs": [3, 6, 9],
	},
}

const ZONES := [
	{
		"id": "meadow", "name": "月壤浅滩", "fee": 0, "count": 72,
		"description": "免费进场。晶簇大小分布均衡，适合积累资金。",
		"size_weights": [0.45, 0.35, 0.20], "burial": [0.10, 0.38], "exposed": 0.28,
		"wear_range": [0, 65], "relic_fraction": 0.20,
	},
	{
		"id": "salvage", "name": "碎晶洼地", "fee": 60, "count": 90,
		"description": "小件密集、露头多；磨损不高于 55%，适合快速装包。",
		"size_weights": [0.65, 0.28, 0.07], "burial": [0.06, 0.24], "exposed": 0.40,
		"wear_range": [0, 55], "relic_fraction": 0.18,
	},
	{
		"id": "deep", "name": "深埋矿脉", "fee": 120, "count": 48,
		"description": "大件和遗物较多、埋得更深；磨损不高于 30%，带回的品相更好。",
		"size_weights": [0.15, 0.30, 0.55], "burial": [0.35, 0.70], "exposed": 0.08,
		"wear_range": [0, 30], "relic_fraction": 0.33,
	},
]

var bank := DEFAULT_BANK
var levels := {"drill": 0, "mining_radius": 0, "oxygen": 0, "oxygen_supply": 0, "boots": 0, "backpack": 0, "detector": 0, "excavation_range": 0, "museum_capacity": 0, "museum_appeal": 0}
var research_points := 0
var museum_state := Museum.initial_state()
var trip_serial := 0
var active_trip: Dictionary = {}
var selected_zone := DEFAULT_ZONE
var last_report: Dictionary = {}
var last_save_error: Error = OK
var profile_path: String:
	get:
		return _save_path

var _save_path: String
var _blocked_save_error: Error = OK

func _init(path: String = "@default") -> void:
	_save_path = ("res://.demo-data/progression.cfg" if OS.has_feature("editor") else "user://progression.cfg") if path == "@default" else path

func load_profile() -> Error:
	if _save_path.is_empty() or not FileAccess.file_exists(_save_path):
		_blocked_save_error = OK
		last_save_error = OK
		return OK

	var config := ConfigFile.new()
	var error := config.load(_save_path)
	if error != OK:
		return _block_save(ERR_FILE_CORRUPT if error == ERR_PARSE_ERROR else error)

	var version: Variant = config.get_value("profile", "version", 0)
	var saved_bank: Variant = config.get_value("profile", "bank", -1)
	var saved_levels: Variant = config.get_value("profile", "levels", {})
	var saved_zone: Variant = config.get_value("profile", "selected_zone", "")
	var saved_report: Variant = config.get_value("profile", "last_report", {})
	if not version is int or version not in [1, 2, 3, 4, PROFILE_VERSION]:
		return _block_save(ERR_FILE_CORRUPT)
	if not _is_valid_profile(saved_bank, saved_levels, saved_zone, saved_report, version):
		return _block_save(ERR_FILE_CORRUPT)

	var migrated_levels: Dictionary = saved_levels.duplicate(true)
	if version == 1:
		migrated_levels["oxygen_supply"] = 0
	if version <= 2:
		migrated_levels["excavation_range"] = 0
	if version <= 3:
		migrated_levels["museum_capacity"] = 0
		migrated_levels["museum_appeal"] = 0
	if version <= 4:
		migrated_levels["mining_radius"] = 0
	var saved_research: Variant = config.get_value("profile", "research_points", 0)
	var saved_museum: Variant = config.get_value("profile", "museum", Museum.initial_state())
	var saved_serial: Variant = config.get_value("profile", "trip_serial", 0)
	var saved_trip: Variant = config.get_value("profile", "active_trip", {})
	if version >= 4:
		for key: String in ["research_points", "museum", "trip_serial", "active_trip"]:
			if not config.has_section_key("profile", key):
				return _block_save(ERR_FILE_CORRUPT)
		if not _valid_extended(saved_research, saved_museum, saved_serial, saved_trip, migrated_levels):
			return _block_save(ERR_FILE_CORRUPT)
	bank = saved_bank
	levels = migrated_levels
	research_points = int(saved_research) if version >= 4 else 0
	museum_state = saved_museum.duplicate(true) if version >= 4 else Museum.initial_state()
	trip_serial = int(saved_serial) if version >= 4 else 0
	active_trip = saved_trip.duplicate(true) if version >= 4 else {}
	selected_zone = saved_zone
	last_report = saved_report
	_blocked_save_error = OK
	last_save_error = OK
	return OK

func _block_save(error: Error) -> Error:
	_blocked_save_error = error
	last_save_error = error
	push_warning("无法载入局外存档，已保留原文件：%s" % error_string(error))
	return error

func save_profile() -> Error:
	last_save_error = _write_profile(bank, levels, selected_zone, last_report, research_points, museum_state, trip_serial, active_trip)
	return last_save_error

func stats() -> Dictionary:
	var bag: Vector2i = UPGRADES.backpack["values"][levels.backpack]
	var activity_radius: float = UPGRADES.excavation_range["values"][levels.excavation_range]
	return {
		"mining_time": UPGRADES.drill["values"][levels.drill],
		"mining_radius": UPGRADES.mining_radius["values"][levels.mining_radius],
		"oxygen": UPGRADES.oxygen["values"][levels.oxygen],
		"oxygen_supply_density": UPGRADES.oxygen_supply["values"][levels.oxygen_supply],
		"oxygen_recovery_limit": OXYGEN_RECOVERY_LIMITS[levels.oxygen_supply],
		"walk_speed": UPGRADES.boots["values"][levels.boots],
		"bag_columns": bag.x,
		"bag_rows": bag.y,
		"detector_level": levels.detector,
		"detector_range": UPGRADES.detector["values"][levels.detector],
		"activity_radius": activity_radius,
		"map_area_multiplier": pow(activity_radius / MAX_ACTIVITY_RADIUS, 2.0),
		"museum_capacity": int(UPGRADES.museum_capacity["values"][levels.get("museum_capacity", 0)]),
		"museum_appeal": float(UPGRADES.museum_appeal["values"][levels.get("museum_appeal", 0)]),
	}

func upgrade_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for id: String in UPGRADES:
		var upgrade: Dictionary = UPGRADES[id]
		var level: int = levels[id]
		var max_level: int = upgrade.costs.size()
		var available := level < max_level
		var cost: int = upgrade.costs[level] if available else 0
		var research_cost: int = upgrade.get("research_costs", [0, 0, 0])[level] if available else 0
		rows.append({
			"id": id, "name": upgrade.name, "description": upgrade.description,
			"level": level, "max_level": max_level, "cost": cost,
			"current": _stat_label(id, level),
			"next": _stat_label(id, level + 1) if available else "已满级",
			"research_cost": research_cost, "currency": "research" if upgrade.has("research_costs") else "money",
			"can_buy": available and bank >= cost and research_points >= research_cost and _blocked_save_error == OK,
		})
	return rows

func buy_upgrade(id: String) -> Dictionary:
	if not UPGRADES.has(id):
		return {"ok": false, "message": "找不到这项升级"}
	var upgrade: Dictionary = UPGRADES[id]
	var level: int = levels[id]
	if level >= upgrade.costs.size():
		return {"ok": false, "message": "%s已满级" % upgrade.name}
	var cost: int = upgrade.costs[level]
	var research_cost: int = upgrade.get("research_costs", [0, 0, 0])[level]
	if bank < cost:
		return {"ok": false, "message": "资金不足，还差 %d" % (cost - bank)}
	if research_points < research_cost:
		return {"ok": false, "message": "研究点不足，还差 %d" % (research_cost - research_points)}

	var next_levels := levels.duplicate()
	next_levels[id] = level + 1
	if _commit(bank - cost, next_levels, selected_zone, last_report, research_points - research_cost) != OK:
		return {"ok": false, "message": "无法保存升级，资金未扣除"}
	return {"ok": true, "message": "%s已升到 %d 级" % [upgrade.name, level + 1]}

func apply_debug_change(action: String, upgrade_id: String = "", value: int = 0) -> Dictionary:
	# Debug changes use the same persisted transaction as real purchases. Never
	# resize a live expedition's backpack/map or alter its exhibition snapshot.
	if not active_trip.is_empty():
		return {"ok": false, "message": "请先结算当前远征，再调整科技或资源", "error": ERR_BUSY}
	var next_bank := bank
	var next_research := research_points
	var next_levels := levels.duplicate(true)
	var next_museum := museum_state.duplicate(true)
	var message := ""
	match action:
		"grant_cash":
			if value <= 0 or value > MAX_BANK - bank:
				return {"ok": false, "message": "资金增量无效或超过余额上限", "error": ERR_INVALID_PARAMETER}
			next_bank += value
			message = "GM：资金 +%d" % value
		"grant_research":
			if value <= 0 or value > MAX_BANK - research_points:
				return {"ok": false, "message": "研究点增量无效或超过上限", "error": ERR_INVALID_PARAMETER}
			next_research += value
			message = "GM：研究点 +%d" % value
		"set_level":
			if not UPGRADES.has(upgrade_id) or value < 0 or value > UPGRADES[upgrade_id].costs.size():
				return {"ok": false, "message": "科技或目标等级无效", "error": ERR_INVALID_PARAMETER}
			next_levels[upgrade_id] = value
			message = "GM：%s设为 Lv.%d" % [UPGRADES[upgrade_id].name, value]
		"reset_levels", "max_levels":
			for id: String in UPGRADES:
				next_levels[id] = 0 if action == "reset_levels" else UPGRADES[id].costs.size()
			message = "GM：科技已归零，资金、研究点和仓库物品保留" if action == "reset_levels" else "GM：全部科技已满级，未扣除资金或研究点"
		_:
			return {"ok": false, "message": "未知科技调试操作", "error": ERR_INVALID_PARAMETER}
	var capacity := int(UPGRADES.museum_capacity["values"][int(next_levels.museum_capacity)])
	var returned := 0
	for slot in range(capacity, next_museum.slots.size()):
		if not str(next_museum.slots[slot]).is_empty():
			returned += 1
			next_museum.slots[slot] = ""
	if _commit(next_bank, next_levels, selected_zone, last_report, next_research, next_museum) != OK:
		return _failed_transaction("GM 保存失败，科技、资源和仓库物品均未改变")
	if returned > 0:
		message += "；%d 件展品已收回仓库" % returned
	return {"ok": true, "message": message, "returned_exhibits": returned}

func zones() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for zone: Dictionary in ZONES:
		result.append(_scaled_zone(zone))
	return result

func get_zone(id: String) -> Dictionary:
	for zone: Dictionary in ZONES:
		if zone.id == id:
			return _scaled_zone(zone)
	return {}

func _scaled_zone(zone: Dictionary) -> Dictionary:
	var result := zone.duplicate(true)
	var current := stats()
	result["max_count"] = int(zone.count)
	result["count"] = maxi(1, roundi(float(zone.count) * float(current.map_area_multiplier)))
	result["relic_count"] = clampi(roundi(float(result["count"]) * float(zone.relic_fraction)), 3, maxi(3, int(result["count"]) - 3))
	result["activity_radius"] = float(current.activity_radius)
	result["map_area_multiplier"] = float(current.map_area_multiplier)
	return result

func select_zone(id: String) -> bool:
	if get_zone(id).is_empty():
		return false
	return id == selected_zone or _commit(bank, levels, id, last_report) == OK

func pay_entry(id: String, free_entry: bool = false) -> Dictionary:
	var zone := get_zone(id)
	if zone.is_empty():
		return {"ok": false, "message": "找不到这个矿区", "fee": 0, "zone": zone}
	var fee: int = 0 if free_entry else zone.fee
	if bank < fee:
		return {"ok": false, "message": "入场资金不足，还差 %d" % (fee - bank), "fee": fee, "zone": zone}
	if trip_serial >= Museum.MAX_UID:
		return {"ok": false, "message": "远征编号达到上限", "fee": fee, "zone": zone}
	var next_trip := {"trip_id": trip_serial + 1, "fee": fee, "zone": str(zone.name), "zone_id": id, "income_snapshot": int(museum_summary().income)}
	if _commit(bank - fee, levels, id, last_report, research_points, museum_state, trip_serial + 1, next_trip) != OK:
		return {"ok": false, "message": "无法保存出舱记录，入场费未扣除", "fee": fee, "zone": zone}
	return {"ok": true, "message": "已进入%s" % zone.name, "fee": fee, "zone": zone, "trip_id": int(next_trip.trip_id), "income_snapshot": int(next_trip.income_snapshot)}

func credit(amount: int) -> void:
	if amount != 0:
		settle_reward(amount, last_report)

func record_report(report: Dictionary) -> void:
	settle_reward(0, report)

func settle_reward(amount: int, report: Dictionary) -> Error:
	if amount < 0 or amount > MAX_BANK - bank:
		last_save_error = ERR_INVALID_PARAMETER
		return last_save_error
	return _commit(bank + amount, levels, selected_zone, report)

func _stat_label(id: String, level: int) -> String:
	var value: Variant = UPGRADES[id]["values"][level]
	match id:
		"drill":
			return "%.2f 秒/次" % value
		"mining_radius":
			return "开采直径 %.2f 米" % (float(value) * 2.0)
		"oxygen":
			return "%d 秒" % value
		"oxygen_supply":
			return "密度 ×%.1f · 单趟补氧 %.0f 秒" % [float(value) / 0.25, OXYGEN_RECOVERY_LIMITS[level]]
		"boots":
			return "%.2f 米/秒" % value
		"backpack":
			return "%d × %d" % [value.x, value.y]
		"detector":
			var details := ["多目标方位", "扩大范围", "埋深区间", "体积回波"]
			return "%s · %d 米" % [details[level], value]
		"excavation_range":
			return "半径 %.0f 米" % value
		"museum_capacity":
			return "%d 个展台" % int(value)
		"museum_appeal":
			return "展览收益 ×%.2f" % float(value)
	return ""

func museum_summary() -> Dictionary:
	var current := stats()
	return Museum.summary(museum_state, int(current.museum_capacity), float(current.museum_appeal), research_points)

func donate_item(uid: int) -> Dictionary:
	var plan := Museum.plan_donation(museum_state, uid, int(stats().museum_capacity))
	if not plan.ok:
		return plan
	if _commit(bank, levels, selected_zone, last_report, research_points + int(plan.research), plan.state) != OK:
		return _failed_transaction("登记保存失败，物品仍在仓库待整理区")
	return {"ok": true, "message": plan.message, "research": int(plan.research), "key": plan.key, "replaced": plan.replaced}

func sell_item(uid: int) -> Dictionary:
	var plan := Museum.plan_sale(museum_state, uid)
	if not plan.ok:
		return plan
	if int(plan.income) > MAX_BANK - bank:
		return {"ok": false, "message": "资金达到上限，物品仍在仓库", "error": ERR_INVALID_PARAMETER}
	if _commit(bank + int(plan.income), levels, selected_zone, last_report, research_points, plan.state) != OK:
		return _failed_transaction("出售保存失败，物品与资金均未改变")
	return {"ok": true, "message": plan.message, "income": int(plan.income), "item": plan.item}

func place_exhibit(key: String, slot: int) -> Dictionary:
	var plan := Museum.plan_placement(museum_state, key, slot, int(stats().museum_capacity))
	if not plan.ok:
		return plan
	if _commit(bank, levels, selected_zone, last_report, research_points, plan.state) != OK:
		return _failed_transaction("布展保存失败，原展台已保留")
	return {"ok": true, "message": plan.message}

func reset_identification() -> Dictionary:
	var next := museum_state.duplicate(true)
	next.identified_types.clear()
	if _commit(bank, levels, selected_zone, last_report, research_points, next) != OK:
		return _failed_transaction("鉴定重置保存失败，原记录已保留")
	return {"ok": true, "message": "已重置鉴定记录，仓库物品和已登记展品保留"}

func settle_expedition(trip_id: int, cargo: Array, emergency: bool, active_seconds: float, extra_report: Dictionary = {}) -> Dictionary:
	if active_trip.is_empty() or trip_id != int(active_trip.trip_id):
		return {"ok": false, "message": "这趟远征已经结算或编号无效", "error": ERR_DOES_NOT_EXIST}
	if not is_finite(active_seconds) or active_seconds < 0.0 or cargo.size() > 100:
		return {"ok": false, "message": "远征记录无效，物品仍在背包", "error": ERR_INVALID_PARAMETER}
	var next_museum := museum_state.duplicate(true)
	var stored := 0
	var cargo_uids: Array = []
	if not emergency:
		var plan := Museum.append_cargo(museum_state, cargo)
		if not plan.ok:
			return plan
		next_museum = plan.state
		stored = cargo.size()
		cargo_uids = plan.uids
	var income := 0
	if not emergency and active_seconds >= Museum.MIN_INCOME_SECONDS:
		income = floori(float(active_trip.income_snapshot) * clampf(active_seconds / Museum.INCOME_PERIOD, 0.0, 1.0))
	# Passive exhibition income must not trap a cash-capped player outside with
	# real cargo. Credit only the available cash room and still store the finds.
	var income_overflow := maxi(0, income - (MAX_BANK - bank))
	income -= income_overflow
	var fee := int(active_trip.fee)
	var text := "展馆收入 %d · 门票 %d · 净收益 %+d\n" % [income, fee, income - fee]
	text += "%d 件物品遗落，仓库物品与已登记展品保留" % cargo.size() if emergency else "%d 件物品已存入仓库，等待登记或出售" % stored
	if income_overflow > 0:
		text += "\n余额达到上限，展馆收入 %d 未入账" % income_overflow
	if not emergency and active_seconds < Museum.MIN_INCOME_SECONDS and int(active_trip.income_snapshot) > 0:
		text += "\n远征不足 10 秒，本次不结算展馆收入"
	var report := extra_report.duplicate(true)
	report.merge({"text": text, "income": income, "fee": fee, "net": income - fee, "cargo_count": stored,
		"lost_count": cargo.size() if emergency else 0, "emergency": emergency, "zone": str(active_trip.zone),
		"trip_id": trip_id, "active_seconds": active_seconds, "income_overflow": income_overflow}, true)
	if _commit(bank + income, levels, selected_zone, report, research_points, next_museum, trip_serial, {}) != OK:
		return _failed_transaction("回舱保存失败，远征未结算，物品仍在背包")
	return {"ok": true, "message": "紧急救援，已保留仓库物品与展品" if emergency else "安全回舱，物品已存入仓库", "stored": stored, "income": income, "report": report.duplicate(true), "cargo_uids": cargo_uids}

func _failed_transaction(message: String) -> Dictionary:
	return {"ok": false, "message": message, "error": last_save_error}

func _commit(next_bank: int, next_levels: Dictionary, next_zone: String, next_report: Dictionary, next_research: int = -1, next_museum: Dictionary = {}, next_serial: int = -1, next_trip: Variant = null) -> Error:
	var research := research_points if next_research < 0 else next_research
	var museum := museum_state if next_museum.is_empty() else next_museum
	var serial := trip_serial if next_serial < 0 else next_serial
	var trip: Dictionary = active_trip if next_trip == null else next_trip
	last_save_error = _write_profile(next_bank, next_levels, next_zone, next_report, research, museum, serial, trip)
	if last_save_error == OK:
		bank = next_bank
		levels = next_levels.duplicate(true)
		selected_zone = next_zone
		last_report = next_report.duplicate(true)
		research_points = research
		museum_state = museum.duplicate(true)
		trip_serial = serial
		active_trip = trip.duplicate(true)
	return last_save_error

func _write_profile(next_bank: int, next_levels: Dictionary, next_zone: String, next_report: Dictionary, next_research: int, next_museum: Dictionary, next_serial: int, next_trip: Dictionary) -> Error:
	if _blocked_save_error != OK:
		return _blocked_save_error
	if not _is_valid_profile(next_bank, next_levels, next_zone, next_report):
		return ERR_INVALID_PARAMETER
	if not _valid_extended(next_research, next_museum, next_serial, next_trip, next_levels):
		return ERR_INVALID_PARAMETER
	if _save_path.is_empty():
		return OK

	var absolute_path := ProjectSettings.globalize_path(_save_path)
	var parent := absolute_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(parent):
		var make_error := DirAccess.make_dir_recursive_absolute(parent)
		if make_error != OK:
			return make_error

	var config := ConfigFile.new()
	config.set_value("profile", "version", PROFILE_VERSION)
	config.set_value("profile", "bank", next_bank)
	config.set_value("profile", "levels", next_levels)
	config.set_value("profile", "selected_zone", next_zone)
	config.set_value("profile", "last_report", next_report)
	config.set_value("profile", "research_points", next_research)
	config.set_value("profile", "museum", next_museum)
	config.set_value("profile", "trip_serial", next_serial)
	config.set_value("profile", "active_trip", next_trip)

	var temporary := "%s.%d.tmp" % [absolute_path, OS.get_process_id()]
	var error := config.save(temporary)
	if error == OK:
		error = DirAccess.rename_absolute(temporary, absolute_path)
	if error != OK and FileAccess.file_exists(temporary):
		DirAccess.remove_absolute(temporary)
	return error

func _is_valid_profile(saved_bank: Variant, saved_levels: Variant, saved_zone: Variant, saved_report: Variant, version: int = PROFILE_VERSION) -> bool:
	if version not in [1, 2, 3, 4, PROFILE_VERSION]:
		return false
	if not saved_bank is int or saved_bank < 0 or saved_bank > MAX_BANK:
		return false
	var required_count := UPGRADES.size() - (1 if version <= 4 else 0) - (2 if version <= 3 else 0) - (1 if version <= 2 else 0) - (1 if version == 1 else 0)
	if not saved_levels is Dictionary or saved_levels.size() != required_count:
		return false
	for id: String in UPGRADES:
		if version <= 4 and id == "mining_radius":
			continue
		if version == 1 and id == "oxygen_supply":
			continue
		if version <= 2 and id == "excavation_range":
			continue
		if version <= 3 and id in ["museum_capacity", "museum_appeal"]:
			continue
		var level: Variant = saved_levels.get(id)
		if not level is int or level < 0 or level > UPGRADES[id].costs.size():
			return false
	return saved_zone is String and _known_zone(saved_zone) and saved_report is Dictionary

func _known_zone(id: String) -> bool:
	for zone: Dictionary in ZONES:
		if zone.id == id:
			return true
	return false

func _valid_extended(saved_research: Variant, saved_museum: Variant, saved_serial: Variant, saved_trip: Variant, saved_levels: Dictionary) -> bool:
	if not saved_research is int or saved_research < 0 or saved_research > MAX_BANK:
		return false
	var capacity := int(UPGRADES.museum_capacity["values"][int(saved_levels.get("museum_capacity", 0))])
	if not Museum.is_valid_state(saved_museum, capacity):
		return false
	if not saved_serial is int or saved_serial < 0 or saved_serial > Museum.MAX_UID or not saved_trip is Dictionary:
		return false
	if saved_trip.is_empty():
		return true
	if saved_trip.size() != 5:
		return false
	for key: String in ["trip_id", "fee", "zone", "zone_id", "income_snapshot"]:
		if not saved_trip.has(key):
			return false
	if not saved_trip.trip_id is int or saved_trip.trip_id != saved_serial or saved_trip.trip_id < 1:
		return false
	if not saved_trip.zone_id is String or not _known_zone(saved_trip.zone_id) or not saved_trip.zone is String:
		return false
	if not saved_trip.fee is int or saved_trip.fee < 0 or saved_trip.fee > 120:
		return false
	return saved_trip.income_snapshot is int and saved_trip.income_snapshot >= 0 and saved_trip.income_snapshot <= MAX_BANK
