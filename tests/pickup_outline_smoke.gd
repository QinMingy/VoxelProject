extends SceneTree

const Main = preload("res://main.gd")
const Crystal = preload("res://crystal.gd")
const Appraisal = preload("res://appraisal.gd")
const OUT_DIR := "res://.demo-data/pickup-outline"
var failed := false
var preview := false
var game: Node3D

func _initialize() -> void:
	call_deferred("run")

func require(condition: bool, description: String) -> void:
	if not condition:
		failed = true
		push_error("PICKUP OUTLINE FAIL: " + description)
		quit(1)
		assert(condition, description)

func has_rigid_body(node: Node) -> bool:
	if node is RigidBody3D:
		return true
	for child in node.get_children():
		if has_rigid_body(child):
			return true
	return false

func outline_quad(item: Node3D) -> MeshInstance3D:
	return game.pickup_outline.quad_for(item)

func create_specimen(site: Vector3, tier: int, wear: int) -> Crystal:
	var item := Crystal.new()
	game.add_child(item)
	item.position = site
	item.setup_site(game.terrain.natural_height_at(site.x, site.z), 0.25, [0.30, 0.42, 0.54][tier])
	require(item.embed_in(game.terrain), "test specimen registers its solid voxel shape")
	item.set_wear(float(wear) / 100.0)
	game.crystals.append(item)
	return item

func approach(item: Node3D) -> void:
	var at := item.position + Vector3(0.65, 0.0, 0.55)
	at.y = game.terrain.height_at(at.x, at.z)
	game.suit.position = at
	game.camera.position = at + Vector3(0.0, 1.0, 1.0)
	game.camera.look_at(item.position)
	game.update_crystal_targets()

func excavate(item: Node3D) -> void:
	var bounds: AABB = item.get_local_bounds()
	var center := item.position + bounds.get_center()
	var reach := Vector2(bounds.size.x, bounds.size.z) * 0.5 + Vector2.ONE * Main.Terrain.CELL_SIZE
	for layer in range(10):
		for offset in [Vector2.ZERO, Vector2(-reach.x, 0), Vector2(reach.x, 0), Vector2(0, -reach.y), Vector2(0, reach.y), Vector2(-reach.x, -reach.y), Vector2(reach.x, -reach.y), Vector2(-reach.x, reach.y), Vector2(reach.x, reach.y)]:
			var origin := Vector3(center.x + offset.x, Main.Terrain.WORLD_MAX.y + 1.0, center.z + offset.y)
			var hit: Dictionary = game.terrain.raycast_voxels(origin, Vector3.DOWN, 10.0)
			require(not hit.is_empty(), "actual excavation ray finds surrounding terrain")
			game.terrain.mine_at(hit.position, hit.normal, 0)
			item.refresh_exposure(game.terrain)
			if item.is_loose():
				return
	require(false, "real surrounding soil removal makes specimen collectible")

func assert_unregistered(cells: Array[Vector3i]) -> void:
	for cell in cells:
		require(game.terrain.crystal_owner_at(cell) == 0 and not game.terrain.is_solid_cell(cell), "stored specimen leaves its former occupied cells empty")

func shot(name: String, focus: Vector3) -> void:
	if not preview:
		return
	for frame in range(90):
		game.terrain.update_focus(focus)
		await process_frame
	game.update_crystal_targets()
	game.update_hud()
	game.camera.position = focus + Vector3(1.5, 1.8, 1.8)
	game.camera.look_at(focus)
	game.cursor.hide()
	game.ring.hide()
	game.reticle.hide()
	for frame in range(4):
		await process_frame
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(OUT_DIR + "/" + name + ".png")
	require(error == OK, "native preview frame saves successfully")

func run() -> void:
	preview = OS.get_cmdline_user_args().has("--preview") and DisplayServer.get_name() != "headless"
	if preview:
		DirAccess.make_dir_recursive_absolute(OUT_DIR)
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
	game.terrain.set_fragment_cleanup(false, 9)
	var target := create_specimen(Vector3(-2.5, 0, 5.25), 2, 37)
	var old_cells := target.get_world_cells()
	var focus := target.position + target.get_local_bounds().get_center()
	approach(target)
	target.refresh_exposure(game.terrain)
	require(not target.is_loose() and target.exposure_ratio == 0.0, "fixture starts fully buried")
	require(not target.wants_outline() and not game.pickup_outline.outline_visible(target), "buried specimen has no pickup outline")
	require(not has_rigid_body(target), "specimen remains a static Node3D without rigid-body physics")
	await shot("before", focus)
	excavate(target)
	approach(target)
	# process_frame fires before node _process, so wait two frames for the outline pass.
	await process_frame
	await process_frame
	require(target.is_loose() and target.wants_outline(), "actual excavation marks the specimen collectible")
	var ready_quad: MeshInstance3D = outline_quad(target)
	require(ready_quad != null and ready_quad.visible, "collectible silhouette is drawn by the screen-space outline pass")
	var outline_material := ready_quad.material_override as ShaderMaterial
	require(outline_material != null and not String(outline_material.shader.code).contains("depth_test_disabled"), "pickup outline stays depth tested so soil still hides it")
	require(game.pickup_outline.mask_cull_mask() == (1 << (Main.PickupOutline.LAYER - 1)), "outline mask renders only the collectible layer")
	await shot("ready", focus)
	# Keep another stored item to catch both the per-frame back attachment and
	# the old behaviour which showed the previous item when dropping one.
	var other := create_specimen(Vector3(-5.0, 0, 5.25), 0, 20)
	excavate(other)
	approach(other)
	game.pick_up_cluster()
	require(other.collected and not other.is_visible_in_tree(), "first stored specimen is hidden")
	approach(target)
	var model_before: Transform3D = target._model.transform
	game.pick_up_cluster()
	var target_id := target.get_instance_id()
	var record: Dictionary = game.inventory.get_item(target_id)
	require(target.collected and not target.visible and not target.wants_outline(), "F collection hides both object and outline")
	require(game.inventory.items.size() == 2 and record.base_value == 760, "collection stores the catalogue price without removing the other item")
	require(target._model.get_parent() == target and target._model.transform == model_before, "collection does not attach or transform the model onto the character")
	assert_unregistered(old_cells)
	for frame in range(30):
		game._process(1.0 / 60.0)
		require(not target.is_visible_in_tree() and not other.is_visible_in_tree(), "main frame updates never make stored specimens visible again")
	target.show_carried(game.suit)
	require(not target.is_visible_in_tree() and target._model.transform == model_before, "legacy show_carried alias also stores invisibly")
	assert_unregistered(old_cells)
	await shot("stored", focus)
	target.set_wear(0.65)
	for heading in range(8):
		game.view_yaw = heading * TAU / 8.0
		game.drop_inventory_item(target_id)
		if not target.collected:
			break
	require(not target.collected and target.is_visible_in_tree() and target.wants_outline(), "safe static drop restores object and pickup outline")
	require(game.inventory.get_item(target_id).is_empty() and game.inventory.items.size() == 1 and not game.inventory.get_item(other.get_instance_id()).is_empty(), "drop removes only its own inventory record")
	require(not other.is_visible_in_tree(), "dropping one item never shows another stored item on the character")
	require(target.wear_percent == 0 and target.base_value == 760 and target.footprint == Vector2i(2, 2), "drop preserves size and base price")
	var dropped_cells := target.get_world_cells()
	for cell in dropped_cells:
		require(game.terrain.crystal_owner_at(cell) == target_id and not game.terrain.is_soil_cell(cell), "static dropped specimen reclaims its voxel cells without soil overlap")
	var drop_transform: Transform3D = target.global_transform
	for frame in range(8):
		game._process(1.0 / 60.0)
		await physics_frame
	require(target.global_transform == drop_transform and not has_rigid_body(target), "dropped crystal stays stationary without physics")
	await shot("dropped", target.position + target.get_local_bounds().get_center())
	approach(target)
	game.pick_up_cluster()
	require(target.collected and not target.is_visible_in_tree() and not target.wants_outline(), "dropped item can be collected and hidden again")
	assert_unregistered(dropped_cells)
	var repacked: Dictionary = game.inventory.get_item(target_id)
	require(game.inventory.items.size() == 2 and repacked.base_value == record.base_value, "repick restores the same independent item value without duplication")
	game.appraisal.base_value = repacked.base_value
	require(game.appraisal.sale_value() == 760, "the large crystal quotes its catalogue value")
	game.queue_free()
	await process_frame
	if not failed:
		print("PICKUP_OUTLINE_OK buried_off/ready_on stored_hidden=true no_back_attachment=true static_drop=true reclaims_grid=true repick=true value=760 preview=%s" % preview)
	quit(1 if failed else 0)
