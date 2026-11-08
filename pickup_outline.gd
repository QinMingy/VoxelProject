extends Node3D

# Pickup outlines are a screen-space pass: a mask viewport renders only the
# collectible silhouettes, and each collectible draws that mask back onto a
# depth-tested quad sitting at its own centre. Silhouettes therefore keep a
# constant pixel width and terrain still occludes them.

const Palette = preload("res://palette.gd")
const LAYER := 20
const LAYER_MASK := 1 << (LAYER - 1)
const OUTLINE_PIXELS := 7.0
const OUTLINE_COLOR := Palette.CYAN_LIGHT

const OUTLINE_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled, ambient_light_disabled;

uniform sampler2D mask_tex : filter_linear, repeat_disable;
uniform vec4 line_color : source_color;
uniform float radius_px;
uniform vec2 mask_texel;

const int TAPS = 24;

void fragment() {
	vec2 uv = SCREEN_UV;
	float inside = texture(mask_tex, uv).a;
	float reach = 0.0;
	for (int i = 0; i < TAPS; i++) {
		float angle = (float(i) + 0.5) * 6.28318530718 / float(TAPS);
		vec2 offset = vec2(cos(angle), sin(angle)) * radius_px * mask_texel;
		reach = max(reach, texture(mask_tex, uv + offset).a);
	}
	// Subtracting the silhouette keeps the ring strictly outside the object.
	float ring = clamp(reach - inside, 0.0, 1.0);
	if (ring <= 0.004) {
		discard;
	}
	ALBEDO = line_color.rgb;
	ALPHA = ring;
}
"""

var camera: Camera3D
var items: Array = []

var _mask_viewport: SubViewport
var _mask_camera: Camera3D
var _material: ShaderMaterial
var _quads: Dictionary = {}

func _ready() -> void:
	_mask_viewport = SubViewport.new()
	_mask_viewport.name = "PickupOutlineMask"
	_mask_viewport.own_world_3d = false
	_mask_viewport.transparent_bg = true
	_mask_viewport.disable_3d = false
	_mask_viewport.msaa_3d = Viewport.MSAA_DISABLED
	_mask_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_mask_viewport)
	_mask_camera = Camera3D.new()
	_mask_camera.cull_mask = LAYER_MASK
	_mask_camera.current = true
	_mask_viewport.add_child(_mask_camera)
	var shader := Shader.new()
	shader.code = OUTLINE_SHADER
	_material = ShaderMaterial.new()
	_material.shader = shader
	_material.set_shader_parameter("mask_tex", _mask_viewport.get_texture())
	_material.set_shader_parameter("line_color", OUTLINE_COLOR)
	_material.set_shader_parameter("radius_px", OUTLINE_PIXELS)

func bind(main_camera: Camera3D, tracked: Array) -> void:
	camera = main_camera
	items = tracked

func _process(_delta: float) -> void:
	if camera == null or not is_instance_valid(camera):
		return
	_sync_mask_camera()
	var active := false
	var seen := {}
	for item: Node3D in items:
		if not is_instance_valid(item):
			continue
		if not item.wants_outline() or not item.is_visible_in_tree():
			continue
		var quad := _quad_for(item)
		_place_quad(quad, item)
		quad.visible = true
		seen[item.get_instance_id()] = true
		active = true
	for id in _quads.keys():
		if not seen.has(id):
			_quads[id].queue_free()
			_quads.erase(id)
	var mode := SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
	if _mask_viewport.render_target_update_mode != mode:
		_mask_viewport.render_target_update_mode = mode

func _sync_mask_camera() -> void:
	var visible_size := get_viewport().get_visible_rect().size
	var size := Vector2i(maxi(1, roundi(visible_size.x)), maxi(1, roundi(visible_size.y)))
	if _mask_viewport.size != size:
		_mask_viewport.size = size
		_material.set_shader_parameter("mask_texel", Vector2(1.0 / float(size.x), 1.0 / float(size.y)))
	_mask_camera.global_transform = camera.global_transform
	_mask_camera.fov = camera.fov
	_mask_camera.near = camera.near
	_mask_camera.far = camera.far
	_mask_camera.keep_aspect = camera.keep_aspect
	_mask_camera.projection = camera.projection
	_mask_camera.size = camera.size
	_mask_camera.h_offset = camera.h_offset
	_mask_camera.v_offset = camera.v_offset
	_mask_camera.frustum_offset = camera.frustum_offset

func _quad_for(item: Node3D) -> MeshInstance3D:
	var id := item.get_instance_id()
	var existing: MeshInstance3D = _quads.get(id)
	if existing != null:
		return existing
	var quad := MeshInstance3D.new()
	quad.name = "PickupOutlineQuad"
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE
	quad.mesh = mesh
	quad.material_override = _material
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	quad.layers = 1
	add_child(quad)
	_quads[id] = quad
	return quad

func _place_quad(quad: MeshInstance3D, item: Node3D) -> void:
	var bounds: AABB = item.get_local_bounds()
	var center: Vector3 = item.global_transform * bounds.get_center()
	var radius := bounds.size.length() * 0.5
	# The quad faces the camera without rotation, so every corner sits at the
	# crystal's own depth and the depth buffer keeps soil in front of the ring.
	var half := radius * 1.45 + 0.06
	var basis := camera.global_basis.orthonormalized().scaled(Vector3.ONE * (half * 2.0))
	quad.global_transform = Transform3D(basis, center)

func quad_for(item: Node3D) -> MeshInstance3D:
	return _quads.get(item.get_instance_id())

func outline_visible(item: Node3D) -> bool:
	var quad: MeshInstance3D = quad_for(item)
	return quad != null and quad.visible

func mask_cull_mask() -> int:
	return _mask_camera.cull_mask
