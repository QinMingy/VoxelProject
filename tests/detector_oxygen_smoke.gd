extends SceneTree

const Terrain = preload("res://terrain.gd")
const Crystal = preload("res://crystal.gd")
const Detector = preload("res://detector.gd")

func _initialize() -> void:
	call_deferred("run")

func require(condition: bool, description: String) -> void:
	if not condition:
		push_error("DETECTOR OXYGEN FAIL: " + description)
		quit(1)
		assert(condition, description)

func run() -> void:
	var terrain := Terrain.new()
	root.add_child(terrain)
	var item := Crystal.new()
	root.add_child(item)
	var baseline: Dictionary = {}
	var origin := Vector3(-5.7, 0.0, 4.9)
	for density: float in [0.0, 1.0]:
		terrain.set_oxygen_supply_density(density)
		terrain.reset_terrain(11235)
		terrain.set_fragment_cleanup(false, 9)
		var surface := terrain.height_at(Terrain.STARTER_VEIN.x, Terrain.STARTER_VEIN.y)
		item.position = Vector3(Terrain.STARTER_VEIN.x, 0.0, Terrain.STARTER_VEIN.y)
		item.setup_site(surface, 0.65, 0.30)
		require(item.embed_in(terrain), "real voxel crystal embeds below oxygen pocket")
		var before := Detector.sample(origin, Vector3.RIGHT, [item], terrain, 3)
		if baseline.is_empty():
			baseline = before.duplicate()
		for key: String in ["strength", "bearing_radians", "distance_m", "horizontal_distance_m", "depth_text"]:
			require(before[key] == baseline[key], "oxygen density leaves radar unchanged: " + key)
		var hit := Vector3(Terrain.STARTER_VEIN.x, surface, Terrain.STARTER_VEIN.y)
		var oxygen_grains := terrain.mine_at(hit, Vector3.UP, Terrain.Brush.BOWL)
		require(terrain.last_removed > 0, "mining removes real covering soil")
		require(oxygen_grains > 0 if density > 0 else oxygen_grains == 0, "fixture distinguishes oxygen ore from plain soil")
		var after := Detector.sample(origin, Vector3.RIGHT, [item], terrain, 3)
		for key: String in ["target", "strength", "bearing_radians", "distance_m", "horizontal_distance_m"]:
			require(after[key] == before[key], "excavating oxygen leaves fixed-position signal unchanged: " + key)
		require(not Detector.sample(origin, Vector3.RIGHT, [], terrain, 3).available, "oxygen-bearing terrain cannot emit a crystal echo")
	print("DETECTOR_OXYGEN_OK density_independent=true mining_signal_unchanged=true oxygen_only_no_echo=true")
	quit()
