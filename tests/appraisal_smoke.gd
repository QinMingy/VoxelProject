extends SceneTree

const Appraisal = preload("res://appraisal.gd")
const Main = preload("res://main.gd")
const Crystal = preload("res://crystal.gd")
const TEST_SAVE := "res://.demo-data/test-appraisal.cfg"

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
	# Excavate real terrain through its public ray/brush API; never set loose flags.
	# The shared grid makes the crystal itself stop a central ray. Work around
	# its sides instead of repeatedly drilling the same protected crystal cell.
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
	var before: int = game.packed_specimens.size()
	game.pick_up_cluster()
	require(game.packed_specimens.size() == before + 1, "F pickup adds one whole specimen")
	require(item.collected, "collected flag prevents duplicate pickup")

func run() -> void:
	DirAccess.remove_absolute(TEST_SAVE)
	var game := Main.new()
	game.progression = Main.Progression.new("")
	game.progression.bank = 0
	game.auto_open_base = false
	game.appraisal = Appraisal.new(TEST_SAVE)
	game.wants_mouse_capture = false
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.appraisal.random.seed = 1234
	var distinct := {}
	for run_index in range(100):
		game.appraisal.roll_specimen()
		distinct[game.appraisal.wear_percent] = true
		require(game.appraisal.wear_percent >= 0 and game.appraisal.wear_percent <= 65, "wear within prototype range")
	require(distinct.size() > 20, "specimens vary across runs")
	game.start_trip(false)
	game.terrain.reset_terrain(77123)
	game.spawn_crystals(1234)
	var first: Crystal = game.crystals[0]
	var second: Crystal = game.crystals[1]
	# Keep these fixtures medium-sized so 400 x condition is an explicit oracle.
	for item: Crystal in [first, second]:
		item.setup_site(game.terrain.natural_height_at(item.position.x, item.position.z), -0.12, 0.42)
	first.set_wear(0.25)
	second.set_wear(0.50)
	approach(game, first)
	game.update_hud()
	require(game.crystal == first and game.specimen_info.text.contains("售价 ？"), "unknown exposed specimen hides price")
	require(not game.specimen_info.text.contains("400"), "unknown card does not leak base value")
	game.oxygen = 42.0
	var refill: float = game.gain_oxygen(10)
	require(refill > 0.0 and game.oxygen_grains == 10 and game.bank == 0, "oxygen grains restore oxygen without adding money")
	release_cluster(game, first)
	release_cluster(game, second)
	require(game.packed_specimens == [25, 50], "cargo snapshots each specimen's wear independently")
	require(game.carried_crystals.size() == 2, "multiple collected specimens retained")
	first.set_wear(0.0)
	game.appraisal.wear_percent = 65
	require(game.packed_specimens == [25, 50], "later model or appraisal changes do not change packed prices")
	game.settle(false)
	game.update_hud()
	require(game.bank == 0 and game.progression.museum_state.warehouse.size() == 2 and not game.appraisal.known, "safe return retains the two unidentified specimens without selling them")
	var warehouse: Array = game.progression.museum_state.warehouse.duplicate(true)
	require(warehouse[0].wear == 25 and warehouse[1].wear == 50, "persistent specimens retain their individual conditions")
	for stored: Dictionary in warehouse:
		game.on_museum_sell(int(stored.uid))
	require(game.bank == 500 and game.progression.museum_state.warehouse.is_empty(), "only explicitly selling the independently priced 300 and 200 crystals credits cash")
	require(game.delivered_clusters == 2, "both specimens counted as delivered")
	require(game.appraisal.known and game.appraisal.last_sale == 200, "safe sale identifies type and remembers latest specimen")
	game.sync_base_state()
	require(roundi(float(warehouse[0].base_value) * (100 - int(warehouse[0].wear)) / 100.0) == 300, "first warehouse item's fixed value is 400 x 75 percent")
	require(roundi(float(warehouse[1].base_value) * (100 - int(warehouse[1].wear)) / 100.0) == 200, "second warehouse item's fixed value is 400 x 50 percent")
	require(game.packed_specimens.is_empty() and game.carried_crystals.is_empty(), "settlement clears cargo")
	var reloaded := Appraisal.new(TEST_SAVE)
	reloaded.load_catalogue()
	require(reloaded.known and reloaded.last_sale == 200, "catalogue persists across instances")
	game.start_trip(true)
	game.terrain.reset_terrain(77123)
	game.spawn_crystals(5678)
	var known_sample: Crystal = game.crystals[0]
	known_sample.setup_site(game.terrain.natural_height_at(known_sample.position.x, known_sample.position.z), -0.12, 0.42)
	known_sample.set_wear(0.10)
	# Inspect by actual excavation before pickup so the UI must quote this specimen.
	for cut in range(18):
		var hit: Dictionary = game.terrain.raycast_voxels(Vector3(known_sample.position.x, 4.0, known_sample.position.z), Vector3.DOWN, 10.0)
		require(not hit.is_empty(), "known specimen remains above bedrock")
		game.terrain.mine_at(hit.position, hit.normal, 0)
		known_sample.refresh_exposure(game.terrain)
		if known_sample.inspected:
			break
	approach(game, known_sample)
	game.update_hud()
	require(game.specimen_info.text.contains("预计售价 360"), "known type uses current specimen's 90 percent condition")
	var fixed_wear: int = known_sample.wear_percent
	known_sample.refresh_exposure(game.terrain)
	game.update_crystal_targets()
	require(known_sample.wear_percent == fixed_wear, "digging and target refresh never reroll wear")
	game.reset_appraisal_catalogue()
	release_cluster(game, known_sample)
	release_cluster(game, game.crystals[1])
	game.oxygen = 1.0
	require(game.gain_oxygen(10) > 0.0, "oxygen grains can refill the trial tank before rescue")
	game.settle(true)
	game.update_hud()
	require(game.bank == 500, "emergency credits nothing and loses both packed crystals")
	require(game.delivered_clusters == 2 and game.packed_specimens.is_empty(), "rescue delivers no crystals and clears cargo")
	require(not game.appraisal.known, "emergency does not identify unknown type")
	require(not game.specimen_info.text.contains("400"), "failed extraction still hides base value")
	var after_reset := Appraisal.new(TEST_SAVE)
	after_reset.load_catalogue()
	require(not after_reset.known, "GM catalogue reset persists")
	DirAccess.remove_absolute(TEST_SAVE)
	game.sfx.set_muted(true)
	await create_timer(0.10, true).timeout
	game.queue_free()
	await process_frame
	await create_timer(0.25, true).timeout
	print("APPRAISAL_OK two_real_pickups=300+200 oxygen_grains=10 bank=500 rescue=0 catalogue=reload/reset independent_wear=true")
	quit(1 if test_failed else 0)
