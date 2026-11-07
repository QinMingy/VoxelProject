extends SceneTree

const Crystal = preload("res://crystal.gd")
const Detector = preload("res://detector.gd")
const RadarPanel = preload("res://detector_panel.gd")
var failed := false

func _initialize() -> void:
	call_deferred("run")

func require(ok: bool, description: String) -> void:
	if not ok:
		failed = true
		push_error("MULTI DETECTOR FAIL: " + description)
		quit(1)
		assert(ok, description)

func make_crystal(at: Vector3) -> Crystal:
	var item := Crystal.new()
	root.add_child(item)
	item.position = at
	return item

func marker(markers: Array, item: Node) -> Dictionary:
	for entry: Dictionary in markers:
		if entry.id == item.get_instance_id():
			return entry
	require(false, "every sampled crystal has a layout record")
	return {}

func run() -> void:
	var panel := RadarPanel.new()
	root.add_child(panel)
	require(not panel.visible and panel.mouse_filter == Control.MOUSE_FILTER_IGNORE, "HUD starts hidden and ignores mouse")
	require(panel.display_mode == RadarPanel.Mode.CIRCLE, "circular radar is the default mode")
	panel.set_display_mode(RadarPanel.Mode.COMPASS)
	var front := make_crystal(Vector3(0, 0, -3))
	var distant := make_crystal(Vector3(0, 0, -8))
	var right := make_crystal(Vector3(5, 0, 0))
	var left := make_crystal(Vector3(-5, 0, 0))
	var back := make_crystal(Vector3(0, 0, 6))
	var items: Array = [back, left, distant, front, right]
	var reading := Detector.sample(Vector3.ZERO, Vector3.FORWARD, items, null, 0)
	panel.set_reading(reading)
	panel.set_enabled(true)
	var layout: Array = panel.marker_layout().duplicate(true)
	require(layout.size() == items.size(), "level zero lays out every detected object")
	var near_marker := marker(layout, front)
	var far_marker := marker(layout, distant)
	var center_x: float = near_marker.position.x
	require(marker(layout, right).position.x > center_x and marker(layout, left).position.x < center_x, "compass east is right and west is left")
	require(near_marker.radius > far_marker.radius and near_marker.alpha > far_marker.alpha, "closer objects are larger and brighter")
	require(is_equal_approx(near_marker.position.x, far_marker.position.x), "targets with the same bearing keep identical horizontal positions")
	require(not panel._depth_label.visible and not panel._size_label.visible, "base detector does not reveal locked depth or size")
	require("m" in panel._echo_label.text, "nearest readout uses horizontal metres")

	var north_positions: Array[float] = []
	for heading in [-0.02, 0.02]:
		var forward := Vector3(sin(heading), 0, -cos(heading))
		panel.set_reading(Detector.sample(Vector3.ZERO, forward, [front], null, 0))
		north_positions.append(marker(panel.marker_layout(), front).position.x)
	require(north_positions[0] > center_x and north_positions[1] < center_x, "turning across north moves target through strip centre in the correct direction")
	require(absf(north_positions[0] - north_positions[1]) < 20.0, "north heading wrap cannot fling a marker across the strip")
	panel.set_reading(Detector.sample(Vector3.ZERO, Vector3(0, -0.98, -0.2).normalized(), items, null, 0))
	var pitched: Array = panel.marker_layout()
	for item in items:
		require(marker(pitched, item).position.is_equal_approx(marker(layout, item).position), "camera pitch leaves each compass marker unchanged")

	# Same-bearing crowded targets must aggregate without inventing sideways bearings.
	var crowded: Array = []
	for index in range(6):
		crowded.append(make_crystal(Vector3(0, 0, -2.0 - float(index))))
	panel.set_reading(Detector.sample(Vector3.ZERO, Vector3.FORWARD, crowded, null, 0))
	var grouped: Array = panel.marker_layout()
	var visible_count := 0
	var represented_count := 0
	var lanes := {}
	var visible_ids := {}
	require(grouped.size() == crowded.size(), "aggregation preserves one traceable record per object")
	for entry: Dictionary in grouped:
		require(is_equal_approx(entry.position.x, center_x), "overlap handling never shifts a target to a false bearing")
		if entry.visible:
			visible_count += 1
			represented_count += int(entry.count)
			lanes[int(entry.lane)] = true
			visible_ids[int(entry.id)] = true
	for entry: Dictionary in grouped:
		if not entry.visible:
			require(visible_ids.has(int(entry.aggregated_into)), "overflow records identify an actual visible aggregate")
	require(visible_count == 3 and lanes.size() == 3 and represented_count == 6, "three lanes plus aggregate counts represent all six overlapping objects")

	panel.set_display_mode(RadarPanel.Mode.CIRCLE)
	require(panel.display_mode == RadarPanel.Mode.CIRCLE, "mode API switches to circular radar")
	require(panel._direction_label.visible and not panel._direction_label.text.is_empty(), "base circle detector displays nearest direction")
	var circles: Array = panel.marker_layout()
	require(circles.size() == 6, "circle retains the same target set after switching")
	for entry: Dictionary in circles:
		require(entry.visible and int(entry.lane) == -1, "circle renders every echo without strip lanes")
	panel.set_reading(reading)
	circles = panel.marker_layout()
	var center: Vector2 = RadarPanel.RADAR_CENTER
	require(marker(circles, right).position.x > center.x and marker(circles, left).position.x < center.x, "circular radar displays both left and right objects")
	require(marker(circles, front).position.y < center.y and marker(circles, back).position.y > center.y, "circular radar includes front and rear objects")
	require(marker(circles, front).position.distance_to(center) < marker(circles, distant).position.distance_to(center), "circle radial distance reflects physical horizontal proximity")
	require(marker(circles, front).radius > marker(circles, distant).radius and marker(circles, front).alpha > marker(circles, distant).alpha, "circle uses larger and brighter nearby markers")
	# An underground item at the player's X/Z must reach the arrow exactly.
	# Physical 3D distance still controls detection and visual prominence.
	var beneath := make_crystal(Vector3(0, -2, 0))
	var too_deep := make_crystal(Vector3(0, -10.01, 0))
	panel.set_reading(Detector.sample(Vector3.ZERO, Vector3.FORWARD, [beneath, too_deep], null, 0))
	var centred: Array = panel.marker_layout()
	require(centred.size() == 1 and int(centred[0].id) == beneath.get_instance_id(), "an item beneath the player is detected but an out-of-range deep item is excluded")
	require(marker(centred, beneath).position.is_equal_approx(center) and panel.target_offset().is_zero_approx(), "same X/Z aligns the echo with the player arrow without a radial dead zone")
	var previous_radius := -1.0
	for horizontal_distance: float in [0.0, 0.02, 0.2, 1.0, 4.0]:
		beneath.position = Vector3(horizontal_distance, -2, 0)
		panel.set_reading(Detector.sample(Vector3.ZERO, Vector3.FORWARD, [beneath], null, 0))
		var point: Vector2 = marker(panel.marker_layout(), beneath).position
		var radius := point.distance_to(center)
		require(is_equal_approx(radius, 54.0 * horizontal_distance / 10.0), "radial displacement is proportional to real horizontal distance down to zero")
		require(radius > previous_radius, "approaching or leaving the centre changes marker position smoothly")
		previous_radius = radius
	beneath.position = Vector3(1, -2, 0)
	var lower := make_crystal(Vector3(1, -8, 0))
	panel.set_reading(Detector.sample(Vector3.ZERO, Vector3.FORWARD, [beneath, lower], null, 0))
	var same_horizontal: Array = panel.marker_layout()
	require(marker(same_horizontal, beneath).position.is_equal_approx(marker(same_horizontal, lower).position), "burial depth does not invent horizontal separation")
	require(marker(same_horizontal, beneath).radius > marker(same_horizontal, lower).radius, "different depths retain their true 3D-distance marker sizes")
	front.collected = true
	panel.set_reading(Detector.sample(Vector3.ZERO, Vector3.FORWARD, items, null, 0))
	require(panel.marker_layout().size() == 4, "collecting one object removes exactly its marker")
	front.collected = false
	panel.set_reading(reading)
	await process_frame
	var sweep: float = panel._sweep_angle
	paused = true
	await process_frame
	await process_frame
	require(is_equal_approx(panel._sweep_angle, sweep), "paused game freezes detector animation")
	paused = false
	for mode in [RadarPanel.Mode.CIRCLE, RadarPanel.Mode.COMPASS]:
		panel.set_display_mode(mode)
		panel.set_reading(Detector.sample(Vector3.ZERO, Vector3.FORWARD, [], null, 0))
		require(panel.marker_layout().is_empty() and panel._echo_label.text == "无目标", "empty readings clear stale markers and text in both modes")
	panel.set_reading(reading)
	panel.set_enabled(false)
	require(not panel.visible and not panel.is_processing(), "disabled HUD remains hidden and stops processing")
	print("DETECTOR_MULTI_OK default_circle=true modes=true all_targets=true compass_signs_northwrap=true near_size_alpha=true aggregation_preserves_bearing=true circle_front_back=true exact_centre_overlap=true no_radial_deadzone=true depth_range=true empty=true paused=true")
	quit(1 if failed else 0)
