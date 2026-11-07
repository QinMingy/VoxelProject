extends Control

signal layout_changed

enum Mode { COMPASS, CIRCLE }

const UI = preload("res://ui_style.gd")
const CIRCLE_WIDTH := 320.0
const CIRCLE_HEIGHT := 220.0
const WIDTH := CIRCLE_WIDTH
const HEIGHT := CIRCLE_HEIGHT
const COMPASS_WIDTH := 640.0
const COMPASS_HEIGHT := 112.0
const COMPASS_PADDING := 24.0
const COMPASS_USABLE_WIDTH := COMPASS_WIDTH - COMPASS_PADDING * 2.0
const COMPASS_LANES := [68.0, 85.0, 102.0]
const CARDINALS := ["北", "东", "南", "西"]
const RADAR_CENTER := Vector2(82.0, 134.0)
const RADAR_RADIUS := 60.0

var display_mode := Mode.COMPASS
var _reading: Dictionary = {}
var _markers: Array[Dictionary] = []
var _enabled := false
var _strength := 0.0
var _sweep_angle := 0.0
var _background: StyleBoxFlat
var _title_label: Label
var _tier_label: Label
var _front_label: Label
var _caption_label: Label
var _echo_label: Label
var _direction_label: Label
var _depth_label: Label
var _size_label: Label

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UI.theme()
	_background = UI.panel()
	_title_label = _label(UI.TEXT)
	_title_label.text = "晶石探测"
	_tier_label = _label(UI.MUTED)
	_tier_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_front_label = _label(UI.MUTED)
	_front_label.text = "前"
	_front_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption_label = _label(UI.MUTED)
	_echo_label = _label(UI.ACCENT)
	_direction_label = _label(UI.TEXT)
	_depth_label = _label(UI.TEXT)
	_size_label = _label(UI.TEXT)
	_update_labels()
	_apply_layout()
	set_enabled(_enabled)

func _label(color: Color) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", color)
	add_child(label)
	return label

func _place_label(label: Label, bounds: Rect2, font_size: int) -> void:
	label.add_theme_font_size_override("font_size", font_size)
	label.position = bounds.position
	label.size = bounds.size

func set_display_mode(mode: int) -> void:
	var selected := Mode.CIRCLE if mode == Mode.CIRCLE else Mode.COMPASS
	if display_mode == selected:
		return
	display_mode = selected
	_update_markers()
	if is_node_ready():
		_update_labels()
		_apply_layout()
		layout_changed.emit()
	queue_redraw()

func _apply_layout() -> void:
	if display_mode == Mode.COMPASS:
		set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		offset_left = -COMPASS_WIDTH * 0.5
		offset_right = COMPASS_WIDTH * 0.5
		offset_top = 16.0
		offset_bottom = offset_top + COMPASS_HEIGHT
		_place_label(_title_label, Rect2(16, 4, 106, 24), 20)
		_place_label(_echo_label, Rect2(126, 4, 116, 24), 18)
		_place_label(_depth_label, Rect2(246, 4, 62, 24), 18)
		_place_label(_size_label, Rect2(310, 4, 76, 24), 18)
		_place_label(_tier_label, Rect2(389, 4, 235, 24), 18)
		return
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -CIRCLE_WIDTH - 24.0
	offset_right = -24.0
	offset_top = 24.0
	offset_bottom = offset_top + CIRCLE_HEIGHT
	_place_label(_title_label, Rect2(16, 10, 166, 38), 28)
	_place_label(_tier_label, Rect2(184, 10, 120, 38), 18)
	_place_label(_front_label, Rect2(58, 52, 48, 22), 18)
	_place_label(_caption_label, Rect2(164, 57, 140, 22), 18)
	_place_label(_echo_label, Rect2(164, 79, 140, 42), 32)
	_place_label(_direction_label, Rect2(164, 124, 140, 28), 20)
	_place_label(_depth_label, Rect2(164, 152, 140, 28), 20)
	_place_label(_size_label, Rect2(164, 180, 140, 28), 20)

func set_enabled(enabled: bool) -> void:
	_enabled = enabled
	visible = enabled
	set_process(enabled)

func set_reading(data: Dictionary) -> void:
	_reading = data
	_strength = clampf(float(data.get("strength", 0.0)), 0.0, 1.0)
	_update_markers()
	if is_node_ready():
		_update_labels()
	queue_redraw()

func _update_labels() -> void:
	var level := int(_reading.get("level", 0))
	var range_m := int(_reading.get("range_m", 10))
	var count := _markers.size()
	var available := count > 0
	var circle := display_mode == Mode.CIRCLE
	var nearest_distance := float(_reading.get("horizontal_distance_m", 0.0))
	_front_label.visible = circle
	_caption_label.visible = circle
	_tier_label.text = ("Lv.%d  ·  %d m" % [level, range_m]) if circle else ("Lv.%d  ·  %d 颗  ·  %d m" % [level, count, range_m])
	_caption_label.text = "最近晶石 · %d 颗" % count
	if not available:
		_echo_label.text = "无晶石"
	else:
		_echo_label.text = ("%.1f m" if circle else "最近 %.1f m") % nearest_distance
	_echo_label.add_theme_color_override("font_color", UI.ACCENT if available else UI.MUTED)
	_update_field(_direction_label, "direction_text", available and circle)
	_update_field(_depth_label, "depth_text", available and level >= 2)
	_update_field(_size_label, "size_text", available and level >= 3, "体积")

func _update_field(label: Label, key: String, enabled: bool, suffix: String = "") -> void:
	var value := str(_reading.get(key, ""))
	label.visible = enabled and not value.is_empty()
	label.text = value + suffix if label.visible else ""

func target_offset() -> Vector2:
	if _markers.is_empty():
		return Vector2.ZERO
	return _circle_offset(_markers[0])

func marker_layout() -> Array[Dictionary]:
	return _markers

func _circle_offset(marker: Dictionary) -> Vector2:
	var bearing := float(marker.get("bearing_radians", 0.0))
	var distance := float(marker.get("horizontal_distance_m", 0.0))
	var range_m := maxf(0.01, float(_reading.get("range_m", 10.0)))
	var radius := lerpf(14.0, 54.0, clampf(distance / range_m, 0.0, 1.0))
	return Vector2(sin(bearing), -cos(bearing)) * radius

func _compass_x(bearing: float) -> float:
	return COMPASS_WIDTH * 0.5 + clampf(bearing, -PI, PI) / TAU * COMPASS_USABLE_WIDTH

func _update_markers() -> void:
	_markers = []
	var echoes: Array = _reading.get("echoes", [])
	var ordered := echoes.duplicate()
	ordered.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_distance := float(left.distance_m)
		var right_distance := float(right.distance_m)
		if left_distance == right_distance:
			return int(left.id) < int(right.id)
		return left_distance < right_distance
	)
	var lanes := [[], [], []]
	var range_m := maxf(0.01, float(_reading.get("range_m", 10.0)))
	for echo: Dictionary in ordered:
		var distance := float(echo.distance_m)
		var fraction := clampf(distance / range_m, 0.0, 1.0)
		var maximum_radius := 8.0 if display_mode == Mode.COMPASS else 9.0
		var marker := {
			"id": int(echo.id), "position": Vector2.ZERO, "radius": lerpf(maximum_radius, 4.0, fraction),
			"alpha": lerpf(1.0, 0.35, fraction), "bearing_radians": float(echo.bearing_radians),
			"distance_m": distance, "horizontal_distance_m": float(echo.horizontal_distance_m),
			"lane": -1, "visible": true, "count": 1, "aggregated_into": -1,
		}
		if display_mode == Mode.COMPASS:
			_place_compass_marker(marker, lanes)
		else:
			marker.position = RADAR_CENTER + _circle_offset(marker)
		_markers.append(marker)

func _place_compass_marker(marker: Dictionary, lanes: Array) -> void:
	var x := _compass_x(float(marker.bearing_radians))
	var closest_overlap := -1
	var closest_gap := INF
	for lane in range(COMPASS_LANES.size()):
		var blocked := false
		for index: int in lanes[lane]:
			var placed := _markers[index]
			var point: Vector2 = placed.position
			var gap := absf(point.x - x)
			if gap >= float(marker.radius) + float(placed.radius) + 2.0:
				continue
			blocked = true
			if gap < closest_gap:
				closest_gap = gap
				closest_overlap = index
		if not blocked:
			marker.lane = lane
			marker.position = Vector2(x, COMPASS_LANES[lane])
			lanes[lane].append(_markers.size())
			return
	var anchor := _markers[closest_overlap]
	anchor.count = int(anchor.count) + 1
	marker.lane = anchor.lane
	marker.position = Vector2(x, COMPASS_LANES[int(anchor.lane)])
	marker.visible = false
	marker.aggregated_into = anchor.id

func _process(delta: float) -> void:
	if _markers.is_empty():
		return
	_sweep_angle = fposmod(_sweep_angle + delta * (2.4 + 4.6 * _strength), TAU)
	if display_mode == Mode.CIRCLE:
		queue_redraw()

func _draw() -> void:
	draw_style_box(_background, Rect2(Vector2.ZERO, size))
	if display_mode == Mode.COMPASS:
		_draw_compass()
	else:
		_draw_circle()

func _draw_compass() -> void:
	draw_line(Vector2(16, 30), Vector2(COMPASS_WIDTH - 16, 30), UI.BORDER)
	draw_line(Vector2(COMPASS_PADDING, 56), Vector2(COMPASS_WIDTH - COMPASS_PADDING, 56), UI.BORDER)
	var heading := float(_reading.get("heading_radians", 0.0))
	var font := get_theme_default_font()
	for degree in range(0, 360, 15):
		var relative := wrapf(deg_to_rad(float(degree)) - heading, -PI, PI)
		var label := ""
		if degree % 90 == 0:
			label = CARDINALS[int(degree / 90.0)]
		elif degree % 30 == 0:
			label = "%d°" % degree
		_draw_tick(font, _compass_x(relative), label)
		if is_equal_approx(relative, -PI):
			_draw_tick(font, _compass_x(PI), label)
	var center := COMPASS_WIDTH * 0.5
	draw_colored_polygon(PackedVector2Array([
		Vector2(center - 6.0, 29.0), Vector2(center + 6.0, 29.0), Vector2(center, 36.0),
	]), UI.ACCENT)
	_draw_markers()

func _draw_tick(font: Font, x: float, label: String) -> void:
	var labeled := not label.is_empty()
	draw_line(Vector2(x, 50.0 if labeled else 53.0), Vector2(x, 57.0), UI.MUTED if labeled else UI.BORDER)
	if labeled:
		var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		draw_string(font, Vector2(x - width * 0.5, 47.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UI.TEXT)

func _draw_circle() -> void:
	draw_line(Vector2(16, 49), Vector2(CIRCLE_WIDTH - 16, 49), UI.BORDER)
	draw_circle(RADAR_CENTER, RADAR_RADIUS, Color("#0b1623"))
	for ring in range(1, 4):
		var radius := RADAR_RADIUS * float(ring) / 3.0
		draw_arc(RADAR_CENTER, radius, 0.0, TAU, 52, UI.BORDER, 1.0, true)
	for axis in [Vector2.RIGHT, Vector2.DOWN]:
		draw_line(RADAR_CENTER - axis * RADAR_RADIUS, RADAR_CENTER + axis * RADAR_RADIUS, UI.BORDER, 1.0, true)
	if not _markers.is_empty():
		var pulse := _sweep_angle / TAU
		var opacity := (1.0 - pulse) * (0.14 + 0.27 * _strength)
		draw_arc(RADAR_CENTER, lerpf(10.0, RADAR_RADIUS, pulse), 0.0, TAU, 52, Color(UI.ACCENT, opacity), 1.5, true)
	_draw_markers()
	draw_colored_polygon(PackedVector2Array([
		RADAR_CENTER + Vector2(0.0, -5.0),
		RADAR_CENTER + Vector2(4.5, 4.0),
		RADAR_CENTER + Vector2(-4.5, 4.0),
	]), Color.WHITE)

func _draw_markers() -> void:
	var font := get_theme_default_font()
	for index in range(_markers.size() - 1, -1, -1):
		var marker := _markers[index]
		if not bool(marker.visible):
			continue
		var point: Vector2 = marker.position
		var radius := float(marker.radius)
		var alpha := float(marker.alpha)
		draw_circle(point, radius + 1.25, Color(0.03, 0.07, 0.10, alpha))
		draw_circle(point, radius, Color(UI.ACCENT, alpha))
		var count := int(marker.count)
		if count > 1:
			var label := "×%d" % count
			var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
			var x := minf(point.x + radius + 3.0, COMPASS_WIDTH - width - 8.0)
			draw_string(font, Vector2(x, point.y + 5.5), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, UI.TEXT)
