extends SceneTree

const Main = preload("res://main.gd")
const Appraisal = preload("res://appraisal.gd")
var game: Node3D
var test_failed := false

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, description: String) -> void:
	if not condition:
		test_failed = true
		push_error("GM FAIL: " + description)
		quit(1)
		assert(condition, description)

func control(node_name: String) -> Control:
	return game.gm_panel.find_child(node_name, true, false)

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	root.push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)

func click(button: Control) -> void:
	var ancestor := button.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer:
			ancestor.ensure_control_visible(button)
		ancestor = ancestor.get_parent()
	await process_frame
	await process_frame
	var point := button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion, true)
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	event.pressed = true
	root.push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	event.button_mask = 0
	root.push_input(event, true)

func shot(filename: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await process_frame
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image().save_png("res://.demo-data/" + filename)
	check(result == OK, "native screenshot saves")

func run() -> void:
	create_timer(35.0).timeout.connect(func() -> void: quit(2))
	root.size = Vector2i(1100, 720)
	game = Main.new()
	game.progression = Main.Progression.new("")
	game.progression.bank = 0
	game.auto_open_base = false
	game.appraisal = Appraisal.new("")
	game.wants_mouse_capture = false
	root.add_child(game)
	for warmup in range(12):
		await process_frame
	check(game.terrain.cleanup_enabled and game.terrain.cleanup_max_cells == 9, "cleanup enabled with default nine")
	check(control("GMEntryButton").is_visible_in_tree(), "corner entry always visible")
	await shot("gm-entry.png")
	key(KEY_G)
	await process_frame
	await process_frame
	await process_frame
	check(game.gm_open and paused and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "G opens paused panel and releases pointer")
	check(int(control("CleanupMaxCells").value) == 9, "UI shows actual nine-cell threshold")
	check(control("refill_oxygen").disabled and not control("start_trial").disabled, "base actions have correct availability")
	await click(control("start_trial"))
	await process_frame
	check(game.on_moon and paused and is_equal_approx(game.oxygen, 24.0), "UI starts short trip while keeping world paused")
	check(game.radar_mode == Main.DetectorPanel.Mode.CIRCLE and game.detector_panel.display_mode == game.radar_mode, "default radar is the circular mode")
	var echo_ids: Array = game.detector_reading.get("echoes", []).map(func(echo: Dictionary): return echo.id)
	var radar_oxygen: float = game.oxygen
	await click(control("RadarMode0"))
	check(game.radar_mode == Main.DetectorPanel.Mode.COMPASS and game.detector_panel.display_mode == game.radar_mode, "real GM button switches to the compass strip")
	check(control("RadarMode0").button_pressed and not control("RadarMode1").button_pressed, "GM radar buttons are mutually exclusive")
	check(game.oxygen_card.position.y == 144.0, "compass mode reserves top centre space")
	check(game.oxygen == radar_oxygen and game.detector_reading.get("echoes", []).map(func(echo: Dictionary): return echo.id) == echo_ids, "switching radar preserves oxygen and scan targets")
	await click(control("RadarMode1"))
	check(game.radar_mode == Main.DetectorPanel.Mode.CIRCLE and game.oxygen_card.position.y == 24.0, "circle restores original corner layout")
	var oxygen_before: float = game.oxygen
	var suit_before: Vector3 = game.suit.position
	await create_timer(0.15).timeout
	check(is_equal_approx(oxygen_before, game.oxygen) and game.suit.position == suit_before, "GM pause freezes oxygen and movement")
	check(control("start_trip").disabled and not control("refill_oxygen").disabled, "trip state refreshes all controls")
	game.oxygen = 3.0
	await click(control("refill_oxygen"))
	check(is_equal_approx(game.oxygen, 24.0), "refill respects this trip's oxygen limit")
	await click(control("Brush2"))
	check(game.brush == 2, "UI brush buttons change actual mining brush")
	var old_time: float = game.mining_time
	await click(control("speed_up"))
	check(game.mining_time < old_time and game.upgrades == 0, "GM speed changes without charging or pretending to buy upgrades")
	await click(control("reset_speed"))
	check(is_equal_approx(game.mining_time, 0.9), "reset restores earned tool speed")
	await click(control("ShowPerformance"))
	check(game.show_performance, "performance checkbox changes HUD setting")
	await click(control("CleanupEnabled"))
	check(not game.terrain.cleanup_enabled, "checkbox disables actual cleanup")
	await click(control("CleanupEnabled"))
	check(game.terrain.cleanup_enabled, "checkbox enables actual cleanup")
	var threshold: SpinBox = control("CleanupMaxCells")
	var threshold_input := threshold.get_line_edit()
	await click(threshold_input)
	# SpinBox initializes editing via a deferred editing_toggled connection.
	await process_frame
	# Route Unicode keys through the viewport, just like the real mouse clicks.
	# Setting text and emitting text_changed does not exercise GUI text entry.
	var select_all := InputEventKey.new()
	select_all.keycode = KEY_A
	select_all.physical_keycode = KEY_A
	select_all.ctrl_pressed = true
	select_all.pressed = true
	root.push_input(select_all, true)
	select_all = select_all.duplicate()
	select_all.pressed = false
	root.push_input(select_all, true)
	for digit: Key in [KEY_1, KEY_0]:
		var typed := InputEventKey.new()
		typed.keycode = digit
		typed.physical_keycode = digit
		typed.unicode = int(digit)
		typed.pressed = true
		root.push_input(typed, true)
		typed = typed.duplicate()
		typed.pressed = false
		root.push_input(typed, true)
	check(threshold_input.text == "10", "real Unicode key events edit threshold")
	key(KEY_G)
	await process_frame
	check(not game.gm_open and not paused and game.terrain.cleanup_max_cells == 10, "G while typing commits threshold and closes")
	check(not game.wants_mouse_capture and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "closing preserves deliberately released pointer")
	await click(control("GMEntryButton"))
	await process_frame
	await process_frame
	await process_frame
	check(game.gm_open and paused, "real corner-button click opens panel without capturing mouse")
	threshold.value = 9
	await process_frame
	check(game.terrain.cleanup_max_cells == 9, "threshold updates immediately")
	await click(control("cleanup_nearby"))
	check(game.message.contains("2 米"), "manual cleanup requests bounded nearby scan")
	game.oxygen = 9.0
	check(game.gain_oxygen(12) > 0.0, "oxygen grains restore tank oxygen")
	var teleport_oxygen: float = game.oxygen
	var teleport_recovered: float = game.oxygen_recovered
	game.suit.position = Vector3(8.0, 0, 9.0)
	await click(control("return_to_lander"))
	check(game.on_moon and game.oxygen_grains == 12 and game.bank == 0, "teleport keeps collected oxygen grains without selling")
	check(game.oxygen == teleport_oxygen and game.oxygen_recovered == teleport_recovered, "teleport preserves oxygen state")
	check(game.suit.position.distance_to(Main.LANDER) < Main.HATCH_REACH, "teleport arrives at usable hatch")
	key(KEY_B)
	check(not game.inventory_open and game.gm_open, "backpack cannot open behind GM")
	await click(control("Brush0"))
	check(game.terrain.cleanup_max_cells == 9, "subsequent actions preserve applied threshold")
	await shot("gm-panel.png")
	key(KEY_ESCAPE)
	await process_frame
	check(not game.gm_open and not paused, "Esc closes GM")
	game.open_inventory()
	check(paused and control("GMEntryButton").disabled, "backpack disables GM entry")
	key(KEY_G)
	check(game.inventory_open and not game.gm_open, "GM hotkey does not steal backpack pause")
	game.inventory_panel.close()
	check(not paused and not control("GMEntryButton").disabled, "closing backpack restores GM entry")
	# Native capture also resumes via the same guarded centre-lock path as the backpack.
	if DisplayServer.get_name() != "headless":
		root.grab_focus()
		await process_frame
		await process_frame
		game.wants_mouse_capture = true
		game.capture_mouse()
		key(KEY_G)
		await process_frame
		check(game.gm_open and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "G releases captured pointer")
		key(KEY_G)
		await process_frame
		await process_frame
		await create_timer(0.20).timeout
		check(game.wants_mouse_capture and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "GM restores original mouse capture")
		check(root.get_mouse_position().distance_to(root.get_visible_rect().get_center()) <= 1.0, "GM capture restores centred mouse")
	game.wants_mouse_capture = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game.sfx.set_muted(true)
	await create_timer(0.10, true).timeout
	game.queue_free()
	await process_frame
	await create_timer(0.25, true).timeout
	if not test_failed:
		print("GM_INTEGRATION_OK hotkey/corner-click/threshold9/pause/brush/oxygen/capture/inventory")
	quit(1 if test_failed else 0)
