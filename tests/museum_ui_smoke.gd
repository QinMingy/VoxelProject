extends SceneTree

const MuseumPanel = preload("res://museum_panel.gd")
var failed := false
var requested: Array = []

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, description: String) -> void:
	if not value:
		failed = true
		push_error("MUSEUM UI FAIL: " + description)
		quit(1)
		assert(value, description)

func item(uid: int, kind: String, wear: int = 10, tier: int = 0) -> Dictionary:
	return {"uid": uid, "item_type": kind, "item_name": ["小型晶石", "中型晶石", "大型晶石"][tier] if kind == "crystal" else {"chest": "冒险宝箱", "shield": "冒险者盾牌", "hammer": "遗落战锤"}[kind], "label": kind, "wear": wear, "base_value": 180 if kind == "crystal" else 800, "footprint": [Vector2i(1, 1), Vector2i(1, 2), Vector2i(2, 2)][tier] if kind == "crystal" else Vector2i(2, 2)}

func state(warehouse: Array, exhibits: Dictionary, slots: Array, capacity: int = 3) -> Dictionary:
	return {"bank": 150, "research_points": 4, "message": "", "museum": {"warehouse": warehouse, "exhibits": exhibits, "slots": slots, "capacity": capacity, "appeal": 1.0, "income": 24, "identified_types": ["chest", "shield", "hammer", "crystal"], "max_level": 3}}

func capture(panel: CanvasLayer, filename: String) -> void:
	await create_timer(0.25, true).timeout
	var screen := Rect2(Vector2.ZERO, Vector2(root.size))
	check(screen.encloses(panel._window.get_global_rect()), "museum state stays on screen: " + filename)
	for button: Button in [panel._donate_button, panel._sell_button]:
		if button.is_visible_in_tree():
			check(screen.encloses(button.get_global_rect()), "warehouse actions remain visible: " + filename)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://.build/museum-ui-preview")
		check(root.get_texture().get_image().save_png("res://.build/museum-ui-preview/" + filename + ".png") == OK, "save native state " + filename)

func pointer_click(button: Button) -> void:
	check(button.is_visible_in_tree() and not button.disabled, "real pointer target is visible and enabled")
	var at := button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	root.push_input(motion, true)
	for pressed: bool in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.position = at
		click.global_position = at
		click.pressed = pressed
		root.push_input(click, true)
	await process_frame

func run() -> void:
	root.size = Vector2i(1100, 720)
	var panel := MuseumPanel.new()
	root.add_child(panel)
	panel.sync_state(state([], {}, ["", "", "", "", "", ""]))
	panel.open()
	check(panel._display._models.is_empty(), "new museum does not fabricate pre-filled exhibits")
	check(panel._viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "opening activates the real 3D room")
	paused = true
	await create_timer(0.3, true).timeout
	await capture(panel, "museum-empty-1100")
	var initial := state([item(11, "chest")], {}, ["", "", "", "", "", ""])
	initial.museum.identified_types = []
	panel.sync_state(initial)
	panel.select_warehouse_item(11)
	check(panel._detail_info.text.contains("售价？") and panel._sell_button.text == "出售并鉴定", "unknown warehouse price stays hidden until first registration or sale")
	await capture(panel, "museum-warehouse-unknown-1100")
	panel.donate_requested.connect(func(uid: int) -> void: requested.append(uid))
	await pointer_click(panel._donate_button)
	panel._donate_button.pressed.emit()
	check(requested == [11] and panel._donate_button.disabled and panel._sell_button.disabled, "donation uses owner-only request and guards pending duplicate clicks")
	var exhibits := {"chest": {"key": "chest", "label": "冒险宝箱", "item": item(11, "chest"), "level": 1, "count": 1}}
	panel.sync_state(state([item(12, "shield")], exhibits, ["chest", "", "", "", "", ""]))
	check(panel._display._models.size() == 1 and panel._display.displayed_keys == ["chest"], "only actual registered displayed item appears in museum")
	var model: Node3D = panel._display._models[0]
	check(model.item_type == "chest" and model.get_world_cells().size() == 384, "display reuses the actual canonical voxel treasure chest")
	panel.select_exhibit("chest")
	panel.select_stand(1)
	check(panel._place_button.is_visible_in_tree() and panel._place_button.text.contains("02"), "catalogue placement clearly targets the selected pedestal")
	var placements: Array = []
	panel.place_requested.connect(func(key: String, slot: int) -> void: placements.append([key, slot]))
	panel._place_button.pressed.emit()
	check(placements == [["chest", 1]], "placement delegates the selected actual key and pedestal to owner")
	panel.sync_state(state([], exhibits, ["", "chest", "", "", "", ""]))
	check(panel._display._models.has(1) and not panel._display._models.has(0), "changed owner placement moves the actual museum model")
	panel._clear_button.pressed.emit()
	check(placements == [["chest", 1], ["", 1]], "clearing a display requests moving it back into the collection")
	var slots := ["crystal_small", "crystal_medium", "crystal_large", "chest", "shield", "hammer"]
	exhibits = {}
	for index in range(slots.size()):
		var kind: String = "crystal" if index < 3 else slots[index]
		var snapshot := item(20 + index, kind, index * 8, index if index < 3 else 0)
		exhibits[slots[index]] = {"key": slots[index], "label": snapshot.item_name, "item": snapshot, "level": 3, "count": 3}
	panel.sync_state(state([item(77, "hammer", 4), item(78, "crystal", 55)], exhibits, slots, 6))
	panel.select_warehouse_item(77)
	check(not panel._donate_button.disabled and panel._donate_button.text == "替换更好品相", "max-level collection can still replace a worse exemplar")
	panel.select_warehouse_item(78)
	check(panel._donate_button.disabled and panel._donate_button.text == "展品已满级", "max-level worse duplicate does not silently consume the item")
	check(panel._display._models.size() == 6, "all six real specimen types can be displayed after expansion")
	await pointer_click(panel._catalogue_tab)
	check(panel._tab == "catalogue", "real pointer switches to catalogue tab")
	await pointer_click(panel._warehouse_tab)
	check(panel._tab == "warehouse", "real pointer switches back to warehouse")
	var yaw_before: float = panel._display._yaw
	var drag := InputEventScreenDrag.new()
	drag.relative = Vector2(10, 0)
	panel._room_input(drag)
	var emulated := InputEventMouseMotion.new()
	emulated.device = InputEvent.DEVICE_ID_EMULATION
	emulated.relative = Vector2(10, 0)
	emulated.button_mask = MOUSE_BUTTON_MASK_LEFT
	panel._room_input(emulated)
	check(is_equal_approx(panel._display._yaw, yaw_before - 0.03), "touch drag and its emulated mouse motion only orbit the room once")
	for resolution in [Vector2i(1100, 720), Vector2i(1600, 720)]:
		root.size = resolution
		panel.select_exhibit("chest")
		panel.select_stand(3)
		await create_timer(0.4, true).timeout
		var screen := Rect2(Vector2.ZERO, Vector2(resolution))
		check(screen.encloses(panel._window.get_global_rect()), "museum window fits " + str(resolution))
		for control in [panel._viewport_container, panel._detail_name, panel._place_button, panel._clear_button, panel._income]:
			check(screen.encloses(control.get_global_rect()), "visible museum controls remain on screen")
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			DirAccess.make_dir_recursive_absolute("res://.build/museum-ui-preview")
			check(root.get_texture().get_image().save_png("res://.build/museum-ui-preview/museum-%d.png" % resolution.x) == OK, "save native museum preview")
	panel.close()
	check(paused and panel._viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED and not panel._display._active, "closing releases museum rendering without changing owner pause")
	paused = false
	panel.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	print("MUSEUM_UI_OK real_voxel_display=true warehouse_actions=true catalogue_placement=true pending_guard=true hidden_render_disabled=true fits1100_1600=true")
	quit(1 if failed else 0)
