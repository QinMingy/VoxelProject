extends RefCounted

# Static props are transformed once, then rasterised on the terrain's lattice.
# One cell set drives their visible surface, terrain exclusion and extraction.
const Terrain = preload("res://terrain.gd")
const Palette = preload("res://palette.gd")
const CELL_SIZE := Terrain.CELL_SIZE
const MAX_CANDIDATE_CELLS := 24000
const EPSILON := 0.000001
const STEPS := [Vector3i.UP, Vector3i.DOWN, Vector3i.RIGHT, Vector3i.LEFT, Vector3i.BACK, Vector3i.FORWARD]
const FACE_CORNERS := [[4, 5, 6, 7], [0, 3, 2, 1], [2, 6, 5, 1], [0, 4, 7, 3], [3, 7, 6, 2], [1, 5, 4, 0]]

static var _source_cache: Dictionary = {}
static var _canonical_cache: Dictionary = {}


static func orthogonal_basis(quarter_turns: Vector3i) -> Basis:
	# Match Godot's default Euler order, then snap its signed axis columns exactly.
	# Only 24 distinct orientations result from the 4x4x4 possible turn triples.
	var turns := Vector3i(posmod(quarter_turns.x, 4), posmod(quarter_turns.y, 4), posmod(quarter_turns.z, 4))
	var rotation := Basis.from_euler(Vector3(turns) * (PI * 0.5))
	return Basis(rotation.x.round(), rotation.y.round(), rotation.z.round())


static func _rotated_cell(cell: Vector3i, rotation: Basis) -> Vector3i:
	# Rotate the unit cube's centre; its new integer lower corner is centre-.5.
	return Vector3i((rotation * (Vector3(cell) + Vector3.ONE * 0.5) - Vector3.ONE * 0.5).round())


static func sample_orthogonal_scene(scene: PackedScene, quarter_turns: Vector3i, target_size: float) -> Dictionary:
	if scene == null or target_size <= 0.0:
		push_error("Voxel prop requires a scene and a positive target size")
		return {}
	var started := Time.get_ticks_usec()
	var identity := scene.resource_path if not scene.resource_path.is_empty() else "instance:%d" % scene.get_instance_id()
	var key := identity + "|" + str(target_size)
	if not _canonical_cache.has(key):
		var sampled := sample_scene(scene, Basis.IDENTITY, target_size)
		if sampled.is_empty():
			return {}
		_canonical_cache[key] = sampled
	var canonical: Dictionary = _canonical_cache[key]
	var rotation := orthogonal_basis(quarter_turns)
	var shape := {}
	var colors := {}
	var face_colors := {}
	for cell: Vector3i in canonical.cells:
		var mapped := _rotated_cell(cell, rotation)
		shape[mapped] = true
		colors[mapped] = canonical.cell_colors[cell]
	for face: Vector4i in canonical.face_colors:
		var mapped := _rotated_cell(Vector3i(face.x, face.y, face.z), rotation)
		var normal := Vector3i((rotation * Vector3(STEPS[face.w])).round())
		var side := STEPS.find(normal)
		face_colors[Vector4i(mapped.x, mapped.y, mapped.z, side)] = canonical.face_colors[face]
	var result := _build_geometry(shape, colors, {}, face_colors)
	var diagnostics: Dictionary = canonical.diagnostics.duplicate()
	diagnostics["canonical_sample_us"] = canonical.diagnostics.elapsed_us
	diagnostics["elapsed_us"] = Time.get_ticks_usec() - started
	diagnostics["rotated_bounds"] = Transform3D(rotation, Vector3.ZERO) * (canonical.diagnostics.rotated_bounds as AABB)
	diagnostics["sampling"] = "cached_quarter_turn_permutation"
	diagnostics["color_sampling"] = "canonical_exposed_face_palette_permutation"
	diagnostics["quarter_turns"] = Vector3i(posmod(quarter_turns.x, 4), posmod(quarter_turns.y, 4), posmod(quarter_turns.z, 4))
	diagnostics["cell_size"] = CELL_SIZE
	result["diagnostics"] = diagnostics
	return result


static func sample_scene(scene: PackedScene, basis: Basis, target_size: float) -> Dictionary:
	if scene == null or target_size <= 0.0:
		push_error("Voxel prop requires a scene and a positive target size")
		return {}
	var started := Time.get_ticks_usec()
	var source := _source_for(scene)
	if source.is_empty():
		return {}
	var original_bounds: AABB = source.bounds
	var longest := maxf(original_bounds.size.x, maxf(original_bounds.size.y, original_bounds.size.z))
	if longest <= EPSILON:
		return {}
	var scale_factor := target_size / longest
	var centre := original_bounds.get_center()
	var triangles: Array[Dictionary] = []
	var bounds := AABB()
	var first := true
	for original: Dictionary in source.triangles:
		var triangle := original.duplicate()
		for key: String in ["a", "b", "c"]:
			var vertex: Vector3 = basis * ((original[key] - centre) * scale_factor)
			triangle[key] = vertex
			if first:
				bounds = AABB(vertex, Vector3.ZERO)
				first = false
			else:
				bounds = bounds.expand(vertex)
		triangles.append(triangle)
	var minimum := Vector3i((bounds.position / CELL_SIZE).floor()) - Vector3i.ONE
	var maximum := Vector3i((bounds.end / CELL_SIZE).floor()) + Vector3i.ONE
	var dimensions := maximum - minimum + Vector3i.ONE
	if dimensions.x * dimensions.y * dimensions.z > MAX_CANDIDATE_CELLS:
		push_error("Voxel prop sampling bounds exceed the supported local budget")
		return {}

	var shape := {}
	var colors := {}
	var nearest := {}
	var candidates := {}
	for triangle: Dictionary in triangles:
		_raster_triangle(triangle, shape, colors, nearest, candidates)
	var surface_cells := shape.size()
	_fill_interior(shape, colors, minimum, maximum)
	if shape.is_empty():
		return {}
	var result := _build_geometry(shape, colors, candidates)
	result["diagnostics"] = {
		"source_triangles": triangles.size(), "surface_cells": surface_cells,
		"filled_cells": shape.size() - surface_cells, "occupied_cells": shape.size(),
		"candidate_cells": dimensions.x * dimensions.y * dimensions.z,
		"boundary_faces": result.exterior.size(), "elapsed_us": Time.get_ticks_usec() - started,
		"source_bounds": original_bounds, "rotated_bounds": bounds,
		"sampling": "triangle_box_overlap_and_closed_shell_fill",
		"color_sampling": "nearest_source_triangle_per_exposed_voxel_face"
	}
	return result


static func _source_for(scene: PackedScene) -> Dictionary:
	var key := scene.get_instance_id()
	if _source_cache.has(key):
		return _source_cache[key]
	var instance := scene.instantiate()
	var triangles: Array[Dictionary] = []
	var images := {}
	_collect_meshes(instance, Transform3D.IDENTITY, triangles, images)
	instance.free()
	if triangles.is_empty():
		push_error("Voxel prop scene contains no triangle geometry")
		return {}
	var first: Vector3 = triangles[0].a
	var bounds := AABB(first, Vector3.ZERO)
	for triangle: Dictionary in triangles:
		bounds = bounds.expand(triangle.a).expand(triangle.b).expand(triangle.c)
	var source := {"triangles": triangles, "bounds": bounds}
	_source_cache[key] = source
	return source


static func _collect_meshes(node: Node, parent: Transform3D, triangles: Array[Dictionary], images: Dictionary) -> void:
	var transform := parent
	if node is Node3D:
		transform = parent * (node as Node3D).transform
	if node is MeshInstance3D:
		var item := node as MeshInstance3D
		var mesh := item.mesh
		if mesh != null:
			for surface_index in range(mesh.get_surface_count()):
				if mesh is ArrayMesh and (mesh as ArrayMesh).surface_get_primitive_type(surface_index) != Mesh.PRIMITIVE_TRIANGLES:
					continue
				var arrays := mesh.surface_get_arrays(surface_index)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
				var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
				var vertex_colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
				var material := item.get_active_material(surface_index)
				var tint := Color.WHITE
				var image: Image
				var use_vertex_color := false
				var uv_scale := Vector2.ONE
				var uv_offset := Vector2.ZERO
				if material is BaseMaterial3D:
					var base := material as BaseMaterial3D
					tint = base.albedo_color
					use_vertex_color = base.vertex_color_use_as_albedo
					uv_scale = Vector2(base.uv1_scale.x, base.uv1_scale.y)
					uv_offset = Vector2(base.uv1_offset.x, base.uv1_offset.y)
					if base.albedo_texture != null:
						var texture_key := base.albedo_texture.get_instance_id()
						if not images.has(texture_key):
							var texture_image := base.albedo_texture.get_image()
							if texture_image != null and texture_image.is_compressed():
								texture_image.decompress()
							images[texture_key] = texture_image
						image = images[texture_key]
				var count := indices.size() if not indices.is_empty() else vertices.size()
				for first in range(0, count - 2, 3):
					var ids := [indices[first] if not indices.is_empty() else first, indices[first + 1] if not indices.is_empty() else first + 1, indices[first + 2] if not indices.is_empty() else first + 2]
					var triangle := {"a": transform * vertices[ids[0]], "b": transform * vertices[ids[1]], "c": transform * vertices[ids[2]], "tint": tint, "image": image}
					for corner in range(3):
						triangle["uv%d" % corner] = uvs[ids[corner]] * uv_scale + uv_offset if uvs.size() == vertices.size() else Vector2.ZERO
						triangle["color%d" % corner] = vertex_colors[ids[corner]] if use_vertex_color and vertex_colors.size() == vertices.size() else Color.WHITE
					if ((triangle.b - triangle.a) as Vector3).cross(triangle.c - triangle.a).length_squared() > EPSILON * EPSILON:
						triangles.append(triangle)
	for child in node.get_children():
		_collect_meshes(child, transform, triangles, images)


static func _raster_triangle(triangle: Dictionary, shape: Dictionary, colors: Dictionary, nearest: Dictionary, candidates: Dictionary) -> void:
	var a: Vector3 = triangle.a
	var b: Vector3 = triangle.b
	var c: Vector3 = triangle.c
	var minimum := Vector3i((a.min(b).min(c) / CELL_SIZE).floor())
	var maximum := Vector3i((a.max(b).max(c) / CELL_SIZE).floor())
	for x in range(minimum.x, maximum.x + 1):
		for y in range(minimum.y, maximum.y + 1):
			for z in range(minimum.z, maximum.z + 1):
				var cell := Vector3i(x, y, z)
				var centre := (Vector3(cell) + Vector3.ONE * 0.5) * CELL_SIZE
				if not _triangle_box_overlap(a - centre, b - centre, c - centre):
					continue
				shape[cell] = true
				if not candidates.has(cell):
					candidates[cell] = []
				(candidates[cell] as Array).append(triangle)
				var weights := _closest_weights(centre, a, b, c)
				var closest := a * weights.x + b * weights.y + c * weights.z
				var distance := centre.distance_squared_to(closest)
				if distance < float(nearest.get(cell, INF)):
					nearest[cell] = distance
					colors[cell] = _triangle_color(triangle, weights)


static func _triangle_box_overlap(a: Vector3, b: Vector3, c: Vector3) -> bool:
	var half := CELL_SIZE * 0.5 + EPSILON
	if a.min(b).min(c).x > half or a.max(b).max(c).x < -half:
		return false
	if a.min(b).min(c).y > half or a.max(b).max(c).y < -half:
		return false
	if a.min(b).min(c).z > half or a.max(b).max(c).z < -half:
		return false
	var edges := [b - a, c - b, a - c]
	if _separates((b - a).cross(c - a), a, b, c, half):
		return false
	for edge: Vector3 in edges:
		for axis: Vector3 in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
			if _separates(edge.cross(axis), a, b, c, half):
				return false
	return true


static func _separates(axis: Vector3, a: Vector3, b: Vector3, c: Vector3, half: float) -> bool:
	var radius := half * (absf(axis.x) + absf(axis.y) + absf(axis.z))
	var da := axis.dot(a)
	var db := axis.dot(b)
	var dc := axis.dot(c)
	return minf(da, minf(db, dc)) > radius or maxf(da, maxf(db, dc)) < -radius


static func _closest_weights(point: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	# Closest-point barycentrics include the edge/vertex regions, so atlas colours
	# do not extrapolate outside a triangle when a whole voxel overlaps its edge.
	var ab := b - a
	var ac := c - a
	var ap := point - a
	var d1 := ab.dot(ap)
	var d2 := ac.dot(ap)
	if d1 <= 0.0 and d2 <= 0.0:
		return Vector3(1, 0, 0)
	var bp := point - b
	var d3 := ab.dot(bp)
	var d4 := ac.dot(bp)
	if d3 >= 0.0 and d4 <= d3:
		return Vector3(0, 1, 0)
	var vc := d1 * d4 - d3 * d2
	if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0:
		var v := d1 / (d1 - d3)
		return Vector3(1.0 - v, v, 0)
	var cp := point - c
	var d5 := ab.dot(cp)
	var d6 := ac.dot(cp)
	if d6 >= 0.0 and d5 <= d6:
		return Vector3(0, 0, 1)
	var vb := d5 * d2 - d1 * d6
	if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0:
		var w := d2 / (d2 - d6)
		return Vector3(1.0 - w, 0, w)
	var va := d3 * d6 - d5 * d4
	if va <= 0.0 and d4 - d3 >= 0.0 and d5 - d6 >= 0.0:
		var w := (d4 - d3) / ((d4 - d3) + (d5 - d6))
		return Vector3(0, 1.0 - w, w)
	var inverse := 1.0 / (va + vb + vc)
	var v := vb * inverse
	var w := vc * inverse
	return Vector3(1.0 - v - w, v, w)


static func _triangle_color(triangle: Dictionary, weights: Vector3) -> Color:
	var tint: Color = triangle.tint
	var vertex_color: Color = triangle.color0 * weights.x + triangle.color1 * weights.y + triangle.color2 * weights.z
	var image: Image = triangle.image
	if image != null and not image.is_empty():
		var uv: Vector2 = triangle.uv0 * weights.x + triangle.uv1 * weights.y + triangle.uv2 * weights.z
		var x := clampi(floori(fposmod(uv.x, 1.0) * image.get_width()), 0, image.get_width() - 1)
		var y := clampi(floori(fposmod(uv.y, 1.0) * image.get_height()), 0, image.get_height() - 1)
		return tint * vertex_color * image.get_pixel(x, y)
	return tint * vertex_color


static func _inside_bounds(cell: Vector3i, minimum: Vector3i, maximum: Vector3i) -> bool:
	return cell.x >= minimum.x and cell.y >= minimum.y and cell.z >= minimum.z and cell.x <= maximum.x and cell.y <= maximum.y and cell.z <= maximum.z


static func _fill_interior(shape: Dictionary, colors: Dictionary, minimum: Vector3i, maximum: Vector3i) -> void:
	# Conservative triangle rasterisation seals a closed mesh. Flooding outside
	# then filling its unreachable cells handles overlapping/compound parts as a
	# union without parity errors at coincident triangles. Enclosed inner cavities
	# are intentionally treated as part of a collectible's solid occupied volume.
	var outside := {minimum: true}
	var queue: Array[Vector3i] = [minimum]
	var index := 0
	while index < queue.size():
		var cell := queue[index]
		index += 1
		for step: Vector3i in STEPS:
			var neighbor := cell + step
			if _inside_bounds(neighbor, minimum, maximum) and not outside.has(neighbor) and not shape.has(neighbor):
				outside[neighbor] = true
				queue.append(neighbor)
	var interior := {}
	for x in range(minimum.x, maximum.x + 1):
		for y in range(minimum.y, maximum.y + 1):
			for z in range(minimum.z, maximum.z + 1):
				var cell := Vector3i(x, y, z)
				if not outside.has(cell) and not shape.has(cell):
					interior[cell] = true
	# A multi-source grid flood gives inside cells the nearest shell's palette.
	queue.clear()
	for cell: Vector3i in shape:
		queue.append(cell)
	index = 0
	while index < queue.size() and not interior.is_empty():
		var cell := queue[index]
		index += 1
		for step: Vector3i in STEPS:
			var neighbor := cell + step
			if interior.has(neighbor):
				interior.erase(neighbor)
				shape[neighbor] = true
				colors[neighbor] = colors[cell]
				queue.append(neighbor)


static func _face_color(point: Vector3, candidates: Array, fallback: Color) -> Color:
	# Thin props can have front and back materials inside the same voxel. Sample
	# each *visible face* separately, rather than painting both from its centre.
	var distance := INF
	var color := fallback
	for triangle: Dictionary in candidates:
		var a: Vector3 = triangle.a
		var b: Vector3 = triangle.b
		var c: Vector3 = triangle.c
		var weights := _closest_weights(point, a, b, c)
		var closest := a * weights.x + b * weights.y + c * weights.z
		var next_distance := point.distance_squared_to(closest)
		if next_distance < distance:
			distance = next_distance
			color = _triangle_color(triangle, weights)
	return color


static func _build_geometry(shape: Dictionary, colors: Dictionary, candidates: Dictionary = {}, fixed_face_colors: Dictionary = {}) -> Dictionary:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cells: Array[Vector3i] = []
	var centres := PackedVector3Array()
	var exterior: Array[Vector3i] = []
	var face_colors := {}
	for cell: Vector3i in shape:
		cells.append(cell)
		var low := Vector3(cell) * CELL_SIZE
		var high := low + Vector3.ONE * CELL_SIZE
		centres.append(low + Vector3.ONE * CELL_SIZE * 0.5)
		var corners := [Vector3(low.x, low.y, low.z), Vector3(high.x, low.y, low.z), Vector3(high.x, low.y, high.z), Vector3(low.x, low.y, high.z), Vector3(low.x, high.y, low.z), Vector3(high.x, high.y, low.z), Vector3(high.x, high.y, high.z), Vector3(low.x, high.y, high.z)]
		for side in range(STEPS.size()):
			var adjacent: Vector3i = cell + STEPS[side]
			if shape.has(adjacent):
				continue
			exterior.append(adjacent)
			var normal := Vector3(STEPS[side])
			var face: Array = FACE_CORNERS[side]
			var color: Color = colors.get(cell, Palette.RUST)
			var face_key := Vector4i(cell.x, cell.y, cell.z, side)
			if fixed_face_colors.has(face_key):
				color = fixed_face_colors[face_key]
			elif candidates.has(cell):
				var face_centre := low + Vector3.ONE * CELL_SIZE * 0.5 + normal * CELL_SIZE * 0.5
				color = _face_color(face_centre, candidates[cell], color)
			face_colors[face_key] = color
			if side == 0:
				color = color.lightened(0.07)
			elif side == 1:
				color = color.darkened(0.18)
			for vertex: Vector3 in [corners[face[0]], corners[face[1]], corners[face[2]], corners[face[0]], corners[face[2]], corners[face[3]]]:
				surface.set_color(color)
				surface.set_normal(normal)
				surface.add_vertex(vertex)
	var mesh: ArrayMesh = surface.commit()
	return {"mesh": mesh, "cells": cells, "centers": centres, "exterior": exterior, "cell_colors": colors, "face_colors": face_colors}
