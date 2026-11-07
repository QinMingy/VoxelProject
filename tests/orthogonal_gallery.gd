extends SceneTree

const Crystal = preload("res://crystal.gd")
const Items = preload("res://adventure_items.gd")

func _initialize() -> void:
	call_deferred("run")

func label(parent: Node3D, text: String, at: Vector3, font: int = 44) -> void:
	var node := Label3D.new()
	node.text = text
	node.position = at
	node.font_size = font
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
	var poses := [Vector3.ZERO, Vector3(-PI * 0.5, 0, 0), Vector3(0, 0, PI * 0.5)]
	for row in range(2):
		for index in range(3):
			var definition := Items.definition(index)
			var item := Crystal.new()
			world.add_child(item)
			assert(item.setup_adventure(Items.source_scene(index), definition, Vector3.ZERO if row == 0 else poses[index], 0, 0))
			item.position = Vector3(float(index - 1) * 2.0, -item.get_local_bounds().position.y, -1.15 if row == 0 else 1.15)
			item.set_wear(0.0)
			if row == 1:
				label(world, str(definition.label), Vector3(float(index - 1) * 2.0, 0, 2.0))
	label(world, "原来的正面形状", Vector3(0, 1.8, -1.15))
	label(world, "试挖姿态：直立 / 平放 90° / 侧躺 90°", Vector3(0, 0, 2.7), 40)
	for frame in range(20):
		await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://.demo-data/adventure-preview")
	assert(root.get_texture().get_image().save_png("res://.demo-data/adventure-preview/quarter-turns.png") == OK)
	print("ORTHOGONAL_GALLERY_OK")
	world.queue_free()
	await process_frame
	quit()
