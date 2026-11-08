extends SceneTree

# Exercise the production lobby through real pointer events and the existing
# progression ledger. Both profile owners are in-memory: no player save is read
# or replaced, and only optional native preview PNGs are written.
const Main = preload("res://main.gd")
const OUT := "res://.build/museum-lobby-preview"

var game: Node3D
var lobby: Control
var scene: Node3D
var captures: Array[String] = []
var preview := false

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, description: String) -> void:
	if not condition:
		push_error("MUSEUM LOBBY FAIL: " + description)
		quit(1)
		assert(condition, description)

func settle_ui() -> void:
	await create_timer(0.35, true).timeout
	await process_frame

func pointer_now(at: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	root.push_input(motion, true)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = at
		event.global_position = at
		event.pressed = pressed
		root.push_input(event, true)

func pointer(at: Vector2) -> void:
	pointer_now(at)
	await process_frame

func click(owner: Node, node_name: String) -> void:
	var button := owner.find_child(node_name, true, false) as Button
	check(button != null and button.is_visible_in_tree() and not button.disabled,
		"real action is visible and enabled: " + node_name)
	await pointer(button.get_global_rect().get_center())
	await settle_ui()

func world_screen(at: Vector3) -> Vector2:
	var projected: Vector2 = scene.camera.unproject_position(at)
	var viewport_size := Vector2(lobby.viewport.size)
	check(Rect2(Vector2.ZERO, viewport_size).has_point(projected), "world pointer target is visible")
	return lobby.room_view.global_position + projected * lobby.room_view.size / viewport_size

func world_pointer(at: Vector3) -> void:
	await pointer(world_screen(at))

func overview() -> void:
	# Selection focuses the shared camera; reset to the hall before aiming a
	# pointer at a different stand or at the floor.
	scene.set_selected_stand(-1)
	await settle_ui()

func stand_pointer(slot: int) -> void:
	var at: Vector3 = scene.LOCATIONS[slot] + Vector3(0, 0.64, 0)
	await world_pointer(at)
	await settle_ui()

func all_buttons(node: Node, result: Array[Button]) -> void:
	for child: Node in node.get_children():
		if child is Button:
			result.append(child)
		all_buttons(child, result)

func scene_inventory(node: Node, result: Dictionary) -> void:
	var script: Script = node.get_script()
	if script != null and script.resource_path in ["res://museum_lobby.gd", "res://museum_display.gd"]:
		result.halls.append(node.get_instance_id())
	if node is SubViewport and node.own_world_3d:
		result.worlds.append(node.get_instance_id())
	if node is Camera3D and scene.is_ancestor_of(node):
		result.cameras.append(node.get_instance_id())
	if node.name.begins_with("MuseumVisitor_"):
		result.visitors.append(node.get_instance_id())
	for child: Node in node.get_children():
		scene_inventory(child, result)

func shared_snapshot() -> Dictionary:
	var visitor_ids: Array[int] = []
	var poses: Array[Transform3D] = []
	for visitor: Node3D in scene.visitors:
		visitor_ids.append(visitor.get_instance_id())
		poses.append(visitor.transform)
	return {"hall": scene.get_instance_id(), "viewport": lobby.viewport.get_instance_id(),
		"world": lobby.viewport.find_world_3d().get_instance_id(), "camera": scene.camera.get_instance_id(),
		"view_rect": lobby.room_view.get_global_rect(), "viewport_size": lobby.viewport.size,
		"visitors": visitor_ids, "poses": poses, "visits": scene._visitor_states.duplicate(true),
		"clock": scene._comment_clock, "next_comment": scene._next_comment_at,
		"remaining": scene._bubble_remaining, "text": scene.bubble_text,
		"bubble_slot": scene.bubble_slot, "bubble_visible": scene.bubble_visible}

func check_shared_continuity(before: Dictionary, page: String) -> void:
	check(game.outpost_page == page and game.outpost_panel.is_open and game.outpost_panel.page == page,
		"drawer and hall share the requested active outpost page: " + page)
	var after := shared_snapshot()
	for key: String in before:
		check(after[key] == before[key], "lobby/drawer switch preserves shared scene state: " + key)
	check(scene._active and lobby.viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS,
		"shared exhibition keeps rendering and visitors active during drawer navigation")
	check(lobby._management_mode == (page == "museum"), "drawer controls only the hall management UI mode")
	check(lobby._header.is_visible_in_tree() == (page == "lobby")
		and lobby._footer.is_visible_in_tree() == (page == "lobby"), "management mode hides hall header and footer")
	var inventory := {"halls": [], "worlds": [], "cameras": [], "visitors": []}
	scene_inventory(game, inventory)
	check(inventory.halls == [scene.get_instance_id()] and inventory.worlds == [lobby.viewport.get_instance_id()],
		"only one exhibition scene and one independent SubViewport exist in production Main")
	check(inventory.cameras == [scene.camera.get_instance_id()] and inventory.visitors == before.visitors,
		"one exhibition camera and one persistent visitor group serve both pages")
	for property: Dictionary in game.museum_panel.get_property_list():
		check(property.name not in ["_display", "_viewport"], "warehouse drawer owns no private 3D renderer")

func check_management_pointer(slot: int) -> void:
	await overview()
	var before := shared_snapshot()
	var at := world_screen(scene.LOCATIONS[slot] + Vector3(0, 0.64, 0))
	check(not game.museum_panel._window.get_global_rect().has_point(at), "chosen physical stand is outside the drawer")
	pointer_now(at)
	check_shared_continuity(before, "museum")
	check(game.museum_panel.selected_stand == slot and scene.selected_stand == slot,
		"exposed stand pointer updates the same scene's placement target")
	await settle_ui()
	check(scene.camera.global_position.distance_to(scene.LOCATIONS[slot] + Vector3.UP * scene.FOCUS_HEIGHT) < scene.FOCUS_DISTANCE + 1.5,
		"selecting a stand swings the hall camera onto it")

func check_layout(resolution: Vector2i) -> void:
	# Exercise the actual compact layout as well as each screenshot size, rather
	# than retaining the project's 720px logical canvas in a smaller window.
	root.content_scale_size = resolution
	root.size = resolution
	await settle_ui()
	# canvas_items stretch can keep a larger logical viewport for a small native
	# window. Control rectangles and root-local pointer events use that space.
	var screen := root.get_visible_rect()
	check(screen.grow(1).encloses(lobby.room_view.get_global_rect()), "3D view fits " + str(resolution))
	check(lobby.room_view.size.x > 0 and lobby.room_view.size.y > 0, "3D view has area")
	var buttons: Array[Button] = []
	all_buttons(game.outpost_panel, buttons)
	var painted: Array[Rect2] = []
	for button: Button in buttons:
		if not button.is_visible_in_tree():
			continue
		var bounds := button.get_global_rect()
		check(bounds.has_area() and screen.grow(1).encloses(bounds), "button fits screen: " + str(button.name))
		for other: Rect2 in painted:
			check(not bounds.grow(-0.5).intersects(other.grow(-0.5)), "visible lobby buttons do not overlap")
		painted.append(bounds)
	for node_name: String in ["SkillsButton", "MuseumButton", "ExpeditionsButton"]:
		var action := game.outpost_panel.find_child(node_name, true, false) as Button
		check(action != null and action.is_visible_in_tree(), "primary action is visible: " + node_name)
		check(action.size.x >= 100 and action.size.y >= 44, "primary action remains touch-sized")
	var visible: Array = [scene.selected_stand] if scene.selected_stand >= 0 else range(scene.current_zone * 12, scene.current_zone * 12 + 12)
	for index: int in visible:
		var point: Vector2 = scene.camera.unproject_position(scene.LOCATIONS[index] + Vector3.UP * 0.65)
		check(Rect2(Vector2.ZERO, Vector2(lobby.viewport.size)).has_point(point), "the active stand remains in camera")

func shot(filename: String) -> void:
	if not preview:
		return
	# Capture a naturally timed audience comment in the main-size previews.
	if filename.ends_with("1100"):
		for attempt in range(120):
			if scene.bubble_visible:
				break
			await create_timer(0.1, true).timeout
	await settle_ui()
	await RenderingServer.frame_post_draw
	if scene.bubble_visible:
		var bounds: Rect2 = scene._bubble.get_global_rect()
		check(bounds.size.y <= 100, "initial and subsequent comments stay compact after real rendering")
		check(Rect2(Vector2.ZERO, Vector2(lobby.viewport.size)).grow(1).encloses(bounds), "speech bubble stays inside the hall viewport")
	check(root.get_texture().get_image().save_png(OUT + "/" + filename + ".png") == OK, "save " + filename)
	captures.append(filename)

func back_from(panel: Node) -> void:
	if panel == game.museum_panel:
		var before := shared_snapshot()
		var close_button := panel.find_child("CloseButton", true, false) as Button
		pointer_now(close_button.get_global_rect().get_center())
		check_shared_continuity(before, "lobby")
		check(scene.selected_stand == -1, "closing the drawer clears only the stand selection")
		await settle_ui()
	else:
		await click(panel, "CloseButton")
	check(game.outpost_page == "lobby" and paused, "subpage returns to the paused museum lobby")
	check(lobby.viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS and scene._active,
		"returning to lobby reactivates its rendering and input")

func check_suspended() -> void:
	check(lobby.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED and not scene._active,
		"hidden lobby stops rendering and movement")
	var positions: Array[Vector3] = []
	for visitor: Node3D in scene.visitors:
		positions.append(visitor.position)
	await create_timer(0.2, true).timeout
	for index in range(scene.visitors.size()):
		check(scene.visitors[index].position.is_equal_approx(positions[index]), "hidden visitors stop walking")
	check(not scene.bubble_visible, "hidden hall does not keep a speech bubble visible")

func deposit_real_fixture() -> void:
	var cargo: Array[Dictionary] = []
	for row: Dictionary in Main.Progression.Museum.CATEGORIES:
		cargo.append(row.duplicate(true))
	var entry: Dictionary = game.progression.pay_entry("meadow", true)
	check(entry.ok, "isolated fixture starts a valid free expedition")
	var result: Dictionary = game.progression.settle_expedition(int(entry.trip_id), cargo, false, 65.0)
	check(result.ok and game.progression.museum_state.items.size() == Main.Progression.Museum.CATEGORIES.size(),
		"fixture uses the actual validated collection settlement")
	game.sync_base_state()

func run() -> void:
	create_timer(90.0, true).timeout.connect(func() -> void:
		push_error("MUSEUM LOBBY timed out")
		quit(2))
	preview = DisplayServer.get_name() != "headless"
	if preview:
		check(DirAccess.make_dir_recursive_absolute(OUT) == OK, "create isolated screenshot directory")
	root.size = Vector2i(1100, 720)
	game = Main.new()
	game.progression = Main.Progression.new("")
	game.progression.bank = 5000
	game.appraisal = Main.Appraisal.new("")
	game.wants_mouse_capture = false
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.set_process_unhandled_input(false)
	game.sfx.set_muted(true)
	await settle_ui()
	lobby = game.outpost_panel.lobby
	scene = lobby.scene
	check(game.progression.profile_path.is_empty() and game.appraisal.catalogue_path.is_empty(),
		"both progression and appraisal are isolated in-memory owners")
	check(game.outpost_page == "title" and paused, "normal startup remains on the title")
	await check_suspended()
	await click(game.outpost_panel, "EnterOutpostButton")
	check(game.outpost_page == "lobby" and paused and not game.on_moon, "enter opens museum as the actual lobby")
	check(scene.displayed_keys.is_empty() and scene._models.is_empty(), "fresh lobby never fabricates owned exhibits")
	check(scene._capacity == 6 and scene._bases.size() == 48, "initial cap is six stands out of four zones of twelve")
	check(lobby.viewport.own_world_3d and lobby.viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS,
		"lobby renders an independent active 3D world")
	for resolution: Vector2i in [Vector2i(960, 540), Vector2i(1100, 720), Vector2i(1600, 720)]:
		await check_layout(resolution)
		await shot("empty-%d" % resolution.x)
	await check_layout(Vector2i(1100, 720))

	# This passes through every production Control ancestor, catching transparent
	# overlay/input filters which direct calls to handle_pointer would miss.
	check(scene.find_child("LobbyAstronaut", true, false) == null, "hall contains no controllable protagonist")
	check(scene.visitors.size() >= 3, "hall has autonomous visitors")
	var oxygen: float = game.oxygen
	var world_actor: Vector3 = game.suit.position
	await world_pointer(scene.ZONE_CENTERS[scene.current_zone] + Vector3(0, 0.02, 0))
	await create_timer(0.5, true).timeout
	check(game.outpost_page == "lobby", "floor click does not open a menu or control a protagonist")
	check(paused and game.oxygen == oxygen and game.suit.position.is_equal_approx(world_actor),
		"audience activity neither advances oxygen nor moves the expedition character")
	# Build a live conversation without waiting for real wall time. Navigation
	# itself must preserve every timer, pose and path before the next frame.
	for tick in range(160):
		if scene.bubble_visible and scene._bubble_remaining > 1.0:
			break
		scene._process(0.1)
	check(scene.bubble_visible, "empty hall has a live audience comment before opening the drawer")
	var shared_before := shared_snapshot()
	pointer_now(world_screen(scene.LOCATIONS[0] + Vector3(0, 0.64, 0)))
	check(game.outpost_page == "museum" and game.museum_panel.selected_stand == 0,
		"real unlocked stand click selects the matching stand")
	check_shared_continuity(shared_before, "museum")
	await settle_ui()
	check(scene._comment_clock > float(shared_before.clock), "comments continue advancing while the drawer is open")
	await check_management_pointer(2)
	await overview()
	await world_pointer(scene.ZONE_CENTERS[scene.current_zone] + Vector3(0, 0.02, 0))
	check(game.outpost_page == "museum" and game.museum_panel.selected_stand == 2,
		"exposed floor pointer passes through the drawer overlay without changing placement")
	await overview()
	await stand_pointer(8)
	check(game.outpost_page == "skills" and game.skill_tree_panel._active_tab == "museum",
		"locked stand click also opens expansion research while the drawer is open")
	await check_suspended()
	await back_from(game.skill_tree_panel)
	shared_before = shared_snapshot()
	var warehouse_button := game.outpost_panel.find_child("MuseumButton", true, false) as Button
	pointer_now(warehouse_button.get_global_rect().get_center())
	check_shared_continuity(shared_before, "museum")
	await settle_ui()
	check(game.museum_panel.is_open and game.museum_panel.selected_stand == -1,
		"warehouse button opens the merged drawer without a stale stand target")
	await back_from(game.museum_panel)
	await click(game.outpost_panel, "SkillsButton")
	check(game.skill_tree_panel.is_open and game.skill_tree_panel._active_tab == "equipment",
		"equipment button selects the equipment tree after museum research")
	await back_from(game.skill_tree_panel)

	deposit_real_fixture()
	check(scene._capacity == 6 and scene.displayed_keys.size() == 6, "only six owned displays fit before expansion")
	for expected: int in [12, 24]:
		var upgrade: Dictionary = game.progression.buy_upgrade("museum_capacity")
		check(upgrade.ok, "actual capacity upgrade succeeds")
		game.sync_base_state()
		var keys: Array = game.progression.museum_state.items.keys()
		var placed := mini(int(expected), keys.size())
		for slot in range(placed):
			var placement: Dictionary = game.progression.place_exhibit(str(keys[slot]), slot)
			check(placement.ok, "actual placement into purchased slot succeeds")
		game.sync_base_state()
		check(scene._capacity == expected and scene.displayed_keys.size() == placed,
			"lobby reflects purchased capacity and actual placement: " + str(expected))
		check(scene._models.size() == placed, "one real voxel model is shown per occupied slot")
	for slot: int in scene._models:
		var model: Node3D = scene._models[slot]
		var key: String = game.progression.museum_state.slots[slot]
		check(model is Main.Crystal and not model._geometry.cells.is_empty(), "display uses canonical gameplay voxel geometry")
		check(model.wear_percent == 0 and game.progression.museum_summary().exhibits[key].level == 1,
			"display uses the shared item model at its collected level")
	for resolution: Vector2i in [Vector2i(960, 540), Vector2i(1100, 720), Vector2i(1600, 720)]:
		await check_layout(resolution)
		await shot("populated-%d" % resolution.x)
	await check_layout(Vector2i(1100, 720))
	await stand_pointer(5)
	check(game.outpost_page == "museum" and game.museum_panel.selected_stand == 5,
		"purchased last stand now opens its actual stand target")
	for resolution: Vector2i in [Vector2i(960, 540), Vector2i(1100, 720), Vector2i(1600, 720)]:
		root.content_scale_size = resolution
		root.size = resolution
		await settle_ui()
		await check_management_pointer(2)
		await shot("management-%d" % resolution.x)
	await back_from(game.museum_panel)
	await settle_ui()
	var base_distance: float = scene.camera.global_position.distance_to(scene.ZONE_CENTERS[scene.current_zone] + Vector3(0, 0.1, 0))
	scene.adjust_zoom(-2.0)
	await settle_ui()
	var zoomed_distance: float = scene.camera.global_position.distance_to(scene.ZONE_CENTERS[scene.current_zone] + Vector3(0, 0.1, 0))
	check(zoomed_distance < base_distance - 0.5, "mouse wheel zoom moves the overview camera closer")
	scene.set_selected_stand(0)
	await settle_ui()
	var focus_distance: float = scene.camera.global_position.distance_to(scene.LOCATIONS[0])
	scene.adjust_zoom(2.0)
	await settle_ui()
	check(absf(focus_distance - scene.camera.global_position.distance_to(scene.LOCATIONS[0])) < 0.2,
		"wheel zoom is ignored while a stand is focused")
	scene.reset_view()
	await settle_ui()
	check(scene.zoom == 1.0 and scene.selected_stand == -1, "closing resets zoom and selection")
	await click(game.outpost_panel, "ExpeditionsButton")
	check(game.outpost_page == "zones" and game.base_panel.is_open and paused, "departure opens existing zone selection")
	await check_suspended()
	await click(game.base_panel, "Zone_meadow")
	await click(game.base_panel, "DeployButton")
	check(game.on_moon and not paused and not game.base_open, "confirmed departure starts a real expedition")
	await check_suspended()
	check(game.progression.profile_path.is_empty() and game.appraisal.catalogue_path.is_empty(), "no test action enabled persistent saves")
	game.queue_free()
	await process_frame
	await create_timer(0.15, true).timeout
	print("MUSEUM_LOBBY_OK shared_world_camera_visitors=true drawer_continuity=true real_pointer=true no_protagonist=true audience=true real_collection=true capacity_6_to_48=true hidden_render_disabled=true sizes_960_1100_1600=true in_memory=true captures=", ",".join(captures))
	quit(0)
