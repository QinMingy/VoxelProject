extends CanvasLayer

signal look_changed(delta: Vector2)
signal action_pressed(action: String)
signal edit_mode_changed(active: bool)
signal layout_saved(layout: Dictionary)

const UI = preload("res://ui_style.gd")
const Palette = preload("res://palette.gd")
const NO_FINGER := -2
const MOUSE_FINGER := -1
const JOYSTICK_DEADZONE := 0.14
const CONTROL_IDS := ["joystick", "mine", "jump", "pickup", "interact", "backpack", "view", "help", "base"]
const BASE_SIZES := {
	"joystick": Vector2(196, 196),
	"mine": Vector2(176, 176),
	"jump": Vector2(96, 96),
	"pickup": Vector2(108, 56),
	"interact": Vector2(108, 56),
	"backpack": Vector2(106, 48),
	"view": Vector2(106, 48),
	"help": Vector2(106, 48),
	"base": Vector2(106, 48),
}
const SCALE_MIN := 0.7
const SCALE_MAX := 1.6
const EDIT_STEP := 0.1
const EDIT_MARGIN := 10.0

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
			draw_string(font, Vector2(0, center.y + font_size + 5), "拖动转向", HORIZONTAL_ALIGNMENT_CENTER, size.x, maxi(16, font_size - 4), UI.MUTED)

var _enabled := false
var _gameplay_active := true
var _focused := true
var _surface: Control
var _joystick: TouchPad
var _mine_pad: TouchPad
var _buttons: Dictionary = {}
var _owners: Dictionary = {}
var _available: Dictionary = {}
var _move_finger := NO_FINGER
var _mine_finger := NO_FINGER
var _look_finger := NO_FINGER
var _movement := Vector2.ZERO
var _layout_scale := 1.0
var _custom_layout: Dictionary = {}
var _default_layout: Dictionary = {}
var _edit_mode := false
var _edit_snapshot: Dictionary = {}
var _selected_id := ""
var _edit_finger := NO_FINGER
var _drag_offset := Vector2.ZERO
var _gear: Button
var _edit_bar: PanelContainer
var _edit_label: Label


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
	for action: String in _buttons:
		_available[action] = true
	_gear = Button.new()
	_gear.name = "TouchLayoutGear"
	_gear.text = "⚙"
	_gear.focus_mode = Control.FOCUS_NONE
	_gear.mouse_filter = Control.MOUSE_FILTER_STOP
	_gear.add_theme_font_size_override("font_size", 20)
	_gear.pressed.connect(enter_edit_mode)
	_surface.add_child(_gear)
	_build_edit_bar()
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


func set_action_available(action: String, value: bool) -> void:
	if bool(_available.get(action, true)) == value:
		return
	_available[action] = value
	_refresh_visibility()


func apply_layout(layout: Dictionary) -> void:
	_custom_layout = _sanitize_layout(layout)
	_layout_controls()


func current_layout() -> Dictionary:
	return _custom_layout.duplicate(true)


func is_editing() -> bool:
	return _edit_mode


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
	if not is_instance_valid(_surface):
		return
	var active := _enabled and _gameplay_active and _focused and visible and is_inside_tree()
	var paused := get_tree().paused
	_surface.visible = active and (not paused or _edit_mode)
	if is_instance_valid(_joystick):
		_joystick.visible = true
	if is_instance_valid(_mine_pad):
		_mine_pad.visible = true
	for action: String in _buttons:
		var button: Button = _buttons[action]
		if is_instance_valid(button):
			button.visible = _edit_mode or bool(_available.get(action, true))
	if is_instance_valid(_gear):
		_gear.visible = active and not paused and not _edit_mode
	if is_instance_valid(_edit_bar):
		_edit_bar.visible = _edit_mode and _surface.visible


func _process(_delta: float) -> void:
	if not _can_interact() and not _owners.is_empty() and not _edit_mode:
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
	if _edit_mode:
		_edit_input(event)
		return
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
		if not button.visible:
			continue
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


# --- Layout -----------------------------------------------------------------

func _layout_controls() -> void:
	if not is_instance_valid(_surface):
		return
	var viewport_size := get_viewport().get_visible_rect().size
	_layout_scale = maxf(0.35, minf(viewport_size.x / 1100.0, viewport_size.y / 720.0))
	_default_layout = _compute_default_layout(viewport_size)
	for id: String in CONTROL_IDS:
		var entry: Dictionary = _custom_layout.get(id, _default_layout[id])
		var scale := clampf(float(entry.get("scale", 1.0)), SCALE_MIN, SCALE_MAX)
		var base: Vector2 = BASE_SIZES[id]
		var size := base * _layout_scale * scale
		var center := Vector2(float(entry.get("x", 0.5)), float(entry.get("y", 0.5))) * viewport_size
		var margin := EDIT_MARGIN * _layout_scale
		center.x = clampf(center.x, size.x * 0.5 + margin, viewport_size.x - size.x * 0.5 - margin)
		center.y = clampf(center.y, size.y * 0.5 + margin, viewport_size.y - size.y * 0.5 - margin)
		var control := _control(id)
		if not is_instance_valid(control):
			continue
		control.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		control.position = center - size * 0.5
		control.size = size
		if control is Button:
			_style_button(id, control as Button, size)
	_style_gear(viewport_size)
	_layout_edit_bar(viewport_size)
	_joystick.queue_redraw()
	_mine_pad.queue_redraw()
	release_all()


func _compute_default_layout(viewport_size: Vector2) -> Dictionary:
	var s := _layout_scale
	var result := {}
	var rects := {
		"joystick": Rect2(Vector2(24 * s, viewport_size.y - 250 * s), Vector2(196, 196) * s),
		"mine": Rect2(Vector2(viewport_size.x - 244 * s, viewport_size.y - 288 * s), Vector2(176, 176) * s),
		"jump": Rect2(Vector2(viewport_size.x - 354 * s, viewport_size.y - 146 * s), Vector2(96, 96) * s),
		"pickup": Rect2(Vector2(viewport_size.x - 366 * s, viewport_size.y - 264 * s), Vector2(108, 56) * s),
		"interact": Rect2(Vector2(viewport_size.x - 366 * s, viewport_size.y - 332 * s), Vector2(108, 56) * s),
	}
	var toolbar := ["backpack", "view", "help", "base"]
	for index in range(toolbar.size()):
		rects[toolbar[index]] = Rect2(Vector2(viewport_size.x * 0.5 - 224 * s + index * 114 * s,
			viewport_size.y - 60 * s), Vector2(106, 48) * s)
	for id: String in CONTROL_IDS:
		var rect: Rect2 = rects[id]
		result[id] = {"x": (rect.position.x + rect.size.x * 0.5) / viewport_size.x,
			"y": (rect.position.y + rect.size.y * 0.5) / viewport_size.y, "scale": 1.0}
	return result


func _control(id: String) -> Control:
	if id == "joystick":
		return _joystick
	if id == "mine":
		return _mine_pad
	return _buttons.get(id)


func _style_button(id: String, button: Button, size: Vector2) -> void:
	var radius := int(size.x * 0.5) if id == "jump" else roundi(6 * _layout_scale)
	button.add_theme_font_size_override("font_size", maxi(16, roundi(size.y * 0.24)))
	button.add_theme_stylebox_override("normal", UI.panel(Color(0.065, 0.11, 0.17, 0.82),
		Color(UI.TEXT, 0.4), roundi(8 * _layout_scale), radius))
	button.add_theme_stylebox_override("pressed", UI.panel(Palette.TEAL_SHADOW, UI.ACCENT,
		roundi(8 * _layout_scale), radius))


func _style_gear(viewport_size: Vector2) -> void:
	if not is_instance_valid(_gear):
		return
	var side := maxf(48.0, 44.0 * _layout_scale)
	var size := Vector2(side, side)
	_gear.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_gear.position = Vector2(24 * _layout_scale,
		viewport_size.y - 250 * _layout_scale - side - 12 * _layout_scale)
	_gear.size = size
	_gear.add_theme_font_size_override("font_size", maxi(24, roundi(26 * _layout_scale)))
	_gear.add_theme_color_override("font_color", Palette.CYAN_LIGHT)
	_gear.add_theme_stylebox_override("normal", UI.panel(Palette.TEAL_SHADOW,
		UI.ACCENT, roundi(8 * _layout_scale), int(size.x * 0.5)))
	_gear.add_theme_stylebox_override("pressed", UI.panel(Palette.TEAL_SHADOW, UI.ACCENT,
		roundi(8 * _layout_scale), int(size.x * 0.5)))


# --- Layout editing ---------------------------------------------------------

func _build_edit_bar() -> void:
	_edit_bar = PanelContainer.new()
	_edit_bar.name = "TouchEditBar"
	_edit_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	_edit_bar.add_theme_stylebox_override("panel", UI.panel(UI.PANEL, UI.BORDER, 10, 2))
	_surface.add_child(_edit_bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_edit_bar.add_child(row)
	_edit_label = Label.new()
	_edit_label.text = "点选按键后拖动 / 缩放"
	_edit_label.custom_minimum_size.x = 170
	_edit_label.add_theme_font_size_override("font_size", 16)
	_edit_label.add_theme_color_override("font_color", UI.MUTED)
	row.add_child(_edit_label)
	_edit_button("缩小", "TouchEditShrink", func() -> void: _scale_selected(-EDIT_STEP), row)
	_edit_button("放大", "TouchEditGrow", func() -> void: _scale_selected(EDIT_STEP), row)
	_edit_button("默认", "TouchEditReset", _reset_layout, row)
	_edit_button("取消", "TouchEditCancel", func() -> void: _finish_edit(false), row)
	_edit_button("保存", "TouchEditSave", func() -> void: _finish_edit(true), row)
	_edit_bar.visible = false


func _edit_button(text: String, node_name: String, action: Callable, row: HBoxContainer) -> void:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(64, 48)
	button.add_theme_font_size_override("font_size", 18)
	button.pressed.connect(action)
	row.add_child(button)


func _layout_edit_bar(viewport_size: Vector2) -> void:
	if not is_instance_valid(_edit_bar):
		return
	_edit_bar.reset_size()
	var height := maxf(56.0, _edit_bar.get_combined_minimum_size().y)
	var width := minf(viewport_size.x - 24.0, _edit_bar.get_combined_minimum_size().x)
	_edit_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_edit_bar.offset_left = -width * 0.5
	_edit_bar.offset_right = width * 0.5
	_edit_bar.offset_top = 12.0
	_edit_bar.offset_bottom = 12.0 + height


func enter_edit_mode() -> void:
	if _edit_mode or not _enabled:
		return
	_edit_mode = true
	_edit_snapshot = _custom_layout.duplicate(true)
	_selected_id = ""
	_edit_finger = NO_FINGER
	release_all()
	_layout_controls()
	_refresh_visibility()
	_update_edit_label()
	edit_mode_changed.emit(true)


func _finish_edit(commit: bool) -> void:
	if not _edit_mode:
		return
	if not commit:
		_custom_layout = _edit_snapshot.duplicate(true)
	_edit_mode = false
	_selected_id = ""
	_edit_finger = NO_FINGER
	release_all()
	_layout_controls()
	_refresh_visibility()
	edit_mode_changed.emit(false)
	if commit:
		layout_saved.emit(_custom_layout.duplicate(true))


func _reset_layout() -> void:
	_custom_layout.clear()
	_selected_id = ""
	_layout_controls()
	_refresh_visibility()
	_update_edit_label()


func _scale_selected(delta: float) -> void:
	if _selected_id.is_empty():
		return
	var entry := _entry_for(_selected_id)
	var scale := clampf(float(entry.get("scale", 1.0)) + delta, SCALE_MIN, SCALE_MAX)
	entry["scale"] = scale
	_custom_layout[_selected_id] = entry
	_layout_controls()
	_refresh_visibility()
	_update_edit_label()


func _entry_for(id: String) -> Dictionary:
	return _custom_layout.get(id, _default_layout.get(id, {"x": 0.5, "y": 0.5, "scale": 1.0})).duplicate(true)


func _update_edit_label() -> void:
	if not is_instance_valid(_edit_label):
		return
	if _selected_id.is_empty():
		_edit_label.text = "点选按键后拖动 / 缩放"
		return
	var names := {"joystick": "摇杆", "mine": "采矿区", "jump": "跳跃", "pickup": "拾取",
		"interact": "交互", "backpack": "背包", "view": "视角", "help": "帮助", "base": "基地"}
	var entry := _entry_for(_selected_id)
	_edit_label.text = "%s · 尺寸 %d%%" % [names.get(_selected_id, _selected_id), roundi(float(entry.get("scale", 1.0)) * 100.0)]


func _edit_input(event: InputEvent) -> void:
	if event.device == InputEvent.DEVICE_ID_EMULATION and not event is InputEventMouse:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_edit_press(event.index, event.position)
		elif event.index == _edit_finger:
			_edit_finger = NO_FINGER
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and event.index == _edit_finger:
		_edit_drag(event.position)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_edit_press(MOUSE_FINGER, event.position)
		elif _edit_finger == MOUSE_FINGER:
			_edit_finger = NO_FINGER
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _edit_finger == MOUSE_FINGER:
		_edit_drag(event.position)
		get_viewport().set_input_as_handled()


func _edit_press(finger: int, point: Vector2) -> void:
	var id := _control_at(point)
	if id.is_empty():
		return
	_selected_id = id
	_edit_finger = finger
	var control := _control(id)
	_drag_offset = control.get_global_rect().get_center() - point
	_update_edit_label()
	_highlight_selected()
	get_viewport().set_input_as_handled()


func _edit_drag(point: Vector2) -> void:
	if _selected_id.is_empty() or not is_instance_valid(_control(_selected_id)):
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var control := _control(_selected_id)
	var center := point + _drag_offset
	center.x = clampf(center.x, 0.02 * viewport_size.x, 0.98 * viewport_size.x)
	center.y = clampf(center.y, 0.02 * viewport_size.y, 0.98 * viewport_size.y)
	var entry := _entry_for(_selected_id)
	entry["x"] = center.x / viewport_size.x
	entry["y"] = center.y / viewport_size.y
	_custom_layout[_selected_id] = entry
	_layout_controls()
	_refresh_visibility()
	_highlight_selected()


func _control_at(point: Vector2) -> String:
	for id: String in CONTROL_IDS:
		var control := _control(id)
		if is_instance_valid(control) and control.visible and control.get_global_rect().has_point(point):
			return id
	return ""


func _highlight_selected() -> void:
	for id: String in CONTROL_IDS:
		var control := _control(id)
		if is_instance_valid(control):
			control.modulate = Color(1.15, 1.15, 0.85) if id == _selected_id else Color.WHITE


func _sanitize_layout(layout: Dictionary) -> Dictionary:
	var result := {}
	if not layout is Dictionary:
		return result
	for id: String in CONTROL_IDS:
		var entry: Variant = layout.get(id)
		if not entry is Dictionary:
			continue
		var x: Variant = entry.get("x")
		var y: Variant = entry.get("y")
		var scale: Variant = entry.get("scale", 1.0)
		if not (x is float or x is int) or not (y is float or y is int) or not (scale is float or scale is int):
			continue
		var fx := clampf(float(x), 0.0, 1.0)
		var fy := clampf(float(y), 0.0, 1.0)
		var fs := clampf(float(scale), SCALE_MIN, SCALE_MAX)
		result[id] = {"x": fx, "y": fy, "scale": fs}
	return result


func _gm_corner() -> Rect2:
	var viewport_size := get_viewport().get_visible_rect().size
	# GM uses a fixed bottom-right 126 x 44 button with 24 px outer margins.
	return Rect2(viewport_size - Vector2(170, 88), Vector2(170, 88))
