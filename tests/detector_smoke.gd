extends SceneTree

const Crystal = preload("res://crystal.gd")
const Detector = preload("res://detector.gd")
var failed := false

class SurfaceFixture extends Node:
	var surface := 0.0

	func height_at(_x: float, _z: float) -> float:
		return surface

func _initialize() -> void:
	call_deferred("run")

func require(condition: bool, description: String) -> void:
	if not condition:
		failed = true
		push_error("DETECTOR FAIL: " + description)
		quit(1)
		assert(condition, description)

func make_crystal(at: Vector3) -> Crystal:
	var item := Crystal.new()
	root.add_child(item)
	item.position = at
	return item

func echo(reading: Dictionary, item: Node) -> Dictionary:
	for candidate: Dictionary in reading.echoes:
		if candidate.id == item.get_instance_id():
			return candidate
	return {}

func check_private_fields(reading: Dictionary) -> void:
	var records: Array = reading.echoes.duplicate()
	records.append(reading)
	for record: Dictionary in records:
		for key: String in ["wear", "wear_percent", "value", "base_value", "sale_value", "price"]:
			require(not record.has(key), "signal omits appraisal field: " + key)

func run() -> void:
	var terrain := SurfaceFixture.new()
	root.add_child(terrain)
	var empty := Detector.sample(Vector3.ZERO, Vector3.FORWARD, [], terrain, 0)
	require(not empty.available and empty.strength == 0.0 and empty.echoes.is_empty() and empty.target == null, "empty scan clears every target")
	require(is_zero_approx(empty.heading_radians), "north is zero heading even without a target")
	var near := make_crystal(Vector3(0.0, 0.0, -3.0))
	var far := make_crystal(Vector3(0.0, 0.0, -8.0))
	var base := Detector.sample(Vector3.ZERO, Vector3.FORWARD, [far, near], terrain, 0)
	require(is_equal_approx(base.distance_m, 3.0) and is_equal_approx(base.horizontal_distance_m, 3.0), "reading exposes physical and horizontal distances separately")
	var distant := Detector.sample(Vector3.ZERO, Vector3.FORWARD, [far], terrain, 0)
	var away := Detector.sample(Vector3.ZERO, Vector3.BACK, [far, near], terrain, 0)
	require(base.target == near and base.strength > distant.strength, "closer target yields stronger return")
	require(away.target == near and away.strength < base.strength, "rotating changes gain without switching target")
	require(base.echoes.size() == 2 and base.echoes[0].target == near and base.echoes[1].target == far, "all targets sort nearest first")
	require(base.direction_text == "正前" and base.depth_text.is_empty() and base.size_text.is_empty(), "direction is available at level zero while depth and size remain gated")
	for key: String in ["strength", "distance_m", "horizontal_distance_m", "bearing_radians", "direction_text", "depth_text", "size_text", "target"]:
		require(base[key] == base.echoes[0][key], "legacy nearest field matches first echo: " + key)
	require(not near.discovered and not near.inspected, "scanning does not reveal crystal or appraisal")
	near.collected = true
	require(Detector.sample(Vector3.ZERO, Vector3.FORWARD, [near, far], terrain, 0).target == far, "collected crystals are ignored")
	near.position = Vector3(12.0, 0.0, 0.0)
	near.collected = false
	require(not Detector.sample(Vector3.ZERO, Vector3.FORWARD, [near], terrain, 0).available, "range excludes a distant crystal")
	var directional := Detector.sample(Vector3.ZERO, Vector3.FORWARD, [near], terrain, 1)
	require(directional.target == near and directional.range_m == 16.0 and directional.direction_text == "右侧" and directional.bearing_radians > 0.0, "level one expands range and retains directional readings")
	require(directional.depth_text.is_empty() and directional.size_text.is_empty(), "direction unlock leaves depth and size gated")
	var pitched := Detector.sample(Vector3.ZERO, Vector3(0.0, -0.98, -0.2).normalized(), [near], terrain, 1)
	require(is_equal_approx(pitched.bearing_radians, directional.bearing_radians) and is_equal_approx(pitched.horizontal_distance_m, directional.horizontal_distance_m), "looking down does not move horizontal radar target")
	var elevated := Detector.sample(Vector3.UP * 2.0, Vector3.FORWARD, [near], terrain, 1)
	require(is_equal_approx(elevated.horizontal_distance_m, directional.horizontal_distance_m) and elevated.distance_m > directional.distance_m, "jumping does not inflate the displayed horizontal distance")

	near.setup_site(0.0, 0.125, 0.54)
	var depth := Detector.sample(Vector3.ZERO, Vector3.FORWARD, [near], terrain, 2)
	require(depth.range_m == 22.0 and depth.depth_text == "浅埋" and depth.size_text.is_empty(), "level two estimates shallow cover")
	terrain.surface = -0.25
	require(Detector.sample(Vector3.ZERO, Vector3.FORWARD, [near], terrain, 2).depth_text == "地表", "excavated cover becomes surface")
	terrain.surface = 0.375
	var complete := Detector.sample(Vector3.ZERO, Vector3.FORWARD, [near], terrain, 3)
	require(complete.range_m == 28.0 and complete.depth_text == "深埋" and complete.size_text == "大", "maximum level estimates depth and size")
	check_private_fields(complete)
	check_private_fields(base)

	var left := make_crystal(Vector3(-5, 0, 0))
	var right := make_crystal(Vector3(5, 0, 0))
	var tie := Detector.sample(Vector3.ZERO, Vector3.FORWARD, [right, left], terrain, 0)
	var turned_tie := Detector.sample(Vector3.ZERO, Vector3.RIGHT, [right, left], terrain, 0)
	require(tie.target == right and turned_tie.target == right and tie.echoes[1].target == left, "equal-distance ties retain candidate order when turning")
	require(Detector.sample(Vector3.ZERO, Vector3.FORWARD, [left, right], terrain, 0).target == left, "tie-break is explicitly first candidate")
	require(echo(tie, left).bearing_radians < 0.0 and echo(tie, right).bearing_radians > 0.0, "west is left and east is right when facing north")
	var deleted := make_crystal(Vector3(0, 0, -1))
	var invalid_candidates: Array = [deleted, null, right, left, right, left]
	deleted.free()
	left.collected = true
	var filtered := Detector.sample(Vector3.ZERO, Vector3.FORWARD, invalid_candidates, terrain, 0)
	require(filtered.echoes.size() == 1 and filtered.target == right, "freed, null, collected and duplicate objects never create ghost echoes")
	left.collected = false

	var boundary := make_crystal(Vector3(6, 8, 0))
	var exact := Detector.sample(Vector3.ZERO, Vector3.FORWARD, [boundary], terrain, 0)
	require(exact.available and exact.distance_m == 10.0 and exact.horizontal_distance_m == 6.0, "range includes exact true-3D boundary")
	boundary.position.y = 8.01
	require(not Detector.sample(Vector3.ZERO, Vector3.FORWARD, [boundary], terrain, 0).available, "vertical separation can put horizontally nearby target out of range")
	boundary.position = Vector3(9.999, 0, 0)
	require(Detector.sample(Vector3.ZERO, Vector3.FORWARD, [boundary], terrain, 0).available, "just-inside target remains visible")
	boundary.position.x = 10.001
	require(not Detector.sample(Vector3.ZERO, Vector3.FORWARD, [boundary], terrain, 0).available, "just-outside target is excluded")
	var north := make_crystal(Vector3(0, 0, -3))
	for heading in [-0.02, 0.02, PI * 0.5, -PI * 0.5, PI]:
		var forward := Vector3(sin(heading), 0, -cos(heading))
		var reading := Detector.sample(Vector3.ZERO, forward, [north], terrain, 1)
		require(absf(angle_difference(heading, reading.heading_radians)) < 0.0001, "heading follows north/east/south/west convention")
		require(absf(angle_difference(-heading, reading.bearing_radians)) < 0.0001, "relative north bearing stays consistent through heading wrap")
	var multi_pitched := Detector.sample(Vector3.ZERO, Vector3(0, -0.98, -0.2).normalized(), [right, north], terrain, 1)
	var multi_level := Detector.sample(Vector3.ZERO, Vector3.FORWARD, [right, north], terrain, 1)
	for item in [right, north]:
		require(is_equal_approx(echo(multi_pitched, item).bearing_radians, echo(multi_level, item).bearing_radians) and echo(multi_pitched, item).horizontal_distance_m == echo(multi_level, item).horizontal_distance_m, "camera pitch preserves every target's bearing and horizontal distance")
	var crowd: Array = []
	for index in range(24):
		var angle := TAU * float(index) / 24.0
		crowd.append(make_crystal(Vector3(sin(angle), 0, cos(angle)) * 7.0))
	var crowded := Detector.sample(Vector3.ZERO, Vector3.FORWARD, crowd, terrain, 0)
	require(crowded.echoes.size() == 24, "crowded scan has no hidden nearest-N target cap")
	for index in range(1, crowded.echoes.size()):
		require(crowded.echoes[index - 1].distance_m <= crowded.echoes[index].distance_m, "echo distance ordering is monotonic")
	right.setup_site(0.0, 0.125, 0.30)
	var multiple_details := Detector.sample(Vector3.ZERO, Vector3.FORWARD, [near, right], terrain, 3)
	require(echo(multiple_details, near).size_text == "大" and echo(multiple_details, right).size_text == "小", "every target retains its own size estimate")
	require(echo(multiple_details, near).depth_text == "深埋" and echo(multiple_details, right).depth_text == "深埋", "depth unlock applies to every target")
	print("DETECTOR_SMOKE_OK all_targets=true range_inclusive_3d=true dedup_invalid_collected=true stable_ties=true heading_pitch=true unlocks=true no_appraisal=true")
	quit(1 if failed else 0)
