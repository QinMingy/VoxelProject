extends Node3D

signal slot_requested(slot: int)

const Crystal = preload("res://crystal.gd")
const AdventureItems = preload("res://adventure_items.gd")
const Visitor = preload("res://museum_visitor.gd")
const VisitorComments = preload("res://museum_visitor_comments.gd")

# Three small collections share the existing six paid exhibition slots. These
# indices are save-game slot indices; layout must never reorder stored exhibits.
const LOCATIONS := [Vector3(-4.6, 0, -1.7), Vector3(-2.6, 0, -1.7),
	Vector3(2.6, 0, -1.7), Vector3(4.6, 0, -1.7),
	Vector3(-1.05, 0, 2.25), Vector3(1.05, 0, 2.25)]
const ZONES := [Vector3(-3.6, 0, -1.7), Vector3(3.6, 0, -1.7), Vector3(0, 0, 2.25)]
const PEDESTAL_HEIGHT := 0.68
const WALK_SPEED := 0.95
const WALK_MIN := Vector2(-6.5, -4.0)
const WALK_MAX := Vector2(6.5, 4.5)
const WALK_CELL := 0.25

var displayed_keys: Array[String] = []
var visitors: Array[Node3D] = []
var camera: Camera3D
var bubble_text := ""
var bubble_slot := -1
var bubble_visitor := -1
var bubble_visible: bool:
	get:
		return is_instance_valid(_bubble) and _bubble.visible
var _tops: Array[MeshInstance3D] = []
var _bases: Array[MeshInstance3D] = []
var _signs: Array[Label3D] = []
var _models: Dictionary = {}
var _materials: Dictionary = {}
var _capacity := 3
var _active := false
var _fingerprint := ""
var _pending_collection: Dictionary = {}
var _viewport_size := Vector2(1100, 600)
var _navigation := AStarGrid2D.new()
var _visitor_states: Array[Dictionary] = []
var _entries: Dictionary = {}
var _bubble: PanelContainer
var _bubble_label: Label
var _bubble_tail: Polygon2D
var _bubble_remaining := 0.0
var _comment_clock := 0.0
var _next_comment_at := 2.0
var _comment_count := 0
var _speaker_cursor := 0

func _ready() -> void:
	_build_room()
	_build_navigation()
	_build_bubble()
	set_viewport_size(_viewport_size)
	set_collection(_pending_collection)
	set_process(_active)

func _material(color: Color, unshaded: bool = false) -> StandardMaterial3D:
	var key := color.to_html() + str(unshaded)
	if _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.94
	if unshaded:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_materials[key] = material
	return material

func _box(node_name: String, at: Vector3, dimensions: Vector3, color: Color,
		unshaded: bool = false) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	instance.mesh = mesh
	instance.material_override = _material(color, unshaded)
	instance.position = at
	add_child(instance)
	return instance

func _build_room() -> void:
	var environment := WorldEnvironment.new()
	environment.name = "LobbyEnvironment"
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("#59667f")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("#e5e7ed")
	environment.environment.ambient_light_energy = 0.32
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.name = "LobbyLight"
	sun.rotation_degrees = Vector3(-62, -26, 0)
	sun.light_color = Color("#fffaf2")
	sun.light_energy = 0.48
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 32.0
	add_child(sun)
	_box("PlainFloor", Vector3(0, -0.08, 0), Vector3(60, 0.16, 60), Color("#58667f"))
	for index in range(ZONES.size()):
		var at: Vector3 = ZONES[index]
		_box("ExhibitionZone_%d" % index, at + Vector3(0, 0.009, 0),
			Vector3(4.6, 0.018, 2.75), Color("#8a7f7d"))
		for side in [-1.0, 1.0]:
			_box("ZoneEdgeX_%d" % index, at + Vector3(0, 0.022, side * 1.375),
				Vector3(4.6, 0.014, 0.035), Color("#e9a35c"), true)
			_box("ZoneEdgeZ_%d" % index, at + Vector3(side * 2.3, 0.022, 0),
				Vector3(0.035, 0.014, 2.75), Color("#e9a35c"), true)
	for index in range(LOCATIONS.size()):
		var at: Vector3 = LOCATIONS[index]
		_bases.append(_box("LobbyPedestal_%d" % index, at + Vector3(0, 0.32, 0),
			Vector3(1.23, 0.62, 1.1), Color("#424b60")))
		_tops.append(_box("LobbyPedestalTop_%d" % index, at + Vector3(0, 0.645, 0),
			Vector3(1.3, 0.07, 1.18), Color("#e4d5b9")))
		_box("LobbyPedestalPlate_%d" % index, at + Vector3(0, 0.39, 0.561),
			Vector3(0.38, 0.14, 0.025), Color("#d2a55c"))
		var sign := Label3D.new()
		sign.name = "LobbySlotLabel_%d" % index
		sign.position = at + Vector3(0, 0.24, 1.02)
		sign.font_size = 32
		sign.pixel_size = 0.008
		sign.outline_size = 3
		sign.outline_modulate = Color("#343b4b")
		sign.modulate = Color("#e4e0d8")
		sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sign.no_depth_test = true
		add_child(sign)
		_signs.append(sign)
	var entrances := [Vector3(-3.7, 0.02, 0.05), Vector3(3.1, 0.02, 0.05), Vector3(-2.4, 0.02, 3.65)]
	for index in range(entrances.size()):
		var visitor := Visitor.new()
		visitor.name = "MuseumVisitor_%d" % index
		visitor.palette_index = index
		visitor.position = entrances[index]
		add_child(visitor)
		visitors.append(visitor)
		_visitor_states.append({"target_slot": -1, "path": PackedVector2Array(),
			"path_index": 0, "dwell": 0.0, "phase": "walk", "visits": index})
	camera = Camera3D.new()
	camera.name = "LobbyCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.near = 0.1
	camera.far = 60.0
	add_child(camera)
	camera.current = true
	camera.position = Vector3(0, 12.5, 11.5)
	camera.look_at(Vector3(0, 0.1, 0.1))

func set_viewport_size(dimensions: Vector2) -> void:
	_viewport_size = Vector2(maxf(1.0, dimensions.x), maxf(1.0, dimensions.y))
	if is_instance_valid(camera):
		# KEEP_HEIGHT uses vertical extent: reserve a comfortable margin at either
		# aspect ratio instead of allowing the outer collection bays to be cropped.
		camera.size = maxf(6.6, 12.9 / (_viewport_size.x / _viewport_size.y))
		for sign: Label3D in _signs:
			# Keep captions near 18 screen pixels at either phone or desktop size.
			# A raised anchor and disabled depth test prevent the floor clipping
			# the lower half of billboard glyphs at this elevated camera angle.
			sign.pixel_size = 18.0 * camera.size / (_viewport_size.y * sign.font_size)
	_update_bubble_position()

func set_collection(summary: Dictionary) -> void:
	_pending_collection = summary.duplicate(true)
	if _tops.size() != LOCATIONS.size():
		return
	_capacity = clampi(int(summary.get("capacity", 3)), 0, LOCATIONS.size())
	var slots: Array = summary.get("slots", [])
	var exhibits: Dictionary = summary.get("exhibits", {})
	var fingerprint := var_to_str({"slots": slots, "exhibits": exhibits, "capacity": _capacity})
	if fingerprint == _fingerprint:
		return
	_fingerprint = fingerprint
	# A changed item, placement, wear or level invalidates any old evaluation.
	_clear_bubble()
	_comment_clock = 0.0
	_next_comment_at = 2.0
	_entries.clear()
	for model: Node3D in _models.values():
		remove_child(model)
		model.queue_free()
	_models.clear()
	displayed_keys.clear()
	for index in range(LOCATIONS.size()):
		var unlocked := index < _capacity
		_tops[index].material_override = _material(Color("#e4d5b9") if unlocked else Color("#a3a3a8"))
		_bases[index].material_override = _material(Color("#424b60") if unlocked else Color("#596174"))
		_signs[index].text = "%02d" % (index + 1) if unlocked else "待扩建"
		_signs[index].modulate = Color("#ece2d2") if unlocked else Color("#b0b6c0")
		var key := str(slots[index]) if index < slots.size() else ""
		if not unlocked or key.is_empty() or not exhibits.has(key):
			continue
		var entry: Dictionary = exhibits[key]
		var model := _make_specimen(entry.get("item", {}), index)
		if model == null:
			continue
		_models[index] = model
		_entries[index] = entry.duplicate(true)
		displayed_keys.append(key)
		_signs[index].text = str(entry.get("label", "藏品"))
	for index in range(visitors.size()):
		_choose_next_visit(index, true)

func _make_specimen(data: Dictionary, slot: int) -> Crystal:
	if data.is_empty():
		return null
	var model := Crystal.new()
	model.name = "LobbySpecimen_%d" % slot
	add_child(model)
	var kind := str(data.get("item_type", "crystal"))
	if kind == "crystal":
		var footprint: Vector2i = data.get("footprint", Vector2i(1, 2))
		var tier := 0 if footprint == Vector2i.ONE else (2 if footprint == Vector2i(2, 2) else 1)
		model.setup_site(0, 0, [0.30, 0.42, 0.54][tier])
	else:
		var found := false
		for index in range(AdventureItems.ITEMS.size()):
			var definition: Dictionary = AdventureItems.definition(index)
			if str(definition.id) == kind:
				found = model.setup_adventure(AdventureItems.source_scene(index), definition, Vector3.ZERO, 0, 0)
				break
		if not found:
			remove_child(model)
			model.queue_free()
			return null
	model.set_wear(float(data.get("wear", 0)) / 100.0)
	var bounds: AABB = model.get_local_bounds()
	var fit := minf(1.0, minf(1.13 / maxf(bounds.size.x, bounds.size.z), 1.25 / maxf(0.01, bounds.size.y)))
	model.scale = Vector3.ONE * fit
	model.position = LOCATIONS[slot] + Vector3(-bounds.get_center().x * fit,
		PEDESTAL_HEIGHT - bounds.position.y * fit, -bounds.get_center().z * fit)
	model.set_markers_visible(false)
	return model

func set_active(value: bool) -> void:
	_active = value
	set_process(value)
	if is_instance_valid(_bubble):
		_bubble.visible = value and _bubble_remaining > 0.0
		_update_bubble_position()

func handle_pointer(screen_pos: Vector2) -> void:
	if not _active or not is_instance_valid(camera):
		return
	var origin := camera.project_ray_origin(screen_pos)
	var direction := camera.project_ray_normal(screen_pos)
	var nearest := INF
	var slot := -1
	for index in range(LOCATIONS.size()):
		var bounds := AABB(LOCATIONS[index] + Vector3(-0.65, 0, -0.59), Vector3(1.3, PEDESTAL_HEIGHT, 1.18))
		if _models.has(index):
			var model: Crystal = _models[index]
			bounds = bounds.merge(model.transform * model.get_local_bounds())
		var hit: Variant = bounds.intersects_ray(origin, direction)
		if hit is Vector3:
			var distance := origin.distance_squared_to(hit)
			if distance < nearest:
				nearest = distance
				slot = index
	if slot >= 0:
		slot_requested.emit(slot)
	# The room is directly operated through its exhibits; floor clicks are inert.

func _build_navigation() -> void:
	_navigation.region = Rect2i(0, 0, 53, 35)
	_navigation.cell_size = Vector2.ONE * WALK_CELL
	_navigation.offset = WALK_MIN
	_navigation.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_navigation.update()
	for x in range(_navigation.region.size.x):
		for y in range(_navigation.region.size.y):
			var point := WALK_MIN + Vector2(x, y) * WALK_CELL
			_navigation.set_point_solid(Vector2i(x, y), not _walkable(Vector3(point.x, 0, point.y)))

func _walkable(at: Vector3) -> bool:
	if at.x < WALK_MIN.x or at.x > WALK_MAX.x or at.z < WALK_MIN.y or at.z > WALK_MAX.y:
		return false
	for location: Vector3 in LOCATIONS:
		if absf(at.x - location.x) < 0.9 and absf(at.z - location.z) < 0.82:
			return false
	return true

func _grid_id(point: Vector2) -> Vector2i:
	var id := Vector2i(((point - WALK_MIN) / WALK_CELL).round())
	id.x = clampi(id.x, 0, _navigation.region.size.x - 1)
	id.y = clampi(id.y, 0, _navigation.region.size.y - 1)
	if not _navigation.is_point_solid(id):
		return id
	for radius in range(1, 7):
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				var candidate := id + Vector2i(dx, dy)
				if _navigation.is_in_boundsv(candidate) and not _navigation.is_point_solid(candidate):
					return candidate
	return id

func _process(delta: float) -> void:
	if not _active:
		return
	_comment_clock += maxf(0.0, delta)
	if _bubble_remaining > 0.0:
		_bubble_remaining = maxf(0.0, _bubble_remaining - delta)
		if _bubble_remaining <= 0.0:
			_clear_bubble()
	for index in range(visitors.size()):
		_advance_visitor(index, delta)
	if not bubble_visible and _comment_clock >= _next_comment_at:
		_try_comment()
	_update_bubble_position()

func _choose_next_visit(index: int, first: bool = false) -> void:
	var state: Dictionary = _visitor_states[index]
	var displayed: Array = _entries.keys()
	displayed.sort()
	var slot := -1
	var destination: Vector3
	var visit_index := index * 2 if first else int(state.visits) + 1
	state.visits = visit_index
	if displayed.is_empty():
		var waiting := [Vector3(-3.6, 0, 0.35), Vector3(3.6, 0, 0.35), Vector3(0, 0, 3.8)]
		destination = waiting[posmod(visit_index, waiting.size())]
	else:
		slot = int(displayed[posmod(visit_index, displayed.size())])
		# Visitors inspect the actual model from a free spot just in front of it.
		# Different standing spots keep a single-exhibit crowd from collapsing
		# into one mesh while retaining a clear aisle in front of every stand.
		destination = LOCATIONS[slot] + Vector3((index - 1) * 0.55, 0, 1.1 + (index % 2) * 0.12)
	state.target_slot = slot
	state.phase = "walk"
	state.dwell = 0.0
	state.path_index = 0
	var visitor := visitors[index]
	var from := _grid_id(Vector2(visitor.position.x, visitor.position.z))
	var to := _grid_id(Vector2(destination.x, destination.z))
	state.path = _navigation.get_point_path(from, to)
	if state.path.is_empty():
		state.phase = "view"
		state.dwell = 6.0

func _advance_visitor(index: int, delta: float) -> void:
	var visitor := visitors[index]
	var state: Dictionary = _visitor_states[index]
	var previous := visitor.position
	if state.phase == "walk":
		var path: PackedVector2Array = state.path
		var budget := WALK_SPEED * maxf(0.0, delta)
		while int(state.path_index) < path.size() and budget > 0.0:
			var point := path[int(state.path_index)]
			var target := Vector3(point.x, visitor.position.y, point.y)
			var offset := target - visitor.position
			var length := offset.length()
			var step := minf(budget, length)
			if length > 0.00001:
				var candidate := visitor.position + offset * (step / length)
				if not _walkable(candidate):
					break
				visitor.position = candidate
			budget -= step
			if length <= step + 0.00001:
				state.path_index = int(state.path_index) + 1
			else:
				break
		if int(state.path_index) >= path.size():
			state.phase = "view"
			state.dwell = 7.0 + index * 1.4
	else:
		if not (bubble_visible and bubble_visitor == index):
			state.dwell = float(state.dwell) - delta
		if float(state.dwell) <= 0.0:
			_choose_next_visit(index)
	var actual := visitor.position - previous
	var moving := actual.length_squared() > 0.000001
	if moving:
		visitor.rotation.y = lerp_angle(visitor.rotation.y, atan2(actual.x, actual.z), 1.0 - exp(-delta * 9.0))
	elif state.phase == "view" and int(state.target_slot) >= 0:
		var facing: Vector3 = LOCATIONS[int(state.target_slot)] - visitor.position
		visitor.rotation.y = lerp_angle(visitor.rotation.y, atan2(facing.x, facing.z), 1.0 - exp(-delta * 7.0))
	visitor.animate(delta, moving)

func _build_bubble() -> void:
	var layer := CanvasLayer.new()
	layer.name = "VisitorCommentLayer"
	layer.layer = 5
	add_child(layer)
	_bubble = PanelContainer.new()
	_bubble.name = "VisitorCommentBubble"
	_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble.custom_minimum_size = Vector2(210, 68)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#fff2dc")
	style.border_color = Color("#b59b77")
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	_bubble.add_theme_stylebox_override("panel", style)
	layer.add_child(_bubble)
	_bubble_label = Label.new()
	_bubble_label.name = "VisitorCommentText"
	_bubble_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble_label.add_theme_font_size_override("font_size", 18)
	_bubble_label.add_theme_color_override("font_color", Color("#393b47"))
	_bubble_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bubble_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# Every reaction already contains at most two short, deliberate lines.
	# Wrapping before the first container layout sees a zero-width label and
	# caches one glyph per line as the panel's minimum height.
	_bubble_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_bubble.add_child(_bubble_label)
	_bubble_tail = Polygon2D.new()
	_bubble_tail.name = "CommentTail"
	_bubble_tail.polygon = PackedVector2Array([Vector2(-6, -1), Vector2(6, -1), Vector2(0, 8)])
	_bubble_tail.color = style.bg_color
	_bubble.add_child(_bubble_tail)
	_bubble.resized.connect(_update_bubble_position)
	_bubble.hide()

func _clear_bubble() -> void:
	bubble_text = ""
	bubble_slot = -1
	bubble_visitor = -1
	_bubble_remaining = 0.0
	if is_instance_valid(_bubble):
		_bubble.hide()
		_bubble_label.text = ""

func _try_comment() -> void:
	for offset in range(visitors.size()):
		var index := posmod(_speaker_cursor + offset, visitors.size())
		var state: Dictionary = _visitor_states[index]
		if state.phase != "view":
			continue
		var slot := int(state.target_slot)
		if not _entries.is_empty() and not _entries.has(slot):
			continue
		bubble_visitor = index
		bubble_slot = slot if _entries.has(slot) else -1
		bubble_text = VisitorComments.comment_for(_entries[slot], _comment_count) if _entries.has(slot) else VisitorComments.empty_comment(_comment_count)
		_bubble_label.text = bubble_text
		_bubble_remaining = 4.0
		# Compute from the actual two-line text, independent of previous width.
		# This also allows a wider glyph run to expand horizontally, not turn
		# the first bubble into a tall, stale minimum-size column.
		_bubble.reset_size()
		_bubble.show()
		_comment_count += 1
		_speaker_cursor = (index + 1) % visitors.size()
		_next_comment_at = _comment_clock + 7.0 + float(_comment_count % 5)
		return
	# Nobody has reached a real exhibit yet; don't invent a reaction en route.
	_next_comment_at = _comment_clock + 0.25

func _update_bubble_position() -> void:
	if not bubble_visible or bubble_visitor < 0 or not is_instance_valid(camera):
		return
	var head := camera.unproject_position(visitors[bubble_visitor].position + Vector3.UP * 1.02)
	var desired := head - Vector2(_bubble.size.x * 0.5, _bubble.size.y + 13)
	_bubble.position = Vector2(clampf(desired.x, 6, maxf(6, _viewport_size.x - _bubble.size.x - 6)),
		clampf(desired.y, 6, maxf(6, _viewport_size.y - _bubble.size.y - 14)))
	_bubble_tail.position = Vector2(clampf(head.x - _bubble.position.x, 12, _bubble.size.x - 12), _bubble.size.y)
