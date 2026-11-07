extends SceneTree

const Crystal = preload("res://crystal.gd")
const Items = preload("res://adventure_items.gd")
const VoxelModel = preload("res://voxel_model.gd")

func _initialize() -> void:
	call_deferred("run")

func label(parent: Node3D, text: String, at: Vector3) -> void:
	var node := Label3D.new()
	node.text = text
	node.position = at
	node.font_size = 48
	node.pixel_size = 0.004
	node.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	node.no_depth_test = true
	parent.add_child(node)

func run() -> void:
	root.size = Vector2i(1440, 900)
	var world := Node3D.new()
	root.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("#1b2639")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("#ccd7e8")
	environment.environment.ambient_light_energy = 0.75
	world.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_energy = 1.6
	world.add_child(sun)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 6.6
	camera.position = Vector3(1.2, 5.5, 8.0)
	world.add_child(camera)
	camera.look_at(Vector3(0, 0.15, 0))
	camera.current = true
	for index in range(3):
		var definition := Items.definition(index)
		var source := Items.source_scene(index)
		var data := VoxelModel.sample_scene(source, Basis.IDENTITY, float(definition.size))
		var source_bounds: AABB = data.diagnostics.source_bounds
		var factor: float = float(definition.size) / maxf(source_bounds.size.x, maxf(source_bounds.size.y, source_bounds.size.z))
		var holder := Node3D.new()
		holder.position = Vector3(float(index - 1) * 2.0, source_bounds.size.y * factor * 0.5, -1.15)
		holder.scale = Vector3.ONE * factor
		world.add_child(holder)
		var offset := Node3D.new()
		offset.position = -source_bounds.get_center()
		holder.add_child(offset)
		offset.add_child(source.instantiate())
		var item := Crystal.new()
		world.add_child(item)
		assert(item.setup_adventure(source, definition, Vector3.ZERO, 0.0, 0.0))
		item.position = Vector3(float(index - 1) * 2.0, -item.get_local_bounds().position.y, 1.15)
		item.set_wear(0.0)
		label(world, str(definition.label), Vector3(float(index - 1) * 2.0, 0.0, 2.0))
	label(world, "KayKit 原始低模", Vector3(0, 1.8, -1.15))
	label(world, "同一世界网格 · 12.5 cm 体素", Vector3(0, 0, 2.7))
	for frame in range(20):
		await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://.demo-data/adventure-preview")
	assert(root.get_texture().get_image().save_png("res://.demo-data/adventure-preview/gallery.png") == OK)
	print("ADVENTURE_GALLERY_OK")
	world.queue_free()
	await process_frame
	quit()
