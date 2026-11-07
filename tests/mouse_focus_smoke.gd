extends SceneTree

const Main = preload("res://main.gd")
const Appraisal = preload("res://appraisal.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	create_timer(6.0).timeout.connect(func() -> void: quit(2))
	if DisplayServer.get_name() == "headless":
		push_error("Mouse focus check requires an actual window.")
		quit(1)
		return
	var game := Main.new()
	game.progression = Main.Progression.new("")
	game.progression.bank = 0
	game.auto_open_base = false
	game.appraisal = Appraisal.new("")
	game.wants_mouse_capture = false
	root.add_child(game)
	game.set_physics_process(false)
	root.grab_focus()
	await create_timer(0.15).timeout
	game.wants_mouse_capture = true
	game.capture_mouse()
	var yaw: float = game.view_yaw
	var pitch: float = game.view_pitch
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(600, -300)
	game._unhandled_input(motion)
	assert(is_equal_approx(yaw, game.view_yaw) and is_equal_approx(pitch, game.view_pitch), "Capture must ignore the centering motion")
	await process_frame
	await create_timer(0.25).timeout
	var center := root.get_visible_rect().get_center()
	print("MOUSE_STATE focus=", root.has_focus(), " mode=", Input.mouse_mode, " position=", root.get_mouse_position(), " center=", center, " window=", root.size, " screen_mouse=", DisplayServer.mouse_get_position(), " window_position=", DisplayServer.window_get_position())
	if root.get_mouse_position().distance_to(center) > 1.0:
		push_error("Mouse centering check failed")
		quit(1)
		return
	game._on_window_focus_exited()
	assert(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE)
	game._on_window_focus_entered()
	await process_frame
	await process_frame
	assert(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED)
	assert(root.get_mouse_position().distance_to(center) <= 1.0)
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	game._unhandled_input(escape)
	assert(not game.wants_mouse_capture and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	game._unhandled_input(click)
	await process_frame
	assert(game.wants_mouse_capture and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED)
	assert(root.get_mouse_position().distance_to(center) <= 1.0)
	game.open_inventory()
	assert(paused and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE)
	Input.warp_mouse(Vector2(50, 50))
	game.inventory_panel.close()
	await process_frame
	await process_frame
	assert(not paused and game.wants_mouse_capture and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED)
	assert(root.get_mouse_position().distance_to(center) <= 1.0, "Closing backpack restores centered capture")
	game.wants_mouse_capture = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game.open_inventory()
	game.inventory_panel.close()
	await process_frame
	assert(not game.wants_mouse_capture and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Backpack preserves an intentionally released mouse")
	print("MOUSE_FOCUS_OK center=" + str(center) + " recapture/escape/click/no_camera_jump/backpack_capture_restore")
	quit(0)
