extends "res://museum_lobby.gd"

# Warehouse and catalogue look into the same exhibition as the lobby. Only
# management camera/selection controls differ; there is one source for the art.
var _selected := 0
var _yaw := 0.0
var _zoom := 0.0
var _camera: Camera3D:
	get:
		return camera
var _selection: Node3D
var _summary: Dictionary = {}

func _ready() -> void:
	super._ready()
	_selection = Node3D.new()
	_selection.name = "SelectedExhibitionStand"
	add_child(_selection)
	for side: float in [-1.0, 1.0]:
		var edge_x := _box("SelectedStandEdgeX", Vector3(0, 0.035, side * 0.68),
			Vector3(1.5, 0.025, 0.045), Color("#ffc46e"), true)
		edge_x.reparent(_selection)
		var edge_z := _box("SelectedStandEdgeZ", Vector3(side * 0.75, 0.035, 0),
			Vector3(0.045, 0.025, 1.4), Color("#ffc46e"), true)
		edge_z.reparent(_selection)
	select_stand(_selected)
	_update_camera()

func set_collection(summary: Dictionary) -> void:
	_summary = summary.duplicate(true)
	super.set_collection(summary)
	select_stand(_selected)
	_update_labels()

func select_stand(slot: int) -> void:
	_selected = clampi(slot, 0, maxi(0, _capacity - 1))
	if is_instance_valid(_selection):
		_selection.position = LOCATIONS[_selected]
		_selection.visible = _capacity > 0
	_update_labels()

func set_viewport_size(dimensions: Vector2) -> void:
	super.set_viewport_size(dimensions)
	_update_camera()

func orbit(horizontal: float) -> void:
	_yaw = clampf(_yaw + horizontal, -0.55, 0.75)
	_update_camera()

func zoom(amount: float) -> void:
	_zoom = clampf(_zoom + amount, -1.0, 2.0)
	_update_camera()

func _update_camera() -> void:
	if not is_instance_valid(camera):
		return
	var target := Vector3(0, 0.25, 0.1)
	camera.position = target + Vector3(sin(_yaw) * 11.5, 12.5, cos(_yaw) * 11.5)
	camera.look_at(target)
	var aspect := _viewport_size.x / _viewport_size.y
	var extent := Vector2.ZERO
	# Fit the three exhibit zones at each orbit angle. The management view can
	# be much narrower than the full-screen hall.
	for x: float in [-6.05, 6.05]:
		for z: float in [-3.25, 3.75]:
			for y: float in [0.0, 2.0]:
				var point := camera.global_basis.inverse() * (Vector3(x, y, z) - target)
				extent.x = maxf(extent.x, absf(point.x))
				extent.y = maxf(extent.y, absf(point.y))
	camera.size = maxf(5.8, maxf(extent.y * 2.0, extent.x * 2.0 / aspect) + 0.35 + _zoom)
	_update_labels()

func _update_labels() -> void:
	if not is_instance_valid(camera):
		return
	var slots: Array = _summary.get("slots", [])
	var exhibits: Dictionary = _summary.get("exhibits", {})
	# Compact numeric labels match the six controls below. Full names and
	# condition already appear in the selected-item panel.
	for index in range(_signs.size()):
		var key := str(slots[index]) if index < slots.size() else ""
		var unlocked := index < _capacity
		_signs[index].text = "%02d" % (index + 1) if unlocked else "%02d · 锁" % (index + 1)
		if _viewport_size.x >= 800 and unlocked and exhibits.has(key):
			_signs[index].text += "\n" + str(exhibits[key].get("label", "藏品"))
		_signs[index].pixel_size = 16.0 * camera.size / (_viewport_size.y * _signs[index].font_size)
		_signs[index].modulate = Color("#ffcf86") if unlocked and index == _selected else (Color("#ece2d2") if unlocked else Color("#b0b6c0"))

func _process(delta: float) -> void:
	# The management view shares the same visitors and real exhibit reactions.
	super._process(delta)
