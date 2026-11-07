extends SceneTree

const Main = preload("res://main.gd")
const Appraisal = preload("res://appraisal.gd")
const Crystal = preload("res://crystal.gd")

var test_failed := false

func _initialize() -> void:
	call_deferred("run")

func require(condition: bool, description: String) -> void:
	if not condition:
		test_failed = true
		push_error("BACKPACK INTEGRATION FAIL: " + description)
		quit(1)
		assert(condition, description)

func approach(game: Node3D, item: Node3D) -> void:
	var at := item.position + Vector3(0.65, 0.0, 0.55)
	at.y = game.terrain.height_at(at.x, at.z)
	game.suit.position = at
	game.camera.position = at + Vector3(0.0, 1.0, 1.0)
	game.camera.look_at(item.position)
	game.update_crystal_targets()

func excavate(game: Node3D, item: Crystal, tier: int, wear: int) -> void:
	var scale_by_tier := [0.30, 0.42, 0.54]
	var surface: float = game.terrain.natural_height_at(item.position.x, item.position.z)
	item.setup_site(surface, 0.18, scale_by_tier[tier])
	item.set_wear(float(wear) / 100.0)
	require(not item.is_loose(), "test specimen starts embedded in real terrain")
	# No loose flags or fake inventory records: use the player's ray and brush API.
	var bounds := item.get_local_bounds()
	var center := item.position + bounds.get_center()
	var reach := Vector2(bounds.size.x, bounds.size.z) * 0.5 + Vector2.ONE * Main.Terrain.CELL_SIZE
	for layer in range(10):
		for offset in [Vector2.ZERO, Vector2(-reach.x, 0), Vector2(reach.x, 0), Vector2(0, -reach.y), Vector2(0, reach.y), Vector2(-reach.x, -reach.y), Vector2(reach.x, -reach.y), Vector2(-reach.x, reach.y), Vector2(reach.x, reach.y)]:
			var origin := Vector3(center.x + offset.x, Main.Terrain.WORLD_MAX.y + 1.0, center.z + offset.y)
			var hit: Dictionary = game.terrain.raycast_voxels(origin, Vector3.DOWN, 10.0)
			require(not hit.is_empty(), "specimen has diggable surroundings above bedrock")
			game.terrain.mine_at(hit.position, hit.normal, 0)
			item.refresh_exposure(game.terrain)
			if item.is_loose():
				break
		if item.is_loose():
			break
	require(item.is_loose() and item.exposure_ratio >= Crystal.RELEASE_EXPOSURE, "actual excavation releases specimen")
	approach(game, item)
	require(game.crystal == item, "released specimen is the nearby selected target")

func value_of(record: Dictionary) -> int:
	return roundi(float(record.base_value) * (100 - int(record.wear)) / 100.0)

func inventory_value(game: Node3D) -> int:
	var total := 0
	for record: Dictionary in game.inventory.items:
		total += value_of(record)
	return total

func run() -> void:
	var game := Main.new()
	game.progression = Main.Progression.new("")
	game.progression.bank = 0
	game.auto_open_base = false
	# Empty catalogue path prevents both reads and writes to the player's save.
	game.appraisal = Appraisal.new("")
	game.wants_mouse_capture = false
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.start_trip(false)
	game.terrain.reset_terrain(88273)
	game.spawn_crystals(7712)
	require(game.inventory.columns == 4 and game.inventory.rows == 4, "demo uses a 4 by 4 backpack")
	var tiers := [2, 2, 1, 1, 0, 0, 0, 0]
	var wears := [60, 30, 25, 50, 10, 20, 30, 40]
	var collected: Array[Crystal] = []
	for index in range(tiers.size()):
		var item: Crystal = game.crystals[index]
		excavate(game, item, tiers[index], wears[index])
		require(game.collect_crystal(item), "real excavated specimen fits its assigned footprint")
		collected.append(item)
		var record: Dictionary = game.inventory.get_item(item.get_instance_id())
		require(record.wear == wears[index] and record.base_value == Crystal.BASE_VALUES[tiers[index]], "size and wear are snapshotted separately for every item")
	require(game.inventory.items.size() == 8 and game.inventory.used_cells() == 16, "mixed sizes fill all 16 cells")
	var full_snapshot: Array = game.inventory.items.duplicate(true)
	var medium_id: int = collected[2].get_instance_id()
	require(not game.inventory.move_item(medium_id, Vector2i(0, 2), true), "rotation cannot overlap the adjacent specimen")
	require(game.inventory.items == full_snapshot, "rejected rotation leaves original layout intact")
	var pending: Crystal = game.crystals[8]
	excavate(game, pending, 2, 0)
	game.oxygen = 7.5
	game.pick_up_cluster()
	require(game.inventory_open and paused and game.inventory_panel.is_open, "full backpack F pickup opens the paused inventory")
	require(game.pending_pickup == pending and int(game.inventory_panel.pending_item.id) == pending.get_instance_id(), "full backpack retains exact pending world object")
	require(not pending.collected and pending.visible and game.inventory.items == full_snapshot, "failed pickup does not delete the crystal or change inventory")
	game.collect_pending_item()
	require(game.inventory_open and game.pending_pickup == pending and not pending.collected, "retry while full remains safe and keeps the pending target")
	var oxygen_before: float = game.oxygen
	var position_before: Vector3 = game.suit.position
	game.set_process(true)
	game.set_physics_process(true)
	var walk := InputEventKey.new()
	walk.physical_keycode = KEY_W
	walk.pressed = true
	Input.parse_input_event(walk)
	await create_timer(0.10, true).timeout
	var release_walk := InputEventKey.new()
	release_walk.physical_keycode = KEY_W
	release_walk.pressed = false
	Input.parse_input_event(release_walk)
	game.set_process(false)
	game.set_physics_process(false)
	require(is_equal_approx(game.oxygen, oxygen_before) and game.suit.position.is_equal_approx(position_before), "oxygen and character remain stationary during inventory input")
	var dropped: Crystal = collected[0]
	var dropped_id: int = dropped.get_instance_id()
	var sale_before_drop := inventory_value(game)
	var dropped_value := value_of(game.inventory.get_item(dropped_id))
	# A target below the bedrock cap has no legal placement candidates.
	# Exercise the real drop failure path instead of forcing a false loose flag.
	var safe_position: Vector3 = game.suit.position
	var before_failed_drop: Array = game.inventory.items.duplicate(true)
	var owner_count: int = game.terrain.debug_stats().crystal_cells
	game.suit.position = Vector3(0.0, Main.Terrain.WORLD_MIN.y - 10.0, 0.0)
	game.drop_inventory_item(dropped_id)
	require(game.inventory.items == before_failed_drop and dropped.collected and game.carried_crystals.has(dropped), "failed drop retains inventory and the carried world instance")
	require(game.terrain.debug_stats().crystal_cells == owner_count and game.pending_pickup == pending, "failed drop creates no ownership and preserves pending selection")
	game.suit.position = safe_position
	# Try legal orientations around the nearby excavated pit. A wall or another
	# crystal can legitimately block one drop direction on a shared solid grid.
	for heading in range(8):
		game.view_yaw = heading * TAU / 8.0
		game.drop_inventory_item(dropped_id)
		if not dropped.collected:
			break
	require(game.inventory.used_cells() == 12 and game.inventory.get_item(dropped_id).is_empty(), "dropping frees the entire footprint")
	require(inventory_value(game) == sale_before_drop - dropped_value, "dropped specimen is removed from the eventual sale")
	require(not dropped.collected and dropped.visible and dropped.is_loose(), "drop restores the actual collectible world instance")
	require(game.suit.position.distance_to(dropped.position) <= 1.85 and dropped.wear_percent == 60 and dropped.size_tier == 2, "drop remains within pickup reach and preserves wear and size")
	require(game.collect_crystal(dropped), "dropped specimen can be picked back up")
	game.drop_inventory_item(dropped_id)
	require(game.pending_pickup == pending, "dropping and repicking cannot replace the pending specimen")
	# Rotate both 1 by 2 pieces into the vacated upper-left 2 by 2 region.
	# This makes a fresh 2 by 2 opening at the bottom, exercising rearrangement.
	require(game.inventory.move_item(medium_id, Vector2i(0, 0), true), "first medium rotates into the released space")
	require(game.inventory.move_item(collected[3].get_instance_id(), Vector2i(0, 1), true), "second medium rotates beside the first")
	require(game.inventory.get_item(medium_id).rotated, "rotated orientation is stored")
	# Deliberately select the dropped nearby object; the pending button must still
	# collect the original large discovery, not whatever targeting selects now.
	game.crystal = dropped
	game.collect_pending_item()
	require(pending.collected and not dropped.collected, "pending collection acts on original target despite a different current selection")
	require(game.inventory.get_item(pending.get_instance_id()).pos == Vector2i(0, 2), "new large specimen occupies the opening created by rotations")
	require(not game.inventory_open and not paused and game.pending_pickup == null, "successful pending pickup closes inventory and resumes the game")
	require(game.inventory.used_cells() == 16 and game.inventory.items.size() == 8, "swap restores full inventory without duplication")
	var expected_sale := inventory_value(game)
	var expected_count: int = game.inventory.items.size()
	# Packed values must not depend on subsequently changed world-model state.
	pending.set_wear(0.65)
	game.appraisal.base_value = 1
	game.appraisal.wear_percent = 65
	require(inventory_value(game) == expected_sale, "packed size and wear remain immutable snapshots")
	require(game.gain_oxygen(7) > 0.0 and game.oxygen_grains == 7, "oxygen gains are tracked outside the backpack")
	var bank_before: int = game.bank
	game.settle(false)
	require(game.bank == bank_before and game.progression.museum_state.warehouse.size() == expected_count, "safe return stores each collected crystal and excludes the dropped specimen and oxygen from cargo")
	var warehouse_value := 0
	for stored: Dictionary in game.progression.museum_state.warehouse:
		warehouse_value += value_of(stored)
		require(not stored.has("world_id") and not stored.has("pos") and not stored.has("rotated"), "persistent cargo strips transient world IDs and backpack placement")
	require(warehouse_value == expected_sale and game.delivered_clusters == expected_count and not game.appraisal.known, "warehouse preserves immutable mixed-size prices without identifying unprocessed cargo")
	var stored_cargo: Array = game.progression.museum_state.warehouse.duplicate(true)
	for stored: Dictionary in stored_cargo:
		game.on_museum_sell(int(stored.uid))
	require(game.bank == bank_before + expected_sale and game.appraisal.known and game.progression.museum_state.warehouse.is_empty(), "explicit sales sum independent crystal prices and identify the type exactly once")
	require(game.inventory.items.is_empty() and game.carried_crystals.is_empty(), "safe settlement clears inventory and carried instances")
	game.start_trip(false)
	game.terrain.reset_terrain(88273)
	game.spawn_crystals(7723)
	game.appraisal.reset_catalogue()
	for tier in range(3):
		var item: Crystal = game.crystals[tier]
		excavate(game, item, tier, 10 + tier * 15)
		require(game.collect_crystal(item), "rescue fixture collects each size through gameplay")
	game.oxygen = 1.0
	require(game.gain_oxygen(10) > 0.0, "oxygen grains are absorbed before rescue")
	bank_before = game.bank
	game.settle(true)
	require(game.bank == bank_before and game.delivered_clusters == expected_count, "rescue pays nothing and sells none of the mixed-size crystals")
	require(game.inventory.items.is_empty() and game.carried_crystals.is_empty() and game.packed_specimens.is_empty(), "rescue clears all inventory representations")
	require(not game.appraisal.known, "rescue never identifies an unsold specimen")
	game.sfx.set_muted(true)
	await create_timer(0.10, true).timeout
	game.queue_free()
	await process_frame
	await create_timer(0.25, true).timeout
	print("BACKPACK_INTEGRATION_OK real_excavation=true full=16 pause=true drop_repick=true rotated_swap=true pending_identity=true mixed_size_sale=%d rescue=0" % expected_sale)
	quit(1 if test_failed else 0)
