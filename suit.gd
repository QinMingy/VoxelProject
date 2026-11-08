extends Node3D
const Palette = preload("res://palette.gd")

var body: Node3D
var left_leg: Node3D
var right_leg: Node3D
var drill: Node3D
var bit: MeshInstance3D
var stride := 0.0
var vibration := 0.0

var shell := _material(Palette.BONE)
var joint := _material(Palette.DEEP_SLATE)
var trim := _material(Palette.AMBER)
var glass := _material(Palette.TEAL_SHADOW, 0.24, 0.42)
var glow := _material(Palette.CYAN, 0.38, 0.05, 0.48)


func _ready() -> void:
	body = Node3D.new()
	add_child(body)

	_box(body, Vector3(0.34, 0.38, 0.26), Vector3(0, 0.66, 0), shell)
	_box(body, Vector3(0.32, 0.12, 0.27), Vector3(0, 0.49, 0), joint)
	_box(body, Vector3(0.33, 0.35, 0.16), Vector3(0, 0.68, 0.20), joint)
	for x in [-0.105, 0.105]:
		_tube(body, 0.062, 0.30, Vector3(x, 0.70, 0.28), shell)
		_tube(body, 0.064, 0.058, Vector3(x, 0.62, 0.28), trim)
	_box(body, Vector3(0.23, 0.15, 0.07), Vector3(0, 0.68, -0.15), joint)
	_box(body, Vector3(0.13, 0.027, 0.015), Vector3(0, 0.70, -0.19), glow)

	_ball(body, 0.236, Vector3(0, 1.00, 0), Vector3(1.0, 0.96, 1.0), shell)
	_ball(body, 0.213, Vector3(0, 1.015, -0.093), Vector3(1.0, 0.72, 0.80), glass)
	_box(body, Vector3(0.15, 0.016, 0.013), Vector3(0, 1.062, -0.256), glow)
	for x in [-0.22, 0.22]:
		var ear := _tube(body, 0.070, 0.042, Vector3(x, 1.00, 0.025), trim)
		ear.rotation.z = PI * 0.5

	left_leg = _make_leg(-0.105)
	right_leg = _make_leg(0.105)

	for side in [-1.0, 1.0]:
		var shoulder := Vector3(side * 0.21, 0.76, -0.015)
		var elbow := Vector3(side * 0.27, 0.61, -0.31)
		var hand := Vector3(side * 0.165, 0.68, -0.68)
		_link(body, shoulder, elbow, 0.081, shell)
		_ball(body, 0.073, elbow, Vector3.ONE, joint)
		_link(body, elbow, hand, 0.063, shell)
		_ball(body, 0.068, hand, Vector3.ONE, joint)

	drill = Node3D.new()
	drill.position = Vector3(0, 0, -0.80)
	body.add_child(drill)
	_box(drill, Vector3(0.38, 0.059, 0.13), Vector3(0, 0.67, 0.10), joint)
	_box(drill, Vector3(0.18, 0.25, 0.20), Vector3(0, 0.57, 0), trim)
	_box(drill, Vector3(0.135, 0.12, 0.026), Vector3(0, 0.59, -0.106), joint)
	_box(drill, Vector3(0.087, 0.027, 0.016), Vector3(0, 0.62, -0.123), glow)
	_tube(drill, 0.069, 0.10, Vector3(0, 0.40, 0), joint)
	bit = _tube(drill, 0.030, 0.30, Vector3(0, 0.21, 0), shell)
	_tube(drill, 0.033, 0.07, Vector3(0, 0.04, 0), joint, 0.008)


func animate(delta: float, moving: bool, drilling: bool, airborne: bool = false) -> void:
	if not is_instance_valid(body):
		return

	if moving and not airborne:
		stride += delta * 12.0
	var swing := sin(stride) * 0.50 if moving and not airborne else 0.0
	var blend := 1.0 - exp(-delta * 18.0)
	left_leg.rotation.x = lerpf(left_leg.rotation.x, -0.34 if airborne else swing, blend)
	right_leg.rotation.x = lerpf(right_leg.rotation.x, 0.20 if airborne else -swing, blend)
	body.position.y = lerpf(body.position.y, absf(swing) * 0.042, blend)

	vibration += delta * 86.0
	drill.position.y = sin(vibration) * 0.013 if drilling else 0.0
	bit.position.y = 0.21 + sin(vibration + 1.1) * 0.027 if drilling else 0.21


func _make_leg(x: float) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = Vector3(x, 0.50, 0)
	body.add_child(pivot)
	_tube(pivot, 0.091, 0.25, Vector3(0, -0.13, 0), shell)
	_tube(pivot, 0.075, 0.16, Vector3(0, -0.30, 0), joint)
	_box(pivot, Vector3(0.175, 0.13, 0.25), Vector3(0, -0.427, -0.048), shell)
	_box(pivot, Vector3(0.181, 0.028, 0.26), Vector3(0, -0.486, -0.048), joint)
	_box(pivot, Vector3(0.145, 0.05, 0.025), Vector3(0, -0.43, -0.175), trim)
	return pivot


func _material(color: Color, roughness := 0.76, metallic := 0.0, emission := 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = metallic
	if emission > 0.0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = emission
	return mat


func _add_mesh(parent: Node3D, mesh: Mesh, at: Vector3, mat: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	instance.material_override = mat
	parent.add_child(instance)
	return instance


func _box(parent: Node3D, size: Vector3, at: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _add_mesh(parent, mesh, at, mat)


func _ball(parent: Node3D, radius: float, at: Vector3, shape: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	var instance := _add_mesh(parent, mesh, at, mat)
	instance.scale = shape
	return instance


func _tube(parent: Node3D, radius: float, height: float, at: Vector3, mat: Material, bottom := -1.0) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius if bottom < 0.0 else bottom
	mesh.height = height
	mesh.radial_segments = 10
	return _add_mesh(parent, mesh, at, mat)


func _link(parent: Node3D, from: Vector3, to: Vector3, radius: float, mat: Material) -> void:
	var direction := to - from
	var instance := _tube(parent, radius, direction.length(), (from + to) * 0.5, mat)
	instance.basis = Basis(Quaternion(Vector3.UP, direction.normalized()))
