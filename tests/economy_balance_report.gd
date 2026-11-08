extends SceneTree

# Reproducible accounting for the experience-based collection. Cargo acquisition
# is an explicit assumption, not an automated playtest or collection-rate model.
const Progression = preload("res://progression.gd")
const Museum = preload("res://museum.gd")
const REPORT_PATH := "res://.build/economy-balance-report.json"
var failed := false

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, description: String) -> void:
	if not condition:
		failed = true
		push_error("ECONOMY REPORT FAIL: " + description)

func upgrade_report() -> Dictionary:
	var rows: Array = []
	var cash_total := 0
	var research_total := 0
	for id: String in Progression.UPGRADES:
		var upgrade: Dictionary = Progression.UPGRADES[id]
		var cash := 0
		for cost: int in upgrade.costs:
			cash += cost
		var research := 0
		for cost: int in upgrade.get("research_costs", []):
			research += cost
		cash_total += cash
		research_total += research
		rows.append({"id": id, "name": str(upgrade.name), "total_cash": cash,
			"total_research": research, "levels": upgrade.values.size() - 1})
	return {"rows": rows, "all_cash": cash_total, "all_research": research_total}

func level_curve() -> Array:
	var rows: Array = []
	for level in range(1, Museum.MAX_LEVEL + 1):
		rows.append({"level": level, "copies": Museum.copies_for_level(level),
			"need_for_next": Museum.need_for(level)})
	return rows

func item_report() -> Array:
	var rows: Array = []
	for definition: Dictionary in Museum.CATEGORIES:
		var base := int(definition.base_value)
		rows.append({"key": str(definition.key), "label": str(definition.label), "base_value": base,
			"income_lv1_ap1": Museum.exhibit_income(1, base, 1.0),
			"income_lv1_ap225": Museum.exhibit_income(1, base, 2.25),
			"income_lv10_ap1": Museum.exhibit_income(10, base, 1.0),
			"income_lv10_ap225": Museum.exhibit_income(10, base, 2.25)})
	return rows

func zone_report() -> Array:
	var rows: Array = []
	for zone: Dictionary in Progression.ZONES:
		rows.append({"id": str(zone.id), "name": str(zone.name), "fee": int(zone.fee),
			"spawn_count": int(zone.count), "size_weights": zone.size_weights})
	return rows

func scenario(id: String, plan: Dictionary, appeal: float, capacity: int) -> Dictionary:
	var income := 0
	var levels: Dictionary = {}
	var copies := 0
	var index := 0
	for key: String in plan:
		var count := int(plan[key])
		copies += count
		var level := Museum.level_for(count)
		levels[key] = level
		if index < capacity:
			income += Museum.exhibit_income(level, int(Museum.definition(key).base_value), appeal)
		index += 1
	return {"id": id, "copies": copies, "levels": levels, "capacity": capacity,
		"displayed": mini(plan.size(), capacity), "appeal": appeal,
		"income_per_65s": income, "capped_income": plan.size() > capacity}

func run() -> void:
	var upgrades := upgrade_report()
	check(int(upgrades.all_cash) == 32520, "whole upgrade catalogue keeps its 32520 cash cost")
	check(int(upgrades.all_research) == 60, "museum appeal tiers cost exactly the sixty reachable research points")
	var items := item_report()
	for row: Dictionary in items:
		check(int(row.income_lv10_ap225) > int(row.income_lv1_ap1), "level ten out-earns level one for " + str(row.key))
	var curve := level_curve()
	check(int(curve[1].copies) == 3 and int(curve[Museum.MAX_LEVEL - 1].copies) == 55,
		"level thresholds are 2,3,4…10 more copies")
	var scenarios := [
		scenario("starting", {"crystal_small": 1, "crystal_medium": 1}, 1.0, 3),
		scenario("middle", {"chest": 6, "shield": 6, "hammer": 6, "crystal_large": 6}, 1.35, 4),
		scenario("full", {"crystal_small": 55, "crystal_medium": 55, "crystal_large": 55,
			"chest": 55, "shield": 55, "hammer": 55}, 2.25, 6),
		scenario("crowded", {"crystal_small": 55, "crystal_medium": 55, "crystal_large": 55,
			"chest": 55, "shield": 55, "hammer": 55}, 2.25, 3),
	]
	check(int(scenarios[0].income_per_65s) > 0, "a fresh collection already earns exhibition income")
	check(not bool(scenarios[1].capped_income) and not bool(scenarios[2].capped_income)
		and bool(scenarios[3].capped_income), "capacity caps which collected categories can earn")
	var report := {
		"schema_version": 2,
		"source": "live Progression.UPGRADES/ZONES and Museum.CATEGORIES",
		"assumptions": [
			"Copies are counted as total finds per category; level and experience are derived from that count.",
			"Income is paid once per safe return from a snapshot taken at departure, at most 65 seconds of out-of-base time.",
			"Only items displayed on unlocked stands count toward the snapshot.",
			"Research points come from first discoveries and level-ups, not from selling or donating.",
			"No model here proves human extraction rate, fun, or retention.",
		],
		"level_curve": curve,
		"upgrades": upgrades,
		"items": items,
		"zones": zone_report(),
		"scenarios": scenarios,
	}
	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	check(file != null, "machine-readable report can be written")
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	if not failed:
		print("ECONOMY_BALANCE_OK cash_total=%d research_total=%d max_level=%d copies_to_max=%d" % [
			int(upgrades.all_cash), int(upgrades.all_research), Museum.MAX_LEVEL,
			Museum.copies_for_level(Museum.MAX_LEVEL)])
		for row: Dictionary in scenarios:
			print("SCENARIO %s copies=%d displayed=%d appeal=%.2f income=%d" % [
				row.id, row.copies, row.displayed, float(row.appeal), int(row.income_per_65s)])
	quit(1 if failed else 0)
