extends Node3D

const RADIUS := 26.0
const WARNING_DISTANCE := 6.0
const PLAYER_MARGIN := 0.35
const SEGMENTS := 128
const BOTTOM := -4.0
const TOP := 4.0

const WALL_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;

uniform vec3 player_position = vec3(0.0);
uniform float warning_strength : hint_range(0.0, 1.0) = 0.0;
varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float nearby = 1.0 - smoothstep(2.0, 9.0, distance(world_position.xz, player_position.xz));
	float top_fade = 1.0 - smoothstep(2.2, 4.0, world_position.y);
	float bottom_fade = smoothstep(-4.0, -3.7, world_position.y);
	float reveal = warning_strength * nearby * top_fade * bottom_fade;
	if (reveal < 0.001) { discard; }
	// UV units are metres along the circle and world height, so grid spacing stays uniform.
	vec2 coordinate = UV / 0.75;
	vec2 to_line = abs(fract(coordinate + 0.5) - 0.5);
	vec2 antialias = max(fwidth(coordinate), vec2(0.004));
	vec2 axes = vec2(1.0) - smoothstep(vec2(0.012), vec2(0.012) + antialias, to_line);
	float grid = max(axes.x, axes.y);
	ALBEDO = mix(vec3(0.85, 0.035, 0.07), vec3(1.0, 0.22, 0.25), grid);
	ALPHA = reveal * (0.022 + grid * 0.46);
}
"""

var warning_strength := 0.0
var _player_position := Vector3.ZERO
var _wall: MeshInstance3D
var _material := ShaderMaterial.new()

func _ready() -> void:
	var shader := Shader.new()
	shader.code = WALL_SHADER
	_material.shader = shader
	_wall = MeshInstance3D.new()
	_wall.name = "ActivityBoundaryWall"
	_wall.mesh = _build_wall()
	_wall.material_override = _material
	_wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_wall)
	update_player(_player_position)

func clamp_position(point: Vector3) -> Vector3:
	var horizontal := Vector2(point.x, point.z)
	var limit := RADIUS - PLAYER_MARGIN
	if horizontal.length_squared() <= limit * limit:
		return point
	horizontal = horizontal.normalized() * limit
	return Vector3(horizontal.x, point.y, horizontal.y)

func edge_distance(point: Vector3) -> float:
	return RADIUS - Vector2(point.x, point.z).length()

func update_player(point: Vector3) -> void:
	_player_position = point
	var remaining := maxf(0.0, edge_distance(point))
	warning_strength = 1.0 - smoothstep(0.0, WARNING_DISTANCE, remaining)
	if not is_instance_valid(_wall):
		return
	_wall.visible = warning_strength > 0.00001
	_material.set_shader_parameter("player_position", point)
	_material.set_shader_parameter("warning_strength", warning_strength)

func _build_wall() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(SEGMENTS):
		var first_angle := TAU * float(index) / SEGMENTS
		var second_angle := TAU * float(index + 1) / SEGMENTS
		var first := Vector2(cos(first_angle), sin(first_angle)) * RADIUS
		var second := Vector2(cos(second_angle), sin(second_angle)) * RADIUS
		var corners := [
			Vector3(first.x, BOTTOM, first.y), Vector3(second.x, BOTTOM, second.y),
			Vector3(second.x, TOP, second.y), Vector3(first.x, TOP, first.y),
		]
		var uv := [
			Vector2(first_angle * RADIUS, BOTTOM), Vector2(second_angle * RADIUS, BOTTOM),
			Vector2(second_angle * RADIUS, TOP), Vector2(first_angle * RADIUS, TOP),
		]
		var normal := Vector3(first.x + second.x, 0.0, first.y + second.y).normalized()
		for vertex_index in [0, 1, 2, 0, 2, 3]:
			surface.set_normal(normal)
			surface.set_uv(uv[vertex_index])
			surface.add_vertex(corners[vertex_index])
	return surface.commit()
