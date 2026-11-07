extends SceneTree

const Main = preload("res://main.gd")
const Appraisal = preload("res://appraisal.gd")
const Crystal = preload("res://crystal.gd")
var game: Node3D
var target: Node3D

func _initialize() -> void:
	call_deferred("run")

func shot(filename: String) -> void:
	for frame in range(135):
		game.terrain.update_focus(target.position)
		await process_frame
	game.update_crystal_targets()
	game.update_hud()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.demo-data/" + filename + ".png")

func run() -> void:
	game = Main.new()
	game.progression = Main.Progression.new("")
	game.progression.bank = 0
	game.auto_open_base = false
	game.appraisal = Appraisal.new("")
	game.wants_mouse_capture = false
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.set_process_unhandled_input(false)
	game.inventory_panel.set_process_input(false)
	game.start_trip(false)
	for item in game.crystals:
		game.remove_child(item)
		item.queue_free()
	game.crystals.clear()
	game.terrain.reset_terrain(11235)
	target = Crystal.new()
	game.add_child(target)
	target.position = Vector3(-2.5, 0, 5.25)
	target.setup_site(game.terrain.natural_height_at(-2.5, 5.25), 0.125, 0.54)
	assert(target.embed_in(game.terrain))
	target.set_wear(0.18)
	game.crystals.append(target)
	game.suit.hide()
	game.cursor.hide()
	game.ring.hide()
	game.reticle.hide()
	game.suit.position = target.position + Vector3(1.1, 0, 0.4)
	game.suit.position.y = game.terrain.height_at(game.suit.position.x, game.suit.position.z)
	var middle: Vector3 = target.position + Vector3(0.0625, 0.375, 0.0625)
	game.camera.position = middle + Vector3(1.45, 1.9, 1.55)
	game.camera.look_at(middle)
	await shot("shared-grid-buried")
	# A series of real one-cell-thick shovel cuts opens one side, while the
	# crystal's occupancy prevents the brush from deleting the object itself.
	for layer in range(9, 1, -1):
		var hit := Vector3(target.position.x + layer * Main.Terrain.CELL_SIZE, middle.y, middle.z)
		game.terrain.mine_at(hit, Vector3.RIGHT, Main.Terrain.Brush.DISK)
	game.update_crystal_targets()
	await shot("shared-grid-contact")
	var partial_exposure: float = target.exposure_ratio
	for layer in range(9, -9, -1):
		var hit := Vector3(target.position.x + layer * Main.Terrain.CELL_SIZE, middle.y + 0.125, middle.z)
		game.terrain.mine_at(hit, Vector3.RIGHT, Main.Terrain.Brush.DISK)
	game.update_crystal_targets()
	await shot("shared-grid-released")
	assert(target.is_loose(), "real surrounding soil removal releases the crystal")
	var cells: Array[Vector3i] = target.get_world_cells()
	assert(game.collect_crystal(target))
	# Hide only the carried visual for the cavity comparison; occupancy is removed by pickup.
	target.hide()
	for cell in cells:
		assert(not game.terrain.is_solid_cell(cell), "pickup leaves its occupied cells as air")
	await shot("shared-grid-empty-cavity")
	print("SHARED_GRID_PREVIEW_OK partial_exposure=%.3f cells=%d pickup_cavity=true" % [partial_exposure, cells.size()])
	quit(0)
