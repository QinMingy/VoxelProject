extends RefCounted

const PROFILE_VERSION := 2
const DEFAULT_BANK := 150
const MAX_BANK := 10_000_000
const DEFAULT_ZONE := "meadow"

const UPGRADES := {
	"drill": {
		"name": "电镐", "description": "缩短每次开采的蓄力时间。",
		"values": [0.9, 0.65, 0.45, 0.30], "costs": [120, 320, 800],
	},
	"oxygen": {
		"name": "氧气瓶", "description": "提高每次出舱的氧气上限。",
		"values": [65, 75, 85, 95], "costs": [160, 400, 900],
	},
	"oxygen_supply": {
		"name": "氧矿密度", "description": "提高下一趟矿区氧矿的出现数量；每粒补氧量不变。",
		"values": [0.25, 0.40, 0.60, 0.85], "costs": [180, 420, 900],
	},
	"boots": {
		"name": "推进靴", "description": "提高步行速度，缩短返舱路程耗时。",
		"values": [3.35, 3.7, 4.05, 4.4], "costs": [140, 360, 850],
	},
	"backpack": {
		"name": "标本背包", "description": "扩大格子面积，容纳更多完整标本。",
		"values": [Vector2i(4, 4), Vector2i(5, 4), Vector2i(5, 5)], "costs": [220, 600],
	},
	"detector": {
		"name": "探测仪", "description": "扩大多目标探测范围，后续解锁埋深区间与体积回波。",
		"values": [10, 16, 22, 28], "costs": [100, 280, 650],
	},
}

const ZONES := [
	{
		"id": "meadow", "name": "月壤浅滩", "fee": 0, "count": 72,
		"description": "免费进场。晶簇大小分布均衡，适合积累资金。",
		"size_weights": [0.45, 0.35, 0.20], "burial": [0.10, 0.38], "exposed": 0.28,
	},
	{
		"id": "salvage", "name": "碎晶洼地", "fee": 60, "count": 90,
		"description": "小件密集，露头多，适合在短时间内搜集标本。",
		"size_weights": [0.65, 0.28, 0.07], "burial": [0.06, 0.24], "exposed": 0.40,
	},
	{
		"id": "deep", "name": "深埋矿脉", "fee": 120, "count": 48,
		"description": "矿脉稀疏，大件较多，通常要挖得更深才能取出。",
		"size_weights": [0.15, 0.30, 0.55], "burial": [0.35, 0.70], "exposed": 0.08,
	},
]

var bank := DEFAULT_BANK
var levels := {"drill": 0, "oxygen": 0, "oxygen_supply": 0, "boots": 0, "backpack": 0, "detector": 0}
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
	if not version is int or (version != 1 and version != PROFILE_VERSION):
		return _block_save(ERR_FILE_CORRUPT)
	if not _is_valid_profile(saved_bank, saved_levels, saved_zone, saved_report, version):
		return _block_save(ERR_FILE_CORRUPT)

	bank = saved_bank
	levels = saved_levels
	if version == 1:
		levels["oxygen_supply"] = 0
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
	last_save_error = _write_profile(bank, levels, selected_zone, last_report)
	return last_save_error

func stats() -> Dictionary:
	var bag: Vector2i = UPGRADES.backpack["values"][levels.backpack]
	return {
		"mining_time": UPGRADES.drill["values"][levels.drill],
		"oxygen": UPGRADES.oxygen["values"][levels.oxygen],
		"oxygen_supply_density": UPGRADES.oxygen_supply["values"][levels.oxygen_supply],
		"walk_speed": UPGRADES.boots["values"][levels.boots],
		"bag_columns": bag.x,
		"bag_rows": bag.y,
		"detector_level": levels.detector,
		"detector_range": UPGRADES.detector["values"][levels.detector],
	}

func upgrade_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for id: String in UPGRADES:
		var upgrade: Dictionary = UPGRADES[id]
		var level: int = levels[id]
		var max_level: int = upgrade.costs.size()
		var available := level < max_level
		var cost: int = upgrade.costs[level] if available else 0
		rows.append({
			"id": id, "name": upgrade.name, "description": upgrade.description,
			"level": level, "max_level": max_level, "cost": cost,
			"current": _stat_label(id, level),
			"next": _stat_label(id, level + 1) if available else "已满级",
			"can_buy": available and bank >= cost and _blocked_save_error == OK,
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
	if bank < cost:
		return {"ok": false, "message": "资金不足，还差 %d" % (cost - bank)}

	var next_levels := levels.duplicate()
	next_levels[id] = level + 1
	if _commit(bank - cost, next_levels, selected_zone, last_report) != OK:
		return {"ok": false, "message": "无法保存升级，资金未扣除"}
	return {"ok": true, "message": "%s已升到 %d 级" % [upgrade.name, level + 1]}

func zones() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for zone: Dictionary in ZONES:
		result.append(zone.duplicate(true))
	return result

func get_zone(id: String) -> Dictionary:
	for zone: Dictionary in ZONES:
		if zone.id == id:
			return zone.duplicate(true)
	return {}

func select_zone(id: String) -> bool:
	if get_zone(id).is_empty():
		return false
	return id == selected_zone or _commit(bank, levels, id, last_report) == OK

func pay_entry(id: String) -> Dictionary:
	var zone := get_zone(id)
	if zone.is_empty():
		return {"ok": false, "message": "找不到这个矿区", "fee": 0, "zone": zone}
	var fee: int = zone.fee
	if bank < fee:
		return {"ok": false, "message": "入场资金不足，还差 %d" % (fee - bank), "fee": fee, "zone": zone}
	if _commit(bank - fee, levels, id, last_report) != OK:
		return {"ok": false, "message": "无法保存出舱记录，入场费未扣除", "fee": fee, "zone": zone}
	return {"ok": true, "message": "已进入%s" % zone.name, "fee": fee, "zone": zone}

func credit(amount: int) -> void:
	if amount != 0:
		settle_reward(amount, last_report)

func record_report(report: Dictionary) -> void:
	settle_reward(0, report)

func settle_reward(amount: int, report: Dictionary) -> Error:
	if amount < 0 or amount > MAX_BANK - bank:
		last_save_error = ERR_INVALID_PARAMETER
		return last_save_error
	bank += amount
	last_report = report.duplicate(true)
	if save_profile() != OK:
		push_warning("远征收益已记入本次游戏，暂未写入存档：%s" % error_string(last_save_error))
	return last_save_error

func _stat_label(id: String, level: int) -> String:
	var value: Variant = UPGRADES[id]["values"][level]
	match id:
		"drill":
			return "%.2f 秒/次" % value
		"oxygen":
			return "%d 秒" % value
		"oxygen_supply":
			return "密度 ×%.1f" % (float(value) / 0.25)
		"boots":
			return "%.2f 米/秒" % value
		"backpack":
			return "%d × %d" % [value.x, value.y]
		"detector":
			var details := ["多目标方位", "扩大范围", "埋深区间", "体积回波"]
			return "%s · %d 米" % [details[level], value]
	return ""

func _commit(next_bank: int, next_levels: Dictionary, next_zone: String, next_report: Dictionary) -> Error:
	last_save_error = _write_profile(next_bank, next_levels, next_zone, next_report)
	if last_save_error == OK:
		bank = next_bank
		levels = next_levels
		selected_zone = next_zone
		last_report = next_report.duplicate(true)
	return last_save_error

func _write_profile(next_bank: int, next_levels: Dictionary, next_zone: String, next_report: Dictionary) -> Error:
	if _blocked_save_error != OK:
		return _blocked_save_error
	if not _is_valid_profile(next_bank, next_levels, next_zone, next_report):
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

	var temporary := "%s.%d.tmp" % [absolute_path, OS.get_process_id()]
	var error := config.save(temporary)
	if error == OK:
		error = DirAccess.rename_absolute(temporary, absolute_path)
	if error != OK and FileAccess.file_exists(temporary):
		DirAccess.remove_absolute(temporary)
	return error

func _is_valid_profile(saved_bank: Variant, saved_levels: Variant, saved_zone: Variant, saved_report: Variant, version: int = PROFILE_VERSION) -> bool:
	if not saved_bank is int or saved_bank < 0 or saved_bank > MAX_BANK:
		return false
	var required_count := UPGRADES.size() - (1 if version == 1 else 0)
	if not saved_levels is Dictionary or saved_levels.size() != required_count:
		return false
	for id: String in UPGRADES:
		if version == 1 and id == "oxygen_supply":
			continue
		var level: Variant = saved_levels.get(id)
		if not level is int or level < 0 or level > UPGRADES[id].costs.size():
			return false
	return saved_zone is String and not get_zone(saved_zone).is_empty() and saved_report is Dictionary
