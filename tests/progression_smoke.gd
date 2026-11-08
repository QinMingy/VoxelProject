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
		_check_retired_profiles(scratch)
		_check_v6_migration(scratch.path_join("v6.cfg"))
		_check_mining_radius(scratch.path_join("mining-radius.cfg"))
		_check_range_growth(scratch.path_join("range.cfg"))
		DirAccess.remove_absolute(scratch)
	else:
		_expect(false, "isolated test folder could not be created")
	for failure in _failures:
		push_error(failure)
	if _failures.is_empty():
		print("PROGRESSION_OK defaults, exact upgrade costs, oxygen supply, zone fees, round-trip, failed writes, corrupt protection, v1-v5 profile retirement, mining radius, range area scaling 14/18/22/26")
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
	_expect(profile.touch_layout.is_empty(), "fresh profile has no custom touch layout")
	var layout := {"jump": {"x": 0.8, "y": 0.8, "scale": 1.2}}
	_expect(profile.set_touch_layout(layout).ok and profile.touch_layout == layout, "touch layout saves into the profile")
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
	var layout := {"joystick": {"x": 0.15, "y": 0.75, "scale": 1.1}}
	_expect(reloaded.set_touch_layout(layout).ok, "touch layout persists through the real transaction")
	var layout_reloaded := Progression.new(path)
	_expect(layout_reloaded.load_profile() == OK and layout_reloaded.touch_layout == layout, "touch layout survives a process-style reload")

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

func _check_retired_profiles(directory: String) -> void:
	# Every pre-experience profile is retired: keep a byte-exact backup, start a
	# fresh run in memory, and never rewrite the old file just by loading it.
	for version: int in [1, 3, 5]:
		var path := directory.path_join("retired-v%d.cfg" % version)
		var legacy := ConfigFile.new()
		legacy.set_value("profile", "version", version)
		legacy.set_value("profile", "bank", 6789)
		legacy.set_value("profile", "levels", {"drill": 2, "oxygen": 1, "boots": 3, "backpack": 2, "detector": 1, "oxygen_supply": 1, "excavation_range": 1, "mining_radius": 1, "museum_capacity": 1, "museum_appeal": 1})
		legacy.set_value("profile", "selected_zone", "deep")
		legacy.set_value("profile", "last_report", {"text": "legacy"})
		if version >= 4:
			legacy.set_value("profile", "research_points", 6)
			legacy.set_value("profile", "museum", {"warehouse": [], "exhibits": {}, "slots": ["", "", "", "", "", ""], "next_uid": 1, "identified_types": []})
			legacy.set_value("profile", "trip_serial", 7)
			legacy.set_value("profile", "active_trip", {})
		_expect(legacy.save(path) == OK, "write retired v%d profile" % version)
		var original := FileAccess.get_file_as_string(path)
		var profile := Progression.new(path)
		_expect(profile.load_profile() == OK, "v%d profile loads as a fresh run" % version)
		_expect(profile.bank == Progression.DEFAULT_BANK and profile.research_points == 0 and profile.museum_state == Museum.initial_state(), "v%d discards the old collection and currencies" % version)
		_expect(profile.levels.drill == 0 and profile.levels.museum_appeal == 0 and profile.selected_zone == Progression.DEFAULT_ZONE, "v%d discards old upgrades and selection" % version)
		_expect(profile.active_trip.is_empty() and profile.last_report.is_empty() and profile.trip_serial == 0, "v%d discards the old settlement ledger" % version)
		_expect(FileAccess.get_file_as_string(path) == original, "v%d load does not rewrite the retired file" % version)
		var backup := "%s.v%d.bak" % [path, version]
		_expect(FileAccess.file_exists(backup) and FileAccess.get_file_as_string(backup) == original, "v%d keeps a byte-exact backup beside the new save" % version)
		profile.credit(500)
		_expect(profile.buy_upgrade("boots").ok, "fresh run can save after retirement")
		var saved := ConfigFile.new()
		_expect(saved.load(path) == OK and saved.get_value("profile", "version", 0) == Progression.PROFILE_VERSION, "next save writes the current schema")
		DirAccess.remove_absolute(backup)
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

func _check_v6_migration(path: String) -> void:
	var legacy := ConfigFile.new()
	legacy.set_value("profile", "version", 6)
	legacy.set_value("profile", "bank", 4321)
	legacy.set_value("profile", "levels", {"drill": 1, "mining_radius": 1, "oxygen": 2, "oxygen_supply": 1, "boots": 1, "backpack": 1, "detector": 2, "excavation_range": 1, "museum_capacity": 2, "museum_appeal": 1})
	legacy.set_value("profile", "selected_zone", "deep")
	legacy.set_value("profile", "research_points", 7)
	legacy.set_value("profile", "museum", {"items": {"crystal_small": {"key": "crystal_small", "copies": 6}}, "slots": ["crystal_small", "", "", "", "", ""]})
	legacy.set_value("profile", "trip_serial", 3)
	legacy.set_value("profile", "active_trip", {})
	legacy.set_value("profile", "last_report", {"text": "v6 receipt"})
	_expect(legacy.save(path) == OK, "write v6 fixture")
	var profile := Progression.new(path)
	_expect(profile.load_profile() == OK, "v6 profile migrates instead of retiring")
	_expect(profile.bank == 4321 and profile.research_points == 7 and profile.levels.museum_capacity == 2,
		"v6 keeps cash, research points and capacity tier")
	_expect(profile.museum_state.items.crystal_small.copies == 6 and profile.museum_state.slots.size() == 48
		and profile.museum_state.slots[0] == "crystal_small", "v6 collection survives into the 48-slot layout")
	_expect(FileAccess.file_exists("%s.v6.bak" % path), "v6 backup written before migration")
	profile.credit(10)
	var saved := ConfigFile.new()
	_expect(saved.load(path) == OK and saved.get_value("profile", "version", 0) == Progression.PROFILE_VERSION,
		"next save writes the 48-stand schema")
	DirAccess.remove_absolute("%s.v6.bak" % path)
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
