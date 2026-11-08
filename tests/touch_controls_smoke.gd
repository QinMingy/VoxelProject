extends SceneTree

const TouchControls = preload("res://touch_controls.gd")
const GMPanel = preload("res://gm_panel.gd")
var controls: TouchControls
var looks: Array[Vector2] = []
var actions: Array[String] = []
var touch_toggles: Array[bool] = []
var audio_toggles: Array[bool] = []


func _initialize() -> void:
	call_deferred("run")


func check(value: bool, description: String) -> void:
	if not value:
		push_error("TOUCH FAIL: " + description)
		quit(1)
		assert(value, description)


func point(name: String) -> Vector2:
	return (controls.find_child(name, true, false) as Control).get_global_rect().get_center()


func touch(index: int, at: Vector2, pressed: bool = true, canceled: bool = false, device: int = 0) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = at
	event.pressed = pressed
	event.canceled = canceled
	event.device = device
	root.push_input(event)


func drag(index: int, at: Vector2, delta: Vector2, unscaled: Vector2 = Vector2.ZERO) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = at
	event.relative = delta
	event.screen_relative = unscaled
	root.push_input(event)


func mouse(at: Vector2, pressed: bool, device: int = 0) -> void:
	var event := InputEventMouseButton.new()
	event.position = at
	event.global_position = at
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	event.device = device
	root.push_input(event, true)


func run() -> void:
	root.size = Vector2i(1100, 720)
	controls = TouchControls.new()
	root.add_child(controls)
	controls.look_changed.connect(func(delta: Vector2) -> void: looks.append(delta))
	controls.action_pressed.connect(func(action: String) -> void: actions.append(action))
	controls.set_enabled(true)
	for frame in range(3):
		await process_frame
	var stick := point("TouchJoystick")
	var mine := point("TouchMine")
	var jump := point("TouchJump")
	var free_look := Vector2(620, 340)
	touch(0, stick)
	drag(0, stick + Vector2(65, -45), Vector2(65, -45))
	var movement := controls.movement_vector()
	check(movement.x > 0.0 and movement.y < 0.0 and movement.length() <= 1.0, "left finger creates bounded movement")
	touch(1, mine)
	check(controls.mining_held() and controls.movement_vector() == movement, "two fingers move and mine simultaneously")
	drag(1, mine + Vector2(32, -18), Vector2(16, -9), Vector2(32, -18))
	check(looks.size() == 1 and looks[0] == Vector2(32, -18), "mining finger uses unscaled look delta")
	check(controls.mining_held() and controls.movement_vector() == movement, "turning while mining preserves joystick")
	controls.set_enabled(true)
	controls.set_gameplay_active(true)
	check(controls.mining_held() and controls.movement_vector() == movement, "repeated state sync never drops active fingers")
	touch(1, mine, false)
	check(not controls.mining_held() and controls.movement_vector() == movement, "lifting mining finger keeps movement")
	touch(1, mine)
	touch(0, stick, false)
	check(controls.mining_held() and controls.movement_vector().is_zero_approx(), "lifting joystick keeps mining")
	drag(1, Vector2(450, 250), Vector2(-20, 9))
	check(controls.mining_held() and looks.back() == Vector2(-20, 9), "dragging outside mining pad keeps finger ownership")
	touch(2, jump)
	check(controls.jump_held() and controls.mining_held(), "third finger may hold jump independently")
	touch(2, jump, false)
	check(not controls.jump_held() and controls.mining_held(), "jump release does not release mining")
	touch(1, mine, false, true)
	check(not controls.mining_held(), "canceled touch releases held state")
	touch(3, free_look)
	drag(3, free_look + Vector2(15, 6), Vector2(15, 6))
	check(not controls.mining_held() and looks.back() == Vector2(15, 6), "background right drag turns without mining")
	touch(3, free_look, false)

	var pickup := point("TouchPickup")
	touch(4, pickup)
	mouse(pickup, true, InputEvent.DEVICE_ID_EMULATION)
	mouse(pickup, false, InputEvent.DEVICE_ID_EMULATION)
	touch(4, pickup, false)
	check(actions == ["pickup"], "native touch plus synthesized mouse triggers one action")
	for pair: Array in [["TouchInteract", "interact"], ["TouchBackpack", "backpack"], ["TouchView", "view"], ["TouchHelp", "help"], ["TouchBase", "base"]]:
		touch(5, point(pair[0]))
		touch(5, point(pair[0]), false)
		check(actions.back() == pair[1], "touch action routes " + pair[1])

	mouse(mine, true)
	touch(0, mine, true, false, InputEvent.DEVICE_ID_EMULATION)
	var motion := InputEventMouseMotion.new()
	motion.position = mine + Vector2(21, 3)
	motion.relative = Vector2(21, 3)
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(motion, true)
	check(controls.mining_held() and looks.back() == Vector2(21, 3), "desktop one-finger mouse supports hold-and-drag")
	mouse(mine, false)
	check(not controls.mining_held(), "emulated touch cannot leave duplicate mouse ownership")

	touch(0, stick + Vector2(55, 0))
	touch(1, mine)
	controls.set_gameplay_active(false)
	check(not controls.mining_held() and controls.movement_vector().is_zero_approx(), "opening a modal clears held fingers immediately")
	var count := actions.size()
	touch(8, pickup)
	check(actions.size() == count, "inactive controls do not interact behind menus")
	controls.set_gameplay_active(true)
	drag(1, mine, Vector2(5, 2))
	check(not controls.mining_held(), "old finger cannot resume after a modal closes")
	touch(1, mine)
	paused = true
	await process_frame
	check(not controls.mining_held() and controls._owners.is_empty(), "tree pause releases held touches even without caller sync")
	paused = false
	await process_frame
	touch(1, mine)
	controls.set_enabled(false)
	controls.set_enabled(true)
	check(not controls.mining_held(), "mode switch clears ownership")
	touch(1, mine)
	controls.get_window().focus_exited.emit()
	check(not controls.mining_held() and controls._owners.is_empty(), "focus loss clears ownership")
	controls.get_window().focus_entered.emit()
	touch(1, mine)
	controls.hide()
	await process_frame
	check(not controls.mining_held() and controls._owners.is_empty(), "hiding controls clears ownership")
	controls.show()
	await process_frame

	var gm := GMPanel.new()
	root.add_child(gm)
	gm.touch_mode_changed.connect(func(value: bool) -> void: touch_toggles.append(value))
	gm.audio_enabled_changed.connect(func(value: bool) -> void: audio_toggles.append(value))
	gm.sync_state({"touch_mode": true, "audio_enabled": false})
	check(touch_toggles.is_empty() and audio_toggles.is_empty(), "GM sync does not emit user changes")
	var touch_check: CheckBox = gm.find_child("TouchMode", true, false)
	var audio_check: CheckBox = gm.find_child("AudioEnabled", true, false)
	check(touch_check.button_pressed and not audio_check.button_pressed, "GM displays synchronized touch and audio modes")
	touch_check.button_pressed = false
	audio_check.button_pressed = true
	check(touch_toggles == [false] and audio_toggles == [true], "GM emits explicit mode and mute changes")
	for frame in range(3):
		await process_frame
	var entry: Button = gm.find_child("GMEntryButton", true, false)
	var entry_point := entry.get_global_rect().get_center()
	touch(9, entry_point)
	check(not controls._owners.has(9), "GM corner is never claimed for look or mining")
	var entry_motion := InputEventMouseMotion.new()
	entry_motion.position = entry_point
	entry_motion.global_position = entry_point
	entry_motion.device = InputEvent.DEVICE_ID_EMULATION
	root.push_input(entry_motion, true)
	mouse(entry_point, true, InputEvent.DEVICE_ID_EMULATION)
	mouse(entry_point, false, InputEvent.DEVICE_ID_EMULATION)
	check(gm.is_open, "emulated mouse still clicks normal GM GUI")
	gm.close()
	controls.release_all()
	var jump_button: Button = controls._buttons["jump"]
	var jump_style := jump_button.get_theme_stylebox("normal") as StyleBoxFlat
	check(is_equal_approx(jump_button.size.x, jump_button.size.y) and jump_button.size.y >= 90.0 * controls._layout_scale,
		"jump button is large and square before the circular clip")
	check(jump_style.corner_radius_top_left >= int(jump_button.size.x * 0.5) - 1,
		"jump button uses a full circular corner radius")
	var before_hidden := actions.size()
	controls.set_action_available("pickup", false)
	await process_frame
	check(not (controls.find_child("TouchPickup", true, false) as Button).visible, "unavailable pickup hides its button")
	touch(11, pickup)
	touch(11, pickup, false)
	check(actions.size() == before_hidden, "hidden pickup cannot be triggered")
	controls.set_action_available("pickup", true)
	await process_frame
	check((controls.find_child("TouchPickup", true, false) as Button).visible, "pickup returns when available")
	check((controls.find_child("TouchLayoutGear", true, false) as Button).visible, "layout gear is visible while playing")
	print("TOUCH_CONTROLS_OK multitouch independent_release drag_mine look_only actions mouse_no_duplicates modal_pause_focus_hide GM_toggle GM_corner audio_toggle conditional_actions jump_circle layout_gear")
	quit(0)
