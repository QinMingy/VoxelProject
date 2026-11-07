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
	var panel: Node = game.outpost_panel
	if game.outpost_page == "zones":
		panel = game.base_panel
	elif game.outpost_page == "skills":
		panel = game.skill_tree_panel
	elif game.outpost_page == "museum":
		panel = game.museum_panel
	var button := panel.find_child(node_name, true, false) as Button
	check(button != null and not button.disabled and button.is_visible_in_tree(), "enabled visible real button: " + node_name)
	if button != null:
		button.pressed.emit()

func buy_skill(id: String) -> void:
	var before: int = game.bank
	var tier: int = game.progression.levels[id] + 1
	click("Skill_%s_%d" % [id, tier])
	check(game.bank == before and game.skill_tree_panel.node_state(id, tier) == "available", "selecting a skill node only previews its cost")
	click("PurchaseSkillButton")
	check(game.progression.levels[id] == tier and game.skill_tree_panel.node_state(id, tier) == "purchased", "confirmation purchases the selected real node")
	check(game.bank == before - int(Main.Progression.UPGRADES[id].costs[tier - 1]), "confirmed purchase charges exactly its configured cash price")

func destroy_game() -> void:
	game.sfx.set_muted(true)
	await create_timer(0.10, true).timeout
	paused = false
	game.queue_free()
	await process_frame
	await create_timer(0.25, true).timeout

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
	check(game.base_open and paused and not game.on_moon and game.outpost_page == "title", "startup opens paused title")
	key(KEY_G)
	key(KEY_B)
	check(game.base_open and not game.gm_open and not game.inventory_open and paused, "title blocks G/B panel stacking")
	click("OutpostGMButton")
	check(game.gm_open and paused and not game.base_open and not game.inventory_open and not game.outpost_panel.is_open and not game.base_panel.is_open and not game.skill_tree_panel.is_open, "explicit title GM action opens exclusively and stays paused")
	var touch_toggle := game.gm_panel.find_child("TouchMode", true, false) as CheckBox
	check(touch_toggle != null and touch_toggle.is_visible_in_tree() and not touch_toggle.button_pressed and not game.touch_mode, "actual GM touch checkbox starts in keyboard mode")
	touch_toggle.button_pressed = true
	check(game.touch_mode and game.gm_open and paused and game.bank == 0, "actual GM checkbox enables touch without leaving GM or changing balance")
	check(game.outpost_panel._help.text.contains("左摇杆") and not game.outpost_panel._help.text.contains("WASD"), "outpost help switches to actual touch controls")
	touch_toggle.button_pressed = false
	check(not game.touch_mode and game.gm_open and paused and game.bank == 0, "actual GM checkbox restores keyboard mode without changing balance")
	check(game.outpost_panel._help.text.contains("WASD") and not game.outpost_panel._help.text.contains("左摇杆"), "outpost help restores keyboard controls")
	var gm_close := game.gm_panel.find_child("CloseButton", true, false) as Button
	check(gm_close != null and gm_close.is_visible_in_tree(), "actual GM close button is visible")
	gm_close.pressed.emit()
	check(not game.gm_open and game.base_open and paused and game.outpost_page == "title" and game.outpost_panel.is_open and game.bank == 0, "closing outpost GM returns to the paused title with the same balance")
	await shot("title")
	click("EnterOutpostButton")
	check(game.outpost_page == "lobby" and game.base_open and paused and game.bank == 0, "title enters lobby without charging or deploying")
	click("TitleButton")
	check(game.outpost_page == "title" and paused, "lobby can return to title")
	click("EnterOutpostButton")
	await shot("lobby")
	click("SkillsButton")
	check(game.outpost_page == "skills" and paused and game.skill_tree_panel.is_open and not game.base_panel.is_open, "lobby opens a separate paused skill tree")
	click("Skill_drill_1")
	check(game.skill_tree_panel._buy_button.disabled and game.bank == 0, "unaffordable skill can be inspected but not bought")
	click("CloseButton")
	check(game.outpost_page == "lobby" and paused, "closing skills returns to paused lobby")
	click("ExpeditionsButton")
	check(game.outpost_page == "zones" and paused and game.base_panel.is_open and not game.skill_tree_panel.is_open, "expeditions have a separate paused selection page")
	check(game.base_panel.find_child("TrialButton", true, false) == null and game.base_panel.find_child("Buy_drill", true, false) == null, "normal expedition selection has no trial shortcut or combined shop")
	click("Zone_salvage")
	check(game.base_panel._deploy_button.disabled and game.bank == 0, "unaffordable paid map disables deployment and selection never charges")
	game.start_trip(false)
	check(not game.on_moon and game.bank == 0 and game.base_open, "main also rejects unpaid entry")
	click("Zone_meadow")
	click("DeployButton")
	check(game.on_moon and not paused and not game.base_open and game.bank == 0 and not game.outpost_panel.is_open and not game.skill_tree_panel.is_open and not game.base_panel.is_open, "zero cash can deploy free and all outpost pages close")
	check(game.crystals.size() == 21 and is_equal_approx(game.oxygen_limit, 65.0), "smaller free zone actual spawn and baseline oxygen")
	check(is_equal_approx(game.activity_boundary.radius, 14.0) and game.progression.levels.excavation_range == 0, "new profile uses the starting exploration area")
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
	check(game.base_open and paused and game.bank == 0 and game.outpost_page == "lobby", "return opens paused lobby")
	game.progression.credit(6000)
	game.sync_base_state()
	click("SkillsButton")
	for id in ["drill", "oxygen", "oxygen_supply", "boots", "backpack", "detector", "backpack"]:
		buy_skill(id)
	var upgraded_balance: int = game.bank
	check(upgraded_balance == 3600 and game.progression.bank == game.bank, "seven purchases charge the expected 2400 from the sole balance owner")
	check(is_equal_approx(game.progression.stats().oxygen_supply_density, 0.40), "density purchase increases the next trip's oxygen supply")
	check(is_equal_approx(game.terrain.debug_stats().map_oxygen_supply_density, 0.25), "buying density does not change the old map")
	check(is_equal_approx(game.mining_time, 0.65) and is_equal_approx(game.walk_speed, 3.7), "buttons apply mining/movement stats")
	check(game.oxygen_limit == 75.0 and game.detector_level == 1, "buttons apply oxygen/detector level")
	check(game.inventory.columns == 5 and game.inventory.rows == 5, "two backpack purchases expand model to 5 x 5")
	await shot("skills-upgraded")
	click("CloseButton")
	click("ExpeditionsButton")
	click("Zone_salvage")
	check(game.bank == upgraded_balance, "previewing a paid expedition does not charge after purchases")
	click("DeployButton")
	var expedition_balance: int = upgraded_balance - 60
	check(game.bank == expedition_balance and game.trip_fee == 60 and game.crystals.size() == 26, "paid zone charges exactly its fee and spawns its area-scaled population")
	game.start_trip(false)
	check(game.bank == expedition_balance and game.crystals.size() == 26, "duplicate start on moon cannot pay or respawn again")
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
	check(game.bank == expedition_balance and game.base_open and paused and game.outpost_page == "lobby", "safe extraction returns to the exhibition lobby and preserves cargo instead of auto-selling")
	click("MuseumButton")
	check(game.outpost_page == "museum" and game.museum_panel._tab == "warehouse", "warehouse action opens stored cargo from the returned lobby")
	check(game.progression.museum_state.warehouse.size() == 1 and game.progression.museum_state.warehouse[0].wear == first.wear_percent, "safe cargo preserves its own wear in the persistent warehouse")
	check(game.progression.last_report.income == 0 and game.progression.last_report.fee == 60 and game.progression.last_report.net == -60 and game.progression.last_report.cargo_count == 1, "expedition report separates cash income from newly stored cargo")
	var stored_uid := int(game.progression.museum_state.warehouse[0].uid)
	game.on_museum_sell(stored_uid)
	check(game.bank == expedition_balance + expected_sale and game.progression.museum_state.warehouse.is_empty(), "explicit sale alone credits the specimen's own wear-adjusted value")
	game.museum_panel.close()
	check(game.outpost_page == "lobby" and paused, "closing museum returns to the paused lobby")
	click("ReportButton")
	check(game.outpost_page == "report" and paused and game.outpost_panel.is_open, "last report has a separate paused page")
	check(str(game.outpost_panel._state.receipt) == str(game.progression.last_report.text), "report page receives the real expedition settlement")
	await shot("report")
	game.outpost_panel.close()
	check(game.outpost_page == "lobby" and paused, "closing report returns to lobby")
	var paid_balance: int = game.bank
	game.settle(false)
	check(game.bank == paid_balance, "duplicate settlement cannot credit again")
	click("ExpeditionsButton")
	click("Zone_deep")
	click("DeployButton")
	check(game.crystals.size() == 14 and game.trip_fee == 120 and game.bank == paid_balance - 120 and game.oxygen_limit == 75.0, "deep normal expedition charges its fee once and uses its area-scaled count and full upgraded oxygen")
	game.settle(true)
	var saved_bank: int = game.bank
	var saved_levels: Dictionary = game.progression.levels.duplicate()
	await destroy_game()
	game = make_game(save_path)
	await process_frame
	check(game.bank == saved_bank and game.progression.levels == saved_levels and game.progression.selected_zone == "deep", "new main restores bank, equipment and zone from independent disk profile")
	check(game.inventory.columns == 5 and game.inventory.rows == 5 and game.base_open and paused and game.outpost_page == "title", "relaunch reapplies upgrades and returns to title")
	click("EnterOutpostButton")
	check(game.outpost_page == "lobby" and game.bank == saved_bank, "relaunch enters lobby without replaying rewards")
	await destroy_game()
	var corrupt_path := OUT + "/corrupt-%d.cfg" % OS.get_process_id()
	var bad := "[profile]\nversion=999\nbank=42\n"
	var file := FileAccess.open(corrupt_path, FileAccess.WRITE)
	file.store_string(bad)
	file.close()
	game = make_game(corrupt_path)
	await process_frame
	check(game.profile_transient and game.progression.profile_path == "", "bad profile enters non-saving temporary mode")
	check(str(game.outpost_panel._state.message).contains("临时试玩"), "temporary mode is visible on title and lobby")
	click("EnterOutpostButton")
	click("ExpeditionsButton")
	click("DeployButton")
	check(game.on_moon, "temporary profile can still start free map")
	game.settle(false)
	check(FileAccess.get_file_as_string(corrupt_path) == bad, "bad profile survives trial/settlement unchanged")
	await destroy_game()
	print("BASE_PROGRESSION_INTEGRATION_OK title_lobby_zones_skills_report=true outpost_gm_touch_toggle=true real_node_then_confirm=true normal_full_oxygen=true buttons=6 oxygen_density=25/40 bag=5x5 starting_maps=21/26/14 radius=14 paid_once=true settlement_once=true persistence=true panel_pause=true detector_range=10/16 corruption_preserved=true preview=", preview)
	quit(1 if failed else 0)
