extends SceneTree

const Progression = preload("res://progression.gd")
const Museum = preload("res://museum.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, context: String) -> void:
	if not condition:
		failures.append(context)
		push_error("MUSEUM MODEL FAIL: " + context)

func raw(key: String) -> Dictionary:
	return Museum.definition(key)

func deposit(profile: RefCounted, records: Array, seconds: float = 65.0, emergency: bool = false) -> Dictionary:
	var entry: Dictionary = profile.pay_entry("meadow", true)
	check(entry.ok, "fixture enters a real persisted free expedition")
	return profile.settle_expedition(int(entry.trip_id), records, emergency, seconds, {"oxygen_grains": 4})

func collect(profile: RefCounted, key: String, count: int, seconds: float = 65.0) -> Dictionary:
	var records: Array = []
	for index in range(count):
		records.append(raw(key))
	return deposit(profile, records, seconds)

func run() -> void:
	_check_curve()
	_check_income()
	var directory := "res://.demo-data/museum-model-%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(directory)
	var path := directory + "/profile.cfg"
	var profile := Progression.new(path)
	check(profile.load_profile() == OK and profile.research_points == 0 and profile.museum_state == Museum.initial_state(), "new profile owns no collection and no research")

	var first := collect(profile, "crystal_small", 1)
	check(first.ok and first.stored == 1 and first.income == 0 and profile.bank == 150, "safe return files the specimen without selling it")
	check(profile.museum_state.items.crystal_small.copies == 1 and profile.museum_state.slots[0] == "crystal_small", "first find is auto-displayed on the first stand")
	check(profile.museum_summary().income == 11 and profile.museum_summary().registered_count == 1, "level one small crystal is worth 11 per snandard expedition")
	check(first.changes.size() == 1 and first.changes[0].level_before == 0 and first.changes[0].level_after == 1 and first.changes[0].count == 1, "collection report records the first find")
	check(profile.research_points == 1, "first discovery grants one research point")

	var second := collect(profile, "crystal_small", 2)
	check(profile.museum_state.items.crystal_small.copies == 3 and Museum.level_for(3) == 2, "two more copies reach level two")
	check(second.changes[0].level_before == 1 and second.changes[0].level_after == 2 and second.changes[0].count == 2, "report aggregates duplicates and the level-up")
	check(profile.research_points == 2, "level-up grants one research point")
	check(profile.museum_summary().income == 12, "level two small crystal pays round(180 * 0.06 * 1.15) = 12")

	collect(profile, "crystal_small", 3)
	check(profile.museum_state.items.crystal_small.copies == 6 and Museum.level_for(6) == 3, "six copies reach level three")
	check(profile.museum_summary().income == 14, "level three small crystal pays round(180 * 0.06 * 1.30) = 14")
	check(profile.research_points == 3, "three levels earned three research points so far")

	for definition: Dictionary in Museum.CATEGORIES:
		if str(definition.key) == "crystal_small":
			continue
		check(collect(profile, str(definition.key), 1).ok, "each category collects independently")
	check(profile.museum_state.items.size() == Museum.CATEGORIES.size() and profile.museum_summary().displayed_count == 6, "all categories are owned while the first six stands hold them")
	check(profile.research_points == 3 + Museum.CATEGORIES.size() - 1, "one point per discovery and per crystal level-up")

	check(profile.place_exhibit("hammer", 0).ok and profile.museum_state.slots[0] == "hammer", "an owned item can replace a displayed one")
	check(profile.place_exhibit("crystal_medium", 0).ok and profile.museum_state.slots.count("crystal_medium") == 1 and profile.museum_state.slots.count("hammer") == 1, "moving an item swaps occupied stands instead of duplicating it")
	check(profile.place_exhibit("", 1).ok and profile.museum_state.slots[1] == "", "a stand can be cleared without losing the collection")
	check(not profile.place_exhibit("chest", 6).ok, "locked pedestal refuses placement")
	profile.credit(2000)
	check(profile.buy_upgrade("museum_capacity").ok and profile.place_exhibit("chest", 10).ok, "cash expansion unlocks the next zone")

	# Full ten-level collection: 55 copies per category, 60 research points total.
	var maxed := Progression.new("")
	for definition: Dictionary in Museum.CATEGORIES:
		var records: Array = []
		for index in range(55):
			records.append(raw(str(definition.key)))
		check(deposit(maxed, records).ok, "fixture collects a full stack of " + str(definition.key))
	check(maxed.museum_state.items.crystal_small.copies == 55 and Museum.level_for(55) == Museum.MAX_LEVEL, "fifty-five copies reach level ten")
	check(Museum.xp_for(55) == 0 and Museum.need_for(Museum.MAX_LEVEL) == 0, "max level has no further experience requirement")
	check(maxed.research_points == 10 * Museum.CATEGORIES.size(), "every category at level ten yields ten research points")
	for tier in range(3):
		check(maxed.buy_upgrade("museum_appeal").ok, "appeal tier %d is reachable from collections alone" % (tier + 1))
	check(maxed.research_points == 10 * Museum.CATEGORIES.size() - 60 and not maxed.buy_upgrade("museum_appeal").ok, "appeal tiers consume sixty research points and leave the surplus")
	check(is_equal_approx(maxed.stats().museum_appeal, 2.25), "final appeal multiplier applies")

	# Income settlement, emergency loss and atomic failure.
	var cash_before := maxed.bank
	var safe := deposit(maxed, [raw("hammer"), raw("hammer")])
	check(safe.ok and safe.income >= 0 and maxed.bank == cash_before + int(safe.income), "safe return credits the departure snapshot once")
	var snapshot_state: Dictionary = maxed.museum_state.duplicate(true)
	var snapshot_points: int = maxed.research_points
	var emergency := deposit(maxed, [raw("hammer"), raw("chest")], 65, true)
	check(emergency.ok and emergency.stored == 0 and maxed.museum_state == snapshot_state and maxed.research_points == snapshot_points, "emergency return loses cargo without touching the collection")
	check(emergency.lost.size() == 2 and emergency.lost[0].label == "遗落战锤", "lost cargo is grouped for the settlement panel")

	var real_path: String = maxed._save_path
	var blocked_path := directory + "/blocked"
	DirAccess.make_dir_absolute(blocked_path)
	var departure := maxed.pay_entry("meadow", true)
	maxed._save_path = blocked_path
	var held_state: Dictionary = maxed.museum_state.duplicate(true)
	var held_points: int = maxed.research_points
	var active_before: Dictionary = maxed.active_trip.duplicate(true)
	check(not maxed.settle_expedition(int(departure.trip_id), [raw("shield")], false, 65).ok, "unwritable target rejects the return")
	check(maxed.active_trip == active_before and maxed.museum_state == held_state and maxed.research_points == held_points, "failed return changes neither collection nor trip")
	maxed._save_path = real_path
	check(maxed.settle_expedition(int(departure.trip_id), [raw("shield")], false, 65).ok, "same trip and cargo retry once saving works")
	DirAccess.remove_absolute(blocked_path)

	var restored := Progression.new(path)
	check(restored.load_profile() == OK and restored.museum_state == profile.museum_state and restored.research_points == profile.research_points and restored.bank == profile.bank, "process-style reload restores the whole collection")
	var config := ConfigFile.new()
	config.load(path)
	var damaged: Dictionary = profile.museum_state.duplicate(true)
	damaged["items"]["crystal_small"]["copies"] = 0
	config.set_value("profile", "museum", damaged)
	config.save(path)
	var damaged_text := FileAccess.get_file_as_string(path)
	var broken := Progression.new(path)
	check(broken.load_profile() == ERR_FILE_CORRUPT and not broken.buy_upgrade("drill").ok and FileAccess.get_file_as_string(path) == damaged_text, "malformed collection blocks mutations and preserves bytes")
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(directory)
	if failures.is_empty():
		print("MUSEUM_MODEL_OK collection_levels=true aggregated_changes=true income_curve=true research_economy=true placement=true emergency_loss=true atomic_return=true reload=true malformed_protection=true")
	quit(0 if failures.is_empty() else 1)

func _check_curve() -> void:
	check(Museum.level_for(0) == 0 and Museum.level_for(1) == 1 and Museum.level_for(2) == 1, "the first find opens level one")
	check(Museum.level_for(3) == 2 and Museum.level_for(6) == 3 and Museum.level_for(10) == 4, "level thresholds are 2,3,4 more copies")
	check(Museum.level_for(55) == 10 and Museum.level_for(999) == 10, "level ten is the cap")
	check(Museum.xp_for(4) == 1 and Museum.need_for(2) == 3, "experience is derived from total copies")
	check(Museum.copies_for_level(10) == 55, "fifty-five copies are required for a maxed collection")

func _check_income() -> void:
	check(Museum.exhibit_income(1, 180, 1.0) == 11, "level one pays six percent of base value")
	check(Museum.exhibit_income(10, 180, 2.25) == 57, "max level and max appeal pay round(10.8 * 2.35 * 2.25)")
	check(Museum.exhibit_income(0, 180, 1.0) == 0 and Museum.exhibit_income(3, 0, 1.0) == 0, "unowned or valueless entries pay nothing")
