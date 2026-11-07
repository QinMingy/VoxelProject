extends SceneTree

const Main = preload("res://main.gd")
const RADII := [14.0, 18.0, 22.0, 26.0]
const COUNTS := [21, 35, 52, 72]
var game: Node3D
var failed := false

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, description: String) -> void:
	if not condition:
		failed = true
		push_error("EXCAVATION RANGE FAIL: " + description)
		quit(1)
		assert(condition, description)

func click(panel: Node, node_name: String) -> void:
	var button := panel.find_child(node_name, true, false) as Button
	check(button != null and not button.disabled and button.is_visible_in_tree(), "real visible enabled button: " + node_name)
	button.pressed.emit()

func check_cell_inside(cell: Vector3i, radius: float, description: String) -> void:
	var centre: Vector3 = game.terrain.cell_center(cell)
	var half: float = Main.Terrain.CELL_SIZE * 0.5
	for offset in [Vector2(-half, -half), Vector2(-half, half), Vector2(half, -half), Vector2(half, half)]:
		check((Vector2(centre.x, centre.z) + offset).length() <= radius + 0.0001, description)

func check_spawned_area(radius: float, expected: int) -> void:
	check(game.crystals.size() == expected, "actual spawned count matches the area-scaled zone: %d" % expected)
	var min_spacing := INF
	for index in range(game.crystals.size()):
		var item: Node3D = game.crystals[index]
		check(not item.get_world_cells().is_empty(), "every mine point has actual registered voxel geometry")
		for cell: Vector3i in item.get_world_cells():
			check_cell_inside(cell, radius, "all corners of every buried object fit the playable circle")
			check(game.terrain.crystal_owner_at(cell) == item.get_instance_id(), "actual voxel ownership remains registered")
		for other_index in range(index):
			var other: Node3D = game.crystals[other_index]
			min_spacing = minf(min_spacing, Vector2(item.position.x - other.position.x, item.position.z - other.position.z).length())
	check(min_spacing >= 2.79, "smaller map preserves useful separation between mine points")

func check_boundary(radius: float) -> void:
	check(is_equal_approx(game.activity_boundary.radius, radius), "red warning boundary follows the current trip radius")
	check(is_equal_approx(game.terrain.activity_radius, radius), "terrain extraction clipping shares the trip radius")
	var limited: Vector3 = game.activity_boundary.clamp_position(Vector3(90, 2, 90))
	check(is_equal_approx(Vector2(limited.x, limited.z).length(), radius - Main.ActivityBoundary.PLAYER_MARGIN) and limited.y == 2, "player clamp preserves altitude at the new edge")
	check(is_equal_approx(game.activity_boundary.edge_distance(Vector3(radius - 0.5, 0, 0)), 0.5), "edge distance uses the resized map")
	game.activity_boundary.update_player(Vector3(radius - 0.5, 0, 0))
	check(game.activity_boundary.warning_strength > 0.8 and game.activity_boundary._wall.visible, "red warning appears close to the current edge")
	game.activity_boundary.update_player(Vector3.ZERO)
	check(is_zero_approx(game.activity_boundary.warning_strength) and not game.activity_boundary._wall.visible, "warning disappears away from the current edge")
	var vertices: PackedVector3Array = game.activity_boundary._wall.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	check(not vertices.is_empty(), "warning wall has real geometry")
	for vertex in vertices:
		check(is_equal_approx(Vector2(vertex.x, vertex.z).length(), radius), "warning wall geometry itself moves to the unlocked radius")

func dig(item: Node3D) -> void:
	var bounds: AABB = item.get_local_bounds()
	var centre := item.position + bounds.get_center()
	var reach := Vector2(bounds.size.x, bounds.size.z) * 0.5 + Vector2.ONE * Main.Terrain.CELL_SIZE
	for layer in range(12):
		for offset in [Vector2.ZERO, Vector2(-reach.x, 0), Vector2(reach.x, 0), Vector2(0, -reach.y), Vector2(0, reach.y), Vector2(-reach.x, -reach.y), Vector2(reach.x, -reach.y), Vector2(-reach.x, reach.y), Vector2(reach.x, reach.y)]:
			var hit: Dictionary = game.terrain.raycast_voxels(Vector3(centre.x + offset.x, Main.Terrain.WORLD_MAX.y + 1, centre.z + offset.y), Vector3.DOWN, 10)
			check(not hit.is_empty(), "actual mining ray reaches the buried object")
			game.terrain.mine_at(hit.position, hit.normal, 0)
			item.refresh_exposure(game.terrain)
			if item.is_loose():
				return
	check(false, "real excavation frees a starting specimen")

func check_edge_drop(radius: float) -> void:
	var first: Node3D = game.crystals[0]
	dig(first)
	game.suit.position = first.position + Vector3(0.4, 0.4, 0.4)
	check(game.collect_crystal(first) and game.inventory.items.size() == 1, "actual excavated specimen enters the backpack")
	var item_id: int = game.inventory.items[0].id
	game.suit.position = Vector3(radius - Main.ActivityBoundary.PLAYER_MARGIN, 0, 0)
	game.suit.position.y = game.terrain.height_at(game.suit.position.x, game.suit.position.z)
	game.drop_inventory_item(item_id)
	check(game.inventory.items.is_empty() and not first.collected and first.is_loose(), "dropping beside the map edge succeeds without losing the item")
	for cell: Vector3i in first.get_world_cells():
		check_cell_inside(cell, radius, "the entire dropped object remains reachable inside the map")
		check(game.terrain.crystal_owner_at(cell) == first.get_instance_id(), "edge drop restores complete voxel ownership")

func check_edge_mining(radius: float) -> void:
	var surface: float = game.terrain.height_at(radius, 0)
	var anchor: Vector3i = game.terrain.world_to_cell(Vector3(radius, surface, 0))
	var outside := {}
	var outside_soil := 0
	for x in range(anchor.x - 7, anchor.x + 9):
		for z in range(anchor.z - 7, anchor.z + 8):
			for y in range(anchor.y - 9, anchor.y + 6):
				var cell := Vector3i(x, y, z)
				if not game.terrain.is_activity_cell(cell):
					var solid: bool = game.terrain.is_soil_cell(cell)
					outside[cell] = solid
					outside_soil += int(solid)
	check(outside_soil > 0, "edge fixture contains real out-of-range soil")
	var removed_inside := 0
	for brush in range(3):
		var x := radius - 0.12
		var hit: Dictionary = game.terrain.raycast_voxels(Vector3(x, Main.Terrain.WORLD_MAX.y + 1, 0), Vector3.DOWN, 10)
		check(not hit.is_empty(), "edge brush has an actual terrain hit")
		game.terrain.mine_at(hit.position, hit.normal, brush)
		removed_inside += game.terrain.last_removed
		for cell: Vector3i in outside:
			check(game.terrain.is_soil_cell(cell) == outside[cell], "all brush types preserve every cell crossing or outside the active boundary")
	check(removed_inside > 0, "the same boundary-overlapping brushes still remove allowed soil")
	var wholly_outside := Vector3(radius + 1.5, game.terrain.height_at(radius + 1.5, 0), 0)
	game.terrain.mine_at(wholly_outside, Vector3.UP, Main.Terrain.Brush.BOWL)
	check(game.terrain.last_removed == 0, "a wholly out-of-range brush cannot excavate scenery")

func run() -> void:
	root.size = Vector2i(1100, 720)
	game = Main.new()
	game.progression = Main.Progression.new("")
	game.progression.bank = 5000
	game.progression.levels.boots = 1
	game.progression.levels.detector = 2
	game.appraisal = Main.Appraisal.new("")
	game.wants_mouse_capture = false
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	await process_frame
	check(game.base_open and paused and game.outpost_page == "title", "production starts in the paused outpost flow")
	check(game.progression.levels.excavation_range == 0 and game.progression.stats().activity_radius == 14.0, "a new profile starts at the smaller area")
	game.start_trip(false)
	check(game.on_moon and not game.base_open and not paused, "normal free deployment uses the real gameplay flow")
	for level in range(RADII.size()):
		var radius: float = RADII[level]
		check_boundary(radius)
		check_spawned_area(radius, COUNTS[level])
		if level == 0:
			check_edge_drop(radius)
			check_edge_mining(radius)
		game.settle(false)
		check(game.base_open and paused and game.outpost_page == "lobby", "returning preserves the outpost loop")
		if level == RADII.size() - 1:
			break
		var old_count: int = game.crystals.size()
		var old_levels: Dictionary = game.progression.levels.duplicate()
		var old_balance: int = game.bank
		game.show_outpost("skills")
		click(game.skill_tree_panel, "Skill_excavation_range_%d" % (level + 1))
		check(game.bank == old_balance and game.progression.levels == old_levels, "range node selection only previews the upgrade")
		click(game.skill_tree_panel, "PurchaseSkillButton")
		var price: int = Main.Progression.UPGRADES.excavation_range.costs[level]
		check(game.bank == old_balance - price and game.progression.levels.excavation_range == level + 1, "actual purchase charges the range upgrade once")
		for id: String in old_levels:
			if id != "excavation_range":
				check(game.progression.levels[id] == old_levels[id], "range purchase leaves all other technology intact")
		check(game.progression.stats().activity_radius == RADII[level + 1], "purchased stats advertise the next deployment's area")
		check(game.activity_boundary.radius == radius and game.terrain.activity_radius == radius and game.crystals.size() == old_count, "purchase does not resize or reroll the old trip")
		game.show_outpost("zones")
		check(int(game.base_panel._state.zones[0].count) == COUNTS[level + 1], "zone preview updates its next-trip mine point count")
		click(game.base_panel, "DeployButton")
		check(game.on_moon and not paused and game.trip_fee == 0, "upgraded area deploys through the real free-zone button")
	var capped_balance: int = game.bank
	game.show_outpost("skills")
	click(game.skill_tree_panel, "Skill_excavation_range_3")
	check(game.skill_tree_panel._buy_button.disabled and game.skill_tree_panel.node_state("excavation_range", 3) == "purchased", "the current map size is the final purchased node")
	check(not game.progression.buy_upgrade("excavation_range").ok and game.bank == capped_balance and game.progression.stats().activity_radius == 26.0, "range upgrades stop at the old maximum without another charge")
	game.sfx.set_muted(true)
	await create_timer(0.10, true).timeout
	paused = false
	game.queue_free()
	await process_frame
	await create_timer(0.25, true).timeout
	print("EXCAVATION_RANGE_OK radii=14/18/22/26 counts=21/35/52/72 real_skill_purchase=true next_trip_only=true full_shape_inside=true edge_drop=true brush_clip=true warning_wall=true cap_old_map=true")
	quit(1 if failed else 0)
