extends CanvasLayer

signal look_changed(delta: Vector2)
signal action_pressed(action: String)

const UI = preload("res://ui_style.gd")
const NO_FINGER := -2
const MOUSE_FINGER := -1
const JOYSTICK_DEADZONE := 0.14

class TouchPad extends Control:
	var joystick := false
	var held := false
	var movement := Vector2.ZERO

	func _draw() -> void:
		var center := size * 0.5
		var radius := minf(size.x, size.y) * 0.46
		var edge := UI.ACCENT if held else Color(UI.TEXT, 0.48)
		draw_circle(center, radius, Color(0.04, 0.09, 0.14, 0.65))
		draw_arc(center, radius, 0, TAU, 64, edge, 2.0, true)
		if joystick:
			draw_arc(center, radius * 0.58, 0, TAU, 48, Color(UI.TEXT, 0.18), 1.0, true)
			draw_circle(center + movement * radius * 0.58, radius * 0.28, Color(UI.ACCENT if held else UI.MUTED, 0.8))
		else:
			var font := get_theme_default_font()
			var font_size := maxi(16, roundi(size.x * 0.14))
			draw_string(font, Vector2(0, center.y + 3), "开采", HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, edge)
			draw_string(font, Vector2(0, center.y + font_size + 5), "拖动转向", HORIZONTAL_ALIGNMENT_CENTER, size.x, maxi(14, font_size - 4), UI.MUTED)

var _enabled := false
var _gameplay_active := true
var _focused := true
var _surface: Control
var _joystick: TouchPad
var _mine_pad: TouchPad
var _buttons: Dictionary = {}
var _owners: Dictionary = {}
var _move_finger := NO_FINGER
var _mine_finger := NO_FINGER
var _look_finger := NO_FINGER
var _movement := Vector2.ZERO
var _layout_scale := 1.0


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 18


func _ready() -> void:
	_surface = Control.new()
	_surface.name = "TouchRoot"
	_surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_surface.theme = UI.theme()
	add_child(_surface)
	_surface.visibility_changed.connect(_on_visibility_changed)
	_joystick = TouchPad.new()
	_joystick.name = "TouchJoystick"
	_joystick.joystick = true
	_joystick.mouse_filter = Control.MOUSE_FILTER_STOP
	_surface.add_child(_joystick)
	_mine_pad = TouchPad.new()
	_mine_pad.name = "TouchMine"
	_mine_pad.mouse_filter = Control.MOUSE_FILTER_STOP
	_surface.add_child(_mine_pad)
	_add_button("jump", "跳跃", "TouchJump")
	_add_button("pickup", "拾取", "TouchPickup")
	_add_button("interact", "交互", "TouchInteract")
	_add_button("backpack", "背包", "TouchBackpack")
	_add_button("view", "视角", "TouchView")
	_add_button("help", "帮助", "TouchHelp")
	_add_button("base", "基地", "TouchBase")
	get_viewport().size_changed.connect(_layout_controls)
	get_window().focus_exited.connect(_focus_lost)
	get_window().focus_entered.connect(_focus_gained)
	_layout_controls()
	_refresh_visibility()


func set_enabled(enabled: bool) -> void:
	_enabled = enabled
	if not enabled:
		release_all()
	_refresh_visibility()


func set_gameplay_active(active: bool) -> void:
	_gameplay_active = active
	if not active:
		release_all()
	_refresh_visibility()


func movement_vector() -> Vector2:
	return _movement if _can_interact() else Vector2.ZERO


func mining_held() -> bool:
	return _can_interact() and _mine_finger != NO_FINGER


func jump_held() -> bool:
	return _can_interact() and _owners.values().has("jump")


func release_all() -> void:
	_owners.clear()
	_move_finger = NO_FINGER
	_mine_finger = NO_FINGER
	_look_finger = NO_FINGER
	_movement = Vector2.ZERO
	_update_visuals()


func _can_interact() -> bool:
	return _enabled and _gameplay_active and _focused and visible and is_inside_tree() and not get_tree().paused


func _refresh_visibility() -> void:
	if is_instance_valid(_surface):
		_surface.visible = _can_interact()


func _process(_delta: float) -> void:
	if not _can_interact() and not _owners.is_empty():
		release_all()
	_refresh_visibility()


func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED]:
		_focus_lost()
	elif what in [NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_APPLICATION_RESUMED]:
		_focus_gained()


func _focus_lost() -> void:
	_focused = false
	release_all()
	_refresh_visibility()


func _focus_gained() -> void:
	_focused = true
	_refresh_visibility()


func _on_visibility_changed() -> void:
	if not _surface.is_visible_in_tree():
		release_all()


func _exit_tree() -> void:
	release_all()


func _input(event: InputEvent) -> void:
	if not _can_interact():
		return
	if event.device == InputEvent.DEVICE_ID_EMULATION:
		# The native finger or physical mouse already owns this gesture.
		# Let the reserved GM corner continue through Godot's normal GUI path.
		if event is InputEventMouse and not _gm_corner().has_point(event.position):
			get_viewport().set_input_as_handled()
		return
	var used := false
	if event is InputEventScreenTouch:
		used = _begin_finger(event.index, event.position) if event.pressed and not event.canceled else _end_finger(event.index)
	elif event is InputEventScreenDrag:
		var delta: Vector2 = event.screen_relative
		if delta.is_zero_approx():
			delta = event.relative
		used = _drag_finger(event.index, event.position, delta)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		used = _begin_finger(MOUSE_FINGER, event.position) if event.pressed else _end_finger(MOUSE_FINGER)
	elif event is InputEventMouseMotion and _owners.has(MOUSE_FINGER):
		used = _drag_finger(MOUSE_FINGER, event.position, event.relative)
	if used:
		get_viewport().set_input_as_handled()


func _begin_finger(finger: int, point: Vector2) -> bool:
	if _owners.has(finger):
		return true
	if _gm_corner().has_point(point):
		return false
	for action: String in _buttons:
		var button: Button = _buttons[action]
		if button.get_global_rect().has_point(point):
			_owners[finger] = action
			_update_visuals()
			if action != "jump":
				action_pressed.emit(action)
			return true
	if _joystick.get_global_rect().has_point(point):
		_owners[finger] = "move" if _move_finger == NO_FINGER else "blocked"
		if _move_finger == NO_FINGER:
			_move_finger = finger
			_update_movement(point)
		_update_visuals()
		return true
	if _mine_pad.get_global_rect().has_point(point):
		_owners[finger] = "mine" if _mine_finger == NO_FINGER else "blocked"
		if _mine_finger == NO_FINGER:
			_mine_finger = finger
			if _look_finger == NO_FINGER:
				_look_finger = finger
		_update_visuals()
		return true
	if point.x >= get_viewport().get_visible_rect().size.x * 0.45:
		_owners[finger] = "look" if _look_finger == NO_FINGER else "blocked"
		if _look_finger == NO_FINGER:
			_look_finger = finger
		return true
	return false


func _drag_finger(finger: int, point: Vector2, delta: Vector2) -> bool:
	if not _owners.has(finger):
		return false
	if finger == _move_finger:
		_update_movement(point)
	if finger == _look_finger and not delta.is_zero_approx():
		look_changed.emit(delta)
	_update_visuals()
	return true


func _end_finger(finger: int) -> bool:
	if not _owners.has(finger):
		return false
	_owners.erase(finger)
	if finger == _move_finger:
		_move_finger = NO_FINGER
		_movement = Vector2.ZERO
	if finger == _mine_finger:
		_mine_finger = NO_FINGER
	if finger == _look_finger:
		_look_finger = NO_FINGER
	_update_visuals()
	return true


func _update_movement(point: Vector2) -> void:
	var displacement := (point - _joystick.get_global_rect().get_center()) / (_joystick.size.x * 0.40)
	var strength := minf(1.0, displacement.length())
	_movement = Vector2.ZERO if strength <= JOYSTICK_DEADZONE else displacement.normalized() * ((strength - JOYSTICK_DEADZONE) / (1.0 - JOYSTICK_DEADZONE))


func _update_visuals() -> void:
	if is_instance_valid(_joystick):
		_joystick.held = _move_finger != NO_FINGER
		_joystick.movement = _movement
		_joystick.queue_redraw()
	if is_instance_valid(_mine_pad):
		_mine_pad.held = _mine_finger != NO_FINGER
		_mine_pad.queue_redraw()
	for action: String in _buttons:
		var button: Button = _buttons[action]
		if is_instance_valid(button):
			button.set_pressed_no_signal(_owners.values().has(action))


func _add_button(action: String, text: String, node_name: String) -> void:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.toggle_mode = true
	# Input is routed by finger ownership; GUI signals would duplicate emulated input.
	_surface.add_child(button)
	_buttons[action] = button


func _layout_controls() -> void:
	if not is_instance_valid(_surface):
		return
	var viewport_size := get_viewport().get_visible_rect().size
	_layout_scale = maxf(0.35, minf(viewport_size.x / 1100.0, viewport_size.y / 720.0))
	_place(_joystick, Control.PRESET_BOTTOM_LEFT, Rect2(24, -250, 196, 196))
	_place(_mine_pad, Control.PRESET_BOTTOM_RIGHT, Rect2(-244, -288, 176, 176))
	_place(_buttons.jump, Control.PRESET_BOTTOM_RIGHT, Rect2(-366, -136, 108, 60))
	_place(_buttons.pickup, Control.PRESET_BOTTOM_RIGHT, Rect2(-366, -264, 108, 56))
	_place(_buttons.interact, Control.PRESET_BOTTOM_RIGHT, Rect2(-366, -332, 108, 56))
	var toolbar := ["backpack", "view", "help", "base"]
	for index in range(toolbar.size()):
		_place(_buttons[toolbar[index]], Control.PRESET_CENTER_BOTTOM, Rect2(-224 + index * 114, -60, 106, 48))
	for action: String in _buttons:
		var button: Button = _buttons[action]
		button.add_theme_font_size_override("font_size", maxi(14, roundi(20 * _layout_scale)))
		button.add_theme_stylebox_override("normal", UI.panel(Color(0.065, 0.11, 0.17, 0.82), Color(UI.TEXT, 0.4), roundi(6 * _layout_scale), 10))
		button.add_theme_stylebox_override("pressed", UI.panel(Color("#24574b"), UI.ACCENT, roundi(6 * _layout_scale), 10))
	_joystick.queue_redraw()
	_mine_pad.queue_redraw()
	release_all()


func _place(control: Control, preset: int, bounds: Rect2) -> void:
	control.set_anchors_and_offsets_preset(preset)
	control.offset_left = bounds.position.x * _layout_scale
	control.offset_top = bounds.position.y * _layout_scale
	control.offset_right = bounds.end.x * _layout_scale
	control.offset_bottom = bounds.end.y * _layout_scale


func _gm_corner() -> Rect2:
	var viewport_size := get_viewport().get_visible_rect().size
	# GM uses a fixed bottom-right 126 x 44 button with 24 px outer margins.
	return Rect2(viewport_size - Vector2(170, 88), Vector2(170, 88))
