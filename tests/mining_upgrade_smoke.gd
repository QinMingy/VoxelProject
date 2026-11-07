extends SceneTree

const Main = preload("res://main.gd")
var game: Node3D
var failed := false

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, description: String) -> void:
	if not condition:
		failed = true
		push_error("MINING UPGRADE FAIL: " + description)
		quit(1)
		assert(condition, description)

func run() -> void:
	game = Main.new()
	game.progression = Main.Progression.new("")
	game.progression.bank = 20000
	game.appraisal = Main.Appraisal.new("")
	game.wants_mouse_capture = false
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	await process_frame
	game.terrain.set_fragment_cleanup(false, 9)
	var previous_removed := 0
	for tier in range(4):
		game.apply_progression()
		game.terrain.reset_terrain(11235)
		var radius: float = game.progression.stats().mining_radius
		check(is_equal_approx(game.terrain.brush_radius(0), radius), "purchased radius reaches actual mining geometry")
		check(is_equal_approx(game.terrain.brush_radius(1), 0.60 * radius / 0.45) and is_equal_approx(game.terrain.brush_radius(2), 0.29 * radius / 0.45), "GM alternatives retain their relative widths")
		game.terrain.mine_at(Main.LANDER, Vector3.UP, 0)
		var removed: int = game.terrain.last_removed
		check(removed > previous_removed, "each actual size purchase removes more real soil from the same seeded site")
		previous_removed = removed
		check(is_equal_approx(game.mining_time, 0.9), "size upgrades leave strike interval independent")
		if tier < 3:
			check(game.progression.buy_upgrade("mining_radius").ok, "size purchase succeeds through the actual transaction")
	game.terrain.set_mining_radius(NAN)
	check(is_equal_approx(game.terrain.brush_radius(0), 0.45), "invalid runtime radius falls back to the safe base size")
	game.terrain.set_mining_radius(1000)
	check(is_equal_approx(game.terrain.brush_radius(0), 0.60), "runtime radius cannot cause unbounded voxel scans")

	for tier in range(4):
		game.apply_progression()
		game.start_trip(false)
		check(game.on_moon and game.oxygen_recovered == 0.0, "new expedition resets the cumulative supply budget")
		var budget: float = Main.Progression.OXYGEN_RECOVERY_LIMITS[tier]
		check(game.oxygen_recovery_limit == budget, "supply level reaches the live recovery allowance")
		check(game.gain_oxygen(100000) == 0.0 and game.oxygen_recovered == 0.0, "full tank neither stores oxygen nor consumes recovery allowance")
		game.oxygen = 1.0
		check(is_equal_approx(game.gain_oxygen(100000), budget) and is_equal_approx(game.oxygen, 1.0 + budget), "even a huge vein respects the total per-trip budget")
		game.oxygen = 1.0
		check(game.gain_oxygen(100000) == 0.0 and game.oxygen == 1.0, "spending oxygen cannot refresh an exhausted recovery budget")
		game.update_hud()
		check(game.pickup_label.text == "补氧额度已用尽", "exhausted budget does not falsely claim the low tank is full")
		game.settle(true)
		check(game.gain_oxygen(100000) == 0.0, "base cannot collect delayed or fabricated supply")
		if tier < 3:
			check(game.progression.buy_upgrade("oxygen_supply").ok, "density and recovery allowance upgrade together")

	for zone_id in ["meadow", "salvage", "deep"]:
		check(game.progression.select_zone(zone_id), "select actual mine for item distribution")
		for range_level in [0, 3]:
			game.progression.levels.excavation_range = range_level
			game.apply_progression()
			game.start_trip(false)
			game.terrain.reset_terrain(68217)
			game.spawn_crystals(68217)
			var zone: Dictionary = game.trip_zone
			var relic_count := 0
			for item: Node3D in game.crystals:
				if item.item_type != "crystal":
					relic_count += 1
				check(item.wear_percent >= int(zone.wear_range[0]) and item.wear_percent <= int(zone.wear_range[1]), "actual spawned wear follows the mine's value profile")
			check(game.crystals.size() == int(zone.count) and relic_count == int(zone.relic_count), "real relic count grows with deployed map area instead of staying at six")
			game.settle(true)

	game.sfx.set_muted(true)
	await create_timer(0.10, true).timeout
	paused = false
	game.queue_free()
	await process_frame
	await create_timer(0.25, true).timeout
	if not failed:
		print("MINING_UPGRADE_OK actual_size_growth=true independent_speed=true capped_scan=true cumulative_oxygen_budget=true next_trip_reset=true zone_wear=true scaled_relics=true")
	quit(1 if failed else 0)
