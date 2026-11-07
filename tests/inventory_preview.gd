extends SceneTree

const Main = preload("res://main.gd")
const Appraisal = preload("res://appraisal.gd")
var game: Node3D

func _initialize() -> void:
	call_deferred("run")

func shot(filename: String) -> void:
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
	game.set_physics_process(false)
	game.start_trip(false)
	game.terrain.reset_terrain(11235)
	game.spawn_crystals(11235)
	var fixture := [
		[0, Vector2i(1, 1), 180, 60],
		[1, Vector2i(1, 2), 400, 22],
		[2, Vector2i(2, 2), 760, 8],
		[3, Vector2i(1, 2), 400, 48],
		[4, Vector2i(1, 1), 180, 13],
	]
	for record in fixture:
		var item: Node3D = game.crystals[record[0]]
		var data: Dictionary = game.specimen_data(item)
		data.footprint = record[1]
		data.base_value = record[2]
		data.wear = record[3]
		data.label = "大型晶石" if record[2] == 760 else ("中型晶石" if record[2] == 400 else "小型晶石")
		game.inventory.try_add(data)
	for warmup in range(100):
		await process_frame
	game.open_inventory(game.crystals[2])
	game.inventory_panel._on_cell_clicked(Vector2i(1, 0))
	await shot("backpack-unknown")
	game.appraisal.known = true
	game.inventory_panel.refresh(true)
	await shot("backpack-known")
	game.inventory_panel.close()
	# Reveal a voxel specimen with actual soil cuts, then show the progress card.
	var target: Node3D = game.crystals[2]
	game.suit.position = target.position + Vector3(-0.85, 0, 1.35)
	game.suit.position.y = game.terrain.height_at(game.suit.position.x, game.suit.position.z)
	game.view_yaw = atan2(-0.85, 1.35)
	game.view_pitch = 0.47
	game.camera_anchor = game.suit.position + Vector3.UP * 0.95
	game.suit.rotation.y = game.view_yaw
	for cut in range(2):
		var hit: Dictionary = game.terrain.raycast_voxels(Vector3(target.position.x, 3.0, target.position.z), Vector3.DOWN, 7.0)
		if not hit.is_empty():
			game.terrain.mine_at(hit.position, hit.normal, 0)
	game.update_crystal_targets()
	game.update_hud()
	for warmup in range(100):
		await process_frame
	await shot("voxel-crystal-exposure")
	game.set_process(false)
	game.suit.hide()
	game.cursor.hide()
	game.camera.position = target.position + Vector3(0.8, 2.4, 1.1)
	game.camera.look_at(target.position + Vector3.UP * 0.28)
	print("PREVIEW_TARGET position=", target.position, " visible=", target.visible, " model=", target._model.global_position, " height=", game.terrain.height_at(target.position.x, target.position.z))
	await shot("voxel-crystal-closeup")
	print("INVENTORY_PREVIEW_OK unknown known voxel_exposure")
	quit(0)
