extends SceneTree

const Main = preload("res://main.gd")
const OUT := "res://.demo-data/ui-refresh"
const RESOLUTION := Vector2i(1100, 720)

var game: Node3D
var preview := false
var captures: Array[String] = []
var layout_results: Dictionary = {}


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, description: String) -> void:
	if not condition:
		push_error("UI PREVIEW FAIL: " + description)
		quit(1)
		assert(condition, description)


func run() -> void:
	create_timer(50.0).timeout.connect(func() -> void:
		push_error("UI PREVIEW timed out")
		quit(2))
	preview = OS.get_cmdline_user_args().has("--preview") and DisplayServer.get_name() != "headless"
	root.size = RESOLUTION
	if preview:
		check(DirAccess.make_dir_recursive_absolute(OUT) == OK, "create preview output directory")
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
	check(game.base_open and paused, "production base opens on startup")
	await shot("base")

	game.progression.bank = 6240
	game.progression.levels = {"drill": 1, "oxygen": 1, "oxygen_supply": 1, "boots": 1, "backpack": 2, "detector": 2}
	game.apply_progression()
	game.receipt = "本趟收入 1182 · 门票 60 · 净收益 +1122\n吸收氧矿 86 粒 · 恢复 %.1f 秒\n大型晶石 · 磨损 8%% · 售价 699\n中型晶石 · 磨损 22%% · 售价 312\n小型晶石 · 磨损 5%% · 售价 171\n首次出售已解锁估价" % (86 * Main.OXYGEN_PER_GRAIN)
	game.message = "安全回舱，物品已出售"
	game.sync_base_state()
	await shot("base-rich")
	check(not game.base_panel._receipt.tooltip_text.is_empty(), "settlement retains full tooltip data")

	game.base_panel.close()
	game.start_trip(false)
	check(game.on_moon and not paused, "real free expedition starts")
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
	check(Rect2(Vector2.ZERO, Vector2(RESOLUTION)).encloses(game.help_card.get_global_rect()), "compass help remains on screen")
	game.show_help = false
	game.update_hud()
	check(game.oxygen == 42.0, "HUD preview keeps oxygen frozen")
	check(game.reticle.visible and game.reticle.get_global_rect().has_point(Vector2(RESOLUTION) * 0.5), "real reticle remains at screen centre")

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
		var file := FileAccess.open(OUT + "/layout-results.json", FileAccess.WRITE)
		check(file != null, "layout evidence file opens")
		file.store_string(JSON.stringify(layout_results, "\t"))
	print("UI_PREVIEW_OK in_memory_profiles modal_bounds button_bounds nonoverlap_grid centre_reticle frozen_oxygen captures=", ",".join(captures))
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
	for frame in range(3):
		if update_world:
			game._process(1.0 / 60.0)
		await process_frame
	if game.base_open:
		check_modal(game.base_panel.find_child("BaseWindow", true, false), filename)
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
		check(root.get_texture().get_image().save_png(OUT + "/" + filename + ".png") == OK, "save " + filename)
		captures.append(filename)


func check_modal(window: Control, name: String) -> void:
	var viewport_rect := Rect2(Vector2.ZERO, Vector2(RESOLUTION))
	var window_rect := window.get_global_rect()
	check(viewport_rect.grow(1.0).encloses(window_rect), name + " window stays within 1100 x 720: " + str(window_rect))
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
