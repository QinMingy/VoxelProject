extends SceneTree

const Main = preload("res://main.gd")
const OUT := "res://.demo-data/test-artifacts/base-progression"
var game: Node3D
var failed := false
var preview := false
var save_path := ""

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, description: String) -> void:
	if not ok:
		failed = true
		push_error("BASE INTEGRATION FAIL: " + description)
		quit(1)
		assert(ok, description)

func make_game(path: String, initial_bank: int = 0) -> Node3D:
	var instance := Main.new()
	instance.progression = Main.Progression.new(path)
	instance.progression.bank = initial_bank
	instance.appraisal = Main.Appraisal.new("")
	instance.wants_mouse_capture = false
	root.add_child(instance)
	instance.set_process(false)
	instance.set_physics_process(false)
	return instance

func click(node_name: String) -> void:
	var button := game.base_panel.find_child(node_name, true, false) as Button
	check(button != null and not button.disabled, "enabled real button: " + node_name)
	if button != null:
		button.pressed.emit()

func key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		root.push_input(event)

func shot(name: String) -> void:
	if not preview:
		return
	for frame in range(45):
		game.terrain.update_focus(game.suit.position)
		await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(OUT + "/" + name + ".png") == OK, "save preview " + name)

func dig(item: Node3D) -> void:
	var bounds: AABB = item.get_local_bounds()
	var center := item.position + bounds.get_center()
	var reach := Vector2(bounds.size.x, bounds.size.z) * 0.5 + Vector2.ONE * Main.Terrain.CELL_SIZE
	for layer in range(12):
		for offset in [Vector2.ZERO, Vector2(-reach.x, 0), Vector2(reach.x, 0), Vector2(0, -reach.y), Vector2(0, reach.y), Vector2(-reach.x, -reach.y), Vector2(reach.x, -reach.y), Vector2(-reach.x, reach.y), Vector2(reach.x, reach.y)]:
			var origin := Vector3(center.x + offset.x, Main.Terrain.WORLD_MAX.y + 1.0, center.z + offset.y)
			var hit: Dictionary = game.terrain.raycast_voxels(origin, Vector3.DOWN, 10.0)
			check(not hit.is_empty(), "actual mining ray hits the ground")
			game.terrain.mine_at(hit.position, hit.normal, 0)
			item.refresh_exposure(game.terrain)
			if item.is_loose():
				return
	check(false, "surrounding soil excavation releases an actual spawned crystal")

func run() -> void:
	preview = OS.get_cmdline_user_args().has("--preview") and DisplayServer.get_name() != "headless"
	DirAccess.make_dir_recursive_absolute(OUT)
	save_path = OUT + "/profile-%d.cfg" % OS.get_process_id()
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	game = make_game(save_path)
	await process_frame
	check(game.base_open and paused and not game.on_moon, "startup opens paused base")
	key(KEY_G)
	key(KEY_B)
	check(game.base_open and not game.gm_open and not game.inventory_open and paused, "base blocks G/B panel stacking")
	click("Zone_salvage")
	check(game.base_panel._deploy_button.disabled, "unaffordable paid map disables deployment")
	game.start_trip(false)
	check(not game.on_moon and game.bank == 0 and game.base_open, "main also rejects unpaid entry")
	click("Zone_meadow")
	click("DeployButton")
	check(game.on_moon and not paused and not game.base_open and game.bank == 0, "zero cash can deploy free")
	check(game.crystals.size() == 72 and is_equal_approx(game.oxygen_limit, 65.0), "free zone actual spawn and baseline oxygen")
	check(is_equal_approx(game.terrain.debug_stats().map_oxygen_supply_density, 0.25), "free zone starts with baseline oxygen supply density")
	var first: Node3D = game.crystals[0]
	game.suit.position = first.position + Vector3(1, 1, 1)
	game.update_crystal_targets()
	check(game.detector_reading.available and game.detector_reading.range_m == 10.0, "real target gives baseline echo")
	check(not game.detector_reading.echoes.is_empty() and game.detector_reading.depth_text == "" and game.detector_reading.size_text == "", "level zero detects multiple directions but withholds depth and size")
	for forbidden in ["price", "value", "base_value", "wear", "sale_value"]:
		check(not game.detector_reading.has(forbidden), "detector has no exact price field " + forbidden)
	check(not game.appraisal.known, "starting catalogue leaves exact value unknown")
	game.settle(false)
	check(game.base_open and paused and game.bank == 0, "return opens paused base")
	game.progression.credit(6000)
	game.sync_base_state()
	for id in ["drill", "oxygen", "oxygen_supply", "boots", "backpack", "detector", "backpack"]:
		click("Buy_" + id)
	check(game.bank == 4480 and game.progression.bank == game.bank, "six upgrade categories debit the sole balance owner")
	check(is_equal_approx(game.progression.stats().oxygen_supply_density, 0.40), "density purchase increases the next trip's oxygen supply")
	check(is_equal_approx(game.terrain.debug_stats().map_oxygen_supply_density, 0.25), "buying density does not change the old map")
	check(is_equal_approx(game.mining_time, 0.65) and is_equal_approx(game.walk_speed, 3.7), "buttons apply mining/movement stats")
	check(game.oxygen_limit == 75.0 and game.detector_level == 1, "buttons apply oxygen/detector level")
	check(game.inventory.columns == 5 and game.inventory.rows == 5, "two backpack purchases expand model to 5 x 5")
	await shot("base-shop")
	click("Zone_salvage")
	click("DeployButton")
	check(game.bank == 4420 and game.trip_fee == 60 and game.crystals.size() == 90, "paid zone charges exactly its fee and spawns its population")
	game.start_trip(false)
	check(game.bank == 4420 and game.crystals.size() == 90, "duplicate start on moon cannot pay or respawn again")
	check(game.oxygen == 75.0, "normal trip uses upgraded oxygen")
	check(is_equal_approx(game.terrain.debug_stats().map_oxygen_supply_density, 0.40), "next map applies purchased oxygen supply density")
	first = game.crystals[0]
	# The same real specimen lies outside the baseline range but inside level one.
	var origin := first.position + Vector3(12.0, 0, 0)
	var baseline := Main.Detector.sample(origin, Vector3.LEFT, [first], game.terrain, 0)
	var upgraded := Main.Detector.sample(origin, Vector3.LEFT, [first], game.terrain, game.detector_level)
	check(not baseline.available and upgraded.available and upgraded.range_m == 16.0, "purchased range actually detects a formerly out-of-range specimen")
	dig(first)
	game.suit.position = first.position + Vector3(0.6, 0.5, 0.6)
	game.camera.position = first.position + Vector3(1.8, 1.8, 2)
	game.camera.look_at(first.position + Vector3.UP * 0.2)
	game.update_crystal_targets()
	game.update_hud()
	check(game.detector_reading.target == first and game.detector_panel._reading.target == first, "main and right HUD read the same actual target")
	check(game.detector_panel.marker_layout().size() == game.detector_reading.echoes.size(), "upgraded HUD displays all in-range echoes")
	await shot("detector-excavation")
	check(game.collect_crystal(first), "real mined crystal enters upgraded backpack")
	game.update_crystal_targets()
	check(game.detector_reading.target != first, "stored specimen is excluded from detector")
	key(KEY_B)
	check(game.inventory_open and paused and game.inventory_panel._grid.inventory == game.inventory, "B opens live upgraded inventory")
	check(game.inventory_panel._grid.custom_minimum_size == Vector2(320, 320), "5 x 5 backpack grid fits panel bounds")
	var before_position: Vector3 = game.suit.position
	var before_oxygen: float = game.oxygen
	game._physics_process(2.0)
	key(KEY_G)
	check(game.inventory_open and not game.gm_open and paused and game.oxygen == before_oxygen and game.suit.position == before_position, "inventory pauses oxygen/movement and blocks GM")
	await shot("backpack-5x5")
	key(KEY_B)
	key(KEY_G)
	check(game.gm_open and paused and not game.inventory_open, "GM opens alone after closing inventory")
	key(KEY_B)
	check(game.gm_open and not game.inventory_open, "GM blocks inventory stacking")
	key(KEY_G)
	check(not game.gm_open and not paused, "closing GM resumes gameplay")
	var expected_sale := roundi(float(first.base_value) * (100 - first.wear_percent) / 100.0)
	game.oxygen = 42.0
	check(game.gain_oxygen(17) > 0.0 and game.oxygen_grains == 17, "oxygen collected on a paid trip")
	game.settle(false)
	check(game.bank == 4420 + expected_sale and game.base_open and paused, "safe sale credits only the mined item's own wear/value then opens base")
	check(game.progression.last_report.income == expected_sale and game.progression.last_report.fee == 60 and game.progression.last_report.net == expected_sale - 60, "report includes ticket and crystal sale income")
	var paid_balance: int = game.bank
	game.settle(false)
	check(game.bank == paid_balance, "duplicate settlement cannot credit again")
	click("Zone_deep")
	click("TrialButton")
	check(game.crystals.size() == 48 and game.trip_fee == 120 and game.bank == paid_balance - 120 and game.oxygen_limit == Main.TRIAL_SECONDS, "deep zone trial also charges its fee and uses short oxygen")
	game.settle(true)
	var saved_bank: int = game.bank
	var saved_levels: Dictionary = game.progression.levels.duplicate()
	paused = false
	game.free()
	game = make_game(save_path)
	await process_frame
	check(game.bank == saved_bank and game.progression.levels == saved_levels and game.progression.selected_zone == "deep", "new main restores bank, equipment and zone from independent disk profile")
	check(game.inventory.columns == 5 and game.inventory.rows == 5 and game.base_open and paused, "relaunch reapplies upgrades and base")
	paused = false
	game.free()
	var corrupt_path := OUT + "/corrupt-%d.cfg" % OS.get_process_id()
	var bad := "[profile]\nversion=999\nbank=42\n"
	var file := FileAccess.open(corrupt_path, FileAccess.WRITE)
	file.store_string(bad)
	file.close()
	game = make_game(corrupt_path)
	await process_frame
	check(game.profile_transient and game.progression.profile_path == "", "bad profile enters non-saving temporary mode")
	check(str(game.base_panel._state.message).contains("临时试玩"), "temporary mode is visible in base")
	click("DeployButton")
	check(game.on_moon, "temporary profile can still start free map")
	game.settle(false)
	check(FileAccess.get_file_as_string(corrupt_path) == bad, "bad profile survives trial/settlement unchanged")
	paused = false
	game.free()
	print("BASE_PROGRESSION_INTEGRATION_OK buttons=6 oxygen_density=25/40 bag=5x5 maps=72/90/48 paid_once=true settlement_once=true persistence=true panel_pause=true detector_range=10/16 corruption_preserved=true preview=", preview)
	quit(1 if failed else 0)
