extends SceneTree

const Main = preload("res://main.gd")
const Terrain = preload("res://terrain.gd")
const Motion = preload("res://voxel_movement.gd")
const FLOOR_Y := -2.5
const STEP := 1.0 / 60.0
var failed := false
var terrain: Node3D
var motion: RefCounted
var preview := false

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, description: String) -> void:
	if not ok:
		failed = true
		push_error("JUMP FAIL: " + description)
		quit(1)
		assert(ok, description)

func carve(shape: String = "flat") -> void:
	terrain.reset_terrain(11235)
	terrain.set_fragment_cleanup(false, 9)
	# Remove real soil from a 6 x 4 m underground room. Keep selected natural
	# cells as obstacles; collision queries still use the production voxel grid.
	var low: Vector3i = terrain.world_to_cell(Vector3(-3, FLOOR_Y, -2))
	var high: Vector3i = terrain.world_to_cell(Vector3(3, Terrain.WORLD_MAX.y, 2))
	for z in range(low.z, high.z):
		for x in range(low.x, high.x):
			var bits := 0
			for y in range(low.y, Terrain.LAYER_COUNT):
				var p: Vector3 = terrain.cell_center(Vector3i(x, y, z))
				var keep := false
				match shape:
					"ceiling":
						keep = p.y >= -1.125 and p.y < -1.0
					"wall":
						keep = p.x >= 0.0 and p.x < 0.125 and p.y < FLOOR_Y + 0.125
					"pit":
						keep = p.x >= 0.5 and p.y < FLOOR_Y + 0.625
					"platform":
						keep = p.x > 0.0 and p.x < 0.125 and p.z > 0.0 and p.z < 0.125 and p.y >= -1.75 and p.y < -1.625
				if not keep:
					bits |= 1 << y
			terrain._removed_columns[z * Terrain.GRID_SIZE + x] = bits
	motion = Motion.new()

func tick(at: Vector3, velocity := Vector3.ZERO, held := false, dt := STEP) -> Vector3:
	var result: Vector3 = motion.step(terrain, at, velocity, dt, held)
	check(result.is_finite() and result.y >= FLOOR_Y - 0.002, "movement stays finite and above real room floor")
	return result

func rest(at: Vector3, frames := 120) -> Vector3:
	for frame in range(frames):
		at = tick(at)
	return at

func press_space(pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_SPACE
	event.physical_keycode = KEY_SPACE
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func run() -> void:
	preview = OS.get_cmdline_user_args().has("--preview") and DisplayServer.get_name() != "headless"
	terrain = Terrain.new()
	root.add_child(terrain)
	carve()
	var at := rest(Vector3(0.0625, FLOOR_Y, 0.0625), 2)
	check(motion.grounded, "flat floor establishes grounded state")
	var peak := at.y
	var positive_starts := 0
	var previous_speed := 0.0
	for frame in range(180):
		at = tick(at, Vector3.ZERO, true)
		peak = maxf(peak, at.y)
		if motion.vertical_speed > 0.0 and previous_speed <= 0.0:
			positive_starts += 1
		previous_speed = motion.vertical_speed
	check(peak > FLOOR_Y + 0.625 and is_equal_approx(at.y, FLOOR_Y) and motion.grounded, "jump rises above a shallow pit rim and lands on same floor")
	check(positive_starts == 1, "held Space produces one jump without automatic repeats")
	at = tick(at, Vector3.ZERO, false)
	at = tick(at, Vector3.ZERO, true)
	check(not motion.grounded and motion.vertical_speed > 0.0, "release then press permits a new grounded jump")
	at = tick(at, Vector3.ZERO, false)
	var before_speed: float = motion.vertical_speed
	at = tick(at, Vector3.ZERO, true)
	check(motion.vertical_speed <= before_speed, "airborne release/repress cannot double jump")
	at = rest(at)
	motion.reset(true)
	at = tick(at, Vector3.ZERO, true)
	check(is_equal_approx(at.y, FLOOR_Y) and motion.vertical_speed == 0.0, "reset remembers held input instead of causing an accidental jump")
	motion.sync_jump_input(false)
	at = tick(at, Vector3.ZERO, true)
	check(motion.vertical_speed > 0.0, "input synchronization accepts the next real press")

	carve("ceiling")
	at = rest(Vector3(0.0625, FLOOR_Y, 0.0625), 2)
	var ceiling_peak := at.y
	for frame in range(120):
		at = tick(at, Vector3.ZERO, true)
		ceiling_peak = maxf(ceiling_peak, at.y)
		check(motion.has_clearance(terrain, at.x, at.z, at.y), "low ceiling never overlaps the player's body")
	check(ceiling_peak < peak - 0.25 and is_equal_approx(at.y, FLOOR_Y), "low ceiling stops ascent and permits landing")

	carve("wall")
	at = rest(Vector3(-0.65, FLOOR_Y, 0.0625), 2)
	for frame in range(45):
		at = tick(at, Vector3.RIGHT * 2.0, true)
	check(at.x > 0.5, "horizontal jump crosses a one-voxel wall")
	at = rest(at)
	check(is_equal_approx(at.y, FLOOR_Y), "crossed wall returns to ground")

	carve("pit")
	at = rest(Vector3(-0.1, FLOOR_Y, 0.0625), 2)
	var walking := at
	for frame in range(30):
		walking = tick(walking, Vector3.RIGHT * 2.0)
	check(walking.x < 0.5, "pit rim is too high to walk through")
	motion.reset()
	for frame in range(55):
		at = tick(at, Vector3.RIGHT * 2.0, true)
	at = rest(at)
	check(at.x > 0.5 and is_equal_approx(at.y, FLOOR_Y + 0.625), "jump climbs out of a five-voxel shallow pit")

	for dt in [1.0 / 120.0, 1.0 / 30.0, 0.1]:
		carve("platform")
		at = Vector3(0.0625, -0.4, 0.0625)
		for frame in range(180):
			at = tick(at, Vector3.ZERO, false, dt)
		check(is_equal_approx(at.y, -1.625) and motion.grounded, "fall lands on a single-cell thin platform at timestep %s" % dt)
		var cell: Vector3i = terrain.world_to_cell(Vector3(0.0625, -1.6875, 0.0625))
		check(terrain.is_soil_cell(cell), "thin platform is an actual soil voxel")
		terrain.mine_at(Vector3(0.0625, -1.625, 0.0625), Vector3.UP, 0)
		check(not terrain.is_soil_cell(cell), "real mining removes support beneath feet")
		at = rest(at)
		check(is_equal_approx(at.y, FLOOR_Y) and motion.grounded, "removing support starts gravity and lands on deeper floor")

	terrain.free()
	await test_main()
	print("JUMP_SMOKE_OK flat_jump=true held_once=true no_double_jump=true low_ceiling=true voxel_wall=true pit_exit=true thin_platform_120_30_10fps=true mined_support_fall=true peak=", snappedf(peak - FLOOR_Y, 0.001))
	quit(1 if failed else 0)

func shot(game: Node3D, label: String) -> void:
	if not preview:
		return
	DirAccess.make_dir_recursive_absolute("res://.demo-data/jump-preview")
	for frame in range(45):
		game._process(STEP)
		await process_frame
	game.update_hud()
	var screen := root.get_visible_rect()
	check(screen.has_point(game.camera.unproject_position(game.suit.position + Vector3.UP * 1.25)), "real follow camera keeps head in preview " + label)
	check(screen.has_point(game.camera.unproject_position(game.suit.position)), "real follow camera keeps feet in preview " + label)
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://.demo-data/jump-preview/" + label + ".png") == OK, "save jump preview " + label)

func test_main() -> void:
	var game := Main.new()
	game.progression = Main.Progression.new("")
	game.progression.levels.excavation_range = 3
	game.progression.bank = 0
	game.auto_open_base = false
	game.appraisal = Main.Appraisal.new("")
	game.wants_mouse_capture = false
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.start_trip(false)
	check(game.activity_boundary.radius == 26.0, "full-range fixture preserves the largest jump boundary")
	game.suit.position = Main.LANDER + Vector3(1.3, 0.0, 0.0)
	game.suit.position.y = game.terrain.height_at(game.suit.position.x, game.suit.position.z)
	game.locomotion.reset()
	game.move_suit(Vector3.ZERO, STEP, false)
	var floor_before: float = game.suit.position.y
	game.view_yaw = -PI / 2.0
	game.view_pitch = 0.74
	game.camera_anchor = game.suit.position + Vector3.UP * 0.95
	game.update_camera()
	game._process(STEP)
	check(not game.aim_at_terrain().is_empty(), "main has a real diggable terrain target")
	await shot(game, "ground")
	var native_input := DisplayServer.get_name() != "headless"
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	game.capture_guard_until = 0
	press_space(true)
	check(Input.is_physical_key_pressed(KEY_SPACE), "flushed Space event sets the real input state")
	if native_input:
		check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "native window captures mouse for jump input")
		game._physics_process(STEP)
		check(game.progress == 0.0 and not game.ring.visible, "Space does not charge mining while a terrain target is aimed")
	else:
		# The headless display backend cannot capture a mouse; exercise the real
		# main movement entry point, and reserve captured-input checks for native.
		game.move_suit(Vector3.ZERO, STEP, true)
	game._process(STEP)
	check(game.suit.position.y > floor_before and game.locomotion.vertical_speed > 0.0, "main character jump starts")
	for frame in range(180):
		if native_input:
			game._physics_process(STEP)
		else:
			game.move_suit(Vector3.ZERO, STEP, true)
		game._process(STEP)
		if frame == 24:
			await shot(game, "airborne")
	check(is_equal_approx(game.suit.position.y, floor_before) and game.locomotion.grounded, "main held input does not jump again on landing")
	await shot(game, "landed")
	press_space(false)
	game._physics_process(STEP)
	game._process(STEP)
	for panel in [game.gm_panel, game.inventory_panel]:
		if panel == game.gm_panel:
			game.gm_panel.open()
		else:
			game.open_inventory()
		var at_before: Vector3 = game.suit.position
		var oxygen_before: float = game.oxygen
		press_space(true)
		game._physics_process(0.2)
		game._process(0.2)
		check(paused and game.suit.position == at_before and game.oxygen == oxygen_before, "paused panel freezes jump, position and oxygen")
		panel.close()
		game.move_suit(Vector3.ZERO, STEP, true)
		game._process(STEP)
		check(not paused and is_equal_approx(game.suit.position.y, at_before.y) and game.locomotion.vertical_speed == 0.0, "closing panel with Space held does not trigger a latent jump")
		press_space(false)
		game._physics_process(STEP)
		game._process(STEP)
	game.move_suit(Vector3.ZERO, STEP, true)
	game._process(STEP)
	check(game.locomotion.vertical_speed > 0.0, "test enters an actual jump before GM teleport")
	game._on_gm_action("return_to_lander")
	check(game.locomotion.vertical_speed == 0.0, "GM teleport resets vertical momentum")
	game.move_suit(Vector3.ZERO, STEP, false)
	game._process(STEP)
	game.move_suit(Vector3.ZERO, STEP, true)
	game._process(STEP)
	game.settle(false)
	check(not game.on_moon and game.locomotion.vertical_speed == 0.0, "safe return resets vertical momentum")
	game.start_trip(false)
	check(game.on_moon and game.locomotion.vertical_speed == 0.0, "new departure starts with clean jump state")
	for direction in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
		game.suit.position = direction * (game.activity_boundary.radius - 0.5)
		game.suit.position.y = game.terrain.height_at(game.suit.position.x, game.suit.position.z) + 0.4
		game.locomotion.reset()
		for frame in range(90):
			game.move_suit(Vector3.ZERO, STEP, false)
			game._process(STEP)
		for frame in range(90):
			game.move_suit(direction, STEP, true)
			game._process(STEP)
			check(Vector2(game.suit.position.x, game.suit.position.z).length() <= game.activity_boundary.radius - Main.ActivityBoundary.PLAYER_MARGIN + 0.001, "jump cannot bypass circular map boundary")
	press_space(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game.sfx.set_muted(true)
	await create_timer(0.1, true).timeout
	game.queue_free()
	await process_frame
	await create_timer(0.25, true).timeout
	print("JUMP_MAIN_OK captured_space_input=", "passed" if native_input else "requires_native", " menu_resume_no_latent_jump=true gm_return_reset=true settle_reset=true deploy_reset=true boundary=true preview=", preview)
