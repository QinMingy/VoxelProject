extends SceneTree

const TouchControls = preload("res://touch_controls.gd")
var controls: TouchControls
var saved: Array[Dictionary] = []
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, description: String) -> void:
	if not value:
		failures.append(description)
		push_error("TOUCH LAYOUT FAIL: " + description)

func touch(index: int, at: Vector2, pressed: bool = true) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = at
	event.pressed = pressed
	root.push_input(event)

func drag(index: int, at: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = at
	event.relative = Vector2.ZERO
	event.screen_relative = Vector2.ZERO
	root.push_input(event)

func press_button(name: String) -> void:
	(controls.find_child(name, true, false) as Button).pressed.emit()

func center_of(id: String) -> Vector2:
	return controls._control(id).get_global_rect().get_center()

func run() -> void:
	root.size = Vector2i(1100, 720)
	controls = TouchControls.new()
	root.add_child(controls)
	controls.layout_saved.connect(func(layout: Dictionary) -> void: saved.append(layout))
	controls.set_enabled(true)
	for frame in range(3):
		await process_frame
	var joystick_start := center_of("joystick")
	press_button("TouchLayoutGear")
	await process_frame
	check(controls.is_editing(), "gear enters layout edit mode")
	check((controls.find_child("TouchEditBar", true, false) as Control).visible, "edit toolbar is visible")

	touch(0, joystick_start)
	drag(0, joystick_start + Vector2(80, -40))
	await process_frame
	touch(0, joystick_start + Vector2(80, -40), false)
	await process_frame
	var entry: Dictionary = controls.current_layout().get("joystick", {})
	check(not entry.is_empty() and float(entry.x) > 0.0 and float(entry.y) > 0.0, "dragging records a normalized position")
	check(center_of("joystick").distance_to(joystick_start + Vector2(80, -40)) < 14, "the control follows the finger")

	var jump_center := center_of("jump")
	touch(1, jump_center)
	touch(1, jump_center, false)
	press_button("TouchEditGrow")
	await process_frame
	check(absf(float(controls.current_layout().get("jump", {}).get("scale", 0.0)) - 1.1) < 0.001,
		"size buttons scale the selected control")

	press_button("TouchEditSave")
	await process_frame
	check(not controls.is_editing() and saved.size() == 1, "save exits editing and reports the layout")
	var payload: Dictionary = saved[0]
	check(payload.has("joystick") and payload.has("jump"), "saved layout carries the moved controls")

	controls.enter_edit_mode()
	await process_frame
	var before_cancel := controls.current_layout().duplicate(true)
	touch(2, center_of("jump"))
	drag(2, center_of("jump") + Vector2(-120, 80))
	await process_frame
	touch(2, center_of("jump") + Vector2(-120, 80), false)
	press_button("TouchEditCancel")
	await process_frame
	check(controls.current_layout() == before_cancel and not controls.is_editing(), "cancel restores the previous layout")

	controls.enter_edit_mode()
	await process_frame
	press_button("TouchEditReset")
	await process_frame
	check(controls.current_layout().is_empty(), "reset previews the default layout")
	press_button("TouchEditCancel")
	await process_frame

	var restored := TouchControls.new()
	root.add_child(restored)
	restored.set_enabled(true)
	restored.apply_layout(payload)
	for frame in range(2):
		await process_frame
	var jump_norm: Dictionary = restored.current_layout()["jump"]
	root.size = Vector2i(1600, 720)
	await process_frame
	restored._layout_controls()
	await process_frame
	var resized_center: Vector2 = restored._buttons["jump"].get_global_rect().get_center()
	check(absf(resized_center.x - float(jump_norm.x) * 1600.0) < 40.0
		and absf(resized_center.y - float(jump_norm.y) * 720.0) < 40.0,
		"normalized layout follows a viewport resize")
	restored.queue_free()
	controls.queue_free()
	await process_frame
	if failures.is_empty():
		print("TOUCH_LAYOUT_OK gear=true drag=true scale=true save=true cancel=true reset=true normalized_resize=true")
	quit(0 if failures.is_empty() else 1)
