extends SceneTree

const Main = preload("res://main.gd")
const Appraisal = preload("res://appraisal.gd")
var game: Node3D
var frames: Array[float] = []
var draw_calls := 0
var primitives := 0
var spikes: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("run")

func screenshot(filename: String) -> void:
	game.update_hud()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.demo-data/" + filename + ".png")

func run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	game = Main.new()
	game.progression = Main.Progression.new("")
	game.progression.levels.excavation_range = 3
	game.progression.bank = 0
	game.auto_open_base = false
	game.appraisal = Appraisal.new("")
	game.wants_mouse_capture = false
	root.add_child(game)
	game.set_physics_process(false)
	game.set_process_unhandled_input(false)
	game.inventory_panel.set_process_input(false)
	game.start_trip(false)
	game.terrain.reset_terrain(11235)
	game.spawn_crystals(11235)
	game.show_performance = true
	game.view_pitch = 0.15
	game.view_yaw = -0.6
	for warmup in range(180):
		await process_frame
	game.update_crystal_targets()
	await screenshot("expanded-moon")
	# Exercise streaming and frequent mining on a square route inside the activity area.
	var previous := Time.get_ticks_usec()
	for step in range(1200):
		var delta := 1.0 / 60.0
		var route := [Vector3.RIGHT, Vector3.FORWARD, Vector3.LEFT, Vector3.BACK]
		game.move_suit(route[step / 300], delta)
		if step % 12 == 0:
			game.update_crystal_targets()
			game.update_hud()
		if step % 42 == 0:
			var at: Vector3 = game.suit.position + Vector3(0.6, 0, -0.8)
			var hit: Dictionary = game.terrain.raycast_voxels(at + Vector3.UP * 3, Vector3.DOWN, 7.0)
			if not hit.is_empty():
				var found: int = game.terrain.mine_at(hit.position, hit.normal, 0)
				game.burst(hit.position, found)
		game.update_fragments(delta)
		await process_frame
		var now := Time.get_ticks_usec()
		var elapsed := float(now - previous) / 1000.0
		frames.append(elapsed)
		if elapsed > 16.7:
			spikes.append({"step": step, "ms": elapsed, "terrain": game.terrain.debug_stats()})
		previous = now
		draw_calls = maxi(draw_calls, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		primitives = maxi(primitives, int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
	frames.sort()
	var sum := 0.0
	for duration in frames:
		sum += duration
	var result := {
		"renderer": RenderingServer.get_video_adapter_name(),
		"resolution": str(root.get_visible_rect().size),
		"map_m": Main.Terrain.HALF_EXTENT * 2.0,
		"activity_radius_m": game.activity_boundary.radius,
		"crystals": game.crystals.size(),
		"frames": frames.size(),
		"mean_ms": sum / frames.size(),
		"p50_ms": frames[int(frames.size() * 0.50)],
		"p95_ms": frames[int(frames.size() * 0.95)],
		"p99_ms": frames[int(frames.size() * 0.99)],
		"max_ms": frames.back(),
		"max_draw_calls": draw_calls,
		"max_primitives": primitives,
		"static_memory_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		"terrain": game.terrain.debug_stats(),
		"spikes_over_16_7ms": spikes,
	}
	var file := FileAccess.open("res://.demo-data/world-performance.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	print("WORLD_RENDER_BENCH " + JSON.stringify(result))
	# Show a small, genuinely buried specimen before and after actual soil removal.
	# Replacing a registered shape would leave its old cavity, so use a fresh world.
	game.terrain.reset_terrain(11235)
	game.spawn_crystals(11235)
	var target: Node3D = null
	for candidate in game.crystals:
		if not candidate.discovered:
			target = candidate
			break
	assert(target != null, "fixed seed has a genuinely buried specimen")
	game.suit.position = target.position + Vector3(-0.95, 0, 1.25)
	game.suit.position.y = game.terrain.height_at(game.suit.position.x, game.suit.position.z)
	game.view_yaw = atan2(-0.95, 1.25)
	game.view_pitch = 0.55
	game.camera_anchor = game.suit.position + Vector3.UP * 0.95
	for warmup in range(160):
		await process_frame
	game.update_crystal_targets()
	await screenshot("buried-crystal-before")
	for cut in range(7):
		var hit: Dictionary = game.terrain.raycast_voxels(Vector3(target.position.x, 3.0, target.position.z), Vector3.DOWN, 7.0)
		if not hit.is_empty():
			game.terrain.mine_at(hit.position, hit.normal, 0)
		game.update_crystal_targets()
		for frame in range(8):
			await process_frame
	await screenshot("buried-crystal-after")
	quit(0)
