extends Node3D

# The approved lobby mascot, built as meshes so it remains readable from any
# hall camera angle. The fish and globe are deliberately round; the suit uses
# the same simple blocks as the museum furniture. Forward is +Z.
var body: Node3D
var left_leg: Node3D
var right_leg: Node3D
var left_arm: Node3D
var right_arm: Node3D
var fish: Node3D
var tail: Node3D
var _clock := 0.0
var _stride := 0.0

var _cream := _material(Color("#eee8d9"))
var _white := _material(Color("#fff7e8"))
var _dark := _material(Color("#303441"))
var _orange := _material(Color("#ec8d34"))
var _fish_orange := _material(Color("#e86b19"))
var _fin := _material(Color("#e75b12"))
var _belly := _material(Color("#ffe1aa"))
var _eye := _material(Color("#352321"), 0.22)
var _cyan := _material(Color("#50dbdf"), 0.48, true)

func _ready() -> void:
	body = Node3D.new()
	body.name = "AstronautBody"
	add_child(body)
	_build_suit()
	_build_helmet()
	_build_fish()

func _build_suit() -> void:
	_box(body, "Torso", Vector3(0.56, 0.42, 0.38), Vector3(0, 0.65, 0), _cream)
	_box(body, "ShoulderYoke", Vector3(0.65, 0.11, 0.40), Vector3(0, 0.83, 0), _white)
	_box(body, "Belt", Vector3(0.57, 0.10, 0.40), Vector3(0, 0.47, 0), _dark)
	_box(body, "BeltFront", Vector3(0.45, 0.07, 0.025), Vector3(0, 0.47, 0.213), _cream)
	for side in [-1.0, 1.0]:
		_box(body, "BeltClip", Vector3(0.095, 0.14, 0.055), Vector3(side * 0.22, 0.47, 0.23), _orange)
		_box(body, "BeltStud", Vector3(0.025, 0.04, 0.012), Vector3(side * 0.22, 0.48, 0.265), _dark)
	_box(body, "ChestConsoleFrame", Vector3(0.31, 0.245, 0.07), Vector3(0, 0.68, 0.23), _dark)
	_box(body, "ChestConsole", Vector3(0.28, 0.215, 0.018), Vector3(0, 0.68, 0.273), _orange)
	_box(body, "ChestScreen", Vector3(0.19, 0.09, 0.012), Vector3(0, 0.718, 0.29), _cyan)
	_box(body, "ChestScreenDot", Vector3(0.035, 0.027, 0.009), Vector3(-0.045, 0.721, 0.301), _white)
	for x in [-0.058, 0.058]:
		_box(body, "ConsoleKey", Vector3(0.04, 0.025, 0.012), Vector3(x, 0.626, 0.291), _cream)
	_box(body, "BackpackMount", Vector3(0.51, 0.48, 0.18), Vector3(0, 0.68, -0.25), _dark)
	_box(body, "Backpack", Vector3(0.47, 0.44, 0.20), Vector3(0, 0.69, -0.33), _cream)
	_box(body, "BackpackCap", Vector3(0.45, 0.09, 0.22), Vector3(0, 0.92, -0.33), _orange)
	_box(body, "BackpackBase", Vector3(0.45, 0.09, 0.22), Vector3(0, 0.46, -0.33), _orange)
	_box(body, "PackDisplayFrame", Vector3(0.045, 0.23, 0.13), Vector3(0.263, 0.70, -0.32), _dark)
	_box(body, "PackDisplay", Vector3(0.012, 0.16, 0.085), Vector3(0.29, 0.70, -0.32), _cyan)
	left_leg = _leg(-0.16)
	right_leg = _leg(0.16)
	left_arm = _arm(-1)
	right_arm = _arm(1)
	_cylinder(body, "CollarBase", 0.34, 0.10, Vector3(0, 0.92, 0), _dark, 16)
	_cylinder(body, "Collar", 0.35, 0.09, Vector3(0, 0.98, 0), _cream, 16)
	for index in range(8):
		var angle := TAU * index / 8.0
		var clasp := _box(body, "CollarClasp", Vector3(0.09, 0.05, 0.045), Vector3(sin(angle) * 0.338, 0.965, cos(angle) * 0.338), _orange if index % 2 == 0 else _dark)
		clasp.rotation.y = angle

func _leg(x: float) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = "LeftLeg" if x < 0 else "RightLeg"
	pivot.position = Vector3(x, 0.46, 0)
	body.add_child(pivot)
	_box(pivot, "SuitLeg", Vector3(0.245, 0.27, 0.28), Vector3(0, -0.135, 0), _cream)
	_box(pivot, "Knee", Vector3(0.255, 0.08, 0.30), Vector3(0, -0.20, 0.01), _white)
	_box(pivot, "Ankle", Vector3(0.20, 0.08, 0.23), Vector3(0, -0.31, 0), _dark)
	_box(pivot, "Boot", Vector3(0.265, 0.13, 0.39), Vector3(0, -0.385, 0.055), _dark)
	_box(pivot, "BootToe", Vector3(0.25, 0.055, 0.19), Vector3(0, -0.34, 0.135), _cream)
	_box(pivot, "Sole", Vector3(0.28, 0.025, 0.40), Vector3(0, -0.4475, 0.055), _dark)
	return pivot

func _arm(side: int) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = "LeftArm" if side < 0 else "RightArm"
	pivot.position = Vector3(side * 0.355, 0.79, 0)
	pivot.rotation.z = side * 0.12
	body.add_child(pivot)
	_box(pivot, "Shoulder", Vector3(0.22, 0.20, 0.29), Vector3(0, -0.06, 0), _white)
	_box(pivot, "Sleeve", Vector3(0.20, 0.20, 0.26), Vector3(0, -0.23, 0.015), _cream)
	_box(pivot, "Cuff", Vector3(0.21, 0.07, 0.27), Vector3(0, -0.34, 0.015), _dark)
	_box(pivot, "Glove", Vector3(0.22, 0.16, 0.27), Vector3(0, -0.43, 0.04), _cream)
	_box(pivot, "Thumb", Vector3(0.07, 0.105, 0.13), Vector3(-side * 0.12, -0.405, 0.12), _white)
	_box(pivot, "GloveSeam", Vector3(0.16, 0.023, 0.013), Vector3(0, -0.45, 0.183), _dark)
	return pivot

func _build_helmet() -> void:
	var glass := _transparent(Color(0.63, 0.86, 0.97, 0.055))
	var globe := _ball(body, "GlassGlobe", 0.47, Vector3(0, 1.31, 0), Vector3.ONE, glass, 32, 16)
	globe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# A low-alpha spherical cap and its horizontal surface communicate a filled
	# fishbowl without tinting the orange fish into an unreadable dark silhouette.
	var water := _transparent(Color(0.13, 0.64, 0.83, 0.06))
	var cap_mesh := _water_cap_mesh(0.456, 0.16)
	_mesh(body, "WaterVolume", cap_mesh, Vector3(0, 1.31, 0), water).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var surface := _cylinder(body, "WaterSurface", sqrt(0.456 * 0.456 - 0.16 * 0.16), 0.003, Vector3(0, 1.47, 0), _transparent(Color(0.31, 0.85, 0.97, 0.055)), 32)
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring(body, "Waterline", 0.422, 0.43, Vector3(0, 1.47, 0), _material(Color("#91e1f0"), 0.6, true))
	# Small highlights are actual thin surface meshes, not a billboard portrait.
	var glint := _ball(body, "HelmetReflection", 1.0, Vector3(-0.25, 1.59, 0.275), Vector3(0.055, 0.13, 0.013), _material(Color("#f6fcff"), 0.4, true), 12, 6)
	glint.rotation.z = -0.63
	glint.rotation.y = -0.45
	var glint_small := _ball(body, "HelmetReflectionSmall", 1.0, Vector3(-0.365, 1.40, 0.27), Vector3(0.018, 0.053, 0.012), _white, 10, 5)
	glint_small.rotation.y = -0.8
	for bubble: Vector3 in [Vector3(-0.31, 1.30, 0.20), Vector3(-0.23, 1.43, 0.18)]:
		var bubble_ring := _ring(body, "Bubble", 0.025, 0.031, bubble, _material(Color("#c5eff7"), 0.6, true))
		bubble_ring.rotation.x = PI * 0.5

func _build_fish() -> void:
	fish = Node3D.new()
	fish.name = "Goldfish"
	fish.position = Vector3(0, 1.255, 0.08)
	body.add_child(fish)
	_ball(fish, "FishBody", 1.0, Vector3.ZERO, Vector3(0.245, 0.225, 0.175), _fish_orange, 20, 12)
	_ball(fish, "CreamBelly", 1.0, Vector3(0, -0.10, 0.13), Vector3(0.145, 0.108, 0.045), _belly, 16, 10)
	for side in [-1.0, 1.0]:
		_ball(fish, "Cheek", 1.0, Vector3(side * 0.17, -0.025, 0.132), Vector3(0.057, 0.06, 0.037), _belly, 12, 6)
		_ball(fish, "EyeRim", 1.0, Vector3(side * 0.105, 0.060, 0.157), Vector3(0.086, 0.092, 0.052), _belly, 20, 10)
		_ball(fish, "Eye", 1.0, Vector3(side * 0.105, 0.063, 0.181), Vector3(0.071, 0.079, 0.044), _eye, 20, 10)
		_ball(fish, "EyeSpark", 1.0, Vector3(side * 0.105 - 0.020, 0.090, 0.220), Vector3(0.022, 0.025, 0.008), _white, 12, 6)
		_ball(fish, "EyeSparkSmall", 1.0, Vector3(side * 0.105 + 0.022, 0.039, 0.220), Vector3(0.009, 0.010, 0.005), _white, 10, 4)
	_ball(fish, "MouthRim", 1.0, Vector3(0, -0.039, 0.191), Vector3(0.034, 0.041, 0.018), _belly, 16, 8)
	_ball(fish, "Mouth", 1.0, Vector3(0, -0.039, 0.207), Vector3(0.020, 0.026, 0.010), _eye, 12, 6)
	var dorsal := _ball(fish, "DorsalFin", 1.0, Vector3(0.09, 0.205, -0.025), Vector3(0.078, 0.085, 0.025), _fin, 12, 6)
	dorsal.rotation.z = -0.35
	tail = Node3D.new()
	tail.name = "FishTail"
	tail.position = Vector3(0.205, 0, -0.035)
	fish.add_child(tail)
	for fin: Dictionary in [
		{"at": Vector3(0.085, 0.09, 0), "scale": Vector3(0.11, 0.082, 0.025), "angle": 0.65},
		{"at": Vector3(0.105, 0, 0), "scale": Vector3(0.12, 0.070, 0.027), "angle": 0.0},
		{"at": Vector3(0.08, -0.09, 0), "scale": Vector3(0.105, 0.073, 0.025), "angle": -0.65}
	]:
		var piece := _ball(tail, "TailFin", 1.0, fin.at, fin.scale, _fin, 12, 6)
		piece.rotation.z = float(fin.angle)

func animate(delta: float, moving: bool) -> void:
	if not is_instance_valid(body):
		return
	_clock += delta
	if moving:
		_stride += delta * 10.0
	var step := sin(_stride) * 0.33 if moving else 0.0
	var blend := 1.0 - exp(-delta * 14.0)
	left_leg.rotation.x = lerpf(left_leg.rotation.x, step, blend)
	right_leg.rotation.x = lerpf(right_leg.rotation.x, -step, blend)
	left_arm.rotation.x = lerpf(left_arm.rotation.x, -step * 0.65, blend)
	right_arm.rotation.x = lerpf(right_arm.rotation.x, step * 0.65, blend)
	body.position.y = lerpf(body.position.y, absf(step) * 0.05, blend)
	fish.position.y = 1.255 + sin(_clock * 1.8) * 0.009
	tail.rotation.y = sin(_clock * 4.0) * 0.22

func _material(color: Color, roughness: float = 0.78, unshaded: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	if unshaded:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material

func _transparent(color: Color) -> StandardMaterial3D:
	var material := _material(color, 0.12, true)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material

func _mesh(parent: Node3D, part_name: String, geometry: Mesh, at: Vector3, material: Material) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = part_name
	part.mesh = geometry
	part.position = at
	part.material_override = material
	parent.add_child(part)
	return part

func _box(parent: Node3D, part_name: String, dimensions: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
	var geometry := BoxMesh.new()
	geometry.size = dimensions
	return _mesh(parent, part_name, geometry, at, material)

func _ball(parent: Node3D, part_name: String, radius: float, at: Vector3, dimensions: Vector3, material: Material, segments: int = 16, rings: int = 8) -> MeshInstance3D:
	var geometry := SphereMesh.new()
	geometry.radius = radius
	geometry.height = radius * 2.0
	geometry.radial_segments = segments
	geometry.rings = rings
	var part := _mesh(parent, part_name, geometry, at, material)
	part.scale = dimensions
	return part

func _cylinder(parent: Node3D, part_name: String, radius: float, height: float, at: Vector3, material: Material, segments: int) -> MeshInstance3D:
	var geometry := CylinderMesh.new()
	geometry.top_radius = radius
	geometry.bottom_radius = radius
	geometry.height = height
	geometry.radial_segments = segments
	return _mesh(parent, part_name, geometry, at, material)

func _ring(parent: Node3D, part_name: String, inner: float, outer: float, at: Vector3, material: Material) -> MeshInstance3D:
	var geometry := TorusMesh.new()
	geometry.inner_radius = inner
	geometry.outer_radius = outer
	geometry.rings = 32
	geometry.ring_segments = 6
	return _mesh(parent, part_name, geometry, at, material)

func _water_cap_mesh(radius: float, water_height: float) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var start_angle := acos(water_height / radius)
	for row in range(12):
		var a := lerpf(start_angle, PI, row / 12.0)
		var b := lerpf(start_angle, PI, (row + 1) / 12.0)
		for column in range(32):
			var c := TAU * column / 32.0
			var d := TAU * (column + 1) / 32.0
			var points := [Vector3(sin(a) * cos(c), cos(a), sin(a) * sin(c)), Vector3(sin(b) * cos(c), cos(b), sin(b) * sin(c)), Vector3(sin(b) * cos(d), cos(b), sin(b) * sin(d)), Vector3(sin(a) * cos(d), cos(a), sin(a) * sin(d))]
			for index in [0, 1, 2, 0, 2, 3]:
				surface.set_normal(points[index])
				surface.add_vertex(points[index] * radius)
	return surface.commit()
