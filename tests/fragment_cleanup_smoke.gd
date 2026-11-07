extends SceneTree

const Terrain = preload("res://terrain.gd")
var failed := false
var peak_frame_visits := 0
var peak_elapsed_usec := 0
var total_drain_frames := 0

func _initialize() -> void:
	call_deferred("run")

func require(condition: bool, description: String) -> void:
	if not condition:
		failed = true
		push_error("FRAGMENT CLEANUP FAIL: " + description)
		quit(1)
		assert(condition, description)

func reset(terrain: Node3D, limit: int = 9) -> void:
	terrain.reset_terrain(11235)
	terrain.set_fragment_cleanup(true, limit)

func patch_cells(origin: Vector3i, count: int = 9) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	for z in range(3):
		for x in range(3):
			result.append(origin + Vector3i(x, 0, z))
	if count == 10:
		result.append(origin + Vector3i(3, 0, 1))
	return result

func carve_fixture(terrain: Node3D, keep: Array[Vector3i], padding: int = 2) -> void:
	# Sculpt a real soil bitset, leaving exactly the supplied connected shape
	# inside an air moat. Natural terrain outside the moat remains intact.
	var low := keep[0]
	var high := keep[0]
	var occupied := {}
	for cell in keep:
		require(terrain.is_soil_cell(cell), "fixture starts from actual undug soil")
		low = low.min(cell)
		high = high.max(cell)
		occupied[cell] = true
	low -= Vector3i.ONE * padding
	high += Vector3i.ONE * padding
	for z in range(maxi(0, low.z), mini(Terrain.GRID_SIZE - 1, high.z) + 1):
		for x in range(maxi(0, low.x), mini(Terrain.GRID_SIZE - 1, high.x) + 1):
			var key := z * Terrain.GRID_SIZE + x
			var bits: int = terrain._removed_columns.get(key, 0)
			for y in range(maxi(0, low.y), mini(Terrain.LAYER_COUNT - 1, high.y) + 1):
				var bit := 1 << y
				if occupied.has(Vector3i(x, y, z)):
					bits &= ~bit
				else:
					bits |= bit
			terrain._removed_columns[key] = bits

func soil_count(terrain: Node3D, cells: Array[Vector3i]) -> int:
	var count := 0
	for cell in cells:
		if terrain.is_soil_cell(cell):
			count += 1
	return count

func ore_count(terrain: Node3D, cells: Array[Vector3i]) -> int:
	var count := 0
	for cell in cells:
		if terrain.is_soil_cell(cell) and terrain._is_ore(cell.x, cell.z, Terrain.BOTTOM_LEVEL + cell.y + 1):
			count += 1
	return count

func drain(terrain: Node3D) -> Dictionary:
	var total := {"removed": 0, "ore": 0, "visited": 0, "frames": 0}
	for frame in range(1024):
		var result: Dictionary = terrain.process_fragment_cleanup()
		total.frames += 1
		total_drain_frames += 1
		total.removed += int(result.removed)
		total.ore += int(result.ore)
		total.visited += int(result.visited)
		peak_frame_visits = maxi(peak_frame_visits, int(result.frame_visited))
		peak_elapsed_usec = maxi(peak_elapsed_usec, int(result.elapsed_usec))
		require(int(result.frame_visited) <= Terrain.CLEANUP_VISIT_BUDGET, "cleanup stays within its shared per-frame query budget")
		if int(result.pending) == 0 and int(result.get("scans", 0)) == 0:
			return total
		await process_frame
	require(false, "bounded cleanup queue eventually drains")
	return total

func queue_shape(terrain: Node3D, cells: Array[Vector3i]) -> void:
	var center := Vector3.ZERO
	for cell in cells:
		center += terrain.cell_center(cell)
	center /= cells.size()
	terrain.queue_fragment_cleanup_near(center, 0.65)

func run() -> void:
	var terrain := Terrain.new()
	root.add_child(terrain)
	reset(terrain)
	var origin := terrain.world_to_cell(Vector3(-0.0625, -1.5, -0.0625))
	var nine := patch_cells(origin)
	carve_fixture(terrain, nine)
	queue_shape(terrain, nine)
	var result: Dictionary = await drain(terrain)
	require(result.removed == 9 and soil_count(terrain, nine) == 0, "nine-cell component crossing X/Z chunks is completely removed")
	reset(terrain)
	var ten := patch_cells(origin, 10)
	carve_fixture(terrain, ten)
	queue_shape(terrain, ten)
	result = await drain(terrain)
	require(result.removed == 0 and soil_count(terrain, ten) == 10, "ten-cell connected component survives a nine-cell limit")
	terrain.set_fragment_cleanup(true, 10)
	queue_shape(terrain, ten)
	result = await drain(terrain)
	require(result.removed == 10 and soil_count(terrain, ten) == 0, "raising the threshold makes the same ten-cell component eligible")
	reset(terrain, 64)
	var sixty_four: Array[Vector3i] = []
	for z in range(4):
		for y in range(4):
			for x in range(4):
				sixty_four.append(origin + Vector3i(x, y, z))
	carve_fixture(terrain, sixty_four)
	queue_shape(terrain, sixty_four)
	result = await drain(terrain)
	var max_threshold_frames: int = result.frames
	require(result.removed == 64 and soil_count(terrain, sixty_four) == 0, "maximum supported threshold completes an atomic sixty-four-cell search")
	reset(terrain)
	carve_fixture(terrain, nine)
	terrain.set_fragment_cleanup(false, 9)
	queue_shape(terrain, nine)
	result = await drain(terrain)
	require(result.removed == 0 and soil_count(terrain, nine) == 9, "disabled cleanup never deletes a queued small component")
	terrain.set_fragment_cleanup(true, 9)
	queue_shape(terrain, nine)
	result = await drain(terrain)
	require(result.removed == 9, "reenabled cleanup accepts new work")
	reset(terrain)
	var bridge: Array[Vector3i] = [origin, origin + Vector3i.RIGHT, origin + Vector3i.RIGHT * 2]
	carve_fixture(terrain, bridge)
	# Restore a one-cell-wide neck across the air moat into the untouched mass.
	for x in range(origin.x + 3, origin.x + 6):
		var key := origin.z * Terrain.GRID_SIZE + x
		terrain._removed_columns[key] = int(terrain._removed_columns.get(key, 0)) & ~(1 << origin.y)
	queue_shape(terrain, bridge)
	result = await drain(terrain)
	require(result.removed == 0 and soil_count(terrain, bridge) == bridge.size(), "thin soil bridge connected to terrain stays intact")
	reset(terrain)
	var contacts: Array[Vector3i] = [origin, origin + Vector3i.RIGHT]
	carve_fixture(terrain, contacts)
	var crystal_cells: Array[Vector3i] = [contacts[1]]
	require(terrain.claim_crystal(7171, crystal_cells), "crystal contact fixture registers")
	queue_shape(terrain, contacts)
	result = await drain(terrain)
	require(result.removed == 0 and terrain.is_soil_cell(origin), "one soil cell touching crystal is intentionally protected")
	require(terrain.crystal_owner_at(contacts[1]) == 7171 and not terrain.is_soil_cell(contacts[1]), "cleanup never removes or converts crystal material")
	terrain.release_crystal(7171)
	result = await drain(terrain)
	require(result.removed == 1 and not terrain.is_solid_cell(origin), "releasing crystal automatically requeues formerly protected neighbouring soil")
	reset(terrain)
	var edge: Array[Vector3i] = [Vector3i(0, origin.y, origin.z)]
	carve_fixture(terrain, edge)
	queue_shape(terrain, edge)
	result = await drain(terrain)
	require(result.removed == 0 and terrain.is_soil_cell(edge[0]), "world-edge component is protected")
	reset(terrain)
	var bedrock: Array[Vector3i] = [Vector3i(origin.x, Terrain.DIG_LIMIT - Terrain.BOTTOM_LEVEL, origin.z), Vector3i(origin.x, Terrain.DIG_LIMIT - Terrain.BOTTOM_LEVEL - 1, origin.z)]
	carve_fixture(terrain, bedrock)
	queue_shape(terrain, bedrock)
	result = await drain(terrain)
	require(result.removed == 0 and soil_count(terrain, bedrock) == 2, "soil touching an unmineable bedrock cell is protected")
	reset(terrain)
	var ore_origin := terrain.world_to_cell(Vector3(Terrain.STARTER_VEIN.x, -0.25, Terrain.STARTER_VEIN.y))
	var ore_patch := patch_cells(ore_origin)
	carve_fixture(terrain, ore_patch)
	var expected_ore := ore_count(terrain, ore_patch)
	require(expected_ore > 0, "ore accounting fixture contains actual mineral-bearing soil")
	var chunk := Vector2i(ore_origin.x / Terrain.CHUNK_SIZE, ore_origin.z / Terrain.CHUNK_SIZE)
	terrain._rebuild_chunk(chunk)
	terrain._dirty.clear()
	queue_shape(terrain, ore_patch)
	result = await drain(terrain)
	require(result.removed == 9 and result.ore == expected_ore and soil_count(terrain, ore_patch) == 0, "ordinary ore credit matches removed mineral cells exactly")
	require(terrain._dirty.has(chunk), "cleanup schedules the resident mesh for rebuild")
	var second: Dictionary = await drain(terrain)
	require(second.removed == 0 and second.ore == 0, "already-cleaned soil never pays twice")
	reset(terrain)
	carve_fixture(terrain, nine)
	# Mine one edge of the isolated patch; automatic seed generation should
	# detect and remove its remaining small component without a manual queue.
	var dig_at := terrain.cell_center(origin + Vector3i.BACK) + Vector3.LEFT * 0.40
	var mined_ore: int = terrain.mine_at(dig_at, Vector3.UP, 0)
	var directly_removed: int = terrain.last_removed
	var remaining := soil_count(terrain, nine)
	require(remaining > 0 and remaining < 9, "real brush leaves a non-empty small fragment")
	var remaining_ore := ore_count(terrain, nine)
	result = await drain(terrain)
	require(soil_count(terrain, nine) == 0 and result.removed >= remaining and result.ore >= remaining_ore, "normal mining automatically enqueues surviving fragment cells")
	require(mined_ore >= 0 and directly_removed > 0, "automatic cleanup coexists with normal mining accounting")
	reset(terrain)
	for index in range(30):
		var at := Vector3(-3.0 + float(index % 10) * 0.5, -0.25, -3.0 + float(index / 10) * 0.5)
		terrain.mine_at(at, Vector3.UP, 0)
		terrain.queue_fragment_cleanup_near(at, 2.0)
	var first_batch: Dictionary = terrain.process_fragment_cleanup()
	var same_frame: Dictionary = terrain.process_fragment_cleanup()
	require(int(first_batch.visited) + int(same_frame.visited) <= Terrain.CLEANUP_VISIT_BUDGET, "multiple cleanup calls after continuous mining share one frame budget")
	require(int(same_frame.frame_visited) <= Terrain.CLEANUP_VISIT_BUDGET, "manual scanning and flood searches share the same budget")
	result = await drain(terrain)
	terrain.set_fragment_cleanup(true, 7)
	terrain.queue_fragment_cleanup_near(Vector3(0, -1, 0), 2.0)
	terrain.reset_terrain(11235)
	require(terrain.cleanup_enabled and terrain.cleanup_max_cells == 7, "reset retains enabled setting and chosen threshold")
	result = terrain.process_fragment_cleanup()
	require(int(result.pending) == 0 and int(result.get("scans", 0)) == 0 and int(result.visited) == 0 and int(result.removed) == 0, "reset discards stale searches without touching the fresh terrain")
	terrain.set_fragment_cleanup(false, 12)
	terrain.reset_terrain(11235)
	require(not terrain.cleanup_enabled and terrain.cleanup_max_cells == 12, "reset also preserves a disabled custom configuration")
	terrain.queue_free()
	await process_frame
	if not failed:
		print("FRAGMENT_CLEANUP_OK 9_delete/10_keep threshold64=%d_frames toggle cross_chunk bridge crystal_contact release_queue edge/bedrock ore=%d budget_peak=%d process_max_us=%d total_drain_frames=%d reset=true" % [max_threshold_frames, expected_ore, peak_frame_visits, peak_elapsed_usec, total_drain_frames])
	quit(1 if failed else 0)
