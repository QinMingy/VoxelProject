extends SceneTree

const Main = preload("res://main.gd")
const OUT := "res://.demo-data/ui-refresh"
const DEFAULT_RESOLUTION := Vector2i(1100, 720)

var game: Node3D
var preview := false
var captures: Array[String] = []
var layout_results: Dictionary = {}
var resolution := DEFAULT_RESOLUTION
var out_path := OUT


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, description: String) -> void:
	if not condition:
		push_error("UI PREVIEW FAIL: " + description)
		quit(1)
		assert(condition, description)


func run() -> void:
	create_timer(75.0).timeout.connect(func() -> void:
		push_error("UI PREVIEW timed out")
		quit(2))
	preview = OS.get_cmdline_user_args().has("--preview") and DisplayServer.get_name() != "headless"
	if OS.get_cmdline_user_args().has("--wide"):
		resolution = Vector2i(1600, 720)
		out_path += "-wide"
	root.size = resolution
	if preview:
		check(DirAccess.make_dir_recursive_absolute(out_path) == OK, "create preview output directory")
	game = Main.new()
	game.progression = Main.Progression.new("")
	game.progression.bank = 150
	game.appraisal = Main.Appraisal.new("")
	game.wants_mouse_capture = false
	game.auto_open_base = true
	root.add_child(game)
	# _ready() builds the actual camera and panels before automatic updates stop.
	game.set_process(false)
	game.set_physics_process(false)
	game.set_process_unhandled_input(false)
	await process_frame
	check(game.progression.profile_path.is_empty() and game.appraisal.catalogue_path.is_empty(), "both saves are in-memory fixtures")
	check(game.base_open and paused and game.outpost_page == "title", "production title opens on startup")
	check(game.radar_mode == Main.DetectorPanel.Mode.CIRCLE and game.detector_panel.display_mode == Main.DetectorPanel.Mode.CIRCLE, "new games default to the circular radar in both controller and HUD")
	await shot("title")
	var enter := game.outpost_panel.find_child("EnterOutpostButton", true, false) as Button
	check(enter != null and enter.is_visible_in_tree(), "title has a visible enter-outpost action")
	enter.pressed.emit()
	check(game.outpost_page == "lobby" and paused, "title action opens the real paused lobby")
	await shot("lobby")
	game.show_outpost("museum")
	check(game.museum_panel.is_open and paused and game.progression.museum_state.exhibits.is_empty(), "production museum opens empty for a new profile")
	await shot("museum-empty")
	_fill_museum()
	game.show_outpost("museum")
	check(game.progression.museum_state.exhibits.size() == 3 and game.progression.museum_state.warehouse.size() == 3, "visual museum fixture uses backend processing and leaves three real records unprocessed")
	await shot("museum")
	(game.museum_panel.find_child("CatalogueTab", true, false) as Button).pressed.emit()
	game.museum_panel.select_exhibit("chest")
	await shot("museum-catalogue")
	(game.museum_panel.find_child("ResearchButton", true, false) as Button).pressed.emit()
	check(game.outpost_page == "skills" and paused, "museum research opens the actual skill tree")
	check((game.skill_tree_panel.find_child("Skill_museum_appeal_1", true, false) as Button).is_visible_in_tree(), "museum research selects the actual museum tab")
	await shot("museum-research")
	(game.skill_tree_panel.find_child("EquipmentTechTab", true, false) as Button).pressed.emit()
	game.show_outpost("zones")
	check(game.base_panel.is_open and not game.skill_tree_panel.is_open and paused, "zone selection is separate from skills")
	check(game.base_panel.find_child("TrialButton", true, false) == null and game.base_panel.find_child("Buy_drill", true, false) == null, "normal zones contain no trial shortcut or combined upgrades")
	await shot("expeditions")
	game.show_outpost("skills")
	check(game.skill_tree_panel.is_open and not game.base_panel.is_open and paused, "skill tree is a separate paused page")
	check(game.skill_tree_panel._nodes.size() == 28, "equipment and museum branches expose twenty-eight real tier nodes across two tabs")
	var range_node := game.skill_tree_panel.find_child("Skill_excavation_range_1", true, false) as Button
	check(range_node != null and range_node.is_visible_in_tree(), "exploration range has a visible real skill node")
	range_node.pressed.emit()
	await shot("skills")

	game.progression.bank = 6240
	game.progression.levels.merge({"drill": 1, "oxygen": 1, "oxygen_supply": 1, "boots": 1, "backpack": 2, "detector": 2, "excavation_range": 3}, true)
	game.apply_progression()
	game.receipt = str(game.progression.last_report.get("text", ""))
	game.message = "已登记展品，其余物品可在仓库整理"
	game.sync_base_state()
	game.show_outpost("lobby")
	await shot("lobby-rich")
	game.show_outpost("skills")
	(game.skill_tree_panel.find_child("Skill_excavation_range_3", true, false) as Button).pressed.emit()
	await shot("skills-upgraded")
	check(not game.skill_tree_panel._detail_values.text.is_empty(), "selected skill retains exact current and next statistics")
	game.show_outpost("report")
	check(str(game.outpost_panel._state.receipt) == game.receipt and paused, "separate report retains the full settlement data")
	await shot("report")
	check(game.progression.buy_upgrade("museum_capacity").ok and game.progression.buy_upgrade("museum_capacity").ok, "preview expands the museum using actual upgrade transactions")
	var remaining: Array = game.progression.museum_state.warehouse.duplicate(true)
	for record: Dictionary in remaining:
		game.on_museum_donate(int(record.uid))
	game.sync_base_state()
	game.show_outpost("museum")
	check(game.progression.museum_state.exhibits.size() == 6 and game.progression.stats().museum_capacity == 6, "rich fixture opens all six real collected exhibit types and pedestals")
	await shot("museum-expanded")

	game.start_trip(false)
	check(game.on_moon and not paused and not game.outpost_panel.is_open and not game.skill_tree_panel.is_open and not game.base_panel.is_open, "real free expedition starts and closes every outpost page")
	game.terrain.reset_terrain(11235)
	game.spawn_crystals(11235)
	check(game.crystals.size() >= 3, "deterministic mine contains real specimens")
	var target: Node3D = game.crystals[1]
	# The second generated specimen is a real, partially exposed medium crystal.
	# No fake exposure percentages, camera substitutes or HUD labels are injected.
	_frame_target(target)
	game.oxygen = 42.0
	check(game.gain_oxygen(74) > 0.0, "preview tracks oxygen from actual absorption")
	game.oxygen = 42.0
	game.message = ""
	game.appraisal.known = true
	_capture_pointer()
	await warm_world(90)
	game.update_crystal_targets()
	game._physics_process(0.0)
	game._process(0.0)
	game.update_hud()
	check(game.crystal != null and game.crystal.visible, "normal HUD has an actual exposed crystal target")
	check(game.cursor.visible, "normal HUD has an actual mineable ground hit")
	await shot("hud-default-circle", true)
	check(not game.detector_panel.get_global_rect().intersects(game.specimen_card.get_global_rect()), "default circle does not overlap specimen details")
	game.set_radar_mode(Main.DetectorPanel.Mode.COMPASS)
	check(not game.detector_panel.get_global_rect().intersects(game.specimen_card.get_global_rect()), "compass does not overlap specimen details")
	check(not game.detector_panel.get_global_rect().intersects(game.oxygen_card.get_global_rect()), "compass does not overlap oxygen card")
	await shot("hud", true)
	game.set_radar_mode(Main.DetectorPanel.Mode.CIRCLE)
	await shot("hud-circle", true)
	check(not game.detector_panel.get_global_rect().intersects(game.specimen_card.get_global_rect()), "circular radar does not overlap specimen details")
	game.set_radar_mode(Main.DetectorPanel.Mode.COMPASS)
	game.show_help = true
	game.update_hud()
	await shot("help", true)
	check(not game.help_card.get_global_rect().intersects(game.oxygen_card.get_global_rect()), "compass help stays below oxygen card")
	check(Rect2(Vector2.ZERO, Vector2(resolution)).encloses(game.help_card.get_global_rect()), "compass help remains on screen")
	game.show_help = false
	game.update_hud()
	check(game.oxygen == 42.0, "HUD preview keeps oxygen frozen")
	check(game.reticle.visible and game.reticle.get_global_rect().has_point(Vector2(resolution) * 0.5), "real reticle remains at screen centre")

	game.suit.position = Vector3(15.0, 0.0, -10.0)
	game.suit.position.y = game.terrain.height_at(game.suit.position.x, game.suit.position.z)
	game.camera_anchor = game.suit.position + Vector3.UP * 0.95
	game.view_yaw = -0.55
	game.view_pitch = 0.66
	game.oxygen = 4.0
	await warm_world(55)
	game.update_crystal_targets()
	game._physics_process(0.0)
	game._process(0.0)
	game.update_hud()
	check(game.suit.position.distance_to(Main.LANDER) > 20.0, "urgent oxygen view is far from the hatch")
	await shot("low-oxygen", true)
	check(game.oxygen == 4.0 and game.on_moon, "urgent preview never auto-rescues or consumes oxygen")

	_fill_inventory()
	game.open_inventory()
	check(game.inventory_open and paused, "real backpack opens paused")
	game.inventory_panel._on_cell_clicked(Vector2i.ZERO)
	check(game.inventory_panel.selected_id == 9001, "a real 2 x 2 item is selected")
	await shot("inventory")
	check_inventory_geometry()
	game.inventory_panel.close()

	game.show_performance = true
	game.message = ""
	game.sync_gm_state()
	game.gm_panel.open()
	check(game.gm_open and paused, "real GM opens paused")
	await shot("gm")
	game.gm_panel.close()
	game.wants_mouse_capture = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if preview:
		var file := FileAccess.open(out_path + "/layout-results.json", FileAccess.WRITE)
		check(file != null, "layout evidence file opens")
		file.store_string(JSON.stringify(layout_results, "\t"))
	game.sfx.set_muted(true)
	await create_timer(0.10, true).timeout
	game.queue_free()
	await process_frame
	await create_timer(0.25, true).timeout
	print("UI_PREVIEW_OK title_lobby_zones_skills_report_museum in_memory_profiles modal_bounds button_bounds nonoverlap_grid centre_reticle frozen_oxygen resolution=", resolution, " captures=", ",".join(captures))
	quit(0)


func _frame_target(target: Node3D) -> void:
	game.suit.position = target.position + Vector3(-0.85, 0.0, 1.35)
	game.suit.position.y = game.terrain.height_at(game.suit.position.x, game.suit.position.z)
	game.view_yaw = atan2(-0.85, 1.35)
	game.suit.rotation.y = game.view_yaw
	game.camera_anchor = game.suit.position + Vector3.UP * 0.95
	var found := false
	for pitch: float in [0.60, 0.66, 0.72, 0.78, 0.84]:
		game.view_pitch = pitch
		game.update_camera()
		if not game.aim_at_terrain().is_empty():
			found = true
			break
	check(found, "production over-shoulder camera can aim at nearby soil")
	game.update_crystal_targets()


func _capture_pointer() -> void:
	game.wants_mouse_capture = true
	if preview:
		root.grab_focus()
		game.capture_mouse()
	if preview:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func warm_world(frames: int) -> void:
	for frame in range(frames):
		game._process(1.0 / 60.0)
		await process_frame


func shot(filename: String, update_world: bool = false) -> void:
	if game.base_open:
		# Capture settled production UI, not the intentionally faded entrance frame.
		await create_timer(0.35, true).timeout
	for frame in range(3):
		if update_world:
			game._process(1.0 / 60.0)
		await process_frame
	if game.base_open:
		match game.outpost_page:
			"museum":
				check_modal(game.museum_panel.find_child("MuseumWindow", true, false), filename)
			"zones":
				check_modal(game.base_panel.find_child("BaseWindow", true, false), filename)
			"skills":
				check_modal(game.skill_tree_panel.find_child("SkillTreeWindow", true, false), filename)
			_:
				check_modal(game.outpost_panel.find_child("OutpostWindow", true, false), filename)
	elif game.inventory_open:
		var inventory_window: PanelContainer = null
		for child: Node in game.inventory_panel._root_control.get_children():
			if child is PanelContainer:
				inventory_window = child
				break
		check(inventory_window != null, "inventory window exists")
		check_modal(inventory_window, filename)
	elif game.gm_open:
		check_modal(game.gm_panel.find_child("GMWindow", true, false), filename)
	elif preview:
		check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, filename + " captures pointer")
	if preview:
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(out_path + "/" + filename + ".png") == OK, "save " + filename)
		captures.append(filename)


func check_modal(window: Control, name: String) -> void:
	var viewport_rect := Rect2(Vector2.ZERO, Vector2(resolution))
	var window_rect := window.get_global_rect()
	check(viewport_rect.grow(1.0).encloses(window_rect), name + " window stays within " + str(resolution) + ": " + str(window_rect))
	var buttons: Array[Control] = []
	_collect_buttons(window, buttons)
	var painted: Array[Rect2] = []
	for button in buttons:
		if not button.is_visible_in_tree():
			continue
		var bounds := button.get_global_rect()
		check(bounds.size.x > 0.0 and bounds.size.y > 0.0, name + " button has area: " + str(button.name))
		check(bounds.position.x >= window_rect.position.x - 1.0 and bounds.end.x <= window_rect.end.x + 1.0, name + " button width stays inside window: " + str(button.name))
		var visible_bounds := bounds
		var parent: Node = button.get_parent()
		while parent != null and parent != window:
			if parent is ScrollContainer:
				visible_bounds = visible_bounds.intersection(parent.get_global_rect())
			parent = parent.get_parent()
		# Offscreen rows in a scroll container are intentionally clipped.
		if visible_bounds.has_area():
			check(window_rect.grow(1.0).encloses(visible_bounds), name + " visible button stays inside window: " + str(button.name))
			check(viewport_rect.grow(1.0).encloses(visible_bounds), name + " visible button stays on screen: " + str(button.name))
			for other in painted:
				check(not other.grow(-0.5).intersects(visible_bounds.grow(-0.5)), name + " visible button borders do not overlap")
			painted.append(visible_bounds)
	layout_results[name] = {"window": str(window_rect), "buttons_checked": buttons.size(), "visible_buttons": painted.size()}


func _collect_buttons(node: Node, result: Array[Control]) -> void:
	for child: Node in node.get_children():
		if child is BaseButton:
			result.append(child)
		_collect_buttons(child, result)


func _fill_museum() -> void:
	# Visual fixtures travel through the same validated ledger and registration
	# operations as gameplay. Production starts empty; no invented gallery models.
	var fixtures: Array[Dictionary] = [
		{"item_type": "crystal", "label": "小型晶石", "item_name": "小型晶石", "footprint": Vector2i(1, 1), "wear": 8, "base_value": 180, "icon_color": Color("#b875ed")},
		{"item_type": "crystal", "label": "中型晶石", "item_name": "中型晶石", "footprint": Vector2i(1, 2), "wear": 22, "base_value": 400, "icon_color": Color("#b875ed")},
		{"item_type": "crystal", "label": "大型晶石", "item_name": "大型晶石", "footprint": Vector2i(2, 2), "wear": 5, "base_value": 760, "icon_color": Color("#b875ed")},
	]
	for index in range(Main.AdventureItems.ITEMS.size()):
		var definition: Dictionary = Main.AdventureItems.definition(index)
		fixtures.append({"item_type": definition.id, "label": definition.label, "item_name": definition.label,
			"footprint": definition.footprint, "wear": [15, 25, 40][index], "base_value": definition.value, "icon_color": definition.color})
	var entry: Dictionary = game.progression.pay_entry("meadow", true)
	check(entry.ok, "museum preview starts a free isolated fixture expedition")
	var result: Dictionary = game.progression.settle_expedition(int(entry.trip_id), fixtures, false, 65.0)
	check(result.ok, "museum preview deposits validated persistent cargo")
	var records: Array = game.progression.museum_state.warehouse.duplicate(true)
	for record: Dictionary in records:
		if record.key in ["crystal_small", "chest", "shield"]:
			game.on_museum_donate(int(record.uid))
	game.sync_base_state()


func _fill_inventory() -> void:
	game.inventory.clear()
	check(game.inventory.columns == 5 and game.inventory.rows == 5, "purchased backpack dimensions are 5 x 5")
	var fixtures := [
		[9001, Vector2i(2, 2), 8, 760, Vector2i(0, 0), false],
		[9002, Vector2i(1, 2), 22, 400, Vector2i(2, 0), false],
		[9003, Vector2i(1, 1), 64, 180, Vector2i(3, 0), false],
		[9004, Vector2i(1, 2), 44, 400, Vector2i(3, 1), true],
		[9005, Vector2i(1, 1), 5, 180, Vector2i(4, 0), false],
		[9006, Vector2i(2, 2), 31, 760, Vector2i(0, 3), false],
		[9007, Vector2i(1, 2), 16, 400, Vector2i(3, 3), false],
	]
	for entry: Array in fixtures:
		var label := "大型晶石" if entry[3] == 760 else ("中型晶石" if entry[3] == 400 else "小型晶石")
		var item := {"id": entry[0], "world_id": entry[0], "label": label, "footprint": entry[1], "wear": entry[2], "base_value": entry[3]}
		check(game.inventory.try_add(item), "fixture item fits backpack")
		check(game.inventory.move_item(entry[0], entry[4], entry[5]), "fixture item placement uses real inventory rules")
	game.appraisal.known = true


func check_inventory_geometry() -> void:
	var grid: Control = game.inventory_panel._grid
	var cell_size: float = grid.cell_size
	var grid_bounds := Rect2(grid.global_position, Vector2(game.inventory.columns, game.inventory.rows) * cell_size)
	check(root.get_visible_rect().encloses(grid_bounds), "all 25 grid cells stay on screen")
	check(not grid_bounds.intersects(game.inventory_panel._details.get_global_rect()), "grid and item details do not overlap")
	var occupied: Array[Rect2] = []
	for item: Dictionary in game.inventory.items:
		var footprint: Vector2i = Main.Inventory.footprint(item, bool(item.rotated))
		var bounds := Rect2(grid.global_position + Vector2(item.pos) * cell_size, Vector2(footprint) * cell_size)
		check(grid_bounds.encloses(bounds), "item stays inside 5 x 5 grid")
		for previous in occupied:
			check(not previous.intersects(bounds), "backpack item rectangles never overlap")
		occupied.append(bounds)
	layout_results["inventory_grid"] = {"rect": str(grid_bounds), "cell_size": cell_size, "items": occupied.size(), "used_cells": game.inventory.used_cells()}
