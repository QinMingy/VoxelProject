extends Node3D

const REST_POSITION := Vector3(0.30, -0.25, -0.52)
const REST_ROTATION := Vector3(-0.21, 0.14, -0.07)
const BIT_REST := Vector3(0.0, 0.0, -0.186)

var _pivot: Node3D
var _bit: MeshInstance3D
var _indicator: StandardMaterial3D
var _drilling := false
var _drill_blend := 0.0
var _walk_blend := 0.0
var _drill_phase := 0.0
var _walk_phase := 0.0

func _ready() -> void:
	_pivot = Node3D.new()
	_pivot.name = "ToolPivot"
	_pivot.position = REST_POSITION
	_pivot.rotation = REST_ROTATION
	add_child(_pivot)

	var shell := _material(Color("#e7e9d9"), 0.65)
	var rubber := _material(Color("#253841"), 0.88)
	var orange := _material(Color("#ee9e56"), 0.47)
	var steel := _material(Color("#7d919a"), 0.36, 0.34)
	_indicator = _material(Color("#76e5df"), 0.44)
	_indicator.emission_enabled = true
	_indicator.emission = Color("#76e5df")
	_indicator.emission_energy_multiplier = 0.75 if _drilling else 0.25

	_box(Vector3(0.158, 0.128, 0.174), Vector3.ZERO, orange)
	_box(Vector3(0.116, 0.029, 0.157), Vector3(0.0, 0.067, 0.001), orange)
	_box(Vector3(0.123, 0.089, 0.052), Vector3(0.0, -0.004, 0.100), rubber)
	_box(Vector3(0.050, 0.078, 0.062), Vector3(0.030, -0.076, 0.044), rubber)
	_box(Vector3(0.084, 0.013, 0.048), Vector3(0.0, 0.084, 0.024), rubber)
	for index in range(3):
		_box(Vector3(0.014, 0.007, 0.024), Vector3((index - 1) * 0.020, 0.092, 0.024), _indicator)

	var collar := _tube(0.058, 0.052, Vector3(0.0, 0.0, -0.109), rubber)
	collar.rotation.x = PI * 0.5
	var nose := _tube(0.043, 0.024, Vector3(0.0, 0.0, -0.140), steel)
	nose.rotation.x = PI * 0.5
	_bit = _tube(0.019, 0.114, BIT_REST, steel)
	_bit.rotation.x = PI * 0.5
	_box(Vector3(0.046, 0.021, 0.023), Vector3(0.0, -0.055, 0.0), steel, _bit)

	var right_hand := Vector3(0.066, -0.088, 0.069)
	var left_hand := Vector3(-0.069, -0.049, -0.053)
	_link(Vector3(0.191, -0.172, 0.195), right_hand, 0.052, shell)
	_link(Vector3(-0.085, -0.205, 0.094), left_hand, 0.044, shell)
	_glove(right_hand, Vector3(1.1, 0.86, 1.0), rubber)
	_glove(left_hand, Vector3(0.95, 0.74, 1.18), rubber)
	_box(Vector3(0.044, 0.030, 0.036), right_hand + Vector3(0.014, 0.028, 0.0), shell)

func set_drilling(active: bool) -> void:
	if active == _drilling:
		return
	_drilling = active
	if _indicator != null:
		_indicator.emission_energy_multiplier = 0.75 if active else 0.25

func animate(delta: float, moving: bool, drilling: bool) -> void:
	set_drilling(drilling)
	if _pivot == null:
		return
	var blend := 1.0 - exp(-delta * 18.0)
	_drill_blend = lerpf(_drill_blend, float(_drilling), blend)
	_walk_blend = lerpf(_walk_blend, float(moving), blend)
	if moving:
		_walk_phase = fposmod(_walk_phase + delta * 9.0, TAU)
	_drill_phase = fposmod(_drill_phase + delta * 86.0, TAU)

	var recoil := sin(_drill_phase) * _drill_blend
	var stride := sin(_walk_phase) * _walk_blend
	_pivot.position = REST_POSITION + Vector3(
		stride * 0.006 + recoil * 0.002,
		cos(_walk_phase * 2.0) * _walk_blend * 0.006,
		recoil * 0.004
	)
	_pivot.rotation = REST_ROTATION + Vector3(recoil * 0.013, 0.0, stride * 0.018)
	_bit.position = BIT_REST + Vector3.BACK * (recoil * 0.011)

func _material(color: Color, roughness: float, metallic: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material

func _mesh(mesh: Mesh, at: Vector3, material: Material, parent: Node3D = null) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.position = at
	part.material_override = material
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var holder := _pivot if parent == null else parent
	holder.add_child(part)
	return part

func _box(size: Vector3, at: Vector3, material: Material, parent: Node3D = null) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _mesh(mesh, at, material, parent)

func _tube(radius: float, length: float, at: Vector3, material: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 10
	return _mesh(mesh, at, material)

func _link(start: Vector3, end: Vector3, radius: float, material: Material) -> void:
	var direction := end - start
	var sleeve := _tube(radius, direction.length(), (start + end) * 0.5, material)
	sleeve.quaternion = Quaternion(Vector3.UP, direction.normalized())

func _glove(at: Vector3, shape: Vector3, material: Material) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 0.049
	mesh.height = 0.098
	mesh.radial_segments = 10
	mesh.rings = 5
	_mesh(mesh, at, material).scale = shape
