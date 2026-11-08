extends Node3D
const Palette = preload("res://palette.gd")

# A small, ordinary voxel visitor. This is deliberately separate from the
# expedition mascot: visitors are scenery, never a controllable character.
var palette_index := 0
var body: Node3D
var left_leg: Node3D
var right_leg: Node3D
var _stride := 0.0
var _materials: Dictionary = {}
const COATS := [Palette.AMBER, Palette.MOON_BLUE, Palette.VIOLET]
const HAIR := [Palette.RUST_SHADOW, Palette.DEEP_SLATE, Palette.ROSE_SHADOW]

func _ready() -> void:
	body = Node3D.new()
	add_child(body)
	var index := posmod(palette_index, COATS.size())
	_box(body, Vector3(0.29, 0.32, 0.20), Vector3(0, 0.46, 0), COATS[index])
	_box(body, Vector3(0.12, 0.10, 0.12), Vector3(0, 0.66, 0), Palette.SKIN)
	_box(body, Vector3(0.27, 0.25, 0.25), Vector3(0, 0.79, 0), Palette.SKIN)
	_box(body, Vector3(0.28, 0.065, 0.26), Vector3(0, 0.92, -0.005), HAIR[index])
	_box(body, Vector3(0.28, 0.18, 0.065), Vector3(0, 0.81, -0.115), HAIR[index])
	for side in [-1.0, 1.0]:
		_box(body, Vector3(0.035, 0.037, 0.012), Vector3(side * 0.065, 0.81, 0.13), Palette.INK)
		_box(body, Vector3(0.09, 0.24, 0.16), Vector3(side * 0.19, 0.48, 0.015), COATS[index])
		_box(body, Vector3(0.085, 0.09, 0.15), Vector3(side * 0.19, 0.315, 0.015), Palette.SKIN)
	left_leg = _leg(-0.08)
	right_leg = _leg(0.08)

func _leg(x: float) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = Vector3(x, 0.30, 0)
	body.add_child(pivot)
	_box(pivot, Vector3(0.12, 0.22, 0.16), Vector3(0, -0.11, 0), Palette.DEEP_SLATE)
	_box(pivot, Vector3(0.145, 0.075, 0.22), Vector3(0, -0.26, 0.025), Palette.INK)
	return pivot

func _box(parent: Node3D, dimensions: Vector3, at: Vector3, color: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	var key := color.to_html()
	if not _materials.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.95
		_materials[key] = material
	instance.material_override = _materials[key]
	parent.add_child(instance)

func animate(delta: float, moving: bool) -> void:
	if not is_instance_valid(body):
		return
	if moving:
		_stride += delta * 9.0
	var swing := sin(_stride) * 0.30 if moving else 0.0
	var blend := 1.0 - exp(-delta * 15.0)
	left_leg.rotation.x = lerpf(left_leg.rotation.x, swing, blend)
	right_leg.rotation.x = lerpf(right_leg.rotation.x, -swing, blend)
	body.position.y = lerpf(body.position.y, absf(swing) * 0.035, blend)
