extends SceneTree

const Terrain = preload("res://terrain.gd")
const DENSITIES := [0.25, 0.40, 0.60, 0.85]
const SEED := 11235
var terrain: Node3D
var failed := false


func _initialize() -> void:
	call_deferred("run")


func require(condition: bool, description: String) -> void:
	if not condition:
		failed = true
		push_error("OXYGEN DENSITY FAIL: " + description)
		quit(1)
		assert(condition, description)


func generate(density: float, map_seed: int = SEED) -> void:
	terrain.set_oxygen_supply_density(density)
	terrain.reset_terrain(map_seed)
	terrain.set_fragment_cleanup(false, 9)


func ore_cells(cells: Array[Vector3i]) -> Dictionary:
	var result := {}
	for cell in cells:
		if terrain._is_ore(cell.x, cell.z, Terrain.BOTTOM_LEVEL + cell.y + 1):
			result[cell] = true
	return result


func candidate_sample() -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	# A bounded 40m sampling lattice, not a scan of the entire fine voxel map.
	for iz in range(-40, 41):
		for ix in range(-40, 41):
			var x := float(ix) * 0.5 + 0.0625
			var z := float(iz) * 0.5 + 0.0625
			var surface: float = terrain.natural_height_at(x, z)
			for depth in range(1, 17):
				var cell: Vector3i = terrain.world_to_cell(Vector3(x, surface - float(depth) * Terrain.CELL_SIZE + 0.0625, z))
				if terrain.is_soil_cell(cell) and terrain._is_ore_candidate(cell.x, cell.z, Terrain.BOTTOM_LEVEL + cell.y + 1):
					result.append(cell)
	return result


func isolate_patch() -> Array[Vector3i]:
	var origin: Vector3i = terrain.world_to_cell(Vector3(Terrain.STARTER_VEIN.x, -0.25, Terrain.STARTER_VEIN.y))
	var cells: Array[Vector3i] = []
	var keep := {}
	for z in range(3):
		for x in range(3):
			var cell := origin + Vector3i(x, 0, z)
			require(terrain.is_soil_cell(cell), "accounting fixture starts with real soil")
			cells.append(cell)
			keep[cell] = true
	for z in range(origin.z - 4, origin.z + 7):
		for x in range(origin.x - 4, origin.x + 7):
			var key := z * Terrain.GRID_SIZE + x
			var bits: int = terrain._removed_columns.get(key, 0)
			for y in range(origin.y - 4, origin.y + 5):
				if not keep.has(Vector3i(x, y, z)):
					bits |= 1 << y
			terrain._removed_columns[key] = bits
	return cells


func drain() -> Dictionary:
	var total := {"removed": 0, "ore": 0}
	for frame in range(256):
		var result: Dictionary = terrain.process_fragment_cleanup()
		total.removed += int(result.removed)
		total.ore += int(result.ore)
		if int(result.pending) == 0 and int(result.scans) == 0:
			return total
		await process_frame
	require(false, "local fragment cleanup completes within its frame budget")
	return total


func run() -> void:
	terrain = Terrain.new()
	root.add_child(terrain)
	require(is_equal_approx(terrain.oxygen_supply_density, 0.25), "new terrain defaults to quarter-density supplies")
	terrain.set_oxygen_supply_density(-1.0)
	require(terrain.oxygen_supply_density == 0.0, "negative density clamps to zero")
	terrain.set_oxygen_supply_density(2.0)
	require(terrain.oxygen_supply_density == 1.0, "density above one clamps to one")
	generate(1.0)
	var candidates := candidate_sample()
	require(candidates.size() > 1000, "nested-density sample covers many real candidate cells")
	var previous := {}
	var counts: Array[int] = []
	var expected_sixty := {}
	for density: float in DENSITIES:
		generate(density)
		var selected := ore_cells(candidates)
		require(selected.size() > previous.size(), "each upgrade strictly adds supply cells in the fixed sample")
		for cell: Vector3i in previous:
			require(selected.has(cell), "upgrading never removes a previously available supply cell")
		counts.append(selected.size())
		previous = selected
		if is_equal_approx(density, 0.60):
			expected_sixty = selected
	generate(0.60)
	require(ore_cells(candidates) == expected_sixty, "same seed and density reproduce exactly the same supply cells")
	terrain.set_oxygen_supply_density(0.0)
	require(ore_cells(candidates) == expected_sixty, "new configuration cannot change the active map's rendered/mined material")
	terrain.reset_terrain(SEED)
	require(ore_cells(candidates).is_empty(), "zero-density generation contains no supplies")
	generate(1.0)
	require(ore_cells(candidates).size() == candidates.size(), "density one preserves the original candidate distribution")
	generate(0.60, SEED + 1)
	require(ore_cells(candidates) != expected_sixty, "a new seed changes the supply layout")

	generate(0.60)
	var patch := isolate_patch()
	var expected := ore_cells(patch).size()
	require(expected > 0 and expected < patch.size(), "starter vein is filtered rather than exempt from density")
	for cell in patch:
		var level := Terrain.BOTTOM_LEVEL + cell.y + 1
		var color: Color = terrain._color_at(cell.x, cell.z, level)
		var oxygen_color: Color = Terrain.ORE_SHADOW.lerp(Terrain.ORE_HIGHLIGHT, terrain._noise(cell.x, cell.z, level - 20))
		require(color.is_equal_approx(oxygen_color) == terrain._is_ore(cell.x, cell.z, level), "visible cyan material exactly matches supply accounting")
	var center: Vector3 = terrain.cell_center(patch[4])
	var mined: int = terrain.mine_at(center + Vector3.UP * Terrain.HALF_CELL, Vector3.UP, Terrain.Brush.BOWL)
	require(terrain.last_removed == 9 and mined == expected, "real sphere mining awards only the selected supply cells")
	require(terrain.mine_at(center + Vector3.UP * Terrain.HALF_CELL, Vector3.UP, Terrain.Brush.BOWL) == 0 and terrain.last_removed == 0, "mining the same empty patch cannot award supplies twice")
	generate(0.60)
	patch = isolate_patch()
	terrain.set_fragment_cleanup(true, 9)
	terrain.queue_fragment_cleanup_near(center, 0.35)
	var cleaned: Dictionary = await drain()
	require(cleaned.removed == 9 and cleaned.ore == expected and cleaned.ore == mined, "fragment cleanup and manual mining award the same material count")
	terrain.queue_fragment_cleanup_near(center, 0.35)
	cleaned = await drain()
	require(cleaned.removed == 0 and cleaned.ore == 0, "fragment cleanup cannot repeat supply awards")
	print("OXYGEN_DENSITY_OK candidates=%d nested_counts=%s repeat=true latched=true color_consistent=true mine_cleanup=%d" % [candidates.size(), counts, expected])
	if OS.get_cmdline_user_args().has("--sample"):
		sample_shovels()
	terrain.free()
	quit(1 if failed else 0)


func distribution(values: Array[int]) -> Dictionary:
	var sorted := values.duplicate()
	sorted.sort()
	var nonzero: Array[int] = []
	var total := 0
	for value: int in sorted:
		total += value
		if value > 0:
			nonzero.append(value)
	return {"n": sorted.size(), "min": sorted[0], "median": sorted[sorted.size() / 2],
		"p90": sorted[floori(float(sorted.size() - 1) * 0.90)], "max": sorted[-1],
		"mean": float(total) / sorted.size(), "hit_percent": 100.0 * nonzero.size() / sorted.size(),
		"nonzero_median": nonzero[nonzero.size() / 2] if not nonzero.is_empty() else 0,
		"nonzero_p90": nonzero[floori(float(nonzero.size() - 1) * 0.90)] if not nonzero.is_empty() else 0}


func sample_shovels() -> void:
	# Read-only balance evidence: mine disposable terrain instances/state, never
	# player inventory or saves. Repeat the same positions at every density.
	for density: float in DENSITIES:
		var surface: Array[int] = []
		var deeper: Array[int] = []
		var starter: Array[int] = []
		for map_seed in [11235, 13579, 24680]:
			generate(density, map_seed)
			for z in range(-22, 23, 4):
				for x in range(-22, 23, 4):
					var horizontal := Vector2(float(x) + 0.0625, float(z) + 0.0625)
					if horizontal.length() > 24.0 or horizontal.distance_to(Terrain.BASE_CENTRE) < 4.0:
						continue
					for scoop in range(4):
						var hit := Vector3(horizontal.x, terrain.height_at(horizontal.x, horizontal.y), horizontal.y)
						var found: int = terrain.mine_at(hit, Vector3.UP, Terrain.Brush.BOWL)
						if scoop == 0:
							surface.append(found)
						else:
							deeper.append(found)
			for scoop in range(7):
				var hit := Vector3(Terrain.STARTER_VEIN.x, terrain.height_at(Terrain.STARTER_VEIN.x, Terrain.STARTER_VEIN.y), Terrain.STARTER_VEIN.y)
				starter.append(terrain.mine_at(hit, Vector3.UP, Terrain.Brush.BOWL))
		print("OXYGEN_SHOVEL_SAMPLE ", JSON.stringify({"density": density, "surface": distribution(surface),
			"deeper": distribution(deeper), "starter": distribution(starter), "starter_sequence": starter}))
