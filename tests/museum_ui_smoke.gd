extends SceneTree

# The warehouse is a drawer over Main's persistent hall. Both save owners are
# in memory; only optional native screenshot files are written.
const Main = preload("res://main.gd")
const OUT := "res://.build/museum-ui-preview"
var game: Node3D
var panel: CanvasLayer
var scene: Node3D

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, description: String) -> void:
	if not value:
		push_error("MUSEUM UI FAIL: " + description)
		quit(1)
		assert(value, description)

func settle_ui() -> void:
	await create_timer(0.25, true).timeout
	await process_frame

func button_named(node_name: String) -> Button:
	var button := panel.find_child(node_name, true, false) as Button
	check(button != null, "production drawer button exists: " + node_name)
	return button

func reveal(control: Control) -> void:
	await process_frame
	var parent := control.get_parent()
	while parent != null and parent != panel:
		if parent is ScrollContainer:
			parent.ensure_control_visible(control)
			await process_frame
		parent = parent.get_parent()
	await process_frame
	var bounds := control.get_global_rect()
	check(root.get_visible_rect().grow(1).encloses(bounds), "scrolling exposes the whole action: " + str(control.name))
	parent = control.get_parent()
	while parent != null and parent != panel:
		if parent is ScrollContainer:
			check(parent.get_global_rect().grow(1).encloses(bounds), "action is not clipped by its scroll viewport: " + str(control.name))
		parent = parent.get_parent()

func pointer_click(button: Button) -> void:
	check(button.is_visible_in_tree() and not button.disabled, "real pointer target is visible and enabled: " + str(button.name))
	await reveal(button)
	var at := button.get_global_rect().get_center()
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
	await settle_ui()

func specimen(key: String) -> Dictionary:
	return Main.Progression.Museum.definition(key)

func collect(cargo: Array) -> Dictionary:
	var trip: Dictionary = game.progression.pay_entry("meadow", true)
	check(trip.ok, "memory fixture opens a real expedition ledger")
	var receipt: Dictionary = game.progression.settle_expedition(int(trip.trip_id), cargo, false, 65.0)
	check(receipt.ok, "memory fixture settles validated cargo")
	game.sync_base_state()
	return receipt

func check_pure_drawer(node: Node) -> void:
	check(not node is SubViewport and not node is Node3D, "warehouse UI does not instantiate another 3D world")
	for child: Node in node.get_children():
		check_pure_drawer(child)

func check_touch_buttons(node: Node) -> void:
	if node is Button and node.is_visible_in_tree():
		check(node.size.x >= 48 and node.size.y >= 48, "drawer action has at least a 48px touch target: " + str(node.name))
	for child: Node in node.get_children():
		check_touch_buttons(child)

func capture(filename: String) -> void:
	await settle_ui()
	check(root.get_visible_rect().grow(1).encloses(panel._window.get_global_rect()), "left drawer stays on screen: " + filename)
	check(panel._window.size.x < root.get_visible_rect().size.x * 0.5, "the drawer leaves the shared hall exposed")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		check(DirAccess.make_dir_recursive_absolute(OUT) == OK, "create isolated native preview directory")
		check(root.get_texture().get_image().save_png(OUT + "/" + filename + ".png") == OK, "save native drawer preview")

func run() -> void:
	create_timer(90.0, true).timeout.connect(func() -> void:
		push_error("MUSEUM UI timed out")
		quit(2))
	root.content_scale_size = Vector2i(1100, 720)
	root.size = Vector2i(1100, 720)
	game = Main.new()
	game.progression = Main.Progression.new("")
	game.progression.bank = 10000
	game.appraisal = Main.Appraisal.new("")
	game.wants_mouse_capture = false
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.set_process_unhandled_input(false)
	game.sfx.set_muted(true)
	await settle_ui()
	game.show_outpost("lobby")
	game.show_outpost("museum")
	panel = game.museum_panel
	scene = game.outpost_panel.lobby.scene
	await settle_ui()
	check_pure_drawer(panel)
	check(paused and panel.is_open and game.outpost_panel.is_open and scene._active,
		"warehouse drawer shares the live paused exhibition")
	check(scene._models.is_empty() and game.progression.museum_state.items.is_empty(),
		"fresh drawer and room contain no invented items")
	var shared_id: int = scene.get_instance_id()
	var camera_id: int = scene.camera.get_instance_id()
	await capture("museum-empty-1100")

	collect([specimen("chest")])
	check(game.progression.museum_state.items.chest.copies == 1 and scene.displayed_keys == ["chest"],
		"the first find is owned and displayed automatically")
	var model: Node3D = scene._models[0]
	check(model is Main.Crystal and model.item_type == "chest" and model.get_world_cells().size() == 384,
		"shared pedestal reuses canonical voxel treasure-chest geometry")
	check(panel._item_list.get_child_count() == 1 and panel._item_buttons.has("chest"),
		"merged drawer lists only owned item types")
	await pointer_click(button_named("Item_chest"))
	check(panel.selected_key == "chest" and panel._detail_info.text.contains("Lv.1")
		and panel._detail_info.text.contains("展台收益"), "detail card shows level and expedition income")
	check(panel._item_buttons["chest"].icon != null, "item rows carry a palette swatch instead of a live render target")
	check(panel._item_buttons["chest"].find_child("ExhibitTag_chest", true, false) != null,
		"displayed items carry an exhibit tag in the list")
	await capture("museum-items-1100")

	panel.select_stand(1)
	await settle_ui()
	check(panel.selected_stand == 1 and scene.selected_stand == 1 and panel.selected_key.is_empty()
		and panel._action_button.text == "空展台", "selecting an empty stand clears the list selection")
	await pointer_click(button_named("Item_chest"))
	check(panel.selected_key == "chest" and panel._action_button.text == "安装",
		"choosing an item stages it for installation")
	await pointer_click(button_named("NextStandButton"))
	check(panel.selected_stand == 2 and scene.selected_stand == 2 and panel.selected_key.is_empty(),
		"arrow switching clears the staged item")
	await pointer_click(button_named("PrevStandButton"))
	check(panel.selected_stand == 1 and scene.selected_stand == 1, "arrow returns to the previous stand")
	await pointer_click(button_named("Item_chest"))
	check(is_instance_valid(scene._preview_model), "the selected item previews its model on the chosen stand")
	await settle_ui()
	check(scene.camera.global_position.distance_to(scene.LOCATIONS[1] + Vector3.UP * scene.FOCUS_HEIGHT) < scene.FOCUS_DISTANCE + 1.5,
		"selecting a stand swings the shared camera onto it")
	await capture("museum-focus-1100")
	await pointer_click(panel._action_button)
	check(game.progression.museum_state.slots[1] == "chest" and scene._models.has(1) and not scene._models.has(0),
		"install moves the specimen to the chosen pedestal")
	check(not is_instance_valid(scene._preview_model), "installed item replaces the preview with the real display")
	check(panel.selected_key.is_empty() and panel._detail_info.text.contains("当前陈列"),
		"after install the panel shows the stand's own display")
	check(panel._action_button.text == "拆卸", "the same action becomes remove once installed")
	await pointer_click(panel._action_button)
	check(game.progression.museum_state.slots[1] == "" and scene._models.is_empty()
		and game.progression.museum_state.items.has("chest"), "remove keeps the owned specimen in the collection")
	check(panel._item_buttons["chest"].find_child("ExhibitTag_chest", true, false) == null,
		"removing the exhibit clears its list tag")
	check(panel._action_button.disabled and panel._action_button.text == "空展台", "an emptied stand awaits a new choice")
	await pointer_click(button_named("Item_chest"))
	await pointer_click(panel._action_button)
	check(scene._models.has(1), "a removed specimen can be installed again")

	for level in range(3):
		var cargo: Array = []
		for category: Dictionary in Main.Progression.Museum.CATEGORIES:
			if str(category.key) == "chest" and level == 0:
				continue
			cargo.append(specimen(str(category.key)))
		collect(cargo)
	check(game.progression.museum_state.items.size() == Main.Progression.Museum.CATEGORIES.size() and game.progression.museum_state.items.chest.copies == 3,
		"duplicates accumulate only on their own item type")
	check(Main.Progression.Museum.level_for(3) == 2 and panel._item_buttons.has("crystal_small"),
		"duplicates raise the item's level and appear in the merged list")
	for expected_capacity: int in [12, 24]:
		check(game.progression.buy_upgrade("museum_capacity").ok, "actual capacity research succeeds")
		game.sync_base_state()
		check(scene._capacity == expected_capacity, "shared room reflects purchased capacity")
	for index in range(Main.Progression.Museum.CATEGORIES.size()):
		var key: String = Main.Progression.Museum.CATEGORIES[index].key
		game.on_museum_place(key, index)
	check(scene._models.size() == Main.Progression.Museum.CATEGORIES.size(), "every owned specimen is rendered by the same persistent room")
	panel.select_stand(1)
	panel.select_item("crystal_small")
	await settle_ui()
	check(panel._action_button.text == "替换", "an occupied stand offers replace instead of install")
	await pointer_click(panel._action_button)
	check(game.progression.museum_state.slots[1] == "crystal_small"
		and game.progression.museum_state.items.has("chest"), "replace swaps the display without losing either item")
	check(scene.get_instance_id() == shared_id and scene.camera.get_instance_id() == camera_id,
		"placement updates preserve room and camera identities")

	var scroll_rect: Rect2 = panel._item_scroll.get_global_rect()
	var key_before: String = panel.selected_key
	var touch_press := InputEventScreenTouch.new()
	touch_press.index = 0
	touch_press.position = scroll_rect.position + Vector2(40, scroll_rect.size.y - 24)
	touch_press.pressed = true
	root.push_input(touch_press, true)
	for step in range(4):
		var drag := InputEventScreenDrag.new()
		drag.index = 0
		drag.position = touch_press.position + Vector2(0, -30.0 * float(step + 1))
		drag.relative = Vector2(0, -30)
		drag.screen_relative = Vector2(0, -30)
		root.push_input(drag, true)
		await process_frame
	var touch_release := InputEventScreenTouch.new()
	touch_release.index = 0
	touch_release.position = touch_press.position + Vector2(0, -120)
	touch_release.pressed = false
	root.push_input(touch_release, true)
	await settle_ui()
	check(panel._item_scroll.scroll_vertical > 20, "touch drag scrolls the warehouse list")
	check(panel.selected_key == key_before, "dragging the list does not select a row")

	for resolution: Vector2i in [Vector2i(960, 540), Vector2i(1100, 720), Vector2i(1600, 720)]:
		root.content_scale_size = resolution
		root.size = resolution
		await settle_ui()
		panel.select_stand(3)
		await settle_ui()
		check(scene.selected_stand == 3, "stand selection stays connected after logical viewport resize")
		check_touch_buttons(panel)
		for control: Control in [panel._action_button, button_named("ResearchButton")]:
			await reveal(control)
		await capture("museum-focus-%d" % resolution.x)

	await pointer_click(button_named("CloseButton"))
	check(game.outpost_page == "lobby" and paused and not panel.is_open
		and scene.selected_stand == -1, "closing returns to the active shared hall and clears only its selection")
	await settle_ui()
	check(scene.zoom == 1.0 and absf(scene.camera.global_position.distance_to(
		scene.ZONE_CENTERS[scene.current_zone] + Vector3(0, 0.1, 0)) - scene.OVERVIEW_BASE_DISTANCE) < 0.5,
		"closing the drawer resets zoom and returns the shared camera to the zone overview")
	check(game.progression.profile_path.is_empty() and game.appraisal.catalogue_path.is_empty(),
		"no test action enabled persistent saves")
	game.queue_free()
	await process_frame
	await create_timer(0.15, true).timeout
	print("MUSEUM_UI_OK pure_drawer=true shared_scene=true real_collection=true merged_list=true stand_focus=true touch_targets48=true escape_once=true sizes_960_1100_1600=true in_memory=true")
	quit(0)
