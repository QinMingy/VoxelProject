extends SceneTree

# Numerical probe: uses production soil occupancy/mining and crystal release.
# Rendering/streaming is disabled; no saves or player profile are touched.
class ProbeTerrain:
	extends "res://terrain.gd"
	var requested_radius := 0.45
	func _ready() -> void:
		cleanup_enabled = false
		_terrain_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_terrain_noise.frequency = 0.045
		_terrain_noise.fractal_octaves = 3
	func brush_radius(_brush: int) -> float:
		return requested_radius
	func reset_probe(seed_value: int, density: float) -> void:
		_map_seed = seed_value
		_terrain_noise.seed = seed_value
		_map_oxygen_supply_density = density
		_removed_columns.clear()
		_crystal_cells.clear()
		_crystal_columns.clear()
		_owner_cells.clear()
		_height_chunks.clear()

const Crystal = preload("res://crystal.gd")
var terrain: ProbeTerrain
var rows: Array = []

func _initialize() -> void:
	call_deferred("run")

func shape_volume(radius_m: float, brush: int) -> Dictionary:
	terrain.reset_probe(11235, 0.25)
	terrain.requested_radius = radius_m
	# Flat landing patch. One surface hit and one wholly subterranean hit.
	terrain.mine_at(Vector3(-5.7, 0, 4.9), Vector3.UP, brush)
	var surface_cells := terrain.last_removed
	terrain.reset_probe(11235, 0.25)
	terrain.mine_at(Vector3(-5.7, -1.5, 4.9), Vector3.UP, brush)
	return {"kind": "brush_volume", "brush": brush, "radius_m": radius_m,
		"surface_cells": surface_cells, "full_cells": terrain.last_removed,
		"surface_m3": surface_cells * pow(terrain.CELL_SIZE, 3)}

func ore_rates(radius_m: float, density: float) -> Dictionary:
	var removed := 0
	var ore := 0
	var grain_counts: Array[int] = []
	for seed_value in [11235, 68217, 68218]:
		terrain.reset_probe(seed_value, density)
		terrain.requested_radius = radius_m
		for z in [-12.0, -6.0, 0.0, 6.0, 12.0]:
			for x in [-12.0, -6.0, 0.0, 6.0, 12.0]:
				var grains := terrain.mine_at(Vector3(x, terrain.height_at(x,z),z), Vector3.UP, 0)
				removed += terrain.last_removed
				ore += grains
				grain_counts.append(grains)
	grain_counts.sort()
	return {"kind": "oxygen_surface_sample", "hits": grain_counts.size(), "radius_m": radius_m,
		"density": density, "cells_per_hit": float(removed) / grain_counts.size(),
		"grains_per_hit": float(ore) / grain_counts.size(),
		"oxygen_per_hit": float(ore) / grain_counts.size() * 0.02,
		"p95_oxygen_per_hit": grain_counts[floori(0.95 * (grain_counts.size() - 1))] * 0.02,
		"max_oxygen_per_hit": grain_counts[-1] * 0.02}

func excavation(tier: int, burial_m: float, radius_m: float) -> Dictionary:
	terrain.reset_probe(11235, 0.25)
	terrain.requested_radius = radius_m
	var item := Crystal.new()
	root.add_child(item)
	item.position = Vector3(-5.7, 0, 4.9)
	item.setup_site(0.0, burial_m, [0.3, 0.42, 0.54][tier])
	assert(item.embed_in(terrain))
	var origin: Vector3i = item._origin_cell(item.position)
	# Every cell touching an object face or in its required lift path matters.
	var important := {}
	for neighbor: Vector3i in item._geometry.exterior:
		important[origin + neighbor] = true
	for cell: Vector3i in item._geometry.cells:
		for step in range(1, item.LIFT_STEPS + 1):
			important[origin + cell + Vector3i.UP * step] = true
	var bounds: AABB = item.get_local_bounds()
	var points: Array[Vector2] = []
	var spacing := maxf(0.125, radius_m * 0.75)
	for x in range(floori((bounds.position.x - radius_m * 0.7) / spacing), ceili((bounds.end.x + radius_m * 0.7) / spacing) + 1):
		for z in range(floori((bounds.position.z - radius_m * 0.7) / spacing), ceili((bounds.end.z + radius_m * 0.7) / spacing) + 1):
			points.append(Vector2(item.position.x + x * spacing, item.position.z + z * spacing))
	var strikes := 0
	var total_cells := 0
	item.refresh_exposure(terrain)
	while not item.is_loose() and strikes < 120:
		var saved: Dictionary = terrain._removed_columns.duplicate()
		var best_score := -1.0
		var best_hit := Vector3.ZERO
		for point: Vector2 in points:
			var hit := Vector3(point.x, terrain.height_at(point.x, point.y), point.y)
			terrain.mine_at(hit, Vector3.UP, 0)
			var score := float(terrain.last_removed) * 0.0001
			for cell: Vector3i in important:
				# All empty cells count equally between candidates; compare against
				# the same snapshot so only newly opened required space changes score.
				if not terrain.is_solid_cell(cell):
					score += 1.0
			if score > best_score:
				best_score = score
				best_hit = hit
			terrain._removed_columns = saved.duplicate()
		terrain.mine_at(best_hit, Vector3.UP, 0)
		if terrain.last_removed == 0:
			break
		total_cells += terrain.last_removed
		strikes += 1
		item.refresh_exposure(terrain)
	var result := {"kind": "top_down_greedy_extraction", "tier": tier, "burial_m": burial_m,
		"radius_m": radius_m, "strikes": strikes, "loose": item.is_loose(),
		"exposure": item.exposure_ratio, "removed_cells": total_cells,
		"base_seconds": strikes * 0.9, "max_speed_seconds": strikes * 0.30,
		"note": "optimistic deterministic top-down target selection; excludes walking/aiming/pickup"}
	item.free()
	return result

func run() -> void:
	terrain = ProbeTerrain.new()
	root.add_child(terrain)
	terrain.set_process(false)
	for radius_m in [0.35, 0.40, 0.45, 0.50, 0.55, 0.60]:
		rows.append(shape_volume(radius_m, 0))
	for brush in [1, 2]:
		rows.append(shape_volume([0.45, 0.60, 0.29][brush], brush))
	for radius_m in [0.40, 0.45, 0.55, 0.60]:
		for density in [0.25, 0.85]:
			rows.append(ore_rates(radius_m, density))
	for radius_m in [0.40, 0.45, 0.55, 0.60]:
		for tier in range(3):
			for burial_m in [-0.12, 0.24, 0.60]:
				var row := excavation(tier, burial_m, radius_m)
				rows.append(row)
				print(JSON.stringify(row))
	var json := JSON.stringify(rows, "\t")
	var file := FileAccess.open("res://.build/mining-balance-probe.json", FileAccess.WRITE)
	file.store_string(json)
	file.close()
	terrain.free()
	print("MINING_BALANCE_PROBE_OK rows=%d" % rows.size())
	quit()
