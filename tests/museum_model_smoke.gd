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

func raw(key: String, wear: int = 20) -> Dictionary:
	var item := Museum.definition(key)
	item["wear"] = wear
	item["id"] = 989
	item["world_id"] = 989
	item["pos"] = Vector2i(0, 1)
	item["rotated"] = true
	return item

func deposit(profile: RefCounted, records: Array, seconds: float = 65.0, emergency: bool = false) -> Dictionary:
	var entry: Dictionary = profile.pay_entry("meadow", true)
	check(entry.ok, "fixture enters a real persisted free expedition")
	return profile.settle_expedition(int(entry.trip_id), records, emergency, seconds, {"oxygen_grains": 4})

func run() -> void:
	_check_balance_caps()
	var directory := "res://.demo-data/museum-model-%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(directory)
	var path := directory + "/profile.cfg"
	var profile := Progression.new(path)
	check(profile.load_profile() == OK and profile.research_points == 0 and profile.museum_state.warehouse.is_empty(), "new profile has no museum cargo or research")
	var first := deposit(profile, [raw("crystal_small", 50)])
	check(first.ok and first.stored == 1 and first.income == 0 and profile.bank == 150, "safe return stores the actual specimen without automatic sale")
	var small: Dictionary = profile.museum_state.warehouse[0]
	check(small.uid == 1 and small.key == "crystal_small" and small.size_tier == 0 and small.wear == 50 and small.base_value == 180, "cargo gets stable UID and canonical type with original condition")
	for forbidden: String in ["id", "world_id", "pos", "rotated"]:
		check(not small.has(forbidden), "persistent museum cargo strips transient field " + forbidden)
	check(profile.museum_state.identified_types.is_empty(), "arrival does not reveal first-time prices")
	check(not profile.settle_expedition(int(first.report.trip_id), [raw("crystal_small")], false, 65).ok and profile.museum_state.warehouse.size() == 1, "same expedition cannot deposit twice")
	var donation := profile.donate_item(int(small.uid))
	check(donation.ok and donation.research == 1 and profile.bank == 150 and profile.research_points == 1, "first donation consumes cargo for one research point, not cash")
	check(profile.museum_state.warehouse.is_empty() and profile.museum_state.slots[0] == "crystal_small" and profile.museum_state.identified_types == ["crystal"], "first donation displays and identifies the actual specimen")
	check(profile.museum_summary().income == 5 and profile.museum_summary().registered_count == 1, "half-worn small specimen pays round(180 * 0.50 * 0.06) = 5 per standard expedition")
	check(not profile.donate_item(int(small.uid)).ok and profile.research_points == 1, "duplicate donation request never grants points again")

	var active: Dictionary = profile.pay_entry("meadow", true)
	var current_income := int(active.income_snapshot)
	check(profile.settle_expedition(int(active.trip_id), [raw("crystal_small", 20)], false, 65).income == current_income, "cash income is credited from the departure snapshot")
	var second_uid: int = profile.museum_state.warehouse[0].uid
	check(profile.donate_item(second_uid).ok and profile.research_points == 2 and profile.museum_state.exhibits.crystal_small.level == 2 and profile.museum_state.exhibits.crystal_small.bestwear == 20, "duplicate research raises type level and preserves the better condition")
	deposit(profile, [raw("crystal_small", 40)])
	var third_uid: int = profile.museum_state.warehouse[0].uid
	check(profile.donate_item(third_uid).ok and profile.research_points == 3 and profile.museum_state.exhibits.crystal_small.level == 3 and profile.museum_state.exhibits.crystal_small.bestwear == 20, "worse duplicate can fund research without replacing a better display")
	deposit(profile, [raw("crystal_small", 30)])
	var unhelpful_uid: int = profile.museum_state.warehouse[0].uid
	check(not profile.donate_item(unhelpful_uid).ok and profile.research_points == 3 and profile.museum_state.warehouse.size() == 1, "max-level worse duplicate remains in the warehouse")
	var before_sale := profile.bank
	var sold := profile.sell_item(unhelpful_uid)
	check(sold.ok and sold.income == 126 and profile.bank == before_sale + 126 and profile.research_points == 3, "explicit sale honors the specimen's fixed wear and does not grant research")
	check(not profile.sell_item(unhelpful_uid).ok and profile.bank == before_sale + 126, "same warehouse specimen cannot be sold twice")
	deposit(profile, [raw("crystal_small", 5)])
	var replacement_uid: int = profile.museum_state.warehouse[0].uid
	var old_uid: int = profile.museum_state.exhibits.crystal_small.item.uid
	var replacement := profile.donate_item(replacement_uid)
	check(replacement.ok and replacement.replaced and profile.research_points == 3 and profile.museum_state.exhibits.crystal_small.bestwear == 5, "max-level better specimen replaces display without generating extra research")
	check(profile.museum_state.warehouse.size() == 1 and profile.museum_state.warehouse[0].uid == old_uid, "the replaced old specimen returns to the warehouse with the same identity")

	deposit(profile, [raw("crystal_medium"), raw("crystal_large"), raw("chest"), raw("shield"), raw("hammer")])
	var donate_uids: Array[int] = []
	for item: Dictionary in profile.museum_state.warehouse:
		if item.key != "crystal_small":
			donate_uids.append(int(item.uid))
	for uid in donate_uids:
		check(profile.donate_item(uid).ok, "each category is independently registered")
	check(profile.museum_state.exhibits.size() == 6 and profile.museum_summary().displayed_count == 3, "all six types can be registered while only three stands are unlocked")
	check(profile.museum_summary().catalogue_rows.size() == 6 and Museum.is_valid_state(profile.museum_state, 3), "catalogue and serialized museum remain coherent")
	check(profile.place_exhibit("hammer", 0).ok and profile.museum_state.slots[0] == "hammer", "an archived exhibit can replace a displayed exhibit without selling either")
	check(profile.place_exhibit("crystal_medium", 0).ok and profile.museum_state.slots.count("crystal_medium") == 1 and profile.museum_state.slots.count("hammer") == 1, "moving an existing exhibit swaps occupied stands instead of duplicating it")
	check(profile.place_exhibit("", 1).ok and profile.museum_state.slots[1] == "", "a pedestal can be cleared without deleting the collection")
	check(not profile.place_exhibit("chest", 3).ok, "locked pedestal refuses placement")
	profile.credit(2000)
	check(profile.buy_upgrade("museum_capacity").ok and profile.stats().museum_capacity == 4 and profile.place_exhibit("chest", 3).ok, "cash expansion unlocks an actual usable stand")
	var points_before := profile.research_points
	var cash_before := profile.bank
	check(profile.buy_upgrade("museum_appeal").ok and profile.research_points == points_before - 3 and profile.bank == cash_before and profile.stats().museum_appeal == 1.35, "research expansion costs three research points independently from money")

	# No income on immediate turnarounds; proportional income after the minimum,
	# with a fixed standard-expedition cap so oxygen upgrades do not extend it.
	for seconds: float in [0.0, 9.99, 10.0, 32.5, 65.0, 90.0]:
		var entry := profile.pay_entry("meadow", true)
		var before := profile.bank
		var expected := floori(float(entry.income_snapshot) * clampf(seconds / 65.0, 0.0, 1.0)) if seconds >= 10.0 else 0
		var result := profile.settle_expedition(int(entry.trip_id), [], false, seconds)
		check(result.ok and result.income == expected and profile.bank == before + expected, "income prorates and caps correctly for %.2f seconds" % seconds)
		check(not profile.settle_expedition(int(entry.trip_id), [], false, seconds).ok and profile.bank == before + expected, "repeat settlement cannot pay museum income twice")
	var before_warehouse: Array = profile.museum_state.warehouse.duplicate(true)
	var before_collection: Dictionary = profile.museum_state.exhibits.duplicate(true)
	var before_emergency_cash := profile.bank
	check(deposit(profile, [raw("chest")], 65, true).ok and profile.bank == before_emergency_cash and profile.museum_state.warehouse == before_warehouse and profile.museum_state.exhibits == before_collection, "rescue loses current cargo only and does not pay a safe-return bonus")

	# Failed writes must leave both sides of a transaction intact for a safe retry.
	var real_path: String = profile._save_path
	var blocked_path := directory + "/blocked"
	DirAccess.make_dir_absolute(blocked_path)
	profile._save_path = blocked_path
	var snapshot := [profile.bank, profile.research_points, profile.museum_state.duplicate(true), profile.levels.duplicate(true)]
	var sale_uid: int = profile.museum_state.warehouse[0].uid
	check(not profile.sell_item(sale_uid).ok, "unwritable target rejects sale")
	check([profile.bank, profile.research_points, profile.museum_state, profile.levels] == snapshot, "failed sale changes neither cargo nor currency")
	check(not profile.buy_upgrade("museum_capacity").ok and profile.levels == snapshot[3] and profile.bank == snapshot[0], "failed museum upgrade does not charge")
	profile._save_path = real_path
	var departure := profile.pay_entry("meadow", true)
	profile._save_path = blocked_path
	var active_before := profile.active_trip.duplicate(true)
	check(not profile.settle_expedition(int(departure.trip_id), [raw("hammer")], false, 65).ok and profile.active_trip == active_before and profile.museum_state == snapshot[2], "failed return keeps the active expedition and old warehouse intact")
	profile._save_path = real_path
	check(profile.settle_expedition(int(departure.trip_id), [raw("hammer")], false, 65).ok, "same cargo and trip can be retried once saving is available")
	DirAccess.remove_absolute(blocked_path)

	var restored := Progression.new(path)
	check(restored.load_profile() == OK and restored.bank == profile.bank and restored.research_points == profile.research_points and restored.museum_state == profile.museum_state and restored.levels == profile.levels and restored.active_trip.is_empty(), "process-style reload restores all collection, cargo, currencies, upgrades and transaction ledger")
	var file_before := FileAccess.get_file_as_string(path)
	check(not restored.settle_expedition(int(departure.trip_id), [], false, 65).ok and FileAccess.get_file_as_string(path) == file_before, "settlement remains idempotent after a process restart")
	var capped := Progression.new("")
	capped.bank = Progression.MAX_BANK
	capped.levels = profile.levels.duplicate(true)
	capped.museum_state = profile.museum_state.duplicate(true)
	var capped_entry := capped.pay_entry("meadow", true)
	var capped_return := capped.settle_expedition(int(capped_entry.trip_id), [raw("hammer")], false, 65)
	check(capped_return.ok and capped_return.stored == 1 and capped_return.income == 0 and capped_return.report.income_overflow > 0 and capped.bank == Progression.MAX_BANK, "passive income at cash cap does not prevent safe cargo storage")
	var config := ConfigFile.new()
	config.load(path)
	var damaged: Dictionary = profile.museum_state.duplicate(true)
	damaged.warehouse[0]["world_id"] = 8877
	config.set_value("profile", "museum", damaged)
	config.save(path)
	var damaged_text := FileAccess.get_file_as_string(path)
	var broken := Progression.new(path)
	check(broken.load_profile() == ERR_FILE_CORRUPT and not broken.buy_upgrade("drill").ok and FileAccess.get_file_as_string(path) == damaged_text, "malformed persisted cargo blocks mutations and preserves original bytes")
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(directory)
	if failures.is_empty():
		print("MUSEUM_MODEL_OK atomic_profile=true stable_cargo=true donation_levels=true replacement=true placement=true research_currency=true prorated_income=true exact_once=true rollback=true reload=true malformed_protection=true")
	quit(0 if failures.is_empty() else 1)

func _check_balance_caps() -> void:
	# This exhausts the finite research source through real collection donations,
	# rather than assigning points and assuming that every upgrade is reachable.
	var profile := Progression.new("")
	var records: Array = []
	for definition: Dictionary in Museum.CATEGORIES:
		for index in range(3):
			records.append(raw(str(definition.key), 20))
	check(deposit(profile, records).ok, "balance fixture safely stores three copies of all six categories")
	var uids: Array[int] = []
	for item: Dictionary in profile.museum_state.warehouse:
		uids.append(int(item.uid))
	for uid in uids:
		check(profile.donate_item(uid).ok, "each of eighteen specimens grants one reachable research point")
	check(profile.research_points == 18 and profile.museum_summary().total_level == 18, "research source caps at six categories times three levels = eighteen")
	var bank_before := profile.bank
	var points_left := [15, 9, 0]
	var appeals := [1.35, 1.75, 2.25]
	for tier in range(3):
		check(profile.buy_upgrade("museum_appeal").ok and profile.research_points == points_left[tier] and is_equal_approx(profile.stats().museum_appeal, appeals[tier]), "appeal tier %d spends exactly its three/six/nine research points" % (tier + 1))
	check(profile.bank == bank_before and not profile.buy_upgrade("museum_appeal").ok, "all appeal tiers require eighteen research points and no cash; fourth upgrade is blocked")
	profile.credit(3000)
	check(profile.buy_upgrade("museum_capacity").ok and profile.buy_upgrade("museum_capacity").ok and profile.bank == bank_before + 600, "both museum expansions cost exactly600+1800")
	for slot in range(Museum.CATEGORIES.size()):
		check(profile.place_exhibit(str(Museum.CATEGORIES[slot].key), slot).ok, "six unlocked stands accept all six fully researched exhibits")
	var expected_income := [39, 86, 164, 173, 134, 117]
	var summary := profile.museum_summary()
	for index in range(Museum.CATEGORIES.size()):
		var row: Dictionary = summary.catalogue_rows[index]
		check(row.level == 3 and row.wear == 20 and row.income == expected_income[index], "fully researched category %s pays its exact value-based yield" % row.key)
	check(summary.income == 713, "six wear20 level3 exhibits at appeal2.25 pay713 per standard65-second safe expedition")
	for key: String in ["crystal_small", "chest"]:
		var definition := Museum.definition(key)
		var entry := {"item": {"base_value": definition.base_value}, "bestwear": 0, "level": 1}
		var expected := 11 if key == "crystal_small" else 48
		check(Museum.exhibit_income(entry, 1.0) == expected, "perfect first donation earns six percent of that category's value, not a fixed amount")
	var total_cash := 0
	var total_research := 0
	for upgrade: Dictionary in Progression.UPGRADES.values():
		for cost: int in upgrade.costs:
			total_cash += cost
		for cost: int in upgrade.get("research_costs", []):
			total_research += cost
	check(total_cash == 22920 and total_research == 18, "whole upgrade catalogue costs22920cash and eighteen reachable research points")
	var poor := Progression.new("")
	poor.research_points = 2
	check(not poor.buy_upgrade("museum_appeal").ok and poor.research_points == 2 and poor.bank == 150 and poor.levels.museum_appeal == 0, "two points cannot buy the three-point appeal tier and neither currency is charged")
