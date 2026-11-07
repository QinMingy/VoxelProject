extends SceneTree

# Reproducible accounting and forecasts. Cargo acquisition is an explicit
# assumption, not an automated human playtest or an excavation success model.
const Progression = preload("res://progression.gd")
const Museum = preload("res://museum.gd")
const Inventory = preload("res://inventory.gd")
const REPORT_PATH := "res://.build/economy-balance-report.json"
const MAX_FORECAST_TRIPS := 100
const ALL_KEYS := ["crystal_small", "crystal_medium", "crystal_large", "chest", "shield", "hammer"]
var failed := false

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, description: String) -> void:
	if not condition:
		failed = true
		push_error("ECONOMY REPORT FAIL: " + description)

func record(key: String, wear: int) -> Dictionary:
	var item := Museum.definition(key)
	item["wear"] = wear
	return item

func expected_value(key: String, max_wear: int) -> float:
	var total := 0
	for wear in range(max_wear + 1):
		total += Museum.item_value(record(key, wear))
	return float(total) / float(max_wear + 1)

func expected_exhibit_income(key: String, max_wear: int, copies: int, appeal: float) -> float:
	var total := 0.0
	# Best condition is the minimum of the independently drawn integer wears.
	for wear in range(max_wear + 1):
		var survival := float(max_wear - wear + 1) / float(max_wear + 1)
		var next_survival := float(max_wear - wear) / float(max_wear + 1)
		var probability := pow(survival, copies) - pow(next_survival, copies)
		total += probability * Museum.exhibit_income({"level": copies, "bestwear": wear, "item": Museum.definition(key)}, appeal)
	return total

func zone_report() -> Array:
	var rows: Array = []
	var profile := Progression.new("")
	for level in range(Progression.UPGRADES.excavation_range["values"].size()):
		profile.levels.excavation_range = level
		for zone_definition: Dictionary in Progression.ZONES:
			var zone := profile.get_zone(str(zone_definition.id))
			var proportions := {}
			var expected_total_value := 0.0
			var crystal_count := int(zone.count) - int(zone.relic_count)
			for tier in range(3):
				var key: String = ALL_KEYS[tier]
				# The first three are one specimen of each crystal size. Remaining
				# crystal sizes use the zone weights; relic allocation is cyclic.
				var expected_count := 1.0 + maxf(0.0, crystal_count - 3.0) * float(zone.size_weights[tier])
				proportions[key] = expected_count
				expected_total_value += expected_count * expected_value(key, int(zone.wear_range[1]))
			for tier in range(3):
				var key: String = ALL_KEYS[tier + 3]
				var expected_count := int(zone.relic_count) / 3 + (1 if tier < int(zone.relic_count) % 3 else 0)
				proportions[key] = expected_count
				expected_total_value += expected_count * expected_value(key, int(zone.wear_range[1]))
			rows.append({"zone": zone.id, "range_level": level, "activity_radius_m": zone.activity_radius,
				"count": zone.count, "relic_count": zone.relic_count, "actual_relic_fraction": float(zone.relic_count) / float(zone.count),
				"expected_type_counts_before_spawn_rejection": proportions,
				"expected_total_map_sale_value": expected_total_value,
				"expected_value_per_random_specimen": expected_total_value / float(zone.count),
				"note": "not attainable single-trip income; ignores local placement rejection and target selection preference"})
	return rows

func serial_value(value: Variant) -> Variant:
	return [value.x, value.y] if value is Vector2i else value

func magnitude(value: Variant) -> float:
	return float(value.x * value.y) if value is Vector2i else float(value)

func upgrade_report() -> Dictionary:
	var rows: Array = []
	var cash_total := 0
	var research_total := 0
	for id: String in Progression.UPGRADES:
		var upgrade: Dictionary = Progression.UPGRADES[id]
		var cumulative_cash := 0
		var cumulative_research := 0
		var stages: Array = []
		for level in range(upgrade.costs.size()):
			var current: Variant = upgrade["values"][level]
			var next: Variant = upgrade["values"][level + 1]
			var cost := int(upgrade.costs[level])
			var research := int(upgrade.get("research_costs", [0, 0, 0])[level])
			check(cost >= 0 and research >= 0 and cost + research > 0, "each upgrade has a nonzero declared currency cost: " + id)
			cumulative_cash += cost
			cumulative_research += research
			var ratio := magnitude(next) / magnitude(current)
			if id == "drill":
				ratio = 1.0 / ratio
			stages.append({"level": level + 1, "current": serial_value(current), "next": serial_value(next),
				"delta": magnitude(next) - magnitude(current), "benefit_ratio": ratio,
				"sphere_volume_ratio": pow(ratio, 3) if id == "mining_radius" else null,
				"cash_cost": cost, "research_cost": research,
				"cumulative_cash": cumulative_cash, "cumulative_research": cumulative_research})
		cash_total += cumulative_cash
		research_total += cumulative_research
		rows.append({"id": id, "name": upgrade.name, "levels": stages,
			"total_cash": cumulative_cash, "total_research": cumulative_research})
	return {"rows": rows, "all_cash_upgrades": cash_total, "all_research_upgrades": research_total}

func max_oxygen_cap(profile: RefCounted) -> float:
	# Use the stats contract from the same configuration as the running demo.
	return float(profile.stats().get("oxygen_recovery_limit", -1.0))

func full_bag_report() -> Array:
	var rows: Array = []
	for dimensions: Vector2i in Progression.UPGRADES.backpack["values"]:
		var bag := Inventory.new(dimensions.x, dimensions.y)
		var cargo: Array = []
		while bag.try_add(record("crystal_medium", 0)):
			cargo.append(record("crystal_medium", 0))
		while bag.try_add(record("crystal_small", 0)):
			cargo.append(record("crystal_small", 0))
		var perfect := 0
		var expected_by_zone := {}
		for item: Dictionary in cargo:
			perfect += Museum.item_value(item)
		for zone: Dictionary in Progression.ZONES:
			var expected := 0.0
			for item: Dictionary in cargo:
				expected += expected_value(str(item.key), int(zone.wear_range[1]))
			expected_by_zone[zone.id] = expected
		check(bag.used_cells() == dimensions.x * dimensions.y, "the upper-bound cargo is actually placeable and fills the bag")
		rows.append({"bag": [dimensions.x, dimensions.y], "plan": cargo.map(func(item: Dictionary): return item.key),
			"perfect_condition_max": perfect, "expected_if_this_composition_found": expected_by_zone,
			"bound_only": "assumes enough medium crystals can be discovered, mined and packed; not a per-trip yield forecast"})
	return rows

func exhibit_profile(level: int, best_wear: int, capacity: int) -> RefCounted:
	var profile := Progression.new("")
	profile.bank = 0
	profile.levels.museum_capacity = capacity
	for key: String in ALL_KEYS:
		for copy in range(level):
			var append := Museum.append_cargo(profile.museum_state, [record(key, best_wear)])
			check(append.ok, "fixture donation appends a real museum record")
			profile.museum_state = append.state
			check(profile.donate_item(int(append.uids[0])).ok, "fixture uses the real donation transaction")
	return profile

func best_display(profile: RefCounted) -> void:
	var keys: Array = profile.museum_state.exhibits.keys()
	var appeal := float(profile.stats().museum_appeal)
	keys.sort_custom(func(a: String, b: String):
		return Museum.exhibit_income(profile.museum_state.exhibits[a], appeal) > Museum.exhibit_income(profile.museum_state.exhibits[b], appeal))
	for index in range(mini(int(profile.stats().museum_capacity), keys.size())):
		check(profile.place_exhibit(str(keys[index]), index).ok, "exhibit placement is a valid transaction")

func scenario(id: String, zone_id: String, cargo_plan: Array, wear: int, donate_keys: Array, stage: int) -> Dictionary:
	var profile := Progression.new("") if stage == 0 else exhibit_profile(1 if stage == 1 else Museum.MAX_LEVEL, 25 if stage == 1 else 10, 0 if stage == 1 else Progression.UPGRADES.museum_capacity.costs.size())
	profile.bank = 10000
	if stage > 0:
		for upgrade_id: String in profile.levels:
			profile.levels[upgrade_id] = mini(stage, Progression.UPGRADES[upgrade_id].costs.size()) if stage == 1 else Progression.UPGRADES[upgrade_id].costs.size()
		best_display(profile)
	var bag := Inventory.new(int(profile.stats().bag_columns), int(profile.stats().bag_rows))
	var cargo: Array = []
	var gross := 0
	for key: String in cargo_plan:
		var item := record(key, wear)
		check(bag.try_add(item), "scenario cargo really fits its grid backpack: " + id)
		cargo.append(item)
		gross += Museum.item_value(item)
	var start_bank := int(profile.bank)
	var entry: Dictionary = profile.pay_entry(zone_id)
	check(entry.ok, "scenario entry is paid")
	var settle: Dictionary = profile.settle_expedition(int(entry.trip_id), cargo, false, 65.0)
	check(settle.ok, "scenario settlement stores cargo")
	var donation_opportunity_cost := 0
	var cash_sales := 0
	var research := 0
	for uid: int in settle.cargo_uids:
		var item := Museum.find_item(profile.museum_state, uid)
		if str(item.key) in donate_keys:
			var donation: Dictionary = profile.donate_item(uid)
			check(donation.ok, "scenario donation consumes the selected specimen")
			donation_opportunity_cost += Museum.item_value(item)
			research += int(donation.get("research", 0))
		else:
			var sale: Dictionary = profile.sell_item(uid)
			check(sale.ok, "scenario sale uses the real transaction")
			cash_sales += int(sale.get("income", 0))
	check(gross == cash_sales + donation_opportunity_cost, "donating never also sells the same cargo")
	return {"id": id, "zone": zone_id, "stage": stage, "bag_cells_used": bag.used_cells(),
		"wear_percent": wear, "cargo": cargo_plan, "active_seconds": 65.0,
		"cargo_sale_value_before_donations": gross, "donated_sale_value_consumed": donation_opportunity_cost,
		"research_earned": research, "sales": cash_sales, "exhibition_income": int(settle.income),
		"entry_fee": int(entry.fee), "net_cash_change": int(profile.bank) - start_bank,
		"assumption": "cargo plan and wear are illustrative inputs; discovery, aiming and route execution are not simulated"}

func forecast(spec: Dictionary) -> Dictionary:
	var profile := Progression.new("")
	var snapshots: Array = []
	var donated_sale_value := 0
	var earned_research := 0
	var sold_total := 0
	var museum_total := 0
	var fees_total := 0
	var purchase_total := 0
	var failed_trips := 0
	var lost_cargo_value := 0
	var target_cursor := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 618023
	var completed_at := -1
	for trip in range(1, MAX_FORECAST_TRIPS + 1):
		var zone_id := "meadow"
		if trip >= int(spec.paid_from_trip) and int(profile.bank) >= 300:
			zone_id = str(spec.later_zone)
		var entry := profile.pay_entry(zone_id)
		if not entry.ok:
			zone_id = "meadow"
			entry = profile.pay_entry(zone_id)
		check(entry.ok, "free recovery zone always remains accessible")
		var zone: Dictionary = entry.zone
		var stats := profile.stats()
		var bag := Inventory.new(int(stats.bag_columns), int(stats.bag_rows))
		var cargo: Array = []
		var ratio := 0.9 / float(stats.mining_time) * pow(float(stats.mining_radius) / 0.45, 1.5)
		# Deliberately conservative: only half the assumed route is mining. The
		# other half is search/movement/aiming and does not scale with the drill.
		var collection_seconds := float(spec.seconds_per_item) * (0.5 + 0.5 / ratio)
		var trip_seconds := maxf(10.0, float(stats.oxygen) - 5.0)
		var travel_seconds := 10.0 * 3.35 / float(stats.walk_speed)
		var count := mini(int(spec.base_items) + int(floor((ratio - 1.0) * float(spec.growth_factor))), floori((trip_seconds - travel_seconds) / collection_seconds))
		count = maxi(1, mini(count, int(zone.count)))
		for index in range(count):
			var key: String = ALL_KEYS[target_cursor % ALL_KEYS.size()]
			target_cursor += 1
			var item := record(key, rng.randi_range(int(zone.wear_range[0]), int(zone.wear_range[1])))
			if bag.try_add(item):
				cargo.append(item)
		var emergency := int(spec.get("fail_every", 0)) > 0 and trip % int(spec.get("fail_every", 1)) == 0
		var lost_value := 0
		if emergency:
			failed_trips += 1
			for item: Dictionary in cargo:
				lost_value += Museum.item_value(item)
			lost_cargo_value += lost_value
		var result := profile.settle_expedition(int(entry.trip_id), cargo, emergency, trip_seconds)
		check(result.ok, "forecast round uses a valid real settlement")
		if emergency:
			check(int(result.income) == 0 and result.cargo_uids.is_empty(), "fixed-pattern rescue earns neither exhibit income nor stored cargo")
		museum_total += int(result.income)
		fees_total += int(entry.fee)
		var donated_count := 0
		var sales := 0
		for uid: int in result.cargo_uids:
			var item := Museum.find_item(profile.museum_state, uid)
			var collection: Dictionary = profile.museum_state.exhibits.get(item.key, {})
			if collection.is_empty() or int(collection.level) < Museum.MAX_LEVEL:
				var donation := profile.donate_item(uid)
				check(donation.ok, "forecast first three copies are consumed by museum research")
				donated_sale_value += Museum.item_value(item)
				earned_research += int(donation.research)
				donated_count += 1
			else:
				var sale := profile.sell_item(uid)
				check(sale.ok, "forecast surplus specimen sale succeeds")
				sales += int(sale.get("income", 0))
		sold_total += sales
		best_display(profile)
		var purchases: Array = []
		# Keep enough money for the selected paid zone's next entrance. Before
		# paying for one, staying in the free map needs no artificial cash buffer.
		var reserve := int(zone.fee)
		while true:
			var candidates := profile.upgrade_rows()
			candidates.sort_custom(func(a: Dictionary, b: Dictionary):
				var cost_a := int(a.cost) + int(a.research_cost) * 100000
				var cost_b := int(b.cost) + int(b.research_cost) * 100000
				return str(a.id) < str(b.id) if cost_a == cost_b else cost_a < cost_b)
			var bought := false
			for row: Dictionary in candidates:
				if row.can_buy and int(profile.bank) - int(row.cost) >= reserve:
					check(profile.buy_upgrade(str(row.id)).ok, "forecast affordable upgrade transaction succeeds")
					purchase_total += int(row.cost)
					purchases.append("%s:%d" % [row.id, profile.levels[row.id]])
					bought = true
					break
			if not bought:
				break
		best_display(profile)
		var complete := true
		for id: String in profile.levels:
			complete = complete and int(profile.levels[id]) == Progression.UPGRADES[id].costs.size()
		snapshots.append({"trip": trip, "zone": zone_id, "cargo_count": cargo.size(), "donated_count": donated_count,
			"sales": sales, "exhibition": int(result.income), "fee": int(entry.fee),
			"failed_rescue": emergency, "lost_cargo_sale_value": lost_value,
			"bank": profile.bank, "research_balance": profile.research_points, "purchases": purchases,
			"active_seconds": trip_seconds, "museum_total_level": int(profile.museum_summary().total_level)})
		check(int(profile.bank) >= 0 and int(profile.research_points) >= 0, "forecasts cannot spend negative money or research")
		if complete:
			completed_at = trip
			break
	check(earned_research <= ALL_KEYS.size() * Museum.MAX_LEVEL, "research is finite and cannot be farmed from repeated sales")
	return {"id": spec.id, "assumptions": spec, "trips_to_all_upgrades": completed_at,
		"simulated_trips": snapshots.size(), "final_levels": profile.levels.duplicate(),
		"research_earned": earned_research, "research_remaining": profile.research_points,
		"donation_opportunity_cost": donated_sale_value, "sales_total": sold_total,
		"exhibition_total": museum_total, "fees_total": fees_total, "upgrade_spend": purchase_total,
		"failed_trips": failed_trips, "lost_cargo_sale_value": lost_cargo_value,
		"bank": profile.bank, "timeline": snapshots,
		"limitations": "deterministic rotating six-type finds; fixed rescue pattern if requested, not a probabilistic average; no missed targets or device input costs; conditional on cargo assumptions, not predicted player completion times"}

func safety_checks(research_cost: int, cash_cost: int) -> Dictionary:
	var minimum_per_zone: Array = []
	for zone: Dictionary in Progression.ZONES:
		var minimum := 2147483647
		for key: String in ALL_KEYS:
			minimum = mini(minimum, Museum.item_value(record(key, int(zone.wear_range[1]))))
		check(minimum > int(zone.fee), "one lowest-value specimen at worst allowed wear repays the entrance fee: " + str(zone.id))
		minimum_per_zone.append({"zone": zone.id, "fee": zone.fee, "minimum_single_sale": minimum,
			"one_sale_net": minimum - int(zone.fee)})
	var profile := Progression.new("")
	profile.bank = 1000
	var entry := profile.pay_entry("deep")
	var before_failure := int(profile.bank)
	var failure := profile.settle_expedition(int(entry.trip_id), [record("chest", 0)], true, 65.0)
	check(failure.ok and int(failure.income) == 0 and profile.museum_state.warehouse.is_empty(), "failed extraction loses cargo and earns no exhibition income")
	check(int(profile.bank) == before_failure and int(entry.fee) > 0, "failure does not refund the paid entrance fee")
	var empty := Progression.new("")
	empty.bank = 0
	check(not empty.pay_entry("deep").ok and empty.pay_entry("meadow").ok, "zero-money player is never barred from the free recovery map")
	check(research_cost == ALL_KEYS.size() * Museum.MAX_LEVEL, "all museum appeal research can be funded exactly by the existing catalogue")
	check(cash_cost > Progression.DEFAULT_BANK and cash_cost < Progression.MAX_BANK, "max upgrade bill is meaningful and below the supported cash ceiling")
	var max_profile := Progression.new("")
	for id: String in max_profile.levels:
		max_profile.levels[id] = Progression.UPGRADES[id].costs.size()
	var cap := max_oxygen_cap(max_profile)
	check(cap > 0.0 and cap <= float(max_profile.stats().oxygen) * 0.4, "maximum total oxygen recovery is finite and below 40 percent of tank duration")
	return {"single_item_fee_break_even": minimum_per_zone,
		"paid_failure_example": {"cash_change": -int(entry.fee), "lost_cargo_value": 800, "museum_income": 0},
		"total_research_available": ALL_KEYS.size() * Museum.MAX_LEVEL, "total_research_required": research_cost,
		"max_oxygen_recovery_seconds": cap, "max_tank_seconds": max_profile.stats().oxygen,
		"max_continuous_oxygen_seconds": float(max_profile.stats().oxygen) + cap,
		"idle_income_remains_possible": "safe active trips earn exhibition money without selling finds; earning is capped per expedition, not offline"}

func run() -> void:
	var upgrades := upgrade_report()
	var item_rows: Array = []
	for key: String in ALL_KEYS:
		var definition := Museum.definition(key)
		var zone_values := {}
		for zone: Dictionary in Progression.ZONES:
			zone_values[zone.id] = {"wear_range_inclusive": zone.wear_range,
				"expected_sale_exact_integer_rounding": expected_value(key, int(zone.wear_range[1])),
				"worst_sale": Museum.item_value(record(key, int(zone.wear_range[1])))}
		var income_levels: Array = []
		for level in range(1, Museum.MAX_LEVEL + 1):
			income_levels.append({"level": level, "perfect_base_appeal": Museum.exhibit_income({"level": level, "bestwear": 0, "item": definition}, 1.0),
				"perfect_max_appeal": Museum.exhibit_income({"level": level, "bestwear": 0, "item": definition}, float(Progression.UPGRADES.museum_appeal["values"][-1]))})
		var donation_economy := {}
		for zone: Dictionary in Progression.ZONES:
			var stages: Array = []
			var previous_income := 0.0
			for copies in range(1, Museum.MAX_LEVEL + 1):
				var expected_income := expected_exhibit_income(key, int(zone.wear_range[1]), copies, 1.0)
				var expected_max_appeal := expected_exhibit_income(key, int(zone.wear_range[1]), copies, float(Progression.UPGRADES.museum_appeal["values"][-1]))
				var sacrificed := expected_value(key, int(zone.wear_range[1])) * copies
				stages.append({"copies_consumed": copies, "sale_value_opportunity_cost": sacrificed,
					"expected_income_if_displayed_base_appeal": expected_income,
					"expected_income_if_displayed_max_appeal": expected_max_appeal,
					"simple_full_trip_cash_payback_base_appeal": sacrificed / expected_income,
					"marginal_donation_cash_payback_base_appeal": expected_value(key, int(zone.wear_range[1])) / (expected_income - previous_income)})
				previous_income = expected_income
			donation_economy[zone.id] = stages
		item_rows.append({"key": key, "base_value": definition.base_value,
			"footprint": serial_value(definition.footprint), "sales_by_zone": zone_values,
			"exhibition_per_65_seconds": income_levels, "donation_cash_opportunity_cost_and_payback": donation_economy,
			"payback_assumption": "continuously displayed during full65second safe trips; ignores research point utility and opportunity cost of occupied pedestal"})
	var scenarios := [
		scenario("starting", "meadow", ["crystal_small", "crystal_medium", "crystal_large", "crystal_small"], 32, ["crystal_small"], 0),
		scenario("middle", "salvage", ["crystal_small", "crystal_medium", "chest", "shield", "hammer"], 27, ["chest"], 1),
		scenario("full", "deep", ["chest", "chest", "crystal_large", "crystal_large", "hammer", "crystal_medium", "crystal_medium", "crystal_small"], 15, [], 2),
	]
	var forecasts: Array = []
	for spec: Dictionary in [
		{"id": "low", "base_items": 2, "seconds_per_item": 12.0, "growth_factor": 0.50, "paid_from_trip": 999, "later_zone": "meadow"},
		{"id": "typical", "base_items": 4, "seconds_per_item": 8.0, "growth_factor": 0.80, "paid_from_trip": 7, "later_zone": "salvage"},
		{"id": "high", "base_items": 6, "seconds_per_item": 5.0, "growth_factor": 1.25, "paid_from_trip": 7, "later_zone": "deep"},
	]:
		forecasts.append(forecast(spec))
		var failure_spec := spec.duplicate(true)
		failure_spec["id"] = str(spec.id) + "_fail_every5"
		failure_spec["fail_every"] = 5
		forecasts.append(forecast(failure_spec))
	var report := {"schema_version": 1, "source": "live Progression.UPGRADES/ZONES, Museum.CATEGORIES and real in-memory transactions",
		"assumptions": [
			"All expectations enumerate every integer wear value with the same probability, including both endpoints.",
			"Full bag values are packing bounds; illustrative trips state exact cargo and consumed donations.",
			"Progression forecasts cycle six known specimen types, donate the first three of each, then sell surplus.",
			"Forecast income snapshots are taken before departure, scale by safe active time and stop growing after 65 seconds.",
			"No model here proves human extraction rate, fun, or retention; empirical voxel excavation data remains a separate probe.",
			"Every-fifth-trip failure is a fixed sensitivity case (roughly20percent by count); it is not a Monte Carlo estimate or a measured player failure rate.",
		], "upgrades": upgrades, "items": item_rows, "zones_by_map_upgrade": zone_report(), "full_bag_bounds": full_bag_report(),
		"illustrative_safe_trips": scenarios, "forecasts": forecasts,
		"safety": safety_checks(int(upgrades.all_research_upgrades), int(upgrades.all_cash_upgrades))}
	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	check(file != null, "machine-readable report can be written")
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	if not failed:
		print("ECONOMY_BALANCE_OK cash_total=%d research_total=%d oxygen_cap=%.1f" % [upgrades.all_cash_upgrades, upgrades.all_research_upgrades, report.safety.max_oxygen_recovery_seconds])
		for row: Dictionary in scenarios:
			print("SCENARIO %s net_cash=%d donated_value=%d museum=%d fee=%d" % [row.id, row.net_cash_change, row.donated_sale_value_consumed, row.exhibition_income, row.entry_fee])
		for forecast_row: Dictionary in forecasts:
			print("FORECAST %s all_upgrades_trip=%d failures=%d lost=%d cash=%d museum=%d donations=%d" % [forecast_row.id, forecast_row.trips_to_all_upgrades, forecast_row.failed_trips, forecast_row.lost_cargo_sale_value, forecast_row.bank, forecast_row.exhibition_total, forecast_row.donation_opportunity_cost])
	quit(1 if failed else 0)
