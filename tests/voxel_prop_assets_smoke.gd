extends SceneTree

const VoxelModel = preload("res://voxel_model.gd")
const ASSETS := ["chest", "shield", "warhammer", "spellbook"]
var failed := false


func _initialize() -> void:
	call_deferred("run")


func require(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error("VOXEL ASSET FAIL: " + message)


func run() -> void:
	var rotation := Basis.from_euler(Vector3(0.43, 0.72, -0.31))
	for name: String in ASSETS:
		var scene: PackedScene = load("res://assets/adventure/%s.glb" % name)
		require(scene != null, "source scene imports: " + name)
		if scene == null:
			continue
		var result := VoxelModel.sample_scene(scene, rotation, 1.25)
		require(not result.is_empty(), "sample actual source: " + name)
		if result.is_empty():
			continue
		var colors := {}
		for color: Color in result.cell_colors.values():
			colors[color.to_html()] = true
		require(colors.size() >= 3, "original palette survives: " + name)
		require(result.cells.size() >= 20, "recognizable occupied size: " + name)
		require(result.diagnostics.source_triangles >= 12, "triangle source is the actual mesh: " + name)
		var vertices: PackedVector3Array = result.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for vertex in vertices:
			var grid := vertex / VoxelModel.CELL_SIZE
			require(grid.is_equal_approx(grid.round()), "rotated source corners remain on terrain lattice")
		print("VOXEL_ASSET_BENCH name=%s colors=%d " % [name, colors.size()], result.diagnostics)
	if not failed:
		print("VOXEL_PROP_ASSETS_OK original_sources=true nested_transforms=true rotated_lattice=true source_palette=true")
	quit(1 if failed else 0)
