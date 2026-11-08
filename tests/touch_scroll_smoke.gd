extends SceneTree

const TouchScroll = preload("res://touch_scroll.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, context: String) -> void:
	if not condition:
		failures.append(context)
		push_error("TOUCH SCROLL FAIL: " + context)

func run() -> void:
	var scroll := TouchScroll.new()
	scroll.position = Vector2(20, 20)
	scroll.size = Vector2(320, 300)
	root.add_child(scroll)
	var list := VBoxContainer.new()
	list.custom_minimum_size = Vector2(300, 1200)
	scroll.add_child(list)
	var pressed: Array[int] = []
	for index in range(25):
		var button := Button.new()
		button.text = "row %d" % index
		button.custom_minimum_size.y = 48
		button.pressed.connect(func() -> void: pressed.append(index))
		list.add_child(button)
	await process_frame
	await process_frame
	check(scroll.scroll_vertical == 0, "list starts at the top")

	# A short drag stays inside the deadzone.
	var press := InputEventScreenTouch.new()
	press.index = 0
	press.position = Vector2(180, 260)
	press.pressed = true
	root.push_input(press, true)
	var nudge := InputEventScreenDrag.new()
	nudge.index = 0
	nudge.position = Vector2(180, 256)
	nudge.relative = Vector2(0, -4)
	nudge.screen_relative = Vector2(0, -4)
	root.push_input(nudge, true)
	await process_frame
	check(scroll.scroll_vertical == 0, "drags inside the deadzone do not scroll")
	var release := InputEventScreenTouch.new()
	release.index = 0
	release.position = Vector2(180, 256)
	release.pressed = false
	root.push_input(release, true)
	await process_frame

	# A real one-finger drag over the rows scrolls the list, even when it starts
	# on a button, and never counts as a click.
	press.position = Vector2(180, 280)
	root.push_input(press, true)
	for step in range(6):
		var drag := InputEventScreenDrag.new()
		drag.index = 0
		drag.position = Vector2(180, 280 - (step + 1) * 30)
		drag.relative = Vector2(0, -30)
		drag.screen_relative = Vector2(0, -30)
		root.push_input(drag, true)
		await process_frame
	release.position = Vector2(180, 100)
	root.push_input(release, true)
	await process_frame
	check(scroll.scroll_vertical > 60, "touch drag scrolls the list")
	check(pressed.is_empty(), "dragging rows does not press them")

	# Dragging down returns toward the top.
	var scrolled_before: int = scroll.scroll_vertical
	press.position = Vector2(180, 120)
	root.push_input(press, true)
	for step in range(4):
		var drag := InputEventScreenDrag.new()
		drag.index = 0
		drag.position = Vector2(180, 120 + (step + 1) * 30)
		drag.relative = Vector2(0, 30)
		drag.screen_relative = Vector2(0, 30)
		root.push_input(drag, true)
		await process_frame
	release.position = Vector2(180, 240)
	root.push_input(release, true)
	await process_frame
	check(scroll.scroll_vertical <= scrolled_before - 80, "reverse drag scrolls back")
	scroll.queue_free()
	await process_frame
	if failures.is_empty():
		print("TOUCH_SCROLL_OK drag_scroll=true deadzone=true button_rows=true reverse=true")
	quit(0 if failures.is_empty() else 1)
