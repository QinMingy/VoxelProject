extends SceneTree

const Main = preload("res://main.gd")
const OUT := "res://.demo-data/test-artifacts/museum-integration"
var game: Node3D
var failed := false
var save_path := ""

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, description: String) -> void:
	if not ok:
		failed = true
		push_error("MUSEUM INTEGRATION FAIL: " + description)
		quit(1)
		assert(ok, description)

func click(panel: Node, node_name: String) -> void:
	var button := panel.find_child(node_name, true, false) as Button
	check(button != null and not button.disabled and button.is_visible_in_tree(), "visible enabled real action: " + node_name)
	button.pressed.emit()

func make_game(path: String, initial_bank: int = 5000) -> Node3D:
	var instance := Main.new()
	instance.progression = Main.Progression.new(path)
	instance.progression.bank = initial_bank
	instance.appraisal = Main.Appraisal.new("")
	instance.wants_mouse_capture = false
	root.add_child(instance)
	instance.set_process(false)
	instance.set_physics_process(false)
	return instance

func destroy_game() -> void:
	game.sfx.set_muted(true)
	await create_timer(0.10, true).timeout
	paused = false
	game.queue_free()
	await process_frame
	await create_timer(0.25, true).timeout

func dig(item: Node3D) -> void:
	var bounds: AABB = item.get_local_bounds()
	var centre := item.position + bounds.get_center()
	var reach := bounds.size * 0.5 + Vector3.ONE * 0.25
	# Use real brush operations around the protected solid object, never loose flags.
	for y in range(12, -13, -1):
		for x in range(-3, 4):
			for z in range(-3, 4):
				game.terrain.mine_at(centre + Vector3(float(x) * reach.x / 3.0, float(y) * 0.125, float(z) * reach.z / 3.0), Vector3.UP, 0)
		item.refresh_exposure(game.terrain)
		if item.is_loose():
			return
	check(false, "actual excavation releases " + item.item_name)

func collect(index: int, wear: int) -> Dictionary:
	var item: Node3D = game.crystals[index]
	item.set_wear(float(wear) / 100.0)
	dig(item)
	game.suit.position = item.position + Vector3(0.6, 0.5, 0.6)
	check(game.collect_crystal(item), "actual specimen fits in the player's backpack: " + item.item_name)
	var record: Dictionary = game.inventory.get_item(item.get_instance_id())
	check(record.wear == wear, "backpack preserves controlled specimen wear")
	return record

func deploy(seed_value: int) -> void:
	game.start_trip(false)
	check(game.on_moon and not paused and not game.base_open and not game.museum_panel.is_open, "departure closes museum and resumes the real expedition")
	game.terrain.reset_terrain(seed_value)
	game.spawn_crystals(seed_value)
	check(game.crystals.size() == 21, "new museum rules preserve the smaller initial mine population")

func warehouse_item(type_id: String) -> Dictionary:
	for item: Dictionary in game.progression.museum_state.warehouse:
		if item.key == type_id:
			return item
	return {}

func donate(type_id: String) -> void:
	if not game.museum_panel.is_open:
		check(game.outpost_page == "lobby", "returned cargo can be handled from the exhibition lobby")
		click(game.outpost_panel, "MuseumButton")
	var record := warehouse_item(type_id)
	check(not record.is_empty(), "warehouse contains the requested real object: " + type_id)
	game.museum_panel.select_warehouse_item(int(record.uid))
	click(game.museum_panel, "DonateButton")

func research(id: String, tier: int) -> void:
	game.show_outpost("skills")
	click(game.skill_tree_panel, "MuseumTechTab")
	click(game.skill_tree_panel, "Skill_%s_%d" % [id, tier])
	click(game.skill_tree_panel, "PurchaseSkillButton")
	check(game.progression.levels[id] == tier, "real museum research purchase applied")
	game.show_outpost("museum")

func slots_count() -> int:
	var count := 0
	for key: String in game.progression.museum_state.slots:
		count += 0 if key.is_empty() else 1
	return count

func check_real_displays() -> void:
	var summary: Dictionary = game.progression.museum_summary()
	var models: Dictionary = game.museum_panel._display._models
	check(models.size() == slots_count(), "each occupied pedestal has one actual 3D voxel specimen")
	for slot: int in models:
		var model: Node3D = models[slot]
		var key: String = summary.slots[slot]
		check(not key.is_empty() and model is Main.Crystal and not model._geometry.cells.is_empty(), "pedestal renders a real occupied voxel shape")
		check(model.wear_percent == int(summary.exhibits[key].item.wear), "display keeps the selected exemplar's actual wear")

func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	save_path = OUT + "/profile-%d.cfg" % OS.get_process_id()
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	game = make_game(save_path)
	await process_frame
	click(game.outpost_panel, "EnterOutpostButton")
	click(game.outpost_panel, "MuseumButton")
	check(game.base_open and paused and game.outpost_page == "museum" and game.museum_panel.is_open, "lobby opens an exclusive paused museum")
	check(game.progression.museum_state.warehouse.is_empty() and game.progression.museum_state.exhibits.is_empty() and slots_count() == 0, "a fresh museum never invents pre-filled collectibles")
	check(game.museum_panel._display._models.is_empty() and game.progression.research_points == 0, "an empty gallery renders empty pedestals and starts without research points")
	var legacy_balance: int = game.bank
	game.appraisal.record_item_sale("hammer", 0, false)
	game.sync_base_state()
	check(game.museum_panel._state.museum.identified_types.has("hammer") and not game.progression.museum_state.identified_types.has("hammer"), "legacy price knowledge is reflected in museum presentation without silently rewriting the museum profile")
	check(game.bank == legacy_balance and game.progression.research_points == 0 and game.progression.museum_state.exhibits.is_empty(), "legacy catalogue presentation grants no cash, research points or collectibles")
	game.reset_appraisal_catalogue()
	game.sync_base_state()
	check(not game.appraisal.is_known("hammer") and not game.museum_panel._state.museum.identified_types.has("hammer"), "explicit catalogue reset clears legacy and museum presentation knowledge before first discoveries")

	deploy(88273)
	var small := collect(0, 45)
	var medium := collect(1, 25)
	collect(2, 20)
	var chest := collect(3, 40)
	var before_bank: int = game.bank
	game.trip_elapsed = 65.0
	game.settle(false)
	check(not game.on_moon and game.base_open and paused and game.outpost_page == "lobby", "safe cargo return opens the shared exhibition lobby")
	click(game.outpost_panel, "MuseumButton")
	check(game.museum_panel.is_open and game.museum_panel._tab == "warehouse", "the returned lobby exposes warehouse handling")
	check(game.bank == before_bank and game.progression.museum_state.warehouse.size() == 4 and game.inventory.items.is_empty(), "extraction atomically stores cargo without converting it to cash")
	check(not game.appraisal.known and not game.appraisal.is_known("chest"), "merely arriving in storage reveals neither family's first price")
	var stable_ids := {}
	for item: Dictionary in game.progression.museum_state.warehouse:
		check(item.uid > 0 and not stable_ids.has(item.uid), "warehouse uses unique persistent item IDs")
		stable_ids[item.uid] = true
		for transient in ["id", "world_id", "pos", "rotated"]:
			check(not item.has(transient), "persistent museum cargo omits " + transient)
	check(warehouse_item("crystal_small").wear == small.wear and warehouse_item("crystal_medium").base_value == medium.base_value and warehouse_item("chest").wear == chest.wear, "warehouse retains each actual source object's fixed metadata")
	var return_balance: int = game.bank
	game.settle(false)
	check(game.bank == return_balance and game.progression.museum_state.warehouse.size() == 4, "a duplicate main settlement cannot duplicate cargo")

	donate("crystal_small")
	await process_frame
	check(game.progression.research_points == 1 and game.progression.museum_state.exhibits.crystal_small.level == 1 and slots_count() == 1, "first registration grants one research point and automatically fills one pedestal")
	check(game.appraisal.known and game.bank == before_bank, "registration identifies the crystal family without paying sale proceeds")
	check_real_displays()
	var stored_medium := warehouse_item("crystal_medium")
	game.museum_panel.select_warehouse_item(int(stored_medium.uid))
	click(game.museum_panel, "SellButton")
	var medium_value := roundi(float(medium.base_value) * (100 - int(medium.wear)) / 100.0)
	check(game.bank == before_bank + medium_value and game.progression.research_points == 1, "explicit sale credits fixed wear-adjusted cash without research points")
	game.on_museum_sell(int(stored_medium.uid))
	check(game.bank == before_bank + medium_value, "a sold stable item ID cannot be sold again")
	donate("chest")
	donate("crystal_large")
	await process_frame
	check(game.progression.research_points == 3 and slots_count() == 3 and game.progression.museum_state.warehouse.is_empty(), "three distinct real finds fill the initial gallery")
	check_real_displays()
	click(game.museum_panel, "ResearchButton")
	check(game.outpost_page == "skills" and paused and not game.museum_panel.is_open, "museum research navigates to the separate paused skill tree")
	check((game.skill_tree_panel.find_child("Skill_museum_appeal_1", true, false) as Button).is_visible_in_tree(), "research action selects the actual museum technology tab")
	var cash_before_research: int = game.bank
	research("museum_appeal", 1)
	check(game.progression.research_points == 0 and game.bank == cash_before_research and game.progression.stats().museum_appeal == 1.35, "appeal technology consumes three research points instead of money")
	research("museum_capacity", 1)
	check(game.bank == cash_before_research - 600 and game.progression.research_points == 0 and game.progression.stats().museum_capacity == 4, "display expansion consumes its cash price without spending research")

	# Very short excursions must not repeatedly print museum income.
	deploy(7712)
	before_bank = game.bank
	game.trip_elapsed = 9.9
	game.settle(false)
	check(game.bank == before_bank and game.progression.last_report.income == 0, "a sub-ten-second return does not qualify for exhibition income")

	var expected_income: int = game.progression.museum_summary().income
	check(expected_income > 0, "displayed real finds produce a positive expedition income estimate")
	deploy(68217)
	collect(0, 30)
	collect(3, 55)
	collect(4, 15)
	collect(5, 20)
	game.trip_elapsed = 65.0
	before_bank = game.bank
	game.settle(false)
	check(game.bank == before_bank + expected_income and game.progression.last_report.income == expected_income and game.progression.museum_state.warehouse.size() == 4, "qualified return credits the departure snapshot once while retaining all unsold cargo")
	game.settle(false)
	check(game.bank == before_bank + expected_income and game.progression.museum_state.warehouse.size() == 4, "a duplicate return repeats neither museum income nor cargo")
	donate("crystal_small")
	donate("chest")
	donate("shield")
	donate("hammer")
	await process_frame
	check(game.progression.museum_state.exhibits.crystal_small.level == 2 and game.progression.museum_state.exhibits.crystal_small.item.wear == 30, "duplicate research raises the real exhibit and retains a better specimen")
	check(game.progression.museum_state.exhibits.chest.level == 2 and game.progression.museum_state.exhibits.chest.item.wear == 40, "a worse duplicate advances research without replacing the better exemplar")
	check(game.progression.museum_state.exhibits.size() == 5 and slots_count() == 4 and game.progression.research_points == 4, "new collections can be researched safely even when active pedestals are full")
	check_real_displays()
	game.museum_panel.select_exhibit("hammer")
	game.museum_panel.select_stand(0)
	click(game.museum_panel, "PlaceButton")
	await process_frame
	check(game.progression.museum_state.slots[0] == "hammer" and game.progression.museum_state.exhibits.has("crystal_small"), "placing a stored collection replaces a pedestal without losing the previous collection")
	check_real_displays()
	click(game.museum_panel, "ClearStandButton")
	check(game.progression.museum_state.slots[0] == "" and game.progression.research_points == 4, "clearing a pedestal moves its exhibit into the collection without farming research points")
	research("museum_capacity", 2)
	check(game.progression.stats().museum_capacity == 6, "final display expansion opens all six pedestals")

	deploy(11235)
	collect(0, 20)
	collect(1, 5)
	collect(3, 30)
	game.trip_elapsed = 65.0
	game.settle(false)
	donate("crystal_small")
	donate("crystal_medium")
	donate("chest")
	check(game.progression.museum_state.exhibits.crystal_small.level == 3 and game.progression.museum_state.exhibits.chest.level == 3 and game.progression.museum_state.exhibits.size() == 6, "repeated real expeditions complete all six catalogue types and cap existing levels")
	var catalogue_keys := ["crystal_small", "crystal_medium", "crystal_large", "chest", "shield", "hammer"]
	for slot in range(catalogue_keys.size()):
		game.museum_panel.select_exhibit(catalogue_keys[slot])
		game.museum_panel.select_stand(slot)
		click(game.museum_panel, "PlaceButton")
	await process_frame
	check(slots_count() == 6, "all six active pedestals display different collected object types")
	check_real_displays()

	deploy(9999)
	collect(0, 5)
	game.trip_elapsed = 65.0
	game.settle(false)
	var rp_before: int = game.progression.research_points
	donate("crystal_small")
	check(game.progression.museum_state.exhibits.crystal_small.level == 3 and game.progression.museum_state.exhibits.crystal_small.item.wear == 5 and game.progression.research_points == rp_before, "a better max-level specimen replaces condition without granting duplicate research")
	var old_exemplar := warehouse_item("crystal_small")
	check(not old_exemplar.is_empty() and old_exemplar.wear == 20, "max-level replacement returns the previous physical exemplar to the warehouse")
	game.museum_panel.select_warehouse_item(int(old_exemplar.uid))
	check((game.museum_panel.find_child("DonateButton", true, false) as Button).disabled, "a worse max-level duplicate cannot be used to farm museum levels or points")
	click(game.museum_panel, "SellButton")
	check(warehouse_item("crystal_small").is_empty(), "the replaced old exemplar can be explicitly sold")

	# Failure must leave live cargo available for a real retry, not just its UI text.
	deploy(44201)
	var rescued_record := collect(0, 10)
	game.trip_elapsed = 65.0
	var inventory_before: Array = game.inventory.items.duplicate(true)
	var warehouse_before: Array = game.progression.museum_state.warehouse.duplicate(true)
	before_bank = game.bank
	var blocked := ProjectSettings.globalize_path(OUT + "/blocked-%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(blocked)
	game.progression._save_path = blocked
	game.settle(false)
	check(game.on_moon and game.inventory_open and paused and game.inventory.items == inventory_before and game.bank == before_bank and game.progression.museum_state.warehouse == warehouse_before, "a failed persistence commit retains actual world cargo and pauses for retry")
	game.progression._save_path = save_path
	game.inventory_panel.close()
	game.settle(false)
	check(not game.on_moon and game.inventory.items.is_empty() and game.progression.museum_state.warehouse.size() == warehouse_before.size() + 1, "fixing storage and retrying transfers exactly one retained item")
	check(warehouse_item("crystal_small").wear == rescued_record.wear, "retry retains the original item's condition")

	var preserved_museum: Dictionary = game.progression.museum_state.duplicate(true)
	var preserved_rp: int = game.progression.research_points
	deploy(44202)
	collect(0, 65)
	game.trip_elapsed = 65.0
	before_bank = game.bank
	game.settle(true)
	check(not game.on_moon and game.bank == before_bank and game.progression.museum_state == preserved_museum and game.progression.research_points == preserved_rp, "emergency loses only the current trip's cargo, never prior museum progress or warehouse items")
	var saved_bank: int = game.bank
	var saved_levels: Dictionary = game.progression.levels.duplicate(true)
	await destroy_game()
	game = make_game(save_path, 0)
	await process_frame
	check(game.bank == saved_bank and game.progression.levels == saved_levels and game.progression.research_points == preserved_rp and game.progression.museum_state == preserved_museum, "reload restores cash, technology, stable warehouse items and complete gallery state")
	click(game.outpost_panel, "EnterOutpostButton")
	click(game.outpost_panel, "MuseumButton")
	await process_frame
	check_real_displays()
	check(game.appraisal.is_known("chest") and game.appraisal.known, "profile identification restores price knowledge even without a separate appraisal file")
	await destroy_game()
	print("MUSEUM_INTEGRATION_OK real_excavation=true no_auto_sale=true stable_cargo=true real_3d_displays=true research_currency=true duplicates_best_condition=true max_replacement=true arrange=true snapshot_income_once=true save_failure_retry=true rescue_preserves=true reload=true")
	quit(1 if failed else 0)
