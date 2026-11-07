extends SceneTree

const Main = preload("res://main.gd")
var game: Node3D

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, why: String) -> void:
	if not ok:
		push_error("TOUCH GAME FAIL: " + why)
		quit(1)
		assert(ok, why)

func finger(id: int, at: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = id
	event.position = at
	event.pressed = pressed
	root.push_input(event, true)

func drag(id: int, at: Vector2, motion: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = id
	event.position = at
	event.relative = motion
	event.screen_relative = motion
	root.push_input(event, true)

func point(node_name: String) -> Vector2:
	return game.touch_controls.find_child(node_name, true, false).get_global_rect().get_center()

func run() -> void:
	root.size = Vector2i(1100, 720)
	game = Main.new()
	game.progression = Main.Progression.new("")
	game.appraisal = Main.Appraisal.new("")
	game.auto_open_base = false
	game.wants_mouse_capture = false
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	await process_frame
	game.start_trip(false)
	game.terrain.reset_terrain(11235)
	game.spawn_crystals(11235)
	game.set_touch_mode(true)
	await process_frame
	check(game.touch_mode and not game.wants_mouse_capture and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED, "touch mode releases pointer capture")
	var move := point("TouchJoystick")
	var mine := point("TouchMine")
	finger(0, move, true)
	drag(0, move + Vector2(60, 0), Vector2(60, 0))
	finger(1, mine, true)
	var yaw: float = game.view_yaw
	drag(1, mine + Vector2(16, -4), Vector2(16, -4))
	check(game.touch_controls.movement_vector().x > 0.0 and game.touch_controls.mining_held(), "two independent fingers move and mine together")
	check(game.view_yaw < yaw, "mining drag rotates actual game camera")
	finger(0, move, false)
	check(game.touch_controls.movement_vector().is_zero_approx() and game.touch_controls.mining_held(), "releasing movement does not release mining")
	finger(1, mine, false)
	game.suit.position = Vector3(-4.65, 0, 5.18)
	game.suit.position.y = game.terrain.height_at(-4.65, 5.18)
	game.view_yaw = -PI * 0.5
	game.view_pitch = 0.74
	game.set_first_person(true)
	check(not game.aim_at_terrain().is_empty(), "touch mining fixture hits real soil")
	finger(2, mine, true)
	for frame in range(70):
		game._physics_process(1.0 / 60.0)
	check(not game.terrain._removed_columns.is_empty(), "held touch excavates real voxels")
	check(int(game.sfx._variants.get(&"dig", 0)) > 0, "successful voxel mining triggers the real dig sound")
	finger(2, mine, false)
	game._physics_process(0.01)
	check(game.progress == 0.0, "releasing mine stops charge")
	finger(3, mine, true)
	game.gm_panel.open()
	check(paused and not game.touch_controls.mining_held(), "opening GM releases held touch")
	var oxygen: float = game.oxygen
	game.gm_panel.touch_mode_changed.emit(false)
	check(not game.touch_mode, "GM can disable touch mode")
	game.gm_panel.touch_mode_changed.emit(true)
	check(game.touch_mode and not game.touch_controls.mining_held(), "GM can enable touch without stale mining")
	game.gm_panel.audio_enabled_changed.emit(false)
	check(game.sfx.muted, "GM mute reaches audio manager")
	game.gm_panel.audio_enabled_changed.emit(true)
	check(not game.sfx.muted, "GM restores audio")
	game.gm_panel.close()
	await process_frame
	check(not paused and game.oxygen == oxygen, "GM preserves expedition oxygen")
	finger(4, mine, true)
	game._on_window_focus_exited()
	check(not game.touch_controls.mining_held(), "focus loss clears held mine")
	game._on_window_focus_entered()
	check(not game.touch_controls.mining_held(), "focus return cannot resume stale press")
	game.open_inventory()
	check(paused and not game.touch_controls.find_child("TouchRoot", true, false).visible, "inventory hides gameplay touch controls")
	game.inventory_panel.close()
	await process_frame
	game.message = ""
	game.update_hud()
	for frame in range(45):
		game._physics_process(1.0 / 60.0)
		game._process(1.0 / 60.0)
		await process_frame
	if DisplayServer.get_name() != "headless":
		for resolution in [Vector2i(1100, 720), Vector2i(1600, 720)]:
			root.size = resolution
			await process_frame
			await process_frame
			game._process(0.0)
			await RenderingServer.frame_post_draw
			var out := "res://.demo-data/touch-preview"
			DirAccess.make_dir_recursive_absolute(out)
			check(root.get_texture().get_image().save_png(out + "/touch-%d.png" % resolution.x) == OK, "save touch screenshot")
	print("TOUCH_GAME_OK dual_finger=true mine_drag_camera=true actual_voxel_dig=true modal_release=true focus_release=true gm_modes_mute=true saves=in_memory")
	game.queue_free()
	await process_frame
	await create_timer(0.25).timeout
	quit()
