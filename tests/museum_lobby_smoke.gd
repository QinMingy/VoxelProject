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

func pointer(at: Vector2) -> void:
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
	await process_frame

func click(owner: Node, node_name: String) -> void:
	var button := owner.find_child(node_name, true, false) as Button
	check(button != null and button.is_visible_in_tree() and not button.disabled,
		"real action is visible and enabled: " + node_name)
	await pointer(button.get_global_rect().get_center())
	await settle_ui()

func world_pointer(at: Vector3) -> void:
	var projected: Vector2 = scene.camera.unproject_position(at)
	var viewport_size := Vector2(lobby.viewport.size)
	check(Rect2(Vector2.ZERO, viewport_size).has_point(projected), "world pointer target is visible")
	var screen: Vector2 = lobby.room_view.global_position + projected * lobby.room_view.size / viewport_size
	await pointer(screen)

func stand_pointer(slot: int) -> void:
	var at: Vector3 = scene.LOCATIONS[slot] + Vector3(0, 0.64, 0)
	await world_pointer(at)
	await settle_ui()

func all_buttons(node: Node, result: Array[Button]) -> void:
	for child: Node in node.get_children():
		if child is Button:
			result.append(child)
		all_buttons(child, result)

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
	for location: Vector3 in scene.LOCATIONS:
		var point: Vector2 = scene.camera.unproject_position(location + Vector3.UP * 0.65)
		check(Rect2(Vector2.ZERO, Vector2(lobby.viewport.size)).has_point(point), "all six stands remain in camera")

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
		var item: Dictionary = row.duplicate(true)
		item["wear"] = 8 + cargo.size() * 5
		cargo.append(item)
	var entry: Dictionary = game.progression.pay_entry("meadow", true)
	check(entry.ok, "isolated fixture starts a valid free expedition")
	var result: Dictionary = game.progression.settle_expedition(int(entry.trip_id), cargo, false, 65.0)
	check(result.ok and game.progression.museum_state.warehouse.size() == 6,
		"fixture uses the actual validated cargo settlement")
	var records: Array = game.progression.museum_state.warehouse.duplicate(true)
	for record: Dictionary in records:
		game.on_museum_donate(int(record.uid))
	check(game.progression.museum_state.exhibits.size() == 6, "six actual item types enter the collection")
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
	check(scene._capacity == 3 and scene._bases.size() == 6, "initial three unlocked stands preserve the six-slot economy")
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
	await world_pointer(Vector3(0, 0.02, 0))
	await create_timer(0.5, true).timeout
	check(game.outpost_page == "lobby", "floor click does not open a menu or control a protagonist")
	check(paused and game.oxygen == oxygen and game.suit.position.is_equal_approx(world_actor),
		"audience activity neither advances oxygen nor moves the expedition character")
	await stand_pointer(0)
	check(game.outpost_page == "museum" and game.museum_panel._tab == "catalogue"
		and game.museum_panel.selected_stand == 0, "real unlocked stand click opens the matching catalogue slot")
	await check_suspended()
	await back_from(game.museum_panel)
	await stand_pointer(5)
	check(game.outpost_page == "skills" and game.skill_tree_panel._active_tab == "museum",
		"locked stand click opens museum expansion research")
	await check_suspended()
	await back_from(game.skill_tree_panel)
	await click(game.outpost_panel, "MuseumButton")
	check(game.museum_panel.is_open and game.museum_panel._tab == "warehouse",
		"warehouse button resets the old catalogue tab to warehouse")
	await back_from(game.museum_panel)
	await click(game.outpost_panel, "SkillsButton")
	check(game.skill_tree_panel.is_open and game.skill_tree_panel._active_tab == "equipment",
		"equipment button selects the equipment tree after museum research")
	await back_from(game.skill_tree_panel)

	deposit_real_fixture()
	check(scene._capacity == 3 and scene.displayed_keys.size() == 3, "only three owned displays fit before expansion")
	for expected: int in [4, 6]:
		var upgrade: Dictionary = game.progression.buy_upgrade("museum_capacity")
		check(upgrade.ok, "actual capacity upgrade succeeds")
		game.sync_base_state()
		var keys: Array = game.progression.museum_state.exhibits.keys()
		for slot in range(expected):
			var placement: Dictionary = game.progression.place_exhibit(str(keys[slot]), slot)
			check(placement.ok, "actual placement into purchased slot succeeds")
		game.sync_base_state()
		check(scene._capacity == expected and scene.displayed_keys.size() == expected,
			"lobby reflects purchased capacity and actual placement: " + str(expected))
		check(scene._models.size() == expected, "one real voxel model is shown per occupied slot")
	for slot: int in scene._models:
		var model: Node3D = scene._models[slot]
		var key: String = game.progression.museum_state.slots[slot]
		check(model is Main.Crystal and not model._geometry.cells.is_empty(), "display uses canonical gameplay voxel geometry")
		check(model.wear_percent == game.progression.museum_state.exhibits[key].item.wear,
			"display preserves stored specimen wear")
	for resolution: Vector2i in [Vector2i(960, 540), Vector2i(1100, 720), Vector2i(1600, 720)]:
		await check_layout(resolution)
		await shot("populated-%d" % resolution.x)
	await check_layout(Vector2i(1100, 720))
	await stand_pointer(5)
	check(game.outpost_page == "museum" and game.museum_panel.selected_stand == 5
		and game.museum_panel._tab == "catalogue", "purchased last stand now opens its actual catalogue slot")
	await back_from(game.museum_panel)
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
	print("MUSEUM_LOBBY_OK real_pointer=true no_protagonist=true audience=true real_collection=true capacity_3_4_6=true hidden_render_disabled=true sizes_960_1100_1600=true in_memory=true captures=", ",".join(captures))
	quit(0)
