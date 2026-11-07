extends SceneTree

const Progression = preload("res://progression.gd")

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
		DirAccess.remove_absolute(scratch)
	else:
		_expect(false, "isolated test folder could not be created")
	for failure in _failures:
		push_error(failure)
	if _failures.is_empty():
		print("PROGRESSION_OK defaults, upgrades, oxygen supply, zone fees, round-trip, failed writes, corrupt protection, v1 migration")
	quit(0 if _failures.is_empty() else 1)

func _check_in_memory() -> void:
	var profile := Progression.new("")
	_expect(profile.load_profile() == OK and profile.bank == 150 and profile.selected_zone == "meadow", "new profile defaults")
	var baseline := profile.stats()
	_expect(baseline.mining_time == 0.9 and baseline.oxygen == 65 and baseline.walk_speed == 3.35, "starting suit and tool stats")
	_expect(baseline.bag_columns == 4 and baseline.bag_rows == 4 and baseline.detector_range == 10, "starting backpack and detector stats")
	_expect(profile.upgrade_rows().size() == 6 and baseline.oxygen_supply_density == 0.25, "starting oxygen supply density and shop rows")
	_expect(not profile.buy_upgrade("missing").ok and not profile.buy_upgrade("oxygen").ok and profile.bank == 150, "unknown and unaffordable upgrades leave funds alone")
	_expect(profile.buy_upgrade("detector").ok and profile.bank == 50 and profile.stats().detector_level == 1 and profile.stats().detector_range == 16, "detector purchase applies first tier")
	profile.credit(2000)
	for index in range(3):
		_expect(profile.buy_upgrade("drill").ok, "buy drill level %d" % (index + 1))
	_expect(profile.stats().mining_time == 0.30 and profile.bank == 810, "maximum drill stats and exact charges")
	_expect(not profile.buy_upgrade("drill").ok and profile.bank == 810, "maximum tier refuses a fourth charge")
	var drill: Dictionary = profile.upgrade_rows()[0]
	_expect(drill.level == drill.max_level and not drill.can_buy and drill.cost == 0, "maxed shop row is disabled")
	profile.credit(-30)
	_expect(profile.bank == 810 and profile.last_save_error == ERR_INVALID_PARAMETER, "negative credit is rejected")
	_expect(profile.buy_upgrade("oxygen_supply").ok and profile.bank == 630 and profile.stats().oxygen_supply_density == 0.40, "first oxygen supply upgrade")
	_expect(profile.buy_upgrade("oxygen_supply").ok and profile.bank == 210 and profile.stats().oxygen_supply_density == 0.60, "second oxygen supply upgrade")
	_expect(not profile.buy_upgrade("oxygen_supply").ok and profile.bank == 210, "unaffordable oxygen supply tier leaves funds alone")
	profile.credit(690)
	_expect(profile.buy_upgrade("oxygen_supply").ok and profile.bank == 0 and profile.stats().oxygen_supply_density == 0.85, "maximum oxygen supply density")
	_expect(not profile.buy_upgrade("oxygen_supply").ok and profile.stats().oxygen == 65, "oxygen supply upgrades leave tank capacity independent")

	var wallet := Progression.new("")
	var zone_copy := wallet.get_zone("deep")
	zone_copy.burial[0] = 99
	_expect(wallet.get_zone("deep").burial[0] == 0.35, "zone data is isolated from callers")
	_expect(wallet.select_zone("deep") and wallet.bank == 150, "previewing a mine does not pay entry")
	var entry := wallet.pay_entry("deep")
	_expect(entry.ok and entry.fee == 120 and entry.zone.count == 48 and wallet.bank == 30, "deep fee charged once per call")
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
	_expect(damaged.settle_reward(8, {"total": 8}) != OK and damaged.bank == 158, "failed save retains in-memory settlement")
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
	_expect(profile.settle_reward(12, {"total": 12}) != OK and profile.bank == 162 and profile.last_report.total == 12, "failed save keeps earned rewards available")
	_expect(DirAccess.remove_absolute(path) == OK and profile.save_profile() == OK, "reward can be saved after the write failure is fixed")
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
	_expect(profile.load_profile() == OK and profile.bank == 700 and profile.levels == expected_levels, "v1 preserves funds and old upgrades while adding baseline density")
	_expect(profile.selected_zone == "deep" and profile.last_report == old_report, "v1 preserves selected zone and report")
	_expect(FileAccess.get_file_as_string(path) == original, "reading v1 preserves the original file")
	_expect(profile.buy_upgrade("oxygen_supply").ok and profile.bank == 520, "new upgrade purchases can save the migrated profile")
	var saved := ConfigFile.new()
	_expect(saved.load(path) == OK and saved.get_value("profile", "version", 0) == 2, "first mutation writes v2")
	var reloaded := Progression.new(path)
	expected_levels["oxygen_supply"] = 1
	_expect(reloaded.load_profile() == OK and reloaded.bank == 520 and reloaded.levels == expected_levels, "v2 reload preserves the migrated and newly purchased levels")

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

func _expect(condition: bool, context: String) -> void:
	if not condition:
		_failures.append(context)
