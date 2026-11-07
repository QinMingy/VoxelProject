extends SceneTree

const Terrain = preload("res://terrain.gd")
const Crystal = preload("res://crystal.gd")

var test_failed := false

func _initialize() -> void:
	call_deferred("run")

func require(condition: bool, description: String) -> void:
	if not condition:
		test_failed = true
		push_error("SHARED VOXEL FAIL: " + description)
		quit(1)
		assert(condition, description)

func assert_registered(terrain: Node3D, item: Node3D) -> void:
	for cell: Vector3i in item.get_world_cells():
		require(terrain.crystal_owner_at(cell) == item.get_instance_id(), "every occupied cell has exactly the specimen owner")
		require(terrain.is_solid_cell(cell) and not terrain.is_soil_cell(cell), "crystal and soil never occupy the same cell")
		require(terrain.world_to_cell(terrain.cell_center(cell)) == cell, "cell conversion round trip is exact")

func excavate(terrain: Node3D, item: Node3D) -> void:
	var bounds: AABB = item.get_local_bounds()
	var center := item.position + bounds.get_center()
	var reach := Vector2(bounds.size.x, bounds.size.z) * 0.5 + Vector2.ONE * Terrain.CELL_SIZE
	for layer in range(10):
		for offset in [Vector2.ZERO, Vector2(-reach.x, 0), Vector2(reach.x, 0), Vector2(0, -reach.y), Vector2(0, reach.y), Vector2(-reach.x, -reach.y), Vector2(reach.x, -reach.y), Vector2(-reach.x, reach.y), Vector2(reach.x, reach.y)]:
			var origin := Vector3(center.x + offset.x, Terrain.WORLD_MAX.y + 1.0, center.z + offset.y)
			var hit: Dictionary = terrain.raycast_voxels(origin, Vector3.DOWN, 10.0)
			require(not hit.is_empty(), "excavation ray reaches soil or crystal")
			terrain.mine_at(hit.position, hit.normal, 0)
			assert_registered(terrain, item)
			item.refresh_exposure(terrain)
			if item.is_loose():
				return
	require(false, "perimeter excavation releases a real embedded specimen")

func soil_snapshot(terrain: Node3D, middle: Vector3i, radius: int) -> Dictionary:
	var result := {}
	for x in range(middle.x - radius, middle.x + radius + 1):
		for y in range(middle.y - radius, middle.y + radius + 1):
			for z in range(middle.z - radius, middle.z + radius + 1):
				var cell := Vector3i(x, y, z)
				result[cell] = terrain.is_soil_cell(cell)
	return result

func assert_soil_unchanged(terrain: Node3D, snapshot: Dictionary, description: String) -> void:
	for cell: Vector3i in snapshot:
		require(terrain.is_soil_cell(cell) == snapshot[cell], description)

func cavity_faces(terrain: Node3D, cell: Vector3i) -> int:
	var chunk := Vector2i(cell.x / Terrain.CHUNK_SIZE, cell.z / Terrain.CHUNK_SIZE)
	terrain._rebuild_chunk(chunk)
	var mesh: ArrayMesh = terrain._chunks[chunk].mesh
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var low: Vector3 = terrain.cell_center(cell) - Vector3.ONE * Terrain.CELL_SIZE * 0.5 - Vector3.ONE * 0.00001
	var high: Vector3 = low + Vector3.ONE * (Terrain.CELL_SIZE + 0.00002)
	var triangles := 0
	var count := indices.size() if not indices.is_empty() else vertices.size()
	for first in range(0, count, 3):
		var inside := true
		for corner in range(3):
			var vertex := vertices[indices[first + corner] if not indices.is_empty() else first + corner]
			inside = inside and vertex.x >= low.x and vertex.x <= high.x and vertex.y >= low.y and vertex.y <= high.y and vertex.z >= low.z and vertex.z <= high.z
		if inside:
			triangles += 1
	return triangles / 2

func run() -> void:
	var terrain := Terrain.new()
	root.add_child(terrain)
	terrain.reset_terrain(11235)
	var mesh_cell := terrain.world_to_cell(Vector3(0.5625, -1.5, 0.5625))
	var one_cell: Array[Vector3i] = [mesh_cell]
	require(terrain.claim_crystal(999, one_cell), "single-cell material substitution fixture registers")
	require(cavity_faces(terrain, mesh_cell) == 0, "touching soil never draws its six hidden contact faces against crystal")
	terrain.release_crystal(999)
	require(cavity_faces(terrain, mesh_cell) == 6, "the six soil faces appear only after the crystal cell becomes air")
	terrain.reset_terrain(11235)
	# Both X and Z straddle detail-chunk boundaries, while staying underground.
	var anchor := terrain.world_to_cell(Vector3(-0.0625, -1.5, -0.0625))
	var cells: Array[Vector3i] = [anchor, anchor + Vector3i.RIGHT, anchor + Vector3i.BACK, anchor + Vector3i.RIGHT + Vector3i.BACK]
	require(anchor.x % Terrain.CHUNK_SIZE == 15 and anchor.z % Terrain.CHUNK_SIZE == 15, "fixture crosses two chunk boundaries")
	for cell in cells:
		require(terrain.is_soil_cell(cell), "claim starts by replacing actual soil")
	var adjacent := anchor + Vector3i.DOWN
	require(terrain.claim_crystal(1001, cells), "atomic crystal claim succeeds across chunks")
	for cell in cells:
		require(terrain.crystal_owner_at(cell) == 1001 and terrain.is_solid_cell(cell) and not terrain.is_soil_cell(cell), "claim substitutes material without overlapping soil")
	require(terrain.is_soil_cell(adjacent), "adjacent soil directly touches crystal without a clearance halo")
	var lower_boundary := terrain.cell_center(anchor).y - Terrain.CELL_SIZE * 0.5
	var upper_soil_boundary := terrain.cell_center(adjacent).y + Terrain.CELL_SIZE * 0.5
	require(is_equal_approx(lower_boundary, upper_soil_boundary), "neighbouring material faces share exactly the same plane")
	require(terrain.claim_crystal(1001, cells) and terrain.debug_stats().crystal_cells == cells.size(), "repeated registration is idempotent")
	var invalid: Array[Vector3i] = [anchor + Vector3i.UP * 2, anchor]
	require(not terrain.claim_crystal(1002, invalid), "overlapping second-owner claim is rejected atomically")
	require(terrain.crystal_owner_at(invalid[0]) == 0 and terrain.is_soil_cell(invalid[0]), "failed claim never partially replaces soil")
	for normal: Vector3i in Crystal.STEPS:
		mine_direction(terrain, anchor, normal)
		for cell in cells:
			require(terrain.crystal_owner_at(cell) == 1001 and not terrain.is_soil_cell(cell), "all six mining directions preserve crystal cells")
	terrain.release_crystal(1001)
	for cell in cells:
		require(terrain.crystal_owner_at(cell) == 0 and not terrain.is_solid_cell(cell), "unregister leaves exactly the former shape as air")
	require(terrain.debug_stats().crystal_cells == 0 and terrain.debug_stats().crystal_owners == 0, "release removes all cross-chunk ownership")
	terrain.reset_terrain(11235)
	for cell in cells:
		require(terrain.is_soil_cell(cell), "reset restores terrain rather than preserving stale cavities")
	var item := Crystal.new()
	root.add_child(item)
	item.position = Vector3(-4.0, 0.0, 4.0)
	item.setup_site(terrain.natural_height_at(item.position.x, item.position.z), 0.25, 0.54)
	require(item.embed_in(terrain), "real voxel specimen registers with terrain")
	assert_registered(terrain, item)
	var original_cells: Array[Vector3i] = item.get_world_cells().duplicate()
	var bounds := item.get_local_bounds()
	var mesh: ArrayMesh = item._mesh_instance.mesh
	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for vertex in vertices:
		var world := item.to_global(vertex)
		var lattice := (world - Terrain.WORLD_MIN) / Terrain.CELL_SIZE
		require(lattice.is_equal_approx(lattice.round()), "rendered crystal faces align with the terrain lattice")
	item.refresh_exposure(terrain)
	require(item.exposure_ratio == 0.0 and not item.is_loose(), "fully embedded shared-grid crystal has zero air faces")
	excavate(terrain, item)
	var before_pickup := soil_snapshot(terrain, terrain.world_to_cell(item.position + bounds.get_center()), 8)
	require(before_pickup.values().has(true), "pickup conservation fixture includes undug neighbouring soil")
	var suit := Node3D.new()
	root.add_child(suit)
	item.set_wear(0.37)
	item.show_carried(suit)
	for cell in original_cells:
		require(terrain.crystal_owner_at(cell) == 0 and not terrain.is_solid_cell(cell), "pickup unregisters every old crystal cell")
	assert_soil_unchanged(terrain, before_pickup, "pickup never clears additional surrounding soil")
	var landing := Vector3(-6.0, terrain.height_at(-6.0, 3.0), 3.0)
	var before_drop := soil_snapshot(terrain, terrain.world_to_cell(landing), 12)
	require(item.drop_at(landing), "drop finds a legal nearby placement")
	assert_registered(terrain, item)
	assert_soil_unchanged(terrain, before_drop, "dropping does not erase soil to make room")
	require(item.wear_percent == 37 and item.size_tier == 2 and item.is_loose(), "drop preserves item properties and permits repick")
	var drop_cells: Array[Vector3i] = item.get_world_cells().duplicate()
	var registered_count: int = terrain.debug_stats().crystal_cells
	require(item.embed_in(terrain) and terrain.debug_stats().crystal_cells == registered_count, "re-embedding does not duplicate occupancy")
	item.show_carried(suit)
	for cell in drop_cells:
		require(terrain.crystal_owner_at(cell) == 0, "repick leaves no drop-site ghost cells")
	require(terrain.debug_stats().crystal_cells == 0, "repick releases the whole re-registered shape")
	require(item.drop_at(landing), "second drop also safely registers")
	terrain.clear_crystals()
	require(terrain.debug_stats().crystal_cells == 0 and terrain.debug_stats().crystal_owners == 0, "map respawn unregisters all previous crystals")
	terrain.reset_terrain(11235)
	require(terrain.debug_stats().crystal_cells == 0, "new trip begins with no ghost ownership")
	item.queue_free()
	suit.queue_free()
	terrain.queue_free()
	await process_frame
	print("SHARED_VOXEL_OK material_exclusion=true lattice=true cross_chunk=true six_directions=true pickup_cavity=true drop_conservation=true no_ghosts=true")
	quit(1 if test_failed else 0)

func mine_direction(terrain: Node3D, cell: Vector3i, normal: Vector3i) -> void:
	# A brush on any of the six crystal boundary faces may remove soil only.
	terrain.mine_at(terrain.cell_center(cell) + Vector3(normal) * Terrain.CELL_SIZE * 0.5, Vector3(normal), 0)
