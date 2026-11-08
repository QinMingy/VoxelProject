extends ScrollContainer

# Godot's ScrollContainer ignores InputEventScreenDrag and list rows are Buttons
# that swallow the gesture, so touch lists need a viewport-level drag handler.
# Claiming the finger here also scrolls when the drag starts on a row button.

const DEADZONE := 8.0

var _finger := -1
var _origin := Vector2.ZERO
var _last := Vector2.ZERO
var _dragging := false
var _pending := Vector2.ZERO

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _finger < 0 and _accepts(event.position):
			_finger = event.index
			_origin = event.position
			_last = event.position
			_dragging = false
			_pending = Vector2.ZERO
			get_viewport().set_input_as_handled()
		elif not event.pressed and event.index == _finger:
			_finger = -1
			if _dragging:
				get_viewport().set_input_as_handled()
			_dragging = false
	elif event is InputEventScreenDrag and event.index == _finger:
		var drag := event as InputEventScreenDrag
		var step: Vector2 = drag.position - _last
		_last = drag.position
		if not _dragging and drag.position.distance_to(_origin) >= DEADZONE:
			_dragging = true
			_cancel_click()
		if _dragging:
			_pending += step
			var vertical := int(_pending.y)
			var horizontal := int(_pending.x)
			if vertical != 0:
				scroll_vertical -= vertical
				_pending.y -= float(vertical)
			if horizontal != 0:
				scroll_horizontal -= horizontal
				_pending.x -= float(horizontal)
			get_viewport().set_input_as_handled()

func _accepts(point: Vector2) -> bool:
	return is_visible_in_tree() and get_global_rect().has_point(point)

func _cancel_click() -> void:
	# The emulated mouse press is already on a row button. Releasing far outside
	# it prevents the button from firing when the finger lifts.
	var cancel := InputEventMouseButton.new()
	cancel.button_index = MOUSE_BUTTON_LEFT
	cancel.pressed = false
	cancel.position = Vector2(-1000, -1000)
	cancel.global_position = cancel.position
	Input.parse_input_event(cancel)

func is_dragging() -> bool:
	return _dragging
