extends SceneTree

const VoxelModel = preload("res://voxel_model.gd")
const CELL_SIZE := 0.125
var failed := false


func _initialize() -> void:
	call_deferred("run")


func require(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error("VOXEL MODEL FAIL: " + message)


func fixture() -> PackedScene:
	var root_node := Node3D.new()
	var nested := Node3D.new()
	nested.position = Vector3(0.16, 0.0, -0.08)
	root_node.add_child(nested)
	nested.owner = root_node
	var body := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.0, 0.7, 0.8)
	var red := StandardMaterial3D.new()
	red.albedo_color = Color("#e64e35")
	box.material = red
	body.mesh = box
	nested.add_child(body)
	body.owner = root_node
	var handle := MeshInstance3D.new()
	var shaft := BoxMesh.new()
	shaft.size = Vector3(0.18, 0.75, 0.18)
	var blue := StandardMaterial3D.new()
	var palette := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	palette.fill(Color("#326ecb"))
	blue.albedo_texture = ImageTexture.create_from_image(palette)
	shaft.material = blue
	handle.mesh = shaft
	handle.position = Vector3(0.0, -0.6, 0.0)
	nested.add_child(handle)
	handle.owner = root_node
	var result := PackedScene.new()
	require(result.pack(root_node) == OK, "pack nested source fixture")
	root_node.free()
	return result


func verify(data: Dictionary) -> void:
	require(not data.is_empty(), "nonempty sampled shape")
	if data.is_empty():
		return
	var occupied := {}
	for cell: Vector3i in data.cells:
		require(not occupied.has(cell), "no duplicate world-grid cells")
		occupied[cell] = true
	var faces := 0
	for cell: Vector3i in data.cells:
		for step: Vector3i in VoxelModel.STEPS:
			if not occupied.has(cell + step):
				faces += 1
	require(data.exterior.size() == faces, "one exposure sample per exterior face")
	var arrays: Array = data.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	for vertex in vertices:
		var grid := vertex / CELL_SIZE
		require(grid.is_equal_approx(grid.round()), "visible corners stay on exact shared lattice")
	require(vertices.size() == faces * 6, "surface contains exterior faces only")
	var red := false
	var blue := false
	for color in colors:
		red = red or color.r > color.b * 1.5
		blue = blue or color.b > color.r * 1.5
	require(red and blue, "source material palette survives voxelisation")
	require(data.diagnostics.filled_cells > 0, "closed body is filled rather than a hollow surface")
	require(data.diagnostics.candidate_cells <= VoxelModel.MAX_CANDIDATE_CELLS, "bounded local generation work")
	var reached := {data.cells[0]: true}
	var queue: Array[Vector3i] = [data.cells[0]]
	var index := 0
	while index < queue.size():
		var cell := queue[index]
		index += 1
		for step: Vector3i in VoxelModel.STEPS:
			var neighbor := cell + step
			if occupied.has(neighbor) and not reached.has(neighbor):
				reached[neighbor] = true
				queue.append(neighbor)
	require(reached.size() == data.cells.size(), "thin connected handle does not develop a sampling gap")


func run() -> void:
	verify_two_sided_palette()
	var scene := fixture()
	for angle in [Vector3.ZERO, Vector3(0.39, 0.63, -0.27), Vector3(-0.71, 1.12, 0.47)]:
		var result := VoxelModel.sample_scene(scene, Basis.from_euler(angle), 1.4)
		verify(result)
		if not result.is_empty():
			print("VOXEL_MODEL_SAMPLE ", result.diagnostics)
	if not failed:
		print("VOXEL_MODEL_OK rotated_lattice=true material_and_texture_palette=true thin_front_back_palette=true interior=true connected_handle=true face_area=true")
	quit(1 if failed else 0)


func verify_two_sided_palette() -> void:
	# Two differently painted surfaces inside one occupied cell. A cell-centre
	# material cannot represent both; its +Z/-Z visible faces must stay distinct.
	var candidates := []
	for z in [0.025, 0.100]:
		var color := Color.RED if z < 0.05 else Color.BLUE
		candidates.append({"a": Vector3(0, 0, z), "b": Vector3(0.125, 0, z), "c": Vector3(0, 0.125, z), "tint": color, "image": null, "uv0": Vector2.ZERO, "uv1": Vector2.ZERO, "uv2": Vector2.ZERO, "color0": Color.WHITE, "color1": Color.WHITE, "color2": Color.WHITE})
	var result := VoxelModel._build_geometry({Vector3i.ZERO: true}, {Vector3i.ZERO: Color.BROWN}, {Vector3i.ZERO: candidates})
	var front: Color = result.face_colors[Vector4i(0, 0, 0, 4)]
	var back: Color = result.face_colors[Vector4i(0, 0, 0, 5)]
	require(front.b > front.r * 1.5 and back.r > back.b * 1.5, "front and back within one voxel retain their separate material colours")
	require(result.cells.size() == 1 and result.exterior.size() == 6, "per-face paint never changes occupancy or exposure")
