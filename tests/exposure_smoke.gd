extends SceneTree

const Crystal = preload("res://crystal.gd")
const Terrain = preload("res://terrain.gd")

class CellTerrain extends Node:
	var default_solid := true
	var floor_y := -1000
	var overrides := {}
	var owners := {}
	func is_solid_cell(cell: Vector3i) -> bool:
		return owners.has(cell) or bool(overrides.get(cell, default_solid or cell.y < floor_y))
	func is_soil_cell(cell: Vector3i) -> bool:
		return not owners.has(cell) and is_solid_cell(cell)
	func crystal_owner_at(cell: Vector3i) -> int:
		return int(owners.get(cell, 0))
	func claim_crystal(owner_id: int, cells: Array[Vector3i]) -> bool:
		for cell in cells:
			if owners.has(cell) and owners[cell] != owner_id:
				return false
		release_crystal(owner_id)
		for cell in cells:
			owners[cell] = owner_id
		return true
	func release_crystal(owner_id: int) -> void:
		for cell: Vector3i in owners.keys():
			if owners[cell] == owner_id:
				owners.erase(cell)

var test_failed := false

func _initialize() -> void:
	call_deferred("run")

func require(condition: bool, description: String) -> void:
	if not condition:
		test_failed = true
		push_error("EXPOSURE FAIL: " + description)
		quit(1)
		assert(condition, description)

func outside_faces(cells: Array[Vector3i]) -> Array[Vector3i]:
	# A repeated neighbour represents multiple distinct boundary faces.
	var occupied := {}
	for cell in cells:
		occupied[cell] = true
	var result: Array[Vector3i] = []
	for cell in cells:
		for step: Vector3i in [Vector3i.UP, Vector3i.DOWN, Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK]:
			if not occupied.has(cell + step):
				result.append(cell + step)
	return result

func face_ratio(cells: Array[Vector3i], soil: Node) -> float:
	var faces := outside_faces(cells)
	var free := 0
	for cell in faces:
		if not soil.is_solid_cell(cell):
			free += 1
	return float(free) / faces.size()

func run() -> void:
	var soil := CellTerrain.new()
	root.add_child(soil)
	var specimen := Crystal.new()
	root.add_child(specimen)
	specimen.setup_site(0.625, 0.0, 0.42)
	require(specimen.embed_in(soil), "specimen claims distinct material cells")
	var cells := specimen.get_world_cells()
	var faces := outside_faces(cells)
	require(cells.size() > 20, "crystal has a real multi-cell shape")
	require(not specimen.is_exposed(soil), "fully covered specimen is not discovered")
	specimen.refresh_exposure(soil)
	require(specimen.exposure_ratio == 0.0 and not specimen.is_loose(), "fully buried crystal has zero exposed faces")
	var one_opening: Vector3i = faces[0]
	soil.overrides[one_opening] = false
	specimen.refresh_exposure(soil)
	var hand_counted := float(faces.count(one_opening)) / faces.size()
	require(is_equal_approx(specimen.exposure_ratio, hand_counted), "one air cell exposes exactly its adjacent crystal faces")
	require(hand_counted > 0.0 and hand_counted < Crystal.RELEASE_EXPOSURE and not specimen.is_loose(), "a small hole cannot release the whole object")
	soil.overrides.clear()
	soil.default_solid = false
	var highest: Vector3i = cells[0]
	for cell in cells:
		if cell.y > highest.y:
			highest = cell
	var obstruction := highest + Vector3i.UP * 2
	soil.overrides[obstruction] = true
	specimen.refresh_exposure(soil)
	require(is_equal_approx(specimen.exposure_ratio, face_ratio(cells, soil)) and specimen.exposure_ratio >= Crystal.RELEASE_EXPOSURE, "surface exposure and extraction clearance are independent")
	require(not specimen.is_loose() and specimen.release_hint.contains("上方"), "blocked upward travel prevents extraction even with enough exposure")
	soil.overrides.clear()
	soil.floor_y = cells[0].y
	specimen.refresh_exposure(soil)
	require(is_equal_approx(specimen.exposure_ratio, face_ratio(cells, soil)), "ground-contact faces remain in the denominator")
	require(specimen.is_loose(), "ordinary floor contact alone does not require digging under the specimen")
	var ground_ratio := specimen.exposure_ratio
	specimen.queue_free()
	await process_frame
	# A gapped-column fixture distinguishes whole-shape translation from a roof test.
	var hollow := Crystal.new()
	root.add_child(hollow)
	var local_cells: Array[Vector3i] = [Vector3i.ZERO, Vector3i.UP * 4]
	hollow._geometry = hollow._geometry.duplicate()
	hollow._geometry.cells = local_cells
	hollow._geometry.exterior = outside_faces(local_cells)
	soil.floor_y = -1000
	soil.overrides.clear()
	require(hollow.embed_in(soil), "gapped fixture registers both occupied cells")
	var hollow_origin: Vector3i = hollow.get_world_cells()[0]
	soil.overrides[hollow_origin + Vector3i.UP * 2] = true
	hollow.refresh_exposure(soil)
	require(is_equal_approx(hollow.exposure_ratio, 1.0) and not hollow.is_loose(), "whole-shape translation catches an interior-gap obstruction missed by the roof")
	soil.overrides.clear()
	hollow.refresh_exposure(soil)
	require(hollow.is_loose(), "clearing the interior gap enables the same whole-shape translation")
	hollow.queue_free()
	await process_frame
	for tier in range(3):
		var item := Crystal.new()
		root.add_child(item)
		item.setup_site(0.0, 0.2, [0.30, 0.42, 0.54][tier])
		require(item.footprint == [Vector2i(1, 1), Vector2i(1, 2), Vector2i(2, 2)][tier], "size tier matches backpack footprint")
		require(item.base_value == [180, 400, 760][tier], "size tier retains its own base price")
		require(is_equal_approx(item.get_local_bounds().size.y, (tier + 4) * Terrain.CELL_SIZE), "world height is exactly four, five or six shared cells")
		require(item.embed_in(soil), "each tier can register independently")
		soil.floor_y = item.get_world_cells()[0].y
		item.refresh_exposure(soil)
		require(item.is_loose(), "every size can be extracted while resting on ordinary ground")
		item.queue_free()
		await process_frame
	soil.queue_free()
	await process_frame
	print("EXPOSURE_OK shared_neighbor_faces=true hand_counted=%.5f floor_contact=%.5f blocked_ceiling=true whole_shape_gap=true sizes=4/5/6" % [hand_counted, ground_ratio])
	quit(1 if test_failed else 0)
