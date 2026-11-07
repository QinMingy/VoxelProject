extends Node3D

const Terrain = preload("res://terrain.gd")
const VoxelModel = preload("res://voxel_model.gd")
const CELL_SIZE := Terrain.CELL_SIZE
const RELEASE_EXPOSURE := 0.80
const LIFT_STEPS := 3
const DROP_HORIZONTAL_STEPS := 3
const DROP_UP_STEPS := 8
const PICKUP_OUTLINE_WIDTH := 0.014
const GRIP_COUNT := 3 # Compatibility for older prototype callers, not real grip points.
const STEPS := [Vector3i.UP, Vector3i.DOWN, Vector3i.RIGHT, Vector3i.LEFT, Vector3i.BACK, Vector3i.FORWARD]
const FACE_CORNERS := [[4, 5, 6, 7], [0, 3, 2, 1], [2, 6, 5, 1], [0, 4, 7, 3], [3, 7, 6, 2], [1, 5, 4, 0]]
const FOOTPRINTS := [Vector2i(1, 1), Vector2i(1, 2), Vector2i(2, 2)]
const BASE_VALUES := [180, 400, 760]
const SIZE_NAMES := ["小型晶石", "中型晶石", "大型晶石"]
const FACETS := [Color("#a85ce2"), Color("#d9a1fa"), Color("#8c43c5"), Color("#b875ed"), Color("#a860de"), Color("#bc87eb")]

const WEAR_SHADER := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform float wear : hint_range(0.0, 1.0) = 0.0;
uniform float mineral_glow : hint_range(0.0, 1.0) = 1.0;
varying vec3 mineral_position;

float hash_at(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

float noise_at(vec3 p) {
	vec3 cell = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash_at(cell), hash_at(cell + vec3(1, 0, 0)), f.x),
			mix(hash_at(cell + vec3(0, 1, 0)), hash_at(cell + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash_at(cell + vec3(0, 0, 1)), hash_at(cell + vec3(1, 0, 1)), f.x),
			mix(hash_at(cell + vec3(0, 1, 1)), hash_at(cell + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	mineral_position = VERTEX;
}

void fragment() {
	vec3 p = mineral_position * 11.0 + vec3(2.3, 0.6, 4.1);
	float mottling = noise_at(p) * 0.76 + noise_at(p * 3.8) * 0.24;
	float threshold = mix(1.03, 0.22, wear);
	float mask = smoothstep(threshold - 0.07, threshold + 0.07, mottling);
	mask *= clamp(wear * 2.0, 0.0, 1.0);
	ALBEDO = mix(COLOR.rgb, vec3(0.14, 0.13, 0.18), mask * 0.82);
	ROUGHNESS = mix(0.38, 0.96, mask);
	METALLIC = mix(0.18, 0.015, mask);
	SPECULAR = mix(0.55, 0.16, mask);
	EMISSION = vec3(0.27, 0.10, 0.44) * mix(0.24, 0.015, mask) * mineral_glow;
}
"""

static var _mesh_cache: Dictionary = {}
static var _shared_shader: Shader
static var _outline_material: StandardMaterial3D
static var _shared_mesh: ArrayMesh # Medium mesh for legacy debug readers.

var wear_percent := 0
var inspected := false
var discovered := false
var collected := false
var size_tier := 1
var footprint := Vector2i(1, 2)
var size_label := "中型晶石"
var item_type := "crystal"
var item_name := "中型晶石"
var icon_color := Color("#b875ed")
var source_rotation := Vector3.ZERO
var voxel_diagnostics: Dictionary = {}
var base_value := 400
var exposure_ratio := 0.0
var extraction_ready := false
var release_hint := "继续清理晶石周围的土"
var grips_remaining := GRIP_COUNT

var _model: Node3D
var _mesh_instance: MeshInstance3D
var _outline_instance: MeshInstance3D
var _geometry: Dictionary
var _crystal_material := ShaderMaterial.new()
var _loose := false
var _carried := false
var _wear := 0.0
var _terrain: Node
var _claimed := false
var _claimed_origin := Vector3i.ZERO

func _ready() -> void:
	_model = Node3D.new()
	_model.name = "VoxelCrystal"
	add_child(_model)
	if _shared_shader == null:
		_shared_shader = Shader.new()
		_shared_shader.code = WEAR_SHADER
	_crystal_material.shader = _shared_shader
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.material_override = _crystal_material
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh_instance.visibility_range_end = 36.0
	_model.add_child(_mesh_instance)
	if _outline_material == null:
		_outline_material = StandardMaterial3D.new()
		_outline_material.albedo_color = Color("#68f4cc")
		_outline_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_outline_material.cull_mode = BaseMaterial3D.CULL_FRONT
	_outline_instance = MeshInstance3D.new()
	_outline_instance.name = "PickupOutline"
	_outline_instance.material_override = _outline_material
	_outline_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_outline_instance.visibility_range_end = 36.0
	_outline_instance.hide()
	_model.add_child(_outline_instance)
	_apply_tier(1)
	set_wear(_wear)
	reset_site()

static func _shape_voxels(tier: int) -> Dictionary:
	var cells := {}
	var base_radius := tier + 1
	for y in range(2):
		for x in range(-base_radius, base_radius + 1):
			for z in range(-base_radius, base_radius + 1):
				if absi(x) + absi(z) <= base_radius + 1 - y:
					cells[Vector3i(x, y, z)] = true
	var pillars: Array[Vector3i]
	match tier:
		0:
			pillars = [Vector3i(0, 4, 0), Vector3i(-1, 3, 0), Vector3i(0, 2, 1), Vector3i(1, 3, -1)]
		1:
			pillars = [Vector3i(0, 5, 0), Vector3i(-2, 4, 0), Vector3i(1, 4, -1), Vector3i(1, 3, 1), Vector3i(0, 3, -2), Vector3i(0, 3, 2)]
		_:
			pillars = [Vector3i(0, 6, 0), Vector3i(-2, 5, 0), Vector3i(2, 4, 1), Vector3i(0, 5, -2), Vector3i(-1, 4, 2), Vector3i(2, 3, -1)]
	for pillar: Vector3i in pillars:
		for y in range(pillar.y):
			var radius := 1 if y < pillar.y - 2 else 0
			for dx in range(-radius, radius + 1):
				for dz in range(-radius, radius + 1):
					if absi(dx) + absi(dz) <= radius:
						cells[Vector3i(pillar.x + dx, y, pillar.z + dz)] = true
	return cells

static func _geometry_for(tier: int) -> Dictionary:
	if _mesh_cache.has(tier):
		return _mesh_cache[tier]
	var shape := _shape_voxels(tier)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cells: Array[Vector3i] = []
	var centers := PackedVector3Array()
	var exterior: Array[Vector3i] = []
	var corner_normals := {}
	for cell: Vector3i in shape:
		cells.append(cell)
		var low := Vector3(cell) * CELL_SIZE
		var high := low + Vector3.ONE * CELL_SIZE
		var center := low + Vector3.ONE * (CELL_SIZE * 0.5)
		centers.append(center)
		for side in range(STEPS.size()):
			var adjacent: Vector3i = cell + STEPS[side]
			if shape.has(adjacent):
				continue
			var normal := Vector3(STEPS[side])
			exterior.append(adjacent)
			var corners := [Vector3(low.x, low.y, low.z), Vector3(high.x, low.y, low.z), Vector3(high.x, low.y, high.z), Vector3(low.x, low.y, high.z), Vector3(low.x, high.y, low.z), Vector3(high.x, high.y, low.z), Vector3(high.x, high.y, high.z), Vector3(low.x, high.y, high.z)]
			var face: Array = FACE_CORNERS[side]
			for corner_index: int in face:
				var corner: Vector3 = corners[corner_index]
				var previous: Vector3 = corner_normals.get(corner, Vector3.ZERO)
				corner_normals[corner] = previous + normal
			var color: Color = FACETS[(absi(cell.x * 3 + cell.z * 7 + cell.y * 5) + side) % FACETS.size()]
			if side == 0:
				color = color.lightened(0.14)
			elif side == 1:
				color = color.darkened(0.20)
			for vertex: Vector3 in [corners[face[0]], corners[face[1]], corners[face[2]], corners[face[0]], corners[face[2]], corners[face[3]]]:
				surface.set_color(color)
				surface.set_normal(normal)
				surface.add_vertex(vertex)
	var mesh: ArrayMesh = surface.commit()
	var outline := _make_outline(mesh, corner_normals)
	var data := {"mesh": mesh, "outline": outline, "cells": cells, "centers": centers, "exterior": exterior}
	_mesh_cache[tier] = data
	if tier == 1:
		_shared_mesh = mesh
	return data

static func _make_outline(mesh: ArrayMesh, corner_normals: Dictionary) -> ArrayMesh:
	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	# Move shared corners together so hard voxel normals do not split the shell.
	for index in range(vertices.size()):
		var direction: Vector3 = corner_normals[vertices[index]]
		vertices[index] += direction.normalized() * PICKUP_OUTLINE_WIDTH
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var outline := ArrayMesh.new()
	outline.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return outline

func _apply_tier(tier: int) -> void:
	item_type = "crystal"
	source_rotation = Vector3.ZERO
	voxel_diagnostics = {}
	size_tier = clampi(tier, 0, 2)
	footprint = FOOTPRINTS[size_tier]
	base_value = BASE_VALUES[size_tier]
	size_label = SIZE_NAMES[size_tier]
	item_name = size_label
	icon_color = Color("#b875ed")
	_crystal_material.set_shader_parameter("mineral_glow", 1.0)
	_geometry = _geometry_for(size_tier)
	_mesh_instance.mesh = _geometry.mesh
	_outline_instance.mesh = _geometry.outline

func setup_adventure(scene: PackedScene, definition: Dictionary, orientation: Vector3, surface_y: float, burial_depth: float) -> bool:
	_release_occupancy()
	var quarter_turns := Vector3i(roundi(orientation.x / (PI * 0.5)), roundi(orientation.y / (PI * 0.5)), roundi(orientation.z / (PI * 0.5)))
	var sampled := VoxelModel.sample_orthogonal_scene(scene, quarter_turns, float(definition.get("size", 1.0)))
	if sampled.is_empty() or sampled.get("cells", []).is_empty():
		return false
	_geometry = sampled
	_mesh_instance.mesh = _geometry.mesh
	_outline_instance.mesh = _geometry.outline
	item_type = str(definition.id)
	item_name = str(definition.label)
	size_label = item_name
	footprint = definition.get("footprint", Vector2i(2, 2))
	base_value = int(definition.get("value", 400))
	icon_color = definition.get("color", Color("#cda36b"))
	_crystal_material.set_shader_parameter("mineral_glow", 0.0)
	source_rotation = Vector3(posmod(quarter_turns.x, 4), posmod(quarter_turns.y, 4), posmod(quarter_turns.z, 4)) * (PI * 0.5)
	voxel_diagnostics = sampled.get("diagnostics", {})
	# Quarter-turns permute the canonical cells exactly; the owner always stays on the world grid.
	var requested := global_position
	requested.y = surface_y - burial_depth - get_local_bounds().end.y
	global_transform = Transform3D(Basis.IDENTITY, _origin_position(_origin_cell(requested)))
	_reset_site_state()
	return true

func set_wear(wear: float) -> void:
	_wear = clampf(wear, 0.0, 1.0)
	wear_percent = roundi(_wear * 100.0)
	if _crystal_material.shader != null:
		_crystal_material.set_shader_parameter("wear", _wear)

func get_local_bounds() -> AABB:
	return (_geometry.mesh as ArrayMesh).get_aabb()

func get_voxel_centers() -> PackedVector3Array:
	return _geometry.centers

func get_world_cells() -> Array[Vector3i]:
	return _cells_at(_origin_cell(global_position))

func _origin_cell(point: Vector3) -> Vector3i:
	return Vector3i(((point - Terrain.WORLD_MIN) / CELL_SIZE).round())

func _origin_position(cell: Vector3i) -> Vector3:
	return Terrain.WORLD_MIN + Vector3(cell) * CELL_SIZE

func _cells_at(origin: Vector3i) -> Array[Vector3i]:
	var world_cells: Array[Vector3i] = []
	for cell: Vector3i in _geometry.cells:
		world_cells.append(origin + cell)
	return world_cells

func embed_in(terrain: Node) -> bool:
	if not is_instance_valid(terrain):
		return false
	var origin := _origin_cell(global_position)
	var world_cells := _cells_at(origin)
	if _claimed and _terrain == terrain and _claimed_origin == origin:
		if terrain.crystal_owner_at(world_cells[0]) == get_instance_id():
			return true
	_release_occupancy()
	_terrain = terrain
	if not terrain.claim_crystal(get_instance_id(), world_cells):
		return false
	_claimed = true
	_claimed_origin = origin
	global_transform = Transform3D(Basis.IDENTITY, _origin_position(origin))
	return true

func _release_occupancy() -> void:
	if _claimed and is_instance_valid(_terrain):
		_terrain.release_crystal(get_instance_id())
	_claimed = false

func _exit_tree() -> void:
	_release_occupancy()

func reset_site() -> void:
	_release_occupancy()
	_reset_site_state()
	if is_instance_valid(_terrain):
		visible = embed_in(_terrain)

func _reset_site_state() -> void:
	visible = true
	_loose = false
	_carried = false
	collected = false
	discovered = false
	inspected = false
	exposure_ratio = 0.0
	extraction_ready = false
	release_hint = "继续清理物品周围的土"
	grips_remaining = GRIP_COUNT
	_model.transform = Transform3D.IDENTITY
	_outline_instance.hide()

func setup_site(surface_y: float, burial_depth: float, size_scale: float = 0.42) -> void:
	var tier := 0 if size_scale < 0.36 else (1 if size_scale < 0.48 else 2)
	_apply_tier(tier)
	var requested := global_position
	requested.y = surface_y - burial_depth - get_local_bounds().end.y
	global_transform = Transform3D(Basis.IDENTITY, _origin_position(_origin_cell(requested)))
	reset_site()

func is_exposed(terrain: Node) -> bool:
	if _carried or _loose:
		return true
	var origin := _origin_cell(global_position)
	for neighbor: Vector3i in _geometry.exterior:
		if not terrain.is_solid_cell(origin + neighbor):
			discovered = true
			return true
	return false

func refresh_exposure(terrain: Node) -> void:
	if _carried or _loose:
		return
	var origin := _origin_cell(global_position)
	var exterior: Array[Vector3i] = _geometry.exterior
	var open := 0
	for neighbor in exterior:
		if not terrain.is_solid_cell(origin + neighbor):
			open += 1
	exposure_ratio = float(open) / float(exterior.size())
	discovered = discovered or open > 0
	inspected = inspected or exposure_ratio >= 0.25
	grips_remaining = maxi(1, ceili((RELEASE_EXPOSURE - exposure_ratio) / RELEASE_EXPOSURE * GRIP_COUNT))
	if exposure_ratio < RELEASE_EXPOSURE:
		release_hint = "继续清理物品周围的土"
		return
	var owner_id := get_instance_id()
	for cell: Vector3i in _geometry.cells:
		for step in range(1, LIFT_STEPS + 1):
			var raised := origin + cell + Vector3i.UP * step
			if terrain.is_solid_cell(raised) and terrain.crystal_owner_at(raised) != owner_id:
				release_hint = "提起路线被挡住了，请清开上方"
				return
	_loose = true
	extraction_ready = true
	grips_remaining = 0
	release_hint = "已松动 · 靠近按 F 取出"
	_outline_instance.show()

func refresh_grips(terrain: Node) -> int:
	refresh_exposure(terrain)
	return grips_remaining

func set_markers_visible(_enabled: bool) -> void:
	pass

func is_loose() -> bool:
	return extraction_ready

func store_in_inventory() -> void:
	if not _carried:
		_release_occupancy()
		_carried = true
		collected = true
	_outline_instance.hide()
	hide()

func show_carried(_suit: Node3D) -> void:
	store_in_inventory()

func drop_at(surface_point: Vector3) -> bool:
	if not _carried or not is_instance_valid(_terrain):
		return false
	# Rotated source shapes can extend below their local origin; put their lowest row above ground.
	var requested := _origin_cell(surface_point) - Vector3i(0, floori(get_local_bounds().position.y / CELL_SIZE), 0)
	for radius in range(DROP_HORIZONTAL_STEPS + 1):
		for dx in range(-radius, radius + 1):
			for dz in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dz)) != radius:
					continue
				var column := requested + Vector3i(dx, 0, dz)
				var displacement := _origin_position(column) - surface_point
				if Vector2(displacement.x, displacement.z).length() > DROP_HORIZONTAL_STEPS * CELL_SIZE:
					continue
				for dy in range(DROP_UP_STEPS + 1):
					if _try_drop(column + Vector3i.UP * dy):
						return true
					if dy > 0 and dy <= DROP_HORIZONTAL_STEPS and _try_drop(column + Vector3i.DOWN * dy):
						return true
	return false

func _try_drop(origin: Vector3i) -> bool:
	var world_cells := _cells_at(origin)
	var supported := false
	for cell in world_cells:
		if cell.x < 0 or cell.x >= Terrain.GRID_SIZE or cell.z < 0 or cell.z >= Terrain.GRID_SIZE or cell.y < 0 or cell.y >= Terrain.LAYER_COUNT:
			return false
		if _terrain.is_solid_cell(cell):
			return false
		if not supported and _terrain.is_soil_cell(cell + Vector3i.DOWN):
			supported = true
	if not supported or not _terrain.claim_crystal(get_instance_id(), world_cells):
		return false
	_claimed = true
	_claimed_origin = origin
	global_transform = Transform3D(Basis.IDENTITY, _origin_position(origin))
	_model.transform = Transform3D.IDENTITY
	_carried = false
	collected = false
	discovered = true
	inspected = true
	_loose = true
	extraction_ready = true
	exposure_ratio = 1.0
	grips_remaining = 0
	release_hint = "已取出 · 靠近按 F 捡回"
	_outline_instance.show()
	show()
	return true
