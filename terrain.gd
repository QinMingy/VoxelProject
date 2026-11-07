extends Node3D

const CELL_SIZE := 0.125
const GRID_SIZE := 512
const HALF_EXTENT := GRID_SIZE * CELL_SIZE * 0.5
const CHUNK_SIZE := 16
const CHUNK_COUNT := GRID_SIZE / CHUNK_SIZE
const FAR_STEP := CHUNK_SIZE * CELL_SIZE
const FAR_COUNT := CHUNK_COUNT
const BOTTOM_LEVEL := -32
const DIG_LIMIT := -28
const TOP_LEVEL := 24
const LAYER_COUNT := TOP_LEVEL - BOTTOM_LEVEL
const DETAIL_RADIUS := 5
const KEEP_RADIUS := 6
const STREAM_BUDGET_US := 3500
const CLEANUP_VISIT_BUDGET := 1024
const CLEANUP_TIME_BUDGET_US := 1500
const CLEANUP_MAX_THRESHOLD := 64
const CLEANUP_MANUAL_RADIUS := 2.0
const CLEANUP_SCAN_QUOTA := 256
const BASE_CENTRE := Vector2(-5.7, 4.9)
const WORLD_MIN := Vector3(-HALF_EXTENT, BOTTOM_LEVEL * CELL_SIZE, -HALF_EXTENT)
const WORLD_MAX := Vector3(HALF_EXTENT, TOP_LEVEL * CELL_SIZE, HALF_EXTENT)
const HALF_CELL := CELL_SIZE * 0.5
const FACE_STEPS := [Vector3i.UP, Vector3i.DOWN, Vector3i.RIGHT, Vector3i.LEFT, Vector3i.BACK, Vector3i.FORWARD]
const FACE_CORNERS := [[4, 5, 6, 7], [0, 3, 2, 1], [2, 6, 5, 1], [0, 4, 7, 3], [3, 7, 6, 2], [1, 5, 4, 0]]
const EPSILON := 0.00001
const STARTER_VEIN := Vector2(-3.56, 5.18)

const TOP_SOIL := Color("#737984")
const MIDDLE_SOIL := Color("#aa7349")
const DEEP_SOIL := Color("#55526d")
const ORE_SHADOW := Color("#159f8b")
const ORE_HIGHLIGHT := Color("#93fff0")

enum Brush { BOWL, DISK, PUNCH }

var last_removed := 0
var oxygen_supply_density := 0.25
var _map_oxygen_supply_density := 0.25
var cleanup_enabled := true
var cleanup_max_cells := 9
var _cleanup_queue: Array[Vector3i] = []
var _cleanup_queue_head := 0
var _cleanup_queued := {}
var _cleanup_scans: Array[Dictionary] = []
var _cleanup_scan_keys := {}
var _cleanup_frame_id := -1
var _cleanup_frame_visits := 0
var _cleanup_deadline := 0
var _cleanup_total_visits := 0
var _cleanup_total_removed := 0
var _cleanup_total_ore := 0
var _cleanup_last_visits := 0
var _cleanup_last_removed := 0
var _cleanup_last_usec := 0
var _removed_columns := {}
# Soil and collectible crystals share these exact terrain cells. Crystal column
# masks keep collision/raycast queries as cheap as the existing soil bit masks.
var _crystal_cells := {}
var _crystal_columns := {}
var _owner_cells := {}
var _height_chunks := {}
var _chunks := {}
var _dirty := {}
var _pending: Array[Vector2i] = []
var _focus_chunk := Vector2i(-100, -100)
var _detail_mask: Image
var _mask_texture: ImageTexture
var _mask_changed := false
var _far_ground: MeshInstance3D
var _far_heights := PackedFloat32Array()
var _terrain_noise := FastNoiseLite.new()
var _surface_material := ShaderMaterial.new()
var _map_seed := 0
var last_build_usec := 0
var max_build_usec := 0


func _ready() -> void:
	_terrain_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_terrain_noise.frequency = 0.045
	_terrain_noise.fractal_octaves = 3
	_detail_mask = Image.create(CHUNK_COUNT, CHUNK_COUNT, false, Image.FORMAT_R8)
	_mask_texture = ImageTexture.create_from_image(_detail_mask)
	var fine_shader := Shader.new()
	fine_shader.code = """
shader_type spatial;
render_mode cull_disabled, specular_disabled;
uniform sampler2D detail_mask : filter_nearest, repeat_disable;
uniform float half_extent;
uniform float world_size;
varying vec3 ground_position;
varying vec3 face_direction;
void vertex() {
	ground_position = VERTEX;
	face_direction = NORMAL;
}
void fragment() {
	// Alpha is a mesh tag, not transparency: only LOD seam faces use zero.
	if (COLOR.a < 0.5) {
		vec2 neighbor_uv = (ground_position.xz + face_direction.xz * 0.03 + vec2(half_extent)) / world_size;
		if (texture(detail_mask, neighbor_uv).r > 0.5) { discard; }
	}
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.96;
}
"""
	_surface_material.shader = fine_shader
	_surface_material.set_shader_parameter("detail_mask", _mask_texture)
	_surface_material.set_shader_parameter("half_extent", HALF_EXTENT)
	_surface_material.set_shader_parameter("world_size", HALF_EXTENT * 2.0)
	_far_ground = MeshInstance3D.new()
	_far_ground.name = "DistantGround"
	_far_ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode specular_disabled;
uniform sampler2D detail_mask : filter_nearest, repeat_disable;
uniform float half_extent;
uniform float world_size;
uniform float cell_density;
varying vec3 ground_position;
void vertex() { ground_position = VERTEX; }
void fragment() {
	vec2 uv = (ground_position.xz + vec2(half_extent)) / world_size;
	if (texture(detail_mask, uv).r > 0.5) { discard; }
	vec2 cell = floor(ground_position.xz * cell_density);
	float grain = fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
	ALBEDO = vec3(0.451, 0.475, 0.518) * mix(0.86, 1.08, grain);
	ROUGHNESS = 0.96;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("detail_mask", _mask_texture)
	material.set_shader_parameter("half_extent", HALF_EXTENT)
	material.set_shader_parameter("world_size", HALF_EXTENT * 2.0)
	material.set_shader_parameter("cell_density", 1.0 / CELL_SIZE)
	_far_ground.material_override = material
	add_child(_far_ground)
	reset_terrain()


func reset_terrain(seed_value: int = -1) -> void:
	_map_seed = seed_value if seed_value >= 0 else randi_range(1, 2147483646)
	# Density is fixed for this generated map, including existing rendered chunks.
	_map_oxygen_supply_density = oxygen_supply_density
	_terrain_noise.seed = _map_seed
	last_removed = 0
	_clear_fragment_tasks()
	_cleanup_frame_id = -1
	_cleanup_frame_visits = 0
	_cleanup_total_visits = 0
	_cleanup_total_removed = 0
	_cleanup_total_ore = 0
	_cleanup_last_visits = 0
	_cleanup_last_removed = 0
	_cleanup_last_usec = 0
	_removed_columns.clear()
	_crystal_cells.clear()
	_crystal_columns.clear()
	_owner_cells.clear()
	_height_chunks.clear()
	_dirty.clear()
	_pending.clear()
	for chunk: MeshInstance3D in _chunks.values():
		chunk.free()
	_chunks.clear()
	_detail_mask.fill(Color.BLACK)
	_mask_changed = true
	_build_far_ground()
	_focus_chunk = Vector2i(-100, -100)
	update_focus(Vector3(BASE_CENTRE.x, 0, BASE_CENTRE.y))
	# Seed only a small landing patch; remaining detail is streamed by frame budget.
	for z in range(-1, 2):
		for x in range(-1, 2):
			var key := _focus_chunk + Vector2i(x, z)
			if not _chunks.has(key):
				_rebuild_chunk(key)
	_upload_mask()


func update_focus(position: Vector3) -> void:
	var cell := _cell_at(position)
	var focus := Vector2i(clampi(cell.x / CHUNK_SIZE, 0, CHUNK_COUNT - 1), clampi(cell.z / CHUNK_SIZE, 0, CHUNK_COUNT - 1))
	if focus != _focus_chunk:
		_focus_chunk = focus
		for key: Vector2i in _chunks.keys():
			var offset := (key - focus).abs()
			if maxi(offset.x, offset.y) > KEEP_RADIUS:
				_chunks[key].free()
				_chunks.erase(key)
				_height_chunks.erase(key)
				_dirty.erase(key)
				_detail_mask.set_pixel(key.x, key.y, Color.BLACK)
				_mask_changed = true
		_pending.clear()
		for z in range(-DETAIL_RADIUS, DETAIL_RADIUS + 1):
			for x in range(-DETAIL_RADIUS, DETAIL_RADIUS + 1):
				var key := focus + Vector2i(x, z)
				if key.x >= 0 and key.y >= 0 and key.x < CHUNK_COUNT and key.y < CHUNK_COUNT and not _chunks.has(key):
					_pending.append(key)
		_pending.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return (a - focus).length_squared() < (b - focus).length_squared())
	var deadline := Time.get_ticks_usec() + STREAM_BUDGET_US
	var count := 0
	while count < 1 and Time.get_ticks_usec() < deadline:
		var key: Vector2i
		if not _dirty.is_empty():
			key = _dirty.keys()[0]
			_dirty.erase(key)
		elif not _pending.is_empty():
			key = _pending.pop_front()
			if _chunks.has(key):
				continue
		else:
			break
		_rebuild_chunk(key)
		count += 1
	_upload_mask()


func _upload_mask() -> void:
	if _mask_changed:
		_mask_texture.update(_detail_mask)
		_mask_changed = false


func natural_height_at(x: float, z: float) -> float:
	var distance := Vector2(x, z).distance_to(BASE_CENTRE)
	var flatten := smoothstep(3.0, 6.0, distance)
	var rolling := _terrain_noise.get_noise_2d(x, z) * 1.35
	var fine := _terrain_noise.get_noise_2d(x * 3.8 + 37.0, z * 3.8 - 19.0) * 0.20
	return floorf((rolling + fine) * flatten / CELL_SIZE) * CELL_SIZE


func _build_far_ground() -> void:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	vertices.resize((FAR_COUNT + 1) * (FAR_COUNT + 1))
	normals.resize(vertices.size())
	_far_heights.resize(vertices.size())
	for z in range(FAR_COUNT + 1):
		for x in range(FAR_COUNT + 1):
			var wx := -HALF_EXTENT + x * FAR_STEP
			var wz := -HALF_EXTENT + z * FAR_STEP
			var index := z * (FAR_COUNT + 1) + x
			_far_heights[index] = natural_height_at(wx, wz)
			vertices[index] = Vector3(wx, _far_heights[index], wz)
			normals[index] = Vector3.UP
	for z in range(FAR_COUNT):
		for x in range(FAR_COUNT):
			var a := z * (FAR_COUNT + 1) + x
			var b := a + 1
			var c := a + FAR_COUNT + 2
			var d := a + FAR_COUNT + 1
			indices.append_array(PackedInt32Array([a, b, c, a, c, d]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_far_ground.mesh = mesh


func _coarse_height_at(x: float, z: float) -> float:
	var grid_x := clampf((x + HALF_EXTENT) / FAR_STEP, 0.0, float(FAR_COUNT) - EPSILON)
	var grid_z := clampf((z + HALF_EXTENT) / FAR_STEP, 0.0, float(FAR_COUNT) - EPSILON)
	var ix := floori(grid_x)
	var iz := floori(grid_z)
	var fx := grid_x - ix
	var fz := grid_z - iz
	var stride := FAR_COUNT + 1
	var a := iz * stride + ix
	var h00 := _far_heights[a]
	var h10 := _far_heights[a + 1]
	var h11 := _far_heights[a + stride + 1]
	var h01 := _far_heights[a + stride]
	if fz <= fx:
		return h00 + (h10 - h00) * fx + (h11 - h10) * fz
	return h00 + (h11 - h01) * fx + (h01 - h00) * fz


func height_at(x: float, z: float) -> float:
	return support_height(x, z, WORLD_MAX.y)


func support_height(x: float, z: float, max_height: float) -> float:
	var cell := _cell_at(Vector3(x, 0.0, z))
	var highest := mini(LAYER_COUNT - 1, floori((max_height - WORLD_MIN.y + EPSILON) / CELL_SIZE) - 1)
	var bits := _column_bits(cell.x, cell.z)
	for y in range(highest, -1, -1):
		if (bits & (1 << y)) != 0 and (bits & (1 << (y + 1))) == 0:
			return WORLD_MIN.y + (y + 1) * CELL_SIZE
	return WORLD_MIN.y


func is_solid_at(point: Vector3) -> bool:
	return _solid(_cell_at(point))


func world_to_cell(point: Vector3) -> Vector3i:
	# Indices are relative to WORLD_MIN, exactly like the terrain's DDA grid.
	return _cell_at(point)


func cell_center(cell: Vector3i) -> Vector3:
	return _cell_center(cell)


func is_soil_cell(cell: Vector3i) -> bool:
	return cell.y >= 0 and cell.y < LAYER_COUNT and (_soil_column_bits(cell.x, cell.z) & (1 << cell.y)) != 0


func is_solid_cell(cell: Vector3i) -> bool:
	return _solid(cell)


func crystal_owner_at(cell: Vector3i) -> int:
	return int(_crystal_cells.get(cell, 0))


func claim_crystal(owner_id: int, world_cells: Array[Vector3i]) -> bool:
	if owner_id <= 0 or world_cells.is_empty():
		return false
	# Validate the whole shape before changing anything, including when replacing
	# an existing owner's shape. Another crystal must never be partially erased.
	var unique := {}
	for cell: Vector3i in world_cells:
		if not _in_bounds(cell.x, cell.z) or cell.y < 0 or cell.y >= LAYER_COUNT:
			return false
		var existing := crystal_owner_at(cell)
		if existing != 0 and existing != owner_id:
			return false
		unique[cell] = true
	var previous: Array = _owner_cells.get(owner_id, [])
	var unchanged := previous.size() == unique.size()
	if unchanged:
		for cell: Vector3i in previous:
			if not unique.has(cell):
				unchanged = false
				break
	if unchanged:
		return true
	var dirty_chunks := {}
	_remove_crystal_cells(owner_id, dirty_chunks)
	var claimed: Array[Vector3i] = []
	for cell: Vector3i in unique:
		var column_key := cell.z * GRID_SIZE + cell.x
		var bit := 1 << cell.y
		_crystal_cells[cell] = owner_id
		_crystal_columns[column_key] = int(_crystal_columns.get(column_key, 0)) | bit
		# This is a material substitution, not mining: no loose ore is awarded.
		# Keep the removal bit after pickup so only this exact shape becomes air.
		_removed_columns[column_key] = int(_removed_columns.get(column_key, 0)) | bit
		claimed.append(cell)
		_mark_cell_neighbors(dirty_chunks, cell)
	_owner_cells[owner_id] = claimed
	_dirty_resident_chunks(dirty_chunks)
	return true


func release_crystal(owner_id: int) -> void:
	var dirty_chunks := {}
	_remove_crystal_cells(owner_id, dirty_chunks)
	_dirty_resident_chunks(dirty_chunks)


func clear_crystals() -> void:
	# Unregistering retains excavated cavities; reset_terrain restores the world.
	var dirty_chunks := {}
	for owner_id: int in _owner_cells.keys():
		_remove_crystal_cells(owner_id, dirty_chunks)
	_dirty_resident_chunks(dirty_chunks)


func _remove_crystal_cells(owner_id: int, dirty_chunks: Dictionary) -> void:
	if not _owner_cells.has(owner_id):
		return
	for cell: Vector3i in _owner_cells[owner_id]:
		_crystal_cells.erase(cell)
		var column_key := cell.z * GRID_SIZE + cell.x
		var remaining := int(_crystal_columns.get(column_key, 0)) & ~(1 << cell.y)
		if remaining == 0:
			_crystal_columns.erase(column_key)
		else:
			_crystal_columns[column_key] = remaining
		_mark_cell_neighbors(dirty_chunks, cell)
		_queue_fragment_neighbors(cell)
	_owner_cells.erase(owner_id)


func _mark_cell_neighbors(dirty_chunks: Dictionary, cell: Vector3i) -> void:
	_mark_chunk(dirty_chunks, cell.x, cell.z)
	_mark_chunk(dirty_chunks, cell.x - 1, cell.z)
	_mark_chunk(dirty_chunks, cell.x + 1, cell.z)
	_mark_chunk(dirty_chunks, cell.x, cell.z - 1)
	_mark_chunk(dirty_chunks, cell.x, cell.z + 1)


func _dirty_resident_chunks(dirty_chunks: Dictionary) -> void:
	# Unloaded chunks rebuild from the occupancy dictionaries when streamed in.
	for chunk: Vector2i in dirty_chunks:
		if _chunks.has(chunk):
			_dirty[chunk] = true


func set_fragment_cleanup(enabled: bool, max_cells: int) -> void:
	cleanup_enabled = enabled
	cleanup_max_cells = clampi(max_cells, 1, CLEANUP_MAX_THRESHOLD)
	if not enabled:
		_clear_fragment_tasks()


func _clear_fragment_tasks() -> void:
	_cleanup_queue.clear()
	_cleanup_queue_head = 0
	_cleanup_queued.clear()
	_cleanup_scans.clear()
	_cleanup_scan_keys.clear()


func _queue_fragment_seed(cell: Vector3i) -> void:
	if not cleanup_enabled or not _in_bounds(cell.x, cell.z) or cell.y < DIG_LIMIT - BOTTOM_LEVEL or cell.y >= LAYER_COUNT:
		return
	if not _cleanup_queued.has(cell):
		_cleanup_queued[cell] = true
		_cleanup_queue.append(cell)


func _queue_fragment_neighbors(cell: Vector3i) -> void:
	if cleanup_enabled:
		for step: Vector3i in FACE_STEPS:
			_queue_fragment_seed(cell + step)


func queue_fragment_cleanup_near(world_point: Vector3, radius: float) -> void:
	if not cleanup_enabled or not world_point.is_finite() or not is_finite(radius):
		return
	if radius <= 0.0:
		_queue_fragment_seed(_cell_at(world_point))
		return
	var reach := minf(radius, CLEANUP_MANUAL_RADIUS)
	var first := _cell_at(world_point - Vector3.ONE * reach).max(Vector3i(0, DIG_LIMIT - BOTTOM_LEVEL, 0))
	var last := _cell_at(world_point + Vector3.ONE * reach).min(Vector3i(GRID_SIZE - 1, LAYER_COUNT - 1, GRID_SIZE - 1))
	if first.x > last.x or first.y > last.y or first.z > last.z:
		return
	var center_cell := _cell_at(world_point)
	var key := Vector4i(center_cell.x, center_cell.y, center_cell.z, ceili(reach / CELL_SIZE))
	if _cleanup_scan_keys.has(key) or _cleanup_scans.size() >= 4:
		return
	_cleanup_scan_keys[key] = true
	_cleanup_scans.append({"first": first, "last": last, "next": first,
		"center": world_point, "radius_squared": reach * reach, "key": key})


func _scan_fragment_candidates(limit: int) -> int:
	var visits := 0
	while visits < limit and not _cleanup_scans.is_empty() and Time.get_ticks_usec() < _cleanup_deadline:
		var scan: Dictionary = _cleanup_scans[0]
		var cell: Vector3i = scan.next
		visits += 1
		if _cell_center(cell).distance_squared_to(scan.center) <= float(scan.radius_squared) and is_soil_cell(cell):
			_queue_fragment_seed(cell)
		cell.x += 1
		if cell.x > scan.last.x:
			cell.x = scan.first.x
			cell.y += 1
			if cell.y > scan.last.y:
				cell.y = scan.first.y
				cell.z += 1
		if cell.z > scan.last.z:
			_cleanup_scan_keys.erase(scan.key)
			_cleanup_scans.pop_front()
		else:
			scan.next = cell
	return visits


func _inspect_fragment(seed: Vector3i, threshold: int) -> Dictionary:
	var members: Array[Vector3i] = []
	var visits := 1
	if not is_soil_cell(seed):
		return {"members": members, "remove": false, "visited": visits}
	members.append(seed)
	var seen := {seed: true}
	var index := 0
	while index < members.size():
		var cell: Vector3i = members[index]
		# World edges and unmineable bottom layers are anchors, never debris.
		if cell.x == 0 or cell.z == 0 or cell.x == GRID_SIZE - 1 or cell.z == GRID_SIZE - 1 or cell.y < DIG_LIMIT - BOTTOM_LEVEL or cell.y == LAYER_COUNT - 1:
			return {"members": members, "remove": false, "visited": visits}
		for step: Vector3i in FACE_STEPS:
			var neighbor := cell + step
			if seen.has(neighbor):
				continue
			seen[neighbor] = true
			visits += 1
			# Crystal contact currently counts as support. Releasing it queues the
			# neighboring soil again, so supported dust can become removable then.
			if crystal_owner_at(neighbor) != 0:
				return {"members": members, "remove": false, "visited": visits}
			if is_soil_cell(neighbor):
				members.append(neighbor)
				if members.size() > threshold:
					return {"members": members, "remove": false, "visited": visits}
		index += 1
	return {"members": members, "remove": true, "visited": visits}


func process_fragment_cleanup() -> Dictionary:
	var began := Time.get_ticks_usec()
	var visits := 0
	var removed := 0
	var ore := 0
	var frame := Engine.get_process_frames()
	if frame != _cleanup_frame_id:
		_cleanup_frame_id = frame
		_cleanup_frame_visits = 0
		_cleanup_deadline = began + CLEANUP_TIME_BUDGET_US
	var threshold := clampi(cleanup_max_cells, 1, CLEANUP_MAX_THRESHOLD)
	# Each search is atomic and reserves its worst case before starting. No BFS
	# state survives a frame, so later mining/claim/release cannot stale its proof.
	var worst_search_visits := 1 + 6 * threshold
	var dirty_chunks := {}
	if cleanup_enabled:
		visits += _scan_fragment_candidates(mini(CLEANUP_SCAN_QUOTA, CLEANUP_VISIT_BUDGET - _cleanup_frame_visits))
		while _cleanup_queue_head < _cleanup_queue.size() and CLEANUP_VISIT_BUDGET - _cleanup_frame_visits - visits >= worst_search_visits and Time.get_ticks_usec() < _cleanup_deadline:
			var seed := _cleanup_queue[_cleanup_queue_head]
			_cleanup_queue_head += 1
			if not _cleanup_queued.has(seed):
				visits += 1
				continue
			_cleanup_queued.erase(seed)
			var result := _inspect_fragment(seed, threshold)
			visits += int(result.visited)
			for cell: Vector3i in result.members:
				# These seeds belong to the same proven small/large/anchored component.
				# A later terrain change will enqueue its newly cut neighbors again.
				_cleanup_queued.erase(cell)
				if not result.remove:
					continue
				var column_key := cell.z * GRID_SIZE + cell.x
				_removed_columns[column_key] = int(_removed_columns.get(column_key, 0)) | (1 << cell.y)
				removed += 1
				if _is_ore(cell.x, cell.z, BOTTOM_LEVEL + cell.y + 1):
					ore += 1
				_mark_cell_neighbors(dirty_chunks, cell)
	_dirty_resident_chunks(dirty_chunks)
	if _cleanup_queued.is_empty():
		_cleanup_queue.clear()
		_cleanup_queue_head = 0
	elif _cleanup_queue_head > 1024 and _cleanup_queue_head * 2 >= _cleanup_queue.size():
		_cleanup_queue = _cleanup_queue.slice(_cleanup_queue_head)
		_cleanup_queue_head = 0
	_cleanup_frame_visits += visits
	_cleanup_total_visits += visits
	_cleanup_total_removed += removed
	_cleanup_total_ore += ore
	_cleanup_last_visits = visits
	_cleanup_last_removed = removed
	_cleanup_last_usec = Time.get_ticks_usec() - began
	return {"removed": removed, "ore": ore, "visited": visits, "frame_visited": _cleanup_frame_visits,
		"pending": _cleanup_queued.size(), "scans": _cleanup_scans.size(), "elapsed_usec": _cleanup_last_usec}


func raycast_voxels(origin: Vector3, direction: Vector3, max_distance: float) -> Dictionary:
	if direction.is_zero_approx() or max_distance <= 0.0:
		return {}
	var ray := direction.normalized()
	var entry := 0.0
	var exit := max_distance
	var normal := Vector3.ZERO
	for axis in range(3):
		if absf(ray[axis]) < EPSILON:
			if origin[axis] < WORLD_MIN[axis] or origin[axis] >= WORLD_MAX[axis]:
				return {}
			continue
		var a := (WORLD_MIN[axis] - origin[axis]) / ray[axis]
		var b := (WORLD_MAX[axis] - origin[axis]) / ray[axis]
		var near := minf(a, b)
		if near >= entry:
			entry = near
			normal = Vector3.ZERO
			normal[axis] = -signf(ray[axis])
		exit = minf(exit, maxf(a, b))
	if entry >= exit:
		return {}

	var cell := _cell_at(origin + ray * (entry + EPSILON))
	var step := Vector3i(int(signf(ray.x)), int(signf(ray.y)), int(signf(ray.z)))
	var next_face := Vector3(INF, INF, INF)
	var stride := Vector3(INF, INF, INF)
	for axis in range(3):
		if absf(ray[axis]) < EPSILON:
			continue
		var border := WORLD_MIN[axis] + (cell[axis] + int(step[axis] > 0)) * CELL_SIZE
		next_face[axis] = (border - origin[axis]) / ray[axis]
		stride[axis] = CELL_SIZE / absf(ray[axis])

	var solid := _solid(cell)
	if solid and normal == Vector3.ZERO:
		var behind := _cell_at(origin - ray * EPSILON)
		if not _solid(behind):
			for axis in range(3):
				if behind[axis] != cell[axis]:
					normal[axis] = -step[axis]
					break
	if solid and normal != Vector3.ZERO:
		return _ray_hit(origin + ray * entry, normal, cell)

	while true:
		var distance := minf(next_face.x, minf(next_face.y, next_face.z))
		if distance > exit:
			return {}
		var previous := cell
		normal = Vector3.ZERO
		for axis in range(3):
			if next_face[axis] <= distance + EPSILON:
				cell[axis] += step[axis]
				next_face[axis] += stride[axis]
				if normal == Vector3.ZERO:
					normal[axis] = -step[axis]
		var next_solid := _solid(cell)
		if next_solid != solid:
			if next_solid:
				return _ray_hit(origin + ray * distance, normal, cell)
			return _ray_hit(origin + ray * distance, -normal, previous)
		solid = next_solid
	return {}


func _ray_hit(position: Vector3, normal: Vector3, cell: Vector3i) -> Dictionary:
	var owner_id := crystal_owner_at(cell)
	return {"position": position, "normal": normal, "voxel_center": _cell_center(cell),
		"cell": cell, "material": "crystal" if owner_id != 0 else "soil", "crystal_id": owner_id}


func brush_radius(brush: int) -> float:
	match brush:
		Brush.DISK:
			return 0.60
		Brush.PUNCH:
			return 0.29
	return 0.45


func mine(x: float, z: float, brush: int = Brush.BOWL) -> int:
	return mine_at(Vector3(x, height_at(x, z), z), Vector3.UP, brush)


func mine_at(hit: Vector3, normal: Vector3, brush: int) -> int:
	last_removed = 0
	if not hit.is_finite() or not normal.is_finite() or normal.is_zero_approx():
		return 0
	var axis := normal.abs().max_axis_index()
	var outward := Vector3.ZERO
	outward[axis] = signf(normal[axis])
	var radius := brush_radius(brush)
	var radius_squared := radius * radius
	var center := hit
	var extents := Vector3.ONE * radius
	var rounded := brush != Brush.DISK and brush != Brush.PUNCH
	if not rounded:
		var half_depth := (5.0 if brush == Brush.PUNCH else 1.0) * HALF_CELL
		center -= outward * half_depth
		extents[axis] = half_depth
	var first := _cell_at(center - extents).max(Vector3i(0, DIG_LIMIT - BOTTOM_LEVEL, 0))
	var last := _cell_at(center + extents).min(Vector3i(GRID_SIZE - 1, LAYER_COUNT - 1, GRID_SIZE - 1))
	var dirty_chunks := {}
	var ore := 0
	var removed_cells: Array[Vector3i] = []
	for z in range(first.z, last.z + 1):
		for x in range(first.x, last.x + 1):
			var removed_in_column := false
			for y in range(first.y, last.y + 1):
				var cell := Vector3i(x, y, z)
				if not is_soil_cell(cell):
					continue
				var closest := ((_cell_center(cell) - center).abs() - Vector3.ONE * HALF_CELL).max(Vector3.ZERO)
				if not rounded:
					if closest[axis] >= extents[axis] - EPSILON:
						continue
					closest[axis] = 0.0
				if closest.length_squared() >= radius_squared:
					continue
				var column_key := cell.z * GRID_SIZE + cell.x
				_removed_columns[column_key] = int(_removed_columns.get(column_key, 0)) | (1 << cell.y)
				last_removed += 1
				if cleanup_enabled:
					removed_cells.append(cell)
				removed_in_column = true
				if _is_ore(x, z, BOTTOM_LEVEL + y + 1):
					ore += 1
			if removed_in_column:
				_mark_chunk(dirty_chunks, x, z)
				_mark_chunk(dirty_chunks, x - 1, z)
				_mark_chunk(dirty_chunks, x + 1, z)
				_mark_chunk(dirty_chunks, x, z - 1)
				_mark_chunk(dirty_chunks, x, z + 1)
	_dirty_resident_chunks(dirty_chunks)
	for cell: Vector3i in removed_cells:
		_queue_fragment_neighbors(cell)
	return ore


func _cell_at(point: Vector3) -> Vector3i:
	var local := (point - WORLD_MIN) / CELL_SIZE
	return Vector3i(floori(local.x), floori(local.y), floori(local.z))


func _cell_center(cell: Vector3i) -> Vector3:
	return WORLD_MIN + (Vector3(cell) + Vector3.ONE * 0.5) * CELL_SIZE


func _index(cell: Vector3i) -> int:
	return (cell.y * GRID_SIZE + cell.z) * GRID_SIZE + cell.x


func _in_bounds(x: int, z: int) -> bool:
	return x >= 0 and z >= 0 and x < GRID_SIZE and z < GRID_SIZE


func _solid(cell: Vector3i) -> bool:
	return cell.y >= 0 and cell.y < LAYER_COUNT and (_column_bits(cell.x, cell.z) & (1 << cell.y)) != 0


func _column_level(x: int, z: int) -> int:
	var key := Vector2i(x >> 4, z >> 4)
	if _height_chunks.has(key):
		var heights: PackedInt32Array = _height_chunks[key]
		return heights[(z & 15) * CHUNK_SIZE + (x & 15)]
	return roundi(natural_height_at(_world_position(x) + HALF_CELL, _world_position(z) + HALF_CELL) / CELL_SIZE)


func _column_bits(x: int, z: int) -> int:
	if not _in_bounds(x, z):
		return 0
	return _soil_column_bits(x, z) | int(_crystal_columns.get(z * GRID_SIZE + x, 0))


func _soil_column_bits(x: int, z: int) -> int:
	if not _in_bounds(x, z):
		return 0
	var count := clampi(_column_level(x, z) - BOTTOM_LEVEL, 0, LAYER_COUNT)
	return ((1 << count) - 1) & ~int(_removed_columns.get(z * GRID_SIZE + x, 0))


func _world_position(index: int) -> float:
	return index * CELL_SIZE - HALF_EXTENT


func _mark_chunk(dirty_chunks: Dictionary, x: int, z: int) -> void:
	if _in_bounds(x, z):
		dirty_chunks[Vector2i(x >> 4, z >> 4)] = true


func _noise(x: int, z: int, level: int) -> float:
	var value := sin(float(x) * 127.1 + float(z) * 311.7 + float(level) * 74.7 + _map_seed * 17.3) * 43758.5453
	return value - floorf(value)


func set_oxygen_supply_density(value: float) -> void:
	# Configure before reset_terrain. Mid-trip changes must not recolor old soil
	# or make previously rendered cells pay a different amount when excavated.
	oxygen_supply_density = clampf(value, 0.0, 1.0) if not is_nan(value) else 0.25


func _oxygen_density_hash(x: int, z: int, level: int) -> float:
	# A separate integer hash thins the original veins without moving them.
	# Keeping the same score per cell makes every higher density a superset.
	var value := (_map_seed * 1597334677 ^ x * 374761393 ^ z * 668265263 ^ level * 2246822519 ^ 0x6c8e9cf5) & 0xffffffff
	value = ((value ^ (value >> 16)) * 0x45d9f3b) & 0xffffffff
	value = ((value ^ (value >> 16)) * 0x45d9f3b) & 0xffffffff
	value = (value ^ (value >> 16)) & 0xffffffff
	return float(value) / 4294967296.0


func _is_ore(x: int, z: int, level: int) -> bool:
	# Compatibility name: these cyan cells now award oxygen supplies, not money.
	return _map_oxygen_supply_density > 0.0 and _is_ore_candidate(x, z, level) and _oxygen_density_hash(x, z, level) < _map_oxygen_supply_density


func _is_ore_candidate(x: int, z: int, level: int) -> bool:
	var wx := _world_position(x) + CELL_SIZE * 0.5
	var wz := _world_position(z) + CELL_SIZE * 0.5
	var grain := _noise(x, z, level - 100)
	if level >= -3:
		var offset := Vector2(wx, wz) - STARTER_VEIN
		var pocket := Vector2(offset.x * 1.4, offset.y).length_squared()
		if pocket < 0.42 and (pocket < 0.11 or grain < 0.64):
			return true
	var vein := sin(wx * 1.15 + wz * 0.75 + level * 0.31 + _map_seed * 0.7)
	var pocket := sin(wx * 1.22 - wz * 1.74 + level * 0.17 + _map_seed)
	var vein_coverage := 0.002
	if vein > 0.88 and pocket > 0.10:
		vein_coverage = lerpf(0.28, 0.78, (vein - 0.88) / 0.12)
	return grain < vein_coverage


func _color_at(x: int, z: int, level: int) -> Color:
	if _is_ore(x, z, level):
		return ORE_SHADOW.lerp(ORE_HIGHLIGHT, _noise(x, z, level - 20))
	var soil := TOP_SOIL
	var depth := _column_level(x, z) - level
	if depth >= 8:
		soil = DEEP_SOIL
	elif depth >= 3:
		soil = MIDDLE_SOIL
	var shade := lerpf(0.83, 1.12, _noise(x, z, level - 18))
	return Color(soil.r * shade, soil.g * shade, soil.b * shade)


func _quad(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3, color: Color) -> void:
	for vertex: Vector3 in [a, b, c, a, c, d]:
		tool.set_normal(normal)
		tool.set_color(color)
		tool.add_vertex(vertex)


func _rebuild_chunk(chunk: Vector2i) -> void:
	var began := Time.get_ticks_usec()
	if not _height_chunks.has(chunk):
		var heights := PackedInt32Array()
		heights.resize(CHUNK_SIZE * CHUNK_SIZE)
		for z in range(CHUNK_SIZE):
			for x in range(CHUNK_SIZE):
				var wx := _world_position(chunk.x * CHUNK_SIZE + x) + HALF_CELL
				var wz := _world_position(chunk.y * CHUNK_SIZE + z) + HALF_CELL
				heights[z * CHUNK_SIZE + x] = roundi(natural_height_at(wx, wz) / CELL_SIZE)
		_height_chunks[chunk] = heights
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for z in range(chunk.y * CHUNK_SIZE, (chunk.y + 1) * CHUNK_SIZE):
		for x in range(chunk.x * CHUNK_SIZE, (chunk.x + 1) * CHUNK_SIZE):
			var bits := _soil_column_bits(x, z)
			var solid_bits := bits | int(_crystal_columns.get(z * GRID_SIZE + x, 0))
			var exposed := [bits & ~(solid_bits >> 1), bits & ~(solid_bits << 1) & ~1,
				bits & ~_column_bits(x + 1, z), bits & ~_column_bits(x - 1, z),
				bits & ~_column_bits(x, z + 1), bits & ~_column_bits(x, z - 1)]
			for side in range(6):
				var faces: int = exposed[side]
				while faces != 0:
					var lowest := faces & -faces
					var y := roundi(log(float(lowest)) * 1.4426950408889634)
					_add_face(surface, Vector3i(x, y, z), side)
					faces &= ~lowest
	# Double-sided bridges join the actual coarse interpolation height to voxel steps.
	# Their shader hides them as soon as the adjacent chunk has fine detail.
	for index in range(CHUNK_SIZE):
		var first_x := chunk.x * CHUNK_SIZE
		var first_z := chunk.y * CHUNK_SIZE
		_add_skirt(surface, first_x, first_z + index, 3)
		_add_skirt(surface, first_x + CHUNK_SIZE - 1, first_z + index, 2)
		_add_skirt(surface, first_x + index, first_z, 5)
		_add_skirt(surface, first_x + index, first_z + CHUNK_SIZE - 1, 4)
	if not _chunks.has(chunk):
		var node := MeshInstance3D.new()
		node.name = "Ground_%d_%d" % [chunk.x, chunk.y]
		node.material_override = _surface_material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
		_chunks[chunk] = node
	_chunks[chunk].mesh = surface.commit()
	_detail_mask.set_pixel(chunk.x, chunk.y, Color.WHITE)
	_mask_changed = true
	last_build_usec = Time.get_ticks_usec() - began
	max_build_usec = maxi(max_build_usec, last_build_usec)


func _add_face(surface: SurfaceTool, cell: Vector3i, side: int) -> void:
	var west := _world_position(cell.x)
	var north := _world_position(cell.z)
	var east := west + CELL_SIZE
	var south := north + CELL_SIZE
	var low := WORLD_MIN.y + cell.y * CELL_SIZE
	var high := low + CELL_SIZE
	var corners := [Vector3(west, low, north), Vector3(east, low, north),
		Vector3(east, low, south), Vector3(west, low, south),
		Vector3(west, high, north), Vector3(east, high, north),
		Vector3(east, high, south), Vector3(west, high, south)]
	var face: Array = FACE_CORNERS[side]
	var color := _color_at(cell.x, cell.z, BOTTOM_LEVEL + cell.y + 1)
	_quad(surface, corners[face[0]], corners[face[1]], corners[face[2]], corners[face[3]], Vector3(FACE_STEPS[side]), color)


func _add_skirt(surface: SurfaceTool, x: int, z: int, side: int) -> void:
	# Join the actual remaining surface to coarse ground only at the distant LOD edge.
	# The shader discards these faces between fine chunks, so nearby caves stay open.
	var bits := _soil_column_bits(x, z)
	if bits == 0:
		return
	var y := floori(log(float(bits)) * 1.4426950408889634)
	var voxel_height := WORLD_MIN.y + (y + 1) * CELL_SIZE
	var west := _world_position(x)
	var north := _world_position(z)
	var east := west + CELL_SIZE
	var south := north + CELL_SIZE
	var first := Vector2(west, north)
	var second := Vector2(east, south)
	if side == 2:
		first.x = east
	elif side == 3:
		second.x = west
	elif side == 4:
		first.y = south
	else:
		second.y = north
	var coarse_first := _coarse_height_at(first.x, first.y)
	var coarse_second := _coarse_height_at(second.x, second.y)
	var high := maxf(voxel_height, maxf(coarse_first, coarse_second)) + 0.012
	var low := minf(voxel_height, minf(coarse_first, coarse_second)) - 0.025
	var corners := [Vector3(west, low, north), Vector3(east, low, north),
		Vector3(east, low, south), Vector3(west, low, south),
		Vector3(west, high, north), Vector3(east, high, north),
		Vector3(east, high, south), Vector3(west, high, south)]
	var face: Array = FACE_CORNERS[side]
	var color := _color_at(x, z, BOTTOM_LEVEL + y + 1)
	color.a = 0.0
	_quad(surface, corners[face[0]], corners[face[1]], corners[face[2]], corners[face[3]], Vector3(FACE_STEPS[side]), color)


func debug_stats() -> Dictionary:
	return {"map_metres": HALF_EXTENT * 2.0, "fine_chunks": _chunks.size(),
		"oxygen_supply_density": oxygen_supply_density, "map_oxygen_supply_density": _map_oxygen_supply_density,
		"height_chunks": _height_chunks.size(), "modified_columns": _removed_columns.size(),
		"crystal_cells": _crystal_cells.size(), "crystal_owners": _owner_cells.size(),
		"cleanup_enabled": cleanup_enabled, "cleanup_max_cells": cleanup_max_cells,
		"cleanup_pending": _cleanup_queued.size(), "cleanup_scans": _cleanup_scans.size(),
		"cleanup_last_visits": _cleanup_last_visits, "cleanup_frame_visits": _cleanup_frame_visits,
		"cleanup_total_visits": _cleanup_total_visits, "cleanup_total_removed": _cleanup_total_removed,
		"cleanup_removed": _cleanup_total_removed,
		"cleanup_total_ore": _cleanup_total_ore, "cleanup_last_removed": _cleanup_last_removed,
		"cleanup_last_usec": _cleanup_last_usec,
		"queued_chunks": _pending.size(), "dirty_chunks": _dirty.size(),
		"last_build_usec": last_build_usec, "max_build_usec": max_build_usec, "seed": _map_seed}
