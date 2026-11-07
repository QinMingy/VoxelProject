extends SceneTree

const Main = preload("res://main.gd")
const Appraisal = preload("res://appraisal.gd")
const Boundary = preload("res://activity_boundary.gd")

func _initialize() -> void:
	call_deferred("run")

func require(condition: bool, description: String) -> void:
	if not condition:
		push_error("ACTIVITY AREA FAIL: " + description)
		quit(1)
		assert(condition, description)

func preview(game: Node3D, at: Vector3, yaw: float, filename: String) -> void:
	game.suit.position = at
	game.suit.position.y = game.terrain.height_at(at.x, at.z)
	game.view_yaw = yaw
	game.view_pitch = 0.16
	game.camera_anchor = game.suit.position + Vector3.UP * 0.95
	for frame in range(135):
		game._process(1.0 / 60.0)
		await process_frame
	game.update_crystal_targets()
	game.update_hud()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.demo-data/" + filename + ".png")

func run() -> void:
	var game := Main.new()
	game.progression = Main.Progression.new("")
	game.progression.levels.excavation_range = 3
	game.progression.bank = 0
	game.auto_open_base = false
	game.appraisal = Appraisal.new("")
	game.wants_mouse_capture = false
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.set_process_unhandled_input(false)
	game.inventory_panel.set_process_input(false)
	game.start_trip(false)
	var radius: float = game.activity_boundary.radius
	require(radius == 26.0, "full-range fixture retains the previous maximum activity area")
	game.terrain.reset_terrain(11235)
	for map_seed in [11235, 7712, 68217, 1, 9999]:
		game.spawn_crystals(map_seed)
		require(game.crystals.size() == Main.CRYSTAL_COUNT, "compact map keeps requested crystal count")
		for item in game.crystals:
			require(Vector2(item.position.x, item.position.z).length() <= radius - 1.0, "all collectible specimens are inside the warning boundary")
			require(Vector2(item.position.x - Main.LANDER.x, item.position.z - Main.LANDER.z).length() >= 2.8, "crystals cannot spawn inside the lander")
			for cell: Vector3i in item.get_world_cells():
				var center: Vector3 = game.terrain.cell_center(cell)
				var far_x := absf(center.x) + Main.Terrain.CELL_SIZE * 0.5
				var far_z := absf(center.z) + Main.Terrain.CELL_SIZE * 0.5
				require(far_x * far_x + far_z * far_z <= radius * radius + 0.00001, "every corner of every specimen voxel stays inside the allowed map")
		for i in range(game.crystals.size()):
			for j in range(i):
				var a: Vector3 = game.crystals[i].position
				var b: Vector3 = game.crystals[j].position
				require(Vector2(a.x - b.x, a.z - b.z).length() >= 2.79, "smaller map preserves excavation spacing")
	for direction in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK, Vector3(1, 0, 1).normalized()]:
		game.suit.position = direction * (radius - 0.5)
		game.suit.position.y = game.terrain.height_at(game.suit.position.x, game.suit.position.z)
		for step in range(30):
			game.move_suit(direction, 1.0 / 60.0)
		require(Vector2(game.suit.position.x, game.suit.position.z).length() <= radius - Boundary.PLAYER_MARGIN + 0.001, "movement stops before all sides of the circular warning")
	game.suit.position = Vector3.ZERO
	game._process(1.0 / 60.0)
	require(not game.boundary_warning.visible and is_zero_approx(game.activity_boundary.warning_strength), "central play area has no red warning")
	game.suit.position = Vector3(radius - 2.0, 0, 0)
	game._process(1.0 / 60.0)
	require(game.boundary_warning.visible and game.activity_boundary.warning_strength > 0.5, "approaching the edge shows the warning")
	game.open_inventory()
	require(not game.boundary_warning.visible, "backpack hides warning overlay while paused")
	game.inventory_panel.close()
	game._process(1.0 / 60.0)
	require(game.boundary_warning.visible, "warning resumes after backpack closes")
	var env: Environment = game.world_environment.environment
	require(env.fog_enabled and env.fog_mode == Environment.FOG_MODE_DEPTH, "compatible depth fog is enabled")
	require(env.fog_depth_begin >= 10.0 and env.fog_depth_end > env.fog_depth_begin, "near excavation remains outside distance fog")
	if DisplayServer.get_name() != "headless":
		game.spawn_crystals(11235)
		await preview(game, Vector3.ZERO, -PI * 0.5, "compact-moon-fog")
		await preview(game, Vector3(23, 0, 0), -PI * 0.5, "activity-boundary-near")
		await preview(game, Vector3(25.6, 0, 0), -PI * 0.5, "activity-boundary-edge")
	print("ACTIVITY_AREA_OK map=64 radius=%d crystal_seeds=5 whole_voxel_bounds=true spacing=2.8 circle_clamp=true warning_fade=true backpack=true depth_fog=true" % radius)
	game.sfx.set_muted(true)
	await create_timer(0.1, true).timeout
	game.queue_free()
	await process_frame
	await create_timer(0.25, true).timeout
	quit(0)
