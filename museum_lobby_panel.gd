extends Control

signal navigate_requested(page: String)
signal slot_requested(slot: int)

const UI = preload("res://ui_style.gd")
const LobbyScene = preload("res://museum_lobby.gd")
const Palette = preload("res://palette.gd")
const FLOOR := Palette.SLATE
const ORANGE := Palette.AMBER

var scene: LobbyScene
var viewport: SubViewport
var room_view: SubViewportContainer
var utility_row: HBoxContainer
var _active := false
var _management_mode := false
var _balance: Label
var _notice: Label
var _help: Label
var _warehouse_button: Button
var _departure_button: Button
var _header: MarginContainer
var _footer: MarginContainer
var _actions: HBoxContainer
var _touch_mode := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UI.theme()
	_build()
	resized.connect(_layout)
	_layout()
	set_active(false)

func _build() -> void:
	var background := ColorRect.new()
	background.color = FLOOR
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	room_view = SubViewportContainer.new()
	room_view.name = "LobbyRoomView"
	room_view.stretch = true
	room_view.mouse_target = true
	room_view.focus_mode = Control.FOCUS_NONE
	room_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	room_view.gui_input.connect(_room_input)
	add_child(room_view)
	viewport = SubViewport.new()
	viewport.name = "LobbyViewport"
	viewport.own_world_3d = true
	viewport.handle_input_locally = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.msaa_3d = Viewport.MSAA_2X
	room_view.add_child(viewport)
	scene = LobbyScene.new()
	scene.name = "MuseumLobby"
	scene.slot_requested.connect(func(slot: int) -> void: slot_requested.emit(slot))
	viewport.add_child(scene)
	room_view.resized.connect(_resize_scene)
	_header = MarginContainer.new()
	_header.name = "LobbyHeader"
	_header.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	add_child(_header)
	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 18)
	_header.add_child(header_row)
	var title := VBoxContainer.new()
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_constant_override("separation", 4)
	header_row.add_child(title)
	title.add_child(_label("月面展览馆", 28, Palette.CREAM))
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	header_row.add_child(right)
	_balance = _label("", 18, Palette.CREAM)
	_balance.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(_balance)
	var utilities := HBoxContainer.new()
	utility_row = utilities
	utilities.alignment = BoxContainer.ALIGNMENT_END
	utilities.add_theme_constant_override("separation", 8)
	right.add_child(utilities)
	utilities.add_child(_button("收获记录", "ReportButton", func() -> void: navigate_requested.emit("report"), true))
	utilities.add_child(_button("开始页", "TitleButton", func() -> void: navigate_requested.emit("title"), true))
	utilities.add_child(_button("帮助", "LobbyHelpButton", toggle_help, true))
	_footer = MarginContainer.new()
	_footer.name = "LobbyFooter"
	_footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_footer.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(_footer)
	var footer_row := HBoxContainer.new()
	footer_row.add_theme_constant_override("separation", 18)
	_footer.add_child(footer_row)
	var space := Control.new()
	space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	footer_row.add_child(space)
	# Only exceptional save messages occupy this area; routine instructions
	# stay in the optional help panel.
	_notice = _label("", 16, Palette.AMBER_LIGHT)
	_notice.name = "LobbySaveNotice"
	_notice.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_notice.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notice.hide()
	space.add_child(_notice)
	_actions = HBoxContainer.new()
	_actions.name = "LobbyActions"
	_actions.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_actions.add_theme_constant_override("separation", 10)
	footer_row.add_child(_actions)
	_actions.add_child(_button("装备", "SkillsButton", func() -> void: navigate_requested.emit("skills")))
	_warehouse_button = _button("仓库", "MuseumButton", func() -> void: navigate_requested.emit("museum"))
	_warehouse_button.tooltip_text = "查看藏品经验、布展和调整陈列"
	_actions.add_child(_warehouse_button)
	_departure_button = _button("出发  →", "ExpeditionsButton", func() -> void: navigate_requested.emit("zones"))
	_departure_button.add_theme_stylebox_override("normal", UI.panel(ORANGE, Palette.AMBER_LIGHT, 12, 2))
	_departure_button.add_theme_stylebox_override("hover", UI.panel(Palette.AMBER_LIGHT, Palette.AMBER_LIGHT, 12, 2))
	_departure_button.add_theme_stylebox_override("pressed", UI.panel(Palette.AMBER, Palette.AMBER_LIGHT, 12, 2))
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		_departure_button.add_theme_color_override(state, Palette.RUST_SHADOW)
	_actions.add_child(_departure_button)
	_help = _label("", 18, Palette.CREAM)
	_help.name = "LobbyHelp"
	_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_help.add_theme_stylebox_override("normal", UI.panel(Palette.DEEP_SLATE, Palette.DUST, 14, 2))
	_help.mouse_filter = Control.MOUSE_FILTER_STOP
	_help.hide()
	add_child(_help)

func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

func _button(text: String, node_name: String, action: Callable, small: bool = false) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.custom_minimum_size = Vector2(64, 34) if small else Vector2(138, 58)
	button.add_theme_font_size_override("font_size", 16 if small else 24)
	button.add_theme_stylebox_override("normal", UI.panel(Palette.SLATE, Palette.DUST, 8 if small else 12, 2))
	button.add_theme_stylebox_override("hover", UI.panel(Palette.SLATE, ORANGE, 8 if small else 12, 2))
	button.pressed.connect(action)
	return button

func sync_state(data: Dictionary) -> void:
	if scene == null:
		return
	var museum: Dictionary = data.get("museum", {})
	scene.set_collection(museum)
	var exhibits: Dictionary = museum.get("exhibits", {})
	_balance.text = "资金 %d   ·   研究 %d" % [int(data.get("bank", 0)), int(data.get("research_points", 0))]
	_warehouse_button.text = "仓库" if exhibits.is_empty() else "仓库 · %d" % exhibits.size()
	_touch_mode = bool(data.get("touch_mode", false))
	var message := str(data.get("message", ""))
	_notice.text = message if message.contains("存档") or message.contains("未入账") else ""
	_notice.visible = not _notice.text.is_empty()
	_help.text = "点击展台调整陈列；灰色展台可查看扩建。\n仓库：查看藏品经验与布展。\n装备：升级采掘能力；出发：选择矿区。"
	if not _touch_mode:
		_help.text += "\nH 收起帮助 · Esc 返回开始页"

func set_active(value: bool) -> void:
	_active = value
	if scene == null:
		return
	scene.set_active(value and not _help.visible)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if value else SubViewport.UPDATE_DISABLED
	if not value:
		_help.hide()
	else:
		_resize_scene.call_deferred()

func toggle_help() -> void:
	if _management_mode:
		return
	_help.visible = not _help.visible
	# A visible explanation blocks the corresponding ground clicks.
	scene.set_active(_active and not _help.visible)

func set_management_mode(value: bool) -> void:
	_management_mode = value
	_header.visible = not value
	_footer.visible = not value
	if value:
		_help.hide()
	if scene != null:
		scene.set_active(_active and not _help.visible)

func _room_input(event: InputEvent) -> void:
	if not _active or _help.visible or event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if event is InputEventMouseButton and (event.button_index == MOUSE_BUTTON_WHEEL_UP
			or event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		if event.pressed:
			scene.adjust_zoom(-1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0)
			room_view.accept_event()
		return
	var pointer := Vector2.ZERO
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		pointer = event.position
	elif event is InputEventScreenTouch and event.pressed:
		pointer = event.position
	else:
		return
	var ratio := Vector2(viewport.size) / room_view.size.max(Vector2.ONE)
	scene.handle_pointer(pointer * ratio)
	room_view.accept_event()

func _resize_scene() -> void:
	if scene != null:
		scene.set_viewport_size(Vector2(viewport.size))

func _layout() -> void:
	if _header == null:
		return
	var compact := size.x < 1050 or size.y < 600
	var margin := 16 if compact else 24
	_header.offset_left = margin
	_header.offset_right = -margin
	_header.offset_top = margin
	_footer.offset_left = margin
	_footer.offset_right = -margin
	_footer.offset_bottom = -margin
	_footer.offset_top = -margin - (70 if compact else 78)
	room_view.offset_top = 94 if compact else 104
	room_view.offset_bottom = -100 if compact else -112
	for button: Button in _actions.get_children():
		button.custom_minimum_size = Vector2(120 if compact else 138, 54 if compact else 58)
		button.add_theme_font_size_override("font_size", 22 if compact else 24)
	_notice.add_theme_font_size_override("font_size", 14 if compact else 16)
	_help.position = Vector2(margin, 108)
	_help.size = Vector2(minf(490, size.x - margin * 2), 0)
	_resize_scene.call_deferred()
