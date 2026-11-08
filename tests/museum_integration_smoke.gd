extends SceneTree

const Main = preload("res://main.gd")
const Museum = preload("res://museum.gd")
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
	for y in range(12, -13, -1):
		for x in range(-3, 4):
			for z in range(-3, 4):
				game.terrain.mine_at(centre + Vector3(float(x) * reach.x / 3.0, float(y) * 0.125, float(z) * reach.z / 3.0), Vector3.UP, 0)
		item.refresh_exposure(game.terrain)
		if item.is_loose():
			return
	check(false, "actual excavation releases " + item.item_name)

func collect(index: int) -> Dictionary:
	var item: Node3D = game.crystals[index]
	dig(item)
	game.suit.position = item.position + Vector3(0.6, 0.5, 0.6)
	check(game.collect_crystal(item), "actual specimen fits in the player's backpack: " + item.item_name)
	return game.inventory.get_item(item.get_instance_id())

func deploy(seed_value: int) -> void:
	game.start_trip(false)
	check(game.on_moon and not paused and not game.base_open and not game.museum_panel.is_open,
		"departure closes the museum and resumes the real expedition")
	game.terrain.reset_terrain(seed_value)
	game.spawn_crystals(seed_value)
	check(game.crystals.size() == 21, "new collection rules preserve the smaller initial mine population")

func settle(safe: bool) -> void:
	game.trip_elapsed = 65.0
	game.settle(not safe)
	if game.settlement_panel.is_open:
		game.settlement_panel.close()

func total_copies() -> int:
	var total := 0
	for key: String in game.progression.museum_state.items:
		total += int(game.progression.museum_state.items[key].copies)
	return total

func slots_count() -> int:
	var count := 0
	for key: String in game.progression.museum_state.slots:
		count += 0 if key.is_empty() else 1
	return count

func research(id: String, tier: int) -> void:
	game.show_outpost("skills")
	click(game.skill_tree_panel, "MuseumTechTab")
	click(game.skill_tree_panel, "Skill_%s_%d" % [id, tier])
	click(game.skill_tree_panel, "PurchaseSkillButton")
	check(game.progression.levels[id] == tier, "real museum research purchase applied")
	game.show_outpost("museum")

func check_real_displays() -> void:
	var summary: Dictionary = game.progression.museum_summary()
	var models: Dictionary = game.outpost_panel.lobby.scene._models
	check(models.size() == slots_count(), "each occupied pedestal has one actual 3D voxel specimen")
	for slot: int in models:
		var model: Node3D = models[slot]
		var key: String = summary.slots[slot]
		check(not key.is_empty() and model is Main.Crystal and not model._geometry.cells.is_empty(),
			"pedestal renders a real occupied voxel shape")
		check(model.wear_percent == 0 and int(summary.exhibits[key].level) == Museum.level_for(int(summary.items[key].copies)),
			"displayed specimen uses the shared item's current level")

func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	save_path = OUT + "/profile-%d.cfg" % OS.get_process_id()
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	game = make_game(save_path)
	await process_frame
	click(game.outpost_panel, "EnterOutpostButton")
	click(game.outpost_panel, "MuseumButton")
	check(game.base_open and paused and game.outpost_page == "museum" and game.museum_panel.is_open,
		"lobby opens an exclusive paused museum")
	check(game.progression.museum_state.items.is_empty() and slots_count() == 0
		and game.outpost_panel.lobby.scene._models.is_empty() and game.progression.research_points == 0,
		"a fresh museum never invents pre-filled collectibles")

	deploy(88273)
	collect(0)
	collect(1)
	collect(2)
	collect(3)
	var before_bank: int = game.bank
	settle(true)
	check(not game.on_moon and game.base_open and paused and game.outpost_page == "lobby",
		"safe cargo return opens the shared exhibition lobby")
	click(game.outpost_panel, "MuseumButton")
	check(game.museum_panel.is_open, "the returned lobby exposes the merged collection drawer")
	check(game.bank == before_bank and game.inventory.items.is_empty() and total_copies() == 4,
		"extraction archives every find without converting it to cash")
	var capacity := int(game.progression.stats().museum_capacity)
	check(slots_count() == mini(game.progression.museum_state.items.size(), capacity),
		"first finds fill the unlocked stands automatically")
	check(game.progression.research_points == game.progression.museum_state.items.size(),
		"each first discovery grants one research point")
	check_real_displays()
	var preserved: Dictionary = game.progression.museum_state.duplicate(true)
	game.settle(false)
	check(game.progression.museum_state == preserved, "a duplicate settlement cannot archive the same cargo twice")

	deploy(7712)
	collect(0)
	collect(1)
	collect(3)
	settle(true)
	check(total_copies() == 7, "a second trip adds exactly its own finds")
	for key: String in game.progression.museum_state.items:
		var copies := int(game.progression.museum_state.items[key].copies)
		check(Museum.level_for(copies) >= 1 and Museum.xp_for(copies) < maxi(Museum.need_for(Museum.level_for(copies)), 1),
			"every item keeps a coherent level and experience")

	game.progression.research_points = 30
	research("museum_appeal", 1)
	check(game.progression.research_points == 20 and game.progression.stats().museum_appeal == 1.35,
		"appeal technology consumes ten research points instead of money")
	var cash_before_research: int = game.bank
	research("museum_capacity", 1)
	check(game.bank == cash_before_research - 600 and game.progression.stats().museum_capacity == 12,
		"display expansion consumes its cash price without spending research")

	var expected_income: int = game.progression.museum_summary().income
	check(expected_income > 0, "displayed finds produce a positive expedition income estimate")
	before_bank = game.bank
	deploy(68217)
	collect(0)
	settle(true)
	check(game.bank == before_bank + expected_income and game.progression.last_report.income == expected_income,
		"qualified return credits the departure snapshot once")

	click(game.outpost_panel, "MuseumButton")
	check(game.museum_panel.is_open, "the merged drawer reopens for placement")
	var first_key := str(game.progression.museum_state.items.keys()[0])
	game.museum_panel.select_stand(1)
	game.museum_panel.select_item(first_key)
	click(game.museum_panel, "ActionButton")
	await process_frame
	check(game.progression.museum_state.slots[1] == first_key, "placing a collected item fills the chosen stand")
	var displaced := str(game.progression.museum_state.slots[0])
	click(game.museum_panel, "ActionButton")
	check(game.progression.museum_state.slots[1] == "", "clearing a stand keeps the item in the collection")
	check(game.progression.museum_state.items.has(displaced) or displaced == first_key,
		"clearing never deletes a collected category")
	check_real_displays()

	# Failed persistence must retain live cargo for a real retry.
	deploy(44201)
	collect(0)
	var inventory_before: Array = game.inventory.items.duplicate(true)
	var state_before: Dictionary = game.progression.museum_state.duplicate(true)
	var copies_before := total_copies()
	before_bank = game.bank
	var blocked := ProjectSettings.globalize_path(OUT + "/blocked-%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(blocked)
	game.progression._save_path = blocked
	game.settle(false)
	check(game.on_moon and game.inventory_open and paused and game.inventory.items == inventory_before
		and game.bank == before_bank and game.progression.museum_state == state_before,
		"a failed persistence commit retains actual world cargo and pauses for retry")
	game.progression._save_path = save_path
	game.inventory_panel.close()
	game.settle(false)
	if game.settlement_panel.is_open:
		game.settlement_panel.close()
	check(not game.on_moon and game.inventory.items.is_empty() and total_copies() == copies_before + 1,
		"fixing storage and retrying archives exactly one retained item")

	var preserved_state: Dictionary = game.progression.museum_state.duplicate(true)
	var preserved_rp: int = game.progression.research_points
	deploy(44202)
	collect(0)
	settle(false)
	check(not game.on_moon and game.progression.museum_state == preserved_state and game.progression.research_points == preserved_rp,
		"emergency loses only the current trip's cargo, never prior collection progress")

	var saved_bank: int = game.bank
	var saved_levels: Dictionary = game.progression.levels.duplicate(true)
	await destroy_game()
	game = make_game(save_path, 0)
	await process_frame
	check(game.bank == saved_bank and game.progression.levels == saved_levels
		and game.progression.research_points == preserved_rp and game.progression.museum_state == preserved_state,
		"reload restores cash, technology and the complete collection")
	click(game.outpost_panel, "EnterOutpostButton")
	click(game.outpost_panel, "MuseumButton")
	await process_frame
	check_real_displays()
	await destroy_game()
	print("MUSEUM_INTEGRATION_OK real_excavation=true auto_archive=true level_sync=true research_currency=true placement=true snapshot_income_once=true save_failure_retry=true rescue_preserves=true reload=true")
	quit(1 if failed else 0)
