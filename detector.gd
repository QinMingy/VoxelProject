extends RefCounted

const RANGES := [10.0, 16.0, 22.0, 28.0]
const DIRECTIONS := ["正前", "右前", "右侧", "右后", "正后", "左后", "左侧", "左前"]
const SIZE_NAMES := ["小", "中", "大"]

static func sample(origin: Vector3, forward: Vector3, candidates: Array, terrain: Node, level: int) -> Dictionary:
	var tier := clampi(level, 0, RANGES.size() - 1)
	var range_m: float = RANGES[tier]
	var heading := Vector3(forward.x, 0.0, forward.z).normalized()
	if heading.is_zero_approx():
		heading = Vector3.FORWARD
	var reading := {
		"available": false, "strength": 0.0,
		"distance_m": 0.0, "horizontal_distance_m": 0.0,
		"bearing_radians": 0.0,
		"heading_radians": fposmod(atan2(heading.x, -heading.z), TAU),
		"range_m": range_m, "level": tier,
		"direction_text": "", "depth_text": "", "size_text": "",
		"target": null, "echoes": [],
	}
	var echoes: Array[Dictionary] = []
	var seen := {}
	for candidate in candidates:
		if not is_instance_valid(candidate) or candidate.collected:
			continue
		var id: int = candidate.get_instance_id()
		if seen.has(id):
			continue
		seen[id] = true
		var offset: Vector3 = candidate.position - origin
		var distance_squared := offset.length_squared()
		# Range is a true 3D sphere; underground or rear targets are not exempt.
		if distance_squared > range_m * range_m:
			continue
		var distance := sqrt(distance_squared)
		var direction := Vector3(offset.x, 0.0, offset.z).normalized()
		var bearing := 0.0
		var alignment := 1.0
		if not direction.is_zero_approx():
			alignment = clampf(heading.dot(direction), -1.0, 1.0)
			bearing = atan2(direction.dot(heading.cross(Vector3.UP)), alignment)
		var proximity := 1.0 - distance / range_m
		var range_gain := lerpf(0.06, 1.0, pow(clampf(proximity, 0.0, 1.0), 1.25))
		var facing_gain := lerpf(0.25, 1.0, (alignment + 1.0) * 0.5)
		var echo := {
			"id": id, "target": candidate, "order": echoes.size(),
			"distance_m": distance,
			"horizontal_distance_m": Vector2(offset.x, offset.z).length(),
			"bearing_radians": bearing,
			"strength": range_gain * facing_gain,
			"direction_text": DIRECTIONS[posmod(roundi(bearing / (PI * 0.25)), DIRECTIONS.size())],
			"depth_text": "", "size_text": "",
		}
		if tier >= 2 and is_instance_valid(terrain):
			var bounds: AABB = candidate.get_local_bounds()
			var center: Vector3 = candidate.position + bounds.get_center()
			var surface: float = terrain.height_at(center.x, center.z)
			var cover: float = surface - (candidate.position.y + bounds.end.y)
			echo.depth_text = "地表" if cover <= 0.065 else ("浅埋" if cover <= 0.28 else "深埋")
		if tier >= 3:
			echo.size_text = SIZE_NAMES[clampi(candidate.size_tier, 0, SIZE_NAMES.size() - 1)]
		echoes.append(echo)
	# Stable ordering gives deterministic overlap priority and a compatible nearest summary.
	echoes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.distance_m == b.distance_m:
			return a.order < b.order
		return a.distance_m < b.distance_m)
	reading.echoes = echoes
	if not echoes.is_empty():
		reading.available = true
		reading.merge(echoes[0], true)
	return reading
