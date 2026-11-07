extends SceneTree

const Boundary = preload("res://activity_boundary.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var boundary := Boundary.new()
	root.add_child(boundary)
	assert(is_equal_approx(boundary.edge_distance(Vector3.ZERO), 26.0))
	assert(is_equal_approx(boundary.edge_distance(Vector3(27, 20, 0)), -1.0), "edge distance ignores vertical position")
	var inside := Vector3(12, -2.7, 8)
	assert(boundary.clamp_position(inside) == inside, "inside point remains unchanged")
	var outside := boundary.clamp_position(Vector3(60, -2.5, 80))
	assert(is_equal_approx(Vector2(outside.x, outside.z).length(), 25.65), "outside point projects to safe radius")
	assert(is_equal_approx(outside.y, -2.5), "clamping preserves excavation height")
	var other_side := boundary.clamp_position(Vector3(-80, 1.8, -60))
	assert(other_side.x < 0 and other_side.z < 0 and is_equal_approx(other_side.y, 1.8))
	boundary.update_player(Vector3(19.9, 0, 0))
	assert(boundary.warning_strength == 0.0 and not boundary._wall.visible, "wall absent farther than 6 metres")
	boundary.update_player(Vector3(20.001, 0, 0))
	assert(boundary.warning_strength < 0.001, "reveal starts smoothly at threshold")
	boundary.update_player(Vector3(23, -1, 0))
	assert(boundary._wall.visible and is_equal_approx(boundary.warning_strength, 0.5), "halfway approach has half intensity")
	boundary.update_player(Vector3(25.65, -3, 0))
	assert(boundary.warning_strength > 0.98)
	assert(boundary._material.get_shader_parameter("player_position") == Vector3(25.65, -3, 0))
	assert(boundary._wall.mesh.get_surface_count() == 1, "boundary is one render surface")
	var arrays: Array = boundary._wall.mesh.surface_get_arrays(0)
	assert(arrays[Mesh.ARRAY_VERTEX].size() == Boundary.SEGMENTS * 6, "128 wall segments use 256 triangles")
	assert(boundary.get_child_count() == 1 and boundary.get_child(0) is MeshInstance3D, "no collision nodes")
	assert(not Boundary.WALL_SHADER.contains("depth_test_disabled"), "opaque terrain still occludes boundary")
	boundary.queue_free()
	await process_frame
	print("BOUNDARY_OK radius=26 safe_radius=25.65 warning=6 smooth_local_fade single_mesh=256tri depth_test=enabled")
	quit(0)
