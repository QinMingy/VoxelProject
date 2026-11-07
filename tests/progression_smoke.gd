extends SceneTree

const Progression = preload("res://progression.gd")
const Museum = preload("res://museum.gd")

var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_check_in_memory()
	var scratch := ProjectSettings.globalize_path(
		"res://.demo-data/progression-smoke-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	)
	if not DirAccess.dir_exists_absolute(scratch) and DirAccess.make_dir_recursive_absolute(scratch) == OK:
		_check_round_trip(scratch.path_join("profile.cfg"))
		_check_failed_save(scratch.path_join("unwritable.cfg"))
		_check_v1_migration(scratch.path_join("v1.cfg"))
		_check_v2_migration(scratch.path_join("v2.cfg"))
		_check_v3_migration(scratch.path_join("v3.cfg"))
		_check_v4_migration(scratch.path_join("v4.cfg"))
		_check_mining_radius(scratch.path_join("mining-radius.cfg"))
		_check_range_growth(scratch.path_join("range.cfg"))
		DirAccess.remove_absolute(scratch)
	else:
		_expect(false, "isolated test folder could not be created")
	for failure in _failures:
		push_error(failure)
	if _failures.is_empty():
		print("PROGRESSION_OK defaults, exact upgrade costs, oxygen supply, zone fees, round-trip, failed writes, corrupt protection, v1-v4 migrations, mining radius, range area scaling 14/18/22/26")
	quit(0 if _failures.is_empty() else 1)

func _check_in_memory() -> void:
	var profile := Progression.new("")
	_expect(profile.load_profile() == OK and profile.bank == 150 and profile.selected_zone == "meadow", "new profile defaults")
	var baseline := profile.stats()
	_expect(baseline.mining_time == 0.9 and baseline.oxygen == 65 and baseline.walk_speed == 3.35, "starting suit and tool stats")
	_expect(baseline.bag_columns == 4 and baseline.bag_rows == 4 and baseline.detector_range == 10, "starting backpack and detector stats")
	_expect(profile.upgrade_rows().size() == 10 and baseline.oxygen_supply_density == 0.25 and is_equal_approx(baseline.mining_radius, 0.45), "starting oxygen supply density, mining radius and ten upgrade rows")
	_expect(baseline.activity_radius == 14.0 and is_equal_approx(baseline.map_area_multiplier, 196.0 / 676.0), "starting range and area multiplier")
	_expect(not profile.buy_upgrade("missing").ok and not profile.buy_upgrade("oxygen").ok and profile.bank == 150, "unknown and unaffordable upgrades leave funds alone")
	_expect(profile.buy_upgrade("detector").ok and profile.bank == 50 and profile.stats().detector_level == 1 and profile.stats().detector_range == 16, "detector purchase applies first tier")
	profile.credit(4000)
	for index in range(3):
		_expect(profile.buy_upgrade("drill").ok, "buy drill level %d" % (index + 1))
	_expect(profile.stats().mining_time == 0.30 and profile.bank == 1030, "maximum drill stats and exact 3020 charges")
	_expect(not profile.buy_upgrade("drill").ok and profile.bank == 1030, "maximum tier refuses a fourth charge")
	var drill: Dictionary = profile.upgrade_rows()[0]
	_expect(drill.level == drill.max_level and not drill.can_buy and drill.cost == 0, "maxed shop row is disabled")
	profile.credit(-30)
	_expect(profile.bank == 1030 and profile.last_save_error == ERR_INVALID_PARAMETER, "negative credit is rejected")
	_expect(profile.buy_upgrade("oxygen_supply").ok and profile.bank == 850 and profile.stats().oxygen_supply_density == 0.40, "first oxygen supply upgrade costs 180")
	_expect(profile.buy_upgrade("oxygen_supply").ok and profile.bank == 100 and profile.stats().oxygen_supply_density == 0.60, "second oxygen supply upgrade costs 750")
	_expect(not profile.buy_upgrade("oxygen_supply").ok and profile.bank == 100, "unaffordable oxygen supply tier leaves funds alone")
	profile.credit(2100)
	_expect(profile.buy_upgrade("oxygen_supply").ok and profile.bank == 0 and profile.stats().oxygen_supply_density == 0.85, "maximum oxygen supply density")
	_expect(not profile.buy_upgrade("oxygen_supply").ok and profile.stats().oxygen == 65, "oxygen supply upgrades leave tank capacity independent")

	var wallet := Progression.new("")
	var zone_copy := wallet.get_zone("deep")
	zone_copy.burial[0] = 99
	_expect(wallet.get_zone("deep").burial[0] == 0.35, "zone data is isolated from callers")
	_expect(wallet.select_zone("deep") and wallet.bank == 150, "previewing a mine does not pay entry")
	var entry := wallet.pay_entry("deep")
	_expect(entry.ok and entry.fee == 120 and entry.zone.count == 14 and wallet.bank == 30, "deep fee unchanged and scaled mine count returned")
	_expect(not wallet.pay_entry("salvage").ok and wallet.bank == 30 and wallet.selected_zone == "deep", "unaffordable paid zone leaves active selection alone")
	_expect(not wallet.select_zone("missing") and not wallet.pay_entry("missing").ok, "unknown mine is rejected")
	_expect(wallet.pay_entry("meadow").ok and wallet.bank == 30, "free zone always available with low funds")

func _check_round_trip(path: String) -> void:
	var profile := Progression.new(path)
	_expect(profile.load_profile() == OK and not FileAccess.file_exists(path), "first load defers creating the save")
	_expect(profile.buy_upgrade("boots").ok, "first purchase creates the save")
	profile.credit(250)
	_expect(profile.pay_entry("salvage").ok, "replace the existing save on paid entry")
	var report := {"ordinary_ore": 7, "specimens": [{"value": 30}], "total": 37}
	_expect(profile.settle_reward(37, report) == OK, "income and report persist together")
	var reloaded := Progression.new(path)
	_expect(reloaded.load_profile() == OK and reloaded.bank == 237 and reloaded.selected_zone == "salvage", "save reopens with exact funds and zone")
	_expect(reloaded.levels.boots == 1 and reloaded.stats().walk_speed == 3.7 and reloaded.last_report == report, "save reopens with upgrades and nested report")

	var invalid := ConfigFile.new()
	_expect(invalid.load(path) == OK, "open isolated file before injecting corruption")
	invalid.set_value("profile", "bank", 1_000_000_000)
	_expect(invalid.save(path) == OK, "prepare invalid balance")
	var damaged := Progression.new(path)
	var content := FileAccess.get_file_as_string(path)
	_expect(damaged.load_profile() == ERR_FILE_CORRUPT and damaged.bank == 150, "implausible saved balance is rejected")
	_expect(not damaged.buy_upgrade("drill").ok and not damaged.pay_entry("deep").ok and damaged.bank == 150, "corrupt file blocks charges")
	_expect(damaged.settle_reward(8, {"total": 8}) != OK and damaged.bank == 150, "failed save leaves cash unchanged for an atomic retry")
	_expect(FileAccess.get_file_as_string(path) == content, "failed mutations preserve the corrupt file byte for byte")

	invalid.set_value("profile", "bank", 237)
	var bad_levels := reloaded.levels.duplicate()
	bad_levels["oxygen"] = 99
	invalid.set_value("profile", "levels", bad_levels)
	_expect(invalid.save(path) == OK and damaged.load_profile() == ERR_FILE_CORRUPT, "out-of-range saved upgrades are rejected")
	invalid.set_value("profile", "levels", reloaded.levels)
	invalid.set_value("profile", "version", 999)
	_expect(invalid.save(path) == OK and damaged.load_profile() == ERR_FILE_CORRUPT, "unknown save version is rejected")
	invalid.set_value("profile", "version", Progression.PROFILE_VERSION)
	_expect(invalid.save(path) == OK and damaged.load_profile() == OK and damaged.save_profile() == OK, "corrected profile can be reloaded and saved")
	DirAccess.remove_absolute(path)

func _check_failed_save(path: String) -> void:
	_expect(DirAccess.make_dir_absolute(path) == OK, "force rename failure with directory at target")
	var profile := Progression.new(path)
	_expect(not profile.buy_upgrade("drill").ok and profile.bank == 150 and profile.levels.drill == 0, "failed save rolls back a purchase")
	_expect(not profile.pay_entry("salvage").ok and profile.bank == 150 and profile.selected_zone == "meadow", "failed save rolls back paid entry")
	_expect(profile.settle_reward(12, {"total": 12}) != OK and profile.bank == 150 and profile.last_report.is_empty(), "failed settlement rolls back both cash and report")
	_expect(DirAccess.remove_absolute(path) == OK and profile.settle_reward(12, {"total": 12}) == OK, "same reward can be retried after the write failure is fixed")
	var reloaded := Progression.new(path)
	_expect(reloaded.load_profile() == OK and reloaded.bank == 162 and reloaded.last_report.total == 12, "retried save contains the reward and report")
	DirAccess.remove_absolute(path)

func _check_v1_migration(path: String) -> void:
	var legacy := ConfigFile.new()
	var old_levels := {"drill": 2, "oxygen": 1, "boots": 3, "backpack": 2, "detector": 1}
	var old_report := {"text": "legacy receipt", "total": 34}
	legacy.set_value("profile", "version", 1)
	legacy.set_value("profile", "bank", 700)
	legacy.set_value("profile", "levels", old_levels)
	legacy.set_value("profile", "selected_zone", "deep")
	legacy.set_value("profile", "last_report", old_report)
	_expect(legacy.save(path) == OK, "write isolated v1 fixture")
	var profile := Progression.new(path)
	var original := FileAccess.get_file_as_string(path)
	var expected_levels := old_levels.duplicate()
	expected_levels["oxygen_supply"] = 0
	expected_levels["excavation_range"] = 0
	expected_levels["museum_capacity"] = 0
	expected_levels["museum_appeal"] = 0
	expected_levels["mining_radius"] = 0
	_expect(profile.load_profile() == OK and profile.bank == 700 and profile.levels == expected_levels, "v1 preserves funds and old upgrades while adding baseline density and range")
	_expect(profile.selected_zone == "deep" and profile.last_report == old_report, "v1 preserves selected zone and report")
	_expect(FileAccess.get_file_as_string(path) == original, "reading v1 preserves the original file")
	_expect(profile.buy_upgrade("oxygen_supply").ok and profile.bank == 520, "new upgrade purchases can save the migrated profile")
	var saved := ConfigFile.new()
	_expect(saved.load(path) == OK and saved.get_value("profile", "version", 0) == 5, "first mutation writes v5")
	var reloaded := Progression.new(path)
	expected_levels["oxygen_supply"] = 1
	_expect(reloaded.load_profile() == OK and reloaded.bank == 520 and reloaded.levels == expected_levels, "v5 reload preserves the migrated and newly purchased levels")

	var invalid_levels := old_levels.duplicate()
	invalid_levels.erase("detector")
	invalid_levels["unknown"] = 0
	legacy.set_value("profile", "levels", invalid_levels)
	_expect(legacy.save(path) == OK and Progression.new(path).load_profile() == ERR_FILE_CORRUPT, "v1 migration rejects replacing a required upgrade with an unknown key")
	invalid_levels = old_levels.duplicate()
	invalid_levels["drill"] = 4
	legacy.set_value("profile", "levels", invalid_levels)
	_expect(legacy.save(path) == OK and Progression.new(path).load_profile() == ERR_FILE_CORRUPT, "v1 migration rejects illegal old upgrade levels")
	DirAccess.remove_absolute(path)

func _check_v2_migration(path: String) -> void:
	var legacy := ConfigFile.new()
	var old_levels := {"drill": 2, "oxygen": 1, "oxygen_supply": 2, "boots": 3, "backpack": 2, "detector": 1}
	var report := {"text": "density-era receipt", "income": 34, "net": -26}
	legacy.set_value("profile", "version", 2)
	legacy.set_value("profile", "bank", 977)
	legacy.set_value("profile", "levels", old_levels)
	legacy.set_value("profile", "selected_zone", "salvage")
	legacy.set_value("profile", "last_report", report)
	_expect(legacy.save(path) == OK, "write isolated v2 fixture")
	var original := FileAccess.get_file_as_string(path)
	var profile := Progression.new(path)
	var expected := old_levels.duplicate()
	expected["excavation_range"] = 0
	expected["museum_capacity"] = 0
	expected["museum_appeal"] = 0
	expected["mining_radius"] = 0
	_expect(profile.load_profile() == OK and profile.levels == expected and profile.bank == 977, "v2 preserves all six upgrades and cash while adding baseline range")
	_expect(profile.selected_zone == "salvage" and profile.last_report == report and profile.stats().activity_radius == 14.0, "v2 preserves report and region and receives smaller starting range")
	_expect(FileAccess.get_file_as_string(path) == original, "reading v2 does not rewrite the original file")
	_expect(profile.buy_upgrade("excavation_range").ok and profile.bank == 837, "range purchase saves migrated v2 progress")
	var saved := ConfigFile.new()
	_expect(saved.load(path) == OK and saved.get_value("profile", "version", 0) == 5, "v2 mutation writes v5")
	var reloaded := Progression.new(path)
	expected.excavation_range = 1
	_expect(reloaded.load_profile() == OK and reloaded.levels == expected and reloaded.bank == 837 and reloaded.stats().activity_radius == 18.0, "range purchase survives a process-style reload")

	var invalid := old_levels.duplicate()
	invalid.erase("oxygen_supply")
	invalid["excavation_range"] = 0
	legacy.set_value("profile", "levels", invalid)
	_expect(legacy.save(path) == OK and Progression.new(path).load_profile() == ERR_FILE_CORRUPT, "v2 rejects a missing density key replaced with future range")
	invalid = old_levels.duplicate()
	invalid["excavation_range"] = 0
	legacy.set_value("profile", "levels", invalid)
	_expect(legacy.save(path) == OK and Progression.new(path).load_profile() == ERR_FILE_CORRUPT, "v2 rejects unexpected future keys rather than silently overwriting them")
	DirAccess.remove_absolute(path)

func _check_v3_migration(path: String) -> void:
	var legacy := ConfigFile.new()
	var old_levels := {"drill": 1, "oxygen": 2, "oxygen_supply": 1, "boots": 2, "backpack": 1, "detector": 3, "excavation_range": 2}
	var report := {"text": "range-era receipt", "income": 124, "net": 64}
	legacy.set_value("profile", "version", 3)
	legacy.set_value("profile", "bank", 1940)
	legacy.set_value("profile", "levels", old_levels)
	legacy.set_value("profile", "selected_zone", "salvage")
	legacy.set_value("profile", "last_report", report)
	_expect(legacy.save(path) == OK, "write isolated v3 fixture")
	var original := FileAccess.get_file_as_string(path)
	var profile := Progression.new(path)
	var expected := old_levels.duplicate()
	expected.museum_capacity = 0
	expected.museum_appeal = 0
	expected.mining_radius = 0
	_expect(profile.load_profile() == OK and profile.bank == 1940 and profile.levels == expected, "v3 adds museum levels without changing any existing upgrades")
	_expect(profile.last_report == report and profile.selected_zone == "salvage" and profile.research_points == 0 and profile.museum_state.warehouse.is_empty() and profile.museum_state.exhibits.is_empty(), "legacy museum starts empty, with old report retained")
	_expect(FileAccess.get_file_as_string(path) == original, "v3 migration does not write on read")
	_expect(profile.buy_upgrade("museum_capacity").ok and profile.bank == 1340 and profile.stats().museum_capacity == 4, "migrated profile can buy museum space for 600 without affecting equipment")
	var restored := Progression.new(path)
	_expect(restored.load_profile() == OK and restored.bank == 1340 and restored.levels.museum_capacity == 1 and restored.levels.excavation_range == 2 and restored.levels.mining_radius == 0, "v5 persists migrated museum and existing range progress")
	var wrong := old_levels.duplicate()
	wrong.erase("boots")
	wrong["museum_appeal"] = 0
	legacy.set_value("profile", "levels", wrong)
	_expect(legacy.save(path) == OK and Progression.new(path).load_profile() == ERR_FILE_CORRUPT, "v3 rejects a missing legacy upgrade replaced by a museum key")
	DirAccess.remove_absolute(path)

func _check_range_growth(path: String) -> void:
	var profile := Progression.new(path)
	profile.credit(2000)
	var radii := [14.0, 18.0, 22.0, 26.0]
	var expected_counts := [[21, 26, 14], [35, 43, 23], [52, 64, 34], [72, 90, 48]]
	for level in range(radii.size()):
		var current := profile.stats()
		_expect(current.activity_radius == radii[level] and is_equal_approx(current.map_area_multiplier, pow(radii[level] / 26.0, 2.0)), "range level %d has its exact radius and area multiplier" % level)
		var zones := profile.zones()
		for index in range(zones.size()):
			var zone: Dictionary = zones[index]
			_expect(zone.count == expected_counts[level][index] and zone.activity_radius == radii[level], "range level %d scales region %s population with area" % [level, zone.id])
			_expect(profile.get_zone(zone.id) == zone, "selection list and entry source share range metadata")
			_expect(zone.fee == Progression.ZONES[index].fee and zone.max_count == Progression.ZONES[index].count, "range upgrades preserve fees and existing maximum population")
			zone.burial[0] = 99
			_expect(profile.get_zone(zone.id).burial[0] != 99, "scaled regions remain deeply isolated")
		if level < 3:
			_expect(profile.buy_upgrade("excavation_range").ok, "purchase range tier %d" % (level + 1))
	_expect(profile.bank == 460 and not profile.buy_upgrade("excavation_range").ok, "all range purchases charge 1690 total and refuse an extra tier")
	_expect(Progression.ZONES[0].count == 72 and Progression.ZONES[1].count == 90 and Progression.ZONES[2].count == 48, "maximum region populations are not mutated during scaling")
	var reloaded := Progression.new(path)
	_expect(reloaded.load_profile() == OK and reloaded.levels.excavation_range == 3 and reloaded.stats().activity_radius == 26.0 and reloaded.bank == 460, "maximum range and its balance persist")
	DirAccess.remove_absolute(path)

func _check_v4_migration(path: String) -> void:
	# Build a real collection/warehouse with stable specimen UIDs, then encode it
	# as a museum-era v4 profile. Legacy appeal purchases keep their earned level
	# and unspent points even though the new catalogue has different prices.
	var source := Progression.new("")
	source.bank = 6789
	source.levels.drill = 2
	source.levels.oxygen_supply = 1
	source.levels.museum_capacity = 2
	source.levels.museum_appeal = 3
	var records: Array = []
	for definition: Dictionary in Museum.CATEGORIES:
		for wear: int in [20, 10, 30]:
			var item := definition.duplicate(true)
			item["wear"] = wear
			records.append(item)
	var appended: Dictionary = Museum.append_cargo(source.museum_state, records)
	_expect(appended.ok, "v4 fixture creates real canonical specimens")
	source.museum_state = appended.state
	for uid: int in appended.uids:
		var donated: Dictionary = Museum.plan_donation(source.museum_state, uid, 6)
		_expect(donated.ok, "v4 fixture researches each of the six categories")
		source.museum_state = donated.state
	var spare := Museum.definition("hammer")
	spare["wear"] = 44
	appended = Museum.append_cargo(source.museum_state, [spare])
	_expect(appended.ok, "v4 fixture retains actual unsold warehouse cargo")
	source.museum_state = appended.state
	source.research_points = 6 # 18 earned minus the former 2 + 4 + 6 costs.
	source.trip_serial = 7
	source.selected_zone = "deep"
	source.last_report = {"text": "museum-era receipt", "income": 348, "nested": {"cargo": [2, 4]}}
	source.active_trip = {"trip_id": 7, "fee": 120, "zone": "深埋矿脉", "zone_id": "deep", "income_snapshot": 348}
	var config := ConfigFile.new()
	var old_levels: Dictionary = source.levels.duplicate()
	old_levels.erase("mining_radius")
	for key: String in ["bank", "research_points", "trip_serial", "selected_zone", "last_report", "active_trip"]:
		config.set_value("profile", key, source.get(key))
	config.set_value("profile", "version", 4)
	config.set_value("profile", "levels", old_levels)
	config.set_value("profile", "museum", source.museum_state)
	_expect(config.save(path) == OK, "write museum-era v4 profile")
	var original := FileAccess.get_file_as_string(path)
	var profile := Progression.new(path)
	var expected_levels := old_levels.duplicate()
	expected_levels["mining_radius"] = 0
	_expect(profile.load_profile() == OK and profile.bank == 6789 and profile.levels == expected_levels, "v4 adds only baseline mining radius and preserves all nine earned upgrade levels")
	_expect(profile.museum_state == source.museum_state and profile.research_points == 6, "v4 retains every warehouse UID, exhibit condition, display, identification and unspent research point")
	_expect(profile.active_trip == source.active_trip and profile.trip_serial == 7 and profile.last_report == source.last_report and profile.selected_zone == "deep", "v4 preserves outstanding entry payment, original income snapshot and settlement ledger")
	_expect(FileAccess.get_file_as_string(path) == original, "reading v4 preserves original bytes without automatic resave")
	_expect(profile.buy_upgrade("mining_radius").ok and profile.bank == 6609 and profile.levels.mining_radius == 1, "v4 upgrade costs only the newly purchased 180 and retains prior research purchases")
	var restored := Progression.new(path)
	_expect(restored.load_profile() == OK and restored.bank == 6609 and restored.levels.mining_radius == 1 and restored.levels.museum_appeal == 3 and restored.research_points == 6, "v5 reload preserves grandfathered appeal and new radius")
	_expect(restored.museum_state == source.museum_state and restored.active_trip == source.active_trip and restored.last_report == source.last_report, "v4-to-v5 mutation retains cargo and the outstanding trip exactly")
	var saved := ConfigFile.new()
	_expect(saved.load(path) == OK and saved.get_value("profile", "version", 0) == 5, "v4 mutation writes schema five")

	# Extended v4 data still requires validation; adding a radius must never
	# silently reset a corrupt collection or discard an outstanding trip.
	var bad_museum: Dictionary = source.museum_state.duplicate(true)
	bad_museum.warehouse[0]["world_id"] = 99
	config.set_value("profile", "museum", bad_museum)
	_expect(config.save(path) == OK, "write malformed museum-era cargo fixture")
	var broken := Progression.new(path)
	var damaged_text := FileAccess.get_file_as_string(path)
	_expect(broken.load_profile() == ERR_FILE_CORRUPT and broken.save_profile() != OK and FileAccess.get_file_as_string(path) == damaged_text, "v4 malformed cargo blocks migration writes and preserves bytes")
	config.set_value("profile", "museum", source.museum_state)
	var bad_trip: Dictionary = source.active_trip.duplicate()
	bad_trip.erase("income_snapshot")
	config.set_value("profile", "active_trip", bad_trip)
	_expect(config.save(path) == OK, "write malformed museum-era trip fixture")
	_expect(Progression.new(path).load_profile() == ERR_FILE_CORRUPT, "v4 rejects a malformed outstanding settlement ledger")
	DirAccess.remove_absolute(path)

func _check_mining_radius(path: String) -> void:
	var profile := Progression.new(path)
	profile.credit(4000)
	var radii := [0.45, 0.50, 0.55, 0.60]
	var expected_balances := [4150, 3970, 3120, 520]
	for level in range(4):
		_expect(is_equal_approx(profile.stats().mining_radius, radii[level]) and profile.bank == expected_balances[level], "mining radius tier %d has exact size and cumulative charge" % level)
		_expect(profile.levels.drill == 0 and profile.stats().mining_time == 0.9, "radius upgrade leaves cycle speed independent")
		if level < 3:
			_expect(profile.buy_upgrade("mining_radius").ok, "buy mining radius tier %d" % (level + 1))
	_expect(not profile.buy_upgrade("mining_radius").ok and profile.bank == 520, "max radius refuses a fourth charge after total3630")
	var restored := Progression.new(path)
	_expect(restored.load_profile() == OK and restored.levels.mining_radius == 3 and is_equal_approx(restored.stats().mining_radius, 0.60) and restored.bank == 520, "purchased radius and funds survive reload")
	var config := ConfigFile.new()
	_expect(config.load(path) == OK, "open radius save for malformed-level coverage")
	for invalid_level: Variant in [-1, 4, 1.5, "1"]:
		var levels: Dictionary = restored.levels.duplicate()
		levels.mining_radius = invalid_level
		config.set_value("profile", "levels", levels)
		_expect(config.save(path) == OK and Progression.new(path).load_profile() == ERR_FILE_CORRUPT, "invalid radius level %s is rejected" % str(invalid_level))
	DirAccess.remove_absolute(path)

func _expect(condition: bool, context: String) -> void:
	if not condition:
		_failures.append(context)
