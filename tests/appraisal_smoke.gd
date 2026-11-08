extends SceneTree

const Appraisal = preload("res://appraisal.gd")
const Main = preload("res://main.gd")
const Crystal = preload("res://crystal.gd")

var test_failed := false

func _initialize() -> void:
	call_deferred("run")

func require(condition: bool, description: String) -> void:
	if not condition:
		test_failed = true
		push_error("APPRAISAL FAIL: " + description)
		quit(1)
		assert(condition, description)

func approach(game: Node3D, item: Node3D) -> void:
	var at := item.position + Vector3(0.75, 0.0, 0.65)
	at.y = game.terrain.height_at(at.x, at.z)
	game.suit.position = at
	game.camera.position = at + Vector3(0.0, 1.0, 1.0)
	game.camera.look_at(item.position)
	game.update_crystal_targets()

func release_cluster(game: Node3D, item: Node3D) -> void:
	var bounds: AABB = item.get_local_bounds()
	var center := item.position + bounds.get_center()
	var reach := Vector2(bounds.size.x, bounds.size.z) * 0.5 + Vector2.ONE * Main.Terrain.CELL_SIZE
	for layer in range(10):
		for offset in [Vector2.ZERO, Vector2(-reach.x, 0), Vector2(reach.x, 0), Vector2(0, -reach.y), Vector2(0, reach.y), Vector2(-reach.x, -reach.y), Vector2(reach.x, -reach.y), Vector2(-reach.x, reach.y), Vector2(reach.x, reach.y)]:
			var origin := Vector3(center.x + offset.x, Main.Terrain.WORLD_MAX.y + 1.0, center.z + offset.y)
			var hit: Dictionary = game.terrain.raycast_voxels(origin, Vector3.DOWN, 10.0)
			require(not hit.is_empty(), "soil exists around crystal while excavating")
			game.terrain.mine_at(hit.position, hit.normal, 0)
			item.refresh_exposure(game.terrain)
			if item.is_loose():
				break
		if item.is_loose():
			break
	require(item.is_loose(), "actual voxel excavation releases whole specimen")
	approach(game, item)
	require(game.crystal == item, "excavated nearby specimen is selected")
	var before: int = game.inventory.items.size()
	game.pick_up_cluster()
	require(game.inventory.items.size() == before + 1, "F pickup adds one whole specimen")
	require(item.collected, "collected flag prevents duplicate pickup")

func run() -> void:
	var game := Main.new()
	game.progression = Main.Progression.new("")
	game.progression.bank = 0
	game.auto_open_base = false
	game.appraisal = Appraisal.new("")
	game.wants_mouse_capture = false
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	require(game.appraisal.sale_value() == Appraisal.BASE_VALUE, "price helper reports the catalogue value")
	require(game.appraisal.price_label(true).contains(str(Appraisal.BASE_VALUE)), "inspected price text carries the value")

	game.start_trip(false)
	game.terrain.reset_terrain(77123)
	game.spawn_crystals(1234)
	var first: Crystal = game.crystals[0]
	var second: Crystal = game.crystals[1]
	for item: Crystal in [first, second]:
		item.setup_site(game.terrain.natural_height_at(item.position.x, item.position.z), -0.12, 0.42)
	approach(game, first)
	game.update_hud()
	game.oxygen = 42.0
	var refill: float = game.gain_oxygen(10)
	require(refill > 0.0 and game.oxygen_grains == 10 and game.bank == 0,
		"oxygen grains restore oxygen without adding money")
	release_cluster(game, first)
	release_cluster(game, second)
	require(game.carried_crystals.size() == 2, "multiple collected specimens retained")
	for record: Dictionary in game.inventory.items:
		require(not record.has("wear"), "collected records no longer carry condition")
		require(int(record.base_value) == 400, "collected records keep their catalogue value")
	game.settle(false)
	game.update_hud()
	require(game.bank == 0 and game.inventory.items.is_empty(), "safe return archives the two specimens without selling them")
	require(game.progression.museum_state.items.crystal_medium.copies == 2,
		"two identical specimens become one owned type with two copies")
	require(game.delivered_clusters == 2, "both specimens counted as delivered")

	var preserved: Dictionary = game.progression.museum_state.duplicate(true)
	var preserved_bank: int = game.bank
	game.start_trip(true)
	game.terrain.reset_terrain(77123)
	game.spawn_crystals(5678)
	var rescued: Crystal = game.crystals[0]
	rescued.setup_site(game.terrain.natural_height_at(rescued.position.x, rescued.position.z), -0.12, 0.42)
	release_cluster(game, rescued)
	require(game.inventory.items.size() == 1, "rescue trip carries one specimen")
	game.oxygen = 1.0
	game.settle(true)
	require(game.bank == preserved_bank and game.progression.museum_state == preserved,
		"emergency credits nothing and never archives the lost specimen")
	require(game.inventory.items.is_empty() and game.delivered_clusters == 2,
		"rescue delivers no crystals and clears cargo")

	game.sfx.set_muted(true)
	await create_timer(0.10, true).timeout
	game.queue_free()
	await process_frame
	await create_timer(0.25, true).timeout
	print("APPRAISAL_OK always_known=true two_pickups_archived=true no_wear=true oxygen_grains=10 rescue=0 value=%d" % Appraisal.BASE_VALUE)
	quit(1 if test_failed else 0)
