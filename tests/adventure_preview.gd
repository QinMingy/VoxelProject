extends SceneTree

const Main = preload("res://main.gd")
const OUT := "res://.demo-data/adventure-preview"
var game: Node3D

func _initialize() -> void:
	call_deferred("run")

func shot(name: String) -> void:
	game.terrain.update_focus(game.crystals[0].position)
	for frame in range(135):
		await process_frame
	game.update_crystal_targets()
	game.update_hud()
	await process_frame
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(OUT + "/" + name + ".png") == OK)

func uncover(item: Node3D) -> void:
	var middle: Vector3 = item.position + item.get_local_bounds().get_center()
	var reach: Vector3 = item.get_local_bounds().size * 0.5 + Vector3.ONE * 0.25
	for y in range(12, -13, -1):
		for x in range(-3, 4):
			for z in range(-3, 4):
				game.terrain.mine_at(middle + Vector3(float(x) * reach.x / 3.0, float(y) * 0.125, float(z) * reach.z / 3.0), Vector3.UP, 0)
		item.refresh_exposure(game.terrain)
		if item.is_loose():
			return
	assert(item.is_loose())

func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	root.size = Vector2i(1440, 900)
	game = Main.new()
	game.progression = Main.Progression.new("")
	game.appraisal = Main.Appraisal.new("")
	game.auto_open_base = false
	game.wants_mouse_capture = false
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.set_process_unhandled_input(false)
	game.adventure_trial = true
	game.start_trip(true)
	var chest: Node3D = game.crystals[0]
	var middle: Vector3 = chest.position + chest.get_local_bounds().get_center()
	game.suit.position = Vector3(chest.position.x + 1.0, 0, chest.position.z + 1.0)
	game.suit.position.y = game.terrain.height_at(game.suit.position.x, game.suit.position.z)
	game.suit.hide()
	game.camera.position = middle + Vector3(1.65, 2.2, 2.1)
	game.camera.look_at(middle)
	game.cursor.hide()
	game.ring.hide()
	game.reticle.hide()
	game.message = ""
	await shot("buried-chest")
	uncover(chest)
	await shot("excavated-chest")
	for item: Node3D in game.crystals:
		uncover(item)
		game.suit.position = item.position + Vector3(0.65, 0.3, 0.65)
		assert(game.collect_crystal(item))
	game.open_inventory()
	await shot("inventory")
	game.inventory_panel.close()
	game.settle(false)
	game._on_gm_action("adventure_trial")
	game.gm_panel.open()
	await shot("gm")
	game.gm_panel.close()
	print("ADVENTURE_PREVIEW_OK real_source=true real_excavation=true inventory=true gm=true")
	game.sfx.set_muted(true)
	await create_timer(0.10, true).timeout
	game.queue_free()
	await process_frame
	await create_timer(0.25).timeout
	quit()
