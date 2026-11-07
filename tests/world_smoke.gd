extends SceneTree

const Main = preload("res://main.gd")
const Terrain = preload("res://terrain.gd")
const Crystal = preload("res://crystal.gd")
const Appraisal = preload("res://appraisal.gd")

var test_failed := false

func _initialize() -> void:
	call_deferred("run")

func require(condition: bool, description: String) -> void:
	if not condition:
		test_failed = true
		push_error("WORLD FAIL: " + description)
		quit(1)
		assert(condition, description)

func height_signature(terrain: Node3D) -> Array[float]:
	var result: Array[float] = []
	var extent := int(Terrain.HALF_EXTENT) - 4
	var step := maxi(1, floori(float(extent) / 5.0))
	for z in range(-extent, extent + 1, step):
		for x in range(-extent, extent + 1, step):
			result.append(terrain.height_at(float(x) + 0.37, float(z) + 0.63))
	return result

func specimen_signature(game: Node3D) -> Array:
	var result := []
	for item: Node3D in game.crystals:
		result.append([item.position, item.wear_percent])
	return result

func stream_at(terrain: Node3D, at: Vector3, count: int = 75) -> void:
	for frame in range(count):
		terrain.update_focus(at)

func run() -> void:
	var began := Time.get_ticks_usec()
	var game := Main.new()
	game.progression = Main.Progression.new("")
	game.progression.levels.excavation_range = 3
	game.progression.bank = 0
	game.auto_open_base = false
	game.appraisal = Appraisal.new("")
	game.wants_mouse_capture = false
	root.add_child(game)
	require(game.activity_boundary.radius == 26.0, "full-range fixture covers the previous maximum map")
	game.set_process(false)
	game.set_physics_process(false)
	var terrain: Node3D = game.terrain
	require(Terrain.HALF_EXTENT == 32.0 and Terrain.GRID_SIZE == 512, "compact terrain spans 64 metres at 0.125 metre resolution")
	require(terrain._detail_mask.get_width() == Terrain.CHUNK_COUNT and terrain._detail_mask.get_height() == Terrain.CHUNK_COUNT, "LOD mask matches compact chunk coordinates")
	var distant_bounds: AABB = terrain._far_ground.mesh.get_aabb()
	require(is_equal_approx(distant_bounds.position.x, -Terrain.HALF_EXTENT) and is_equal_approx(distant_bounds.end.x, Terrain.HALF_EXTENT), "coarse terrain spans exactly the requested width")
	require(is_equal_approx(distant_bounds.position.z, -Terrain.HALF_EXTENT) and is_equal_approx(distant_bounds.end.z, Terrain.HALF_EXTENT), "coarse terrain spans exactly the requested depth")
	require(terrain._far_heights.size() == (Terrain.FAR_COUNT + 1) * (Terrain.FAR_COUNT + 1), "coarse height lattice resizes with map")
	require(is_equal_approx(float(terrain._surface_material.get_shader_parameter("world_size")), 64.0), "fine LOD shader uses compact world UV size")
	require(is_equal_approx(float(terrain._far_ground.material_override.get_shader_parameter("world_size")), 64.0), "far terrain shader uses the same compact world UV size")
	terrain.reset_terrain(68217)
	var first_heights := height_signature(terrain)
	require(first_heights.max() - first_heights.min() >= 0.50, "noise creates visible terrain variation")
	for x in [-2.0, 0.0, 2.0]:
		for z in [-1.0, 0.0, 1.0]:
			require(is_zero_approx(terrain.height_at(Main.LANDER.x + x, Main.LANDER.z + z)), "landing neighbourhood remains flat")
	terrain.reset_terrain(68217)
	require(height_signature(terrain) == first_heights, "same seed reproduces terrain")
	terrain.reset_terrain(68218)
	require(height_signature(terrain) != first_heights, "different seed changes terrain")
	terrain.reset_terrain(68217)
	# Far coordinates are intentionally queried before their detail chunks exist.
	var near_edge := Terrain.HALF_EXTENT - 0.2
	for at in [Vector2(-near_edge, -near_edge), Vector2(near_edge, near_edge), Vector2(-0.01, 0.01), Vector2(24.0, -24.0)]:
		var height: float = terrain.height_at(at.x, at.y)
		var hit: Dictionary = terrain.raycast_voxels(Vector3(at.x, Terrain.WORLD_MAX.y + 1.0, at.y), Vector3.DOWN, 12.0)
		require(not hit.is_empty() and is_equal_approx(hit.position.y, height), "unloaded cells share collision and height data")
		require(terrain.is_solid_at(Vector3(at.x, height - 0.04, at.y)), "soil exists just below queried surface")
		require(not terrain.is_solid_at(Vector3(at.x, height + 0.04, at.y)), "air exists above queried surface")
	for at in [Vector2(-Terrain.HALF_EXTENT, -Terrain.HALF_EXTENT), Vector2(Terrain.HALF_EXTENT, Terrain.HALF_EXTENT)]:
		require(is_equal_approx(terrain._coarse_height_at(at.x, at.y), terrain.natural_height_at(at.x, at.y)), "coarse interpolation reaches both map corners without old lattice stride")
	require(terrain.raycast_voxels(Vector3(Terrain.HALF_EXTENT + 1.0, 4.0, 0.0), Vector3.DOWN, 10.0).is_empty(), "terrain outside 64 metre bounds is empty")
	# A deep air pocket makes an actual upward ray hit the local ceiling.
	var center := Vector3(18.0625, terrain.height_at(18.0625, 18.0625) - 1.5, 18.0625)
	terrain.mine_at(center, Vector3.RIGHT, 0)
	require(not terrain.is_solid_at(center), "fixture cavity is created through mining API")
	var upward: Dictionary = terrain.raycast_voxels(center, Vector3.UP, 3.0)
	require(not upward.is_empty() and upward.normal.y < -0.5, "upward ray returns ceiling normal")
	var untouched := Vector3(center.x, terrain.height_at(center.x, center.z) - 0.04, center.z)
	require(terrain.is_solid_at(untouched), "upper cap initially solid")
	terrain.mine_at(upward.position, upward.normal, 0)
	require(terrain.last_removed > 0 and terrain.last_removed < 600, "upward brush removes only local voxels")
	require(terrain.is_solid_at(untouched), "upward excavation does not clear entire column")
	var down_origin := Vector3(-0.0625, 4.0, 0.0625)
	var downward: Dictionary = terrain.raycast_voxels(down_origin, Vector3.DOWN, 10.0)
	var original_height: float = terrain.height_at(down_origin.x, down_origin.z)
	terrain.mine_at(downward.position, downward.normal, 0)
	var dug_height: float = terrain.height_at(down_origin.x, down_origin.z)
	require(dug_height < original_height, "downward brush lowers only the dug patch")
	stream_at(terrain, down_origin)
	stream_at(terrain, Vector3(26.0, 0.0, -26.0))
	require(is_equal_approx(terrain.height_at(down_origin.x, down_origin.z), dug_height), "unloading retains sparse edits")
	stream_at(terrain, down_origin)
	require(is_equal_approx(terrain.height_at(down_origin.x, down_origin.z), dug_height), "revisiting preserves excavated height")
	var residence_limit := (2 * Terrain.KEEP_RADIUS + 1) * (2 * Terrain.KEEP_RADIUS + 1)
	for at in [Vector3(-26, 0, -24), Vector3(26, 0, 26), Vector3(31, 0, -31), Main.LANDER]:
		stream_at(terrain, at)
		var stats: Dictionary = terrain.debug_stats()
		require(stats.fine_chunks <= residence_limit and stats.height_chunks <= residence_limit, "detail and height caches stay bounded while traversing world")
	# Confirm character movement is no longer clamped at the former 8 metre edge.
	game.suit.position = Vector3(20.0, terrain.height_at(20.0, 0.0), 0.0)
	game.move_suit(Vector3.RIGHT, 1.0 / 60.0)
	require(game.suit.position.x > 20.0, "player can walk beyond old map boundary")
	terrain.reset_terrain(68217)
	game.spawn_crystals(44201)
	var positions := specimen_signature(game)
	terrain.reset_terrain(68217)
	game.spawn_crystals(44201)
	require(specimen_signature(game) == positions, "same seed reproduces specimen placement and wear")
	terrain.reset_terrain(68217)
	game.spawn_crystals(44202)
	require(specimen_signature(game) != positions, "new seed changes specimen placement")
	require(game.crystals.size() == Main.CRYSTAL_COUNT and game.crystals.size() > 50, "many specimens are generated")
	var buried: Crystal = null
	var buried_count := 0
	for item: Crystal in game.crystals:
		require(absf(item.position.x) < Terrain.HALF_EXTENT and absf(item.position.z) < Terrain.HALF_EXTENT, "specimen is inside map")
		require(Vector2(item.position.x, item.position.z).length() < game.activity_boundary.radius - 1.0, "specimen is safely inside circular play boundary")
		var bounds := item.get_local_bounds()
		require(item.position.y + bounds.position.y > Terrain.DIG_LIMIT * Terrain.CELL_SIZE, "specimen can be excavated above protected bedrock")
		if item.item_type == "crystal":
			require(is_equal_approx(bounds.size.y, [4.0, 5.0, 6.0][item.size_tier] * Terrain.CELL_SIZE), "three crystal heights occupy exactly four, five or six terrain cells")
		else:
			require(item.item_type in ["chest", "shield", "hammer"] and not item.get_world_cells().is_empty(), "adventure specimens use a known type and an occupied voxel shape")
			require(bounds.size.x >= Terrain.CELL_SIZE and bounds.size.y >= Terrain.CELL_SIZE and bounds.size.z >= Terrain.CELL_SIZE and maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z)) <= 1.5, "rotated adventure relics have finite voxel bounds within their source-size budget")
			for extent in [bounds.size.x, bounds.size.y, bounds.size.z]:
				require(is_equal_approx(extent / Terrain.CELL_SIZE, roundf(extent / Terrain.CELL_SIZE)), "adventure relic bounds remain aligned to terrain-sized voxels")
		if not item.is_exposed(terrain):
			buried_count += 1
			buried = item
	require(buried_count > Main.CRYSTAL_COUNT / 3, "a substantial population starts fully buried")
	game.on_moon = true
	var near := buried.position + Vector3(0.5, 0.0, 0.5)
	near.y = terrain.height_at(near.x, near.z)
	game.suit.position = near
	game.update_crystal_targets()
	require(game.crystal != buried and not buried.discovered, "fully buried object is not identified as visible target")
	buried.refresh_exposure(terrain)
	require(is_zero_approx(buried.exposure_ratio) and not buried.is_loose(), "buried object has no exposed surface and cannot release before excavation")
	game.pick_up_cluster()
	require(not buried.collected and game.packed_specimens.is_empty(), "F cannot collect buried object")
	# Dig a perimeter, because a centre-only ray now correctly stops at crystal.
	var bounds := buried.get_local_bounds()
	var center_point := buried.position + bounds.get_center()
	var reach := Vector2(bounds.size.x, bounds.size.z) * 0.5 + Vector2.ONE * Terrain.CELL_SIZE
	for layer in range(10):
		for offset in [Vector2.ZERO, Vector2(-reach.x, 0), Vector2(reach.x, 0), Vector2(0, -reach.y), Vector2(0, reach.y), Vector2(-reach.x, -reach.y), Vector2(reach.x, -reach.y), Vector2(-reach.x, reach.y), Vector2(reach.x, reach.y)]:
			var origin := Vector3(center_point.x + offset.x, Terrain.WORLD_MAX.y + 1.0, center_point.z + offset.y)
			var hit: Dictionary = terrain.raycast_voxels(origin, Vector3.DOWN, 10.0)
			require(not hit.is_empty(), "buried specimen still has diggable surroundings")
			terrain.mine_at(hit.position, hit.normal, 0)
			buried.refresh_exposure(terrain)
			if buried.is_loose():
				break
		if buried.is_loose():
			break
	require(buried.is_exposed(terrain) and buried.is_loose(), "fully buried specimen can be uncovered and released")
	var final_stats: Dictionary = terrain.debug_stats()
	print("WORLD_OK map=64m deterministic=true relief=%.2fm crystals=%d buried=%d fine_chunks=%d max_chunk_ms=%.2f elapsed_ms=%.2f" % [first_heights.max() - first_heights.min(), game.crystals.size(), buried_count, final_stats.fine_chunks, final_stats.max_build_usec / 1000.0, (Time.get_ticks_usec() - began) / 1000.0])
	game.sfx.set_muted(true)
	await create_timer(0.1, true).timeout
	game.queue_free()
	await process_frame
	await create_timer(0.25, true).timeout
	quit(1 if test_failed else 0)
