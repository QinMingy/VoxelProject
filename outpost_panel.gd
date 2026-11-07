extends CanvasLayer

signal opened
signal closed
signal navigate_requested(page: String)
signal debug_requested
signal display_slot_requested(slot: int)

const UI = preload("res://ui_style.gd")
const LobbyPanel = preload("res://museum_lobby_panel.gd")

# Menu art only. The playable terrain and relics remain in the main world.
class MoonSection extends Control:

	var phase := 0.0

	func _process(delta: float) -> void:
		if not is_visible_in_tree():
			return
		phase = fmod(phase + delta * 0.45, TAU)
		queue_redraw()

	func _draw() -> void:
		var origin := size * Vector2(0.5, 0.44)
		var scale_factor := minf(size.x / 420.0, size.y / 380.0)
		draw_set_transform(origin, 0, Vector2.ONE * scale_factor)
		for radius in [140.0, 177.0, 211.0]:
			draw_arc(Vector2.ZERO, radius, 0, TAU, 96, Color("#233648"), 1.0, true)
		for i in range(28):
			var angle := i * TAU / 28.0
			draw_line(Vector2.from_angle(angle) * 196, Vector2.from_angle(angle) * 201, Color("#3c5265"), 1, true)
		var pulse := Vector2.from_angle(phase) * 177
		draw_circle(pulse, 4.0, UI.ACCENT)
		for y in range(-2, 3):
			for x in range(-2, 3):
				var point := Vector2((x - y) * 31, (x + y) * 15)
				var height := 34.0 + float(posmod(x * 7 + y * 3, 3)) * 7.0
				var pit := x >= 0 and y <= 0
				if pit:
					height = 10.0
				var top := PackedVector2Array([point + Vector2(0, -height - 15), point + Vector2(31, -height), point + Vector2(0, -height + 15), point + Vector2(-31, -height)])
				var left := PackedVector2Array([top[3], top[2], point + Vector2(0, 55), point + Vector2(-31, 40)])
				var right := PackedVector2Array([top[2], top[1], point + Vector2(31, 40), point + Vector2(0, 55)])
				draw_colored_polygon(left, Color("#3b4c62"))
				draw_colored_polygon(right, Color("#2d3c50"))
				draw_colored_polygon(top, Color("#5d738d") if not pit else Color("#344b5b"))
				draw_polyline(PackedVector2Array([top[0], top[1], top[2], top[3], top[0]]), Color("#70859b"), 1.0, true)
		# A warm cluster in the cutaway is the focus of the menu artwork.
		for offset in [Vector2(25, -24), Vector2(43, -10), Vector2(8, -7)]:
			var crystal := PackedVector2Array([offset + Vector2(0, -43), offset + Vector2(14, -21), offset + Vector2(12, 8), offset + Vector2(-9, 14), offset + Vector2(-13, -19)])
			draw_colored_polygon(crystal, Color("#d5a259"))
			draw_colored_polygon(PackedVector2Array([crystal[0], crystal[1], crystal[2], offset]), Color("#f6ce88"))
		draw_dashed_line(Vector2(-156, 110), Vector2(154, 110), Color("#496a79"), 1.0, 5.0, true)
		draw_circle(Vector2(154, 110), 3, UI.ACCENT)
		draw_set_transform(Vector2.ZERO)

var is_open := false
var page := "title"
var _state: Dictionary = {"bank": 0, "research_points": 0, "museum": {}, "stats": {}, "receipt": "", "message": "", "report": {}, "zones": [], "selected_zone": "", "touch_mode": false}
var _modal: Control
var _window: MarginContainer
var _body: HBoxContainer
var _pages: Dictionary = {}
var _status: Label
var _balance: Label
var _page_title: Label
var _equipment: Label
var lobby: LobbyPanel
var _receipt: RichTextLabel
var _report_heading: Label
var _zone_name: Label
var _help: Label
var _tween: Tween
var _debug_button: Button
var _menu_footer: HBoxContainer

func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 25

func _ready() -> void:
	_build()
	_modal.hide()
	get_viewport().size_changed.connect(_layout)
	_layout()

func open(next_page: String = "lobby") -> void:
	page = next_page if _pages.has(next_page) else "lobby"
	is_open = true
	_refresh()
	_modal.show()
	_layout()
	if is_instance_valid(_tween):
		_tween.kill()
	var entrance: Control = lobby if page == "lobby" else _body
	entrance.modulate.a = 0.0
	_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.tween_property(entrance, "modulate:a", 1.0, 0.25)
	var focus_name := "EnterOutpostButton" if page == "title" else ("ExpeditionsButton" if page == "lobby" else "ReportBackButton")
	(_modal.find_child(focus_name, true, false) as Button).grab_focus()
	opened.emit()

func close() -> void:
	if not is_open:
		return
	is_open = false
	lobby.set_active(false)
	if is_instance_valid(_tween):
		_tween.kill()
	_modal.hide()
	closed.emit()

func sync_state(data: Dictionary) -> void:
	for key: String in _state:
		if data.has(key):
			_state[key] = data[key]
	if is_instance_valid(_modal):
		_refresh()

func _input(event: InputEvent) -> void:
	if not is_open or not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.physical_keycode == KEY_ESCAPE:
		if page == "report":
			navigate_requested.emit("lobby")
		elif page == "lobby":
			navigate_requested.emit("title")
		else:
			_help.visible = not _help.visible
		get_viewport().set_input_as_handled()
	elif event.physical_keycode == KEY_H:
		if page == "lobby":
			lobby.toggle_help()
		else:
			_help.visible = not _help.visible
		get_viewport().set_input_as_handled()

func _build() -> void:
	_modal = Control.new()
	_modal.name = "OutpostRoot"
	_modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal.theme = UI.theme()
	add_child(_modal)
	var background := ColorRect.new()
	background.color = Color("#0b1522")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal.add_child(background)
	_window = MarginContainer.new()
	_window.name = "OutpostWindow"
	_window.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal.add_child(_window)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 20)
	_window.add_child(content)
	var header := HBoxContainer.new()
	content.add_child(header)
	_page_title = _label("月面采掘", 24, UI.ACCENT)
	_page_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_page_title)
	header.add_child(_label("●  前哨站在线", 18, UI.MUTED))
	_balance = _label("", 22, UI.WARNING)
	_balance.custom_minimum_size.x = 180
	_balance.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(_balance)
	content.add_child(HSeparator.new())
	_body = HBoxContainer.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 36)
	content.add_child(_body)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.25
	_body.add_child(left)
	_build_title(left)
	_build_lobby(left)
	_build_report(left)
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 360
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_child(right)
	var art := MoonSection.new()
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.custom_minimum_size = Vector2(330, 260)
	art.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(art)
	right.add_child(_label("下一站", 18, UI.MUTED))
	_zone_name = _label("月壤浅滩", 26, UI.TEXT)
	right.add_child(_zone_name)
	_equipment = _label("", 18, UI.MUTED)
	right.add_child(_equipment)
	_help = _label("WASD 移动 · 空格 跳跃 · V 切换视角\n长按左键挖土 · F 拾取 · E 回舱\nB 背包 · H 帮助 · G 调试", 18, UI.TEXT)
	_help.name = "OutpostHelp"
	_help.hide()
	right.add_child(_help)
	_status = _label("", 18, UI.WARNING)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_status)
	var footer := HBoxContainer.new()
	_menu_footer = footer
	content.add_child(footer)
	var version := _label("月面前哨站  /  采掘原型", 16, UI.MUTED)
	version.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(version)
	_debug_button = _button("GM", "OutpostGMButton", func() -> void: debug_requested.emit())
	_debug_button.custom_minimum_size = Vector2(64, 34)
	_debug_button.add_theme_font_size_override("font_size", 16)
	footer.add_child(_debug_button)
	var help_button := _button("帮助", "HelpButton", func() -> void: _help.visible = not _help.visible)
	help_button.custom_minimum_size = Vector2(96, 42)
	footer.add_child(help_button)

func _build_title(parent: Control) -> void:
	var box := VBoxContainer.new()
	box.name = "TitlePage"
	box.add_theme_constant_override("separation", 18)
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(box)
	_pages.title = box
	box.add_spacer(false)
	box.add_child(_label("LUNAR  /  EXTRACTION", 18, UI.ACCENT))
	box.add_child(_label("月面采掘", 58, UI.TEXT))
	box.add_child(_label("把埋藏的东西，完整带回来。", 24, UI.MUTED))
	var gap := Control.new()
	gap.custom_minimum_size.y = 20
	box.add_child(gap)
	box.add_child(_button("进入展览馆  →", "EnterOutpostButton", func() -> void: navigate_requested.emit("lobby")))
	box.add_child(_button("退出游戏", "QuitButton", func() -> void: get_tree().quit()))
	box.add_spacer(false)

func _build_lobby(_parent: Control) -> void:
	lobby = LobbyPanel.new()
	lobby.name = "LobbyPage"
	_modal.add_child(lobby)
	_pages.lobby = lobby
	lobby.navigate_requested.connect(func(destination: String) -> void: navigate_requested.emit(destination))
	lobby.slot_requested.connect(func(slot: int) -> void: display_slot_requested.emit(slot))

func _build_report(parent: Control) -> void:
	var box := VBoxContainer.new()
	box.name = "ReportPage"
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 16)
	parent.add_child(box)
	_pages.report = box
	_report_heading = _label("最近一次远征", 32, UI.TEXT)
	box.add_child(_report_heading)
	var card := PanelContainer.new()
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", UI.panel())
	box.add_child(card)
	_receipt = RichTextLabel.new()
	_receipt.name = "Receipt"
	_receipt.bbcode_enabled = false
	_receipt.selection_enabled = true
	_receipt.scroll_active = true
	_receipt.add_theme_font_size_override("normal_font_size", 21)
	card.add_child(_receipt)
	box.add_child(_button("返回大厅", "ReportBackButton", func() -> void: navigate_requested.emit("lobby")))

func _label(text: String, size_px: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size_px)
	label.add_theme_color_override("font_color", color)
	return label

func _button(text: String, node_name: String, action: Callable) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.custom_minimum_size = Vector2(290, 56)
	button.add_theme_font_size_override("font_size", 22)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.pressed.connect(action)
	return button

func _refresh() -> void:
	_help.text = "左摇杆移动 · 右侧拖动视角\n按住开采并拖动 · 拾取完整物品\n舱边点交互返航 · 背包内点选和旋转" if _state.touch_mode else "WASD 移动 · 空格 跳跃 · V 切换视角\n长按左键挖土 · F 拾取 · E 回舱\nB 背包 · H 帮助 · G 调试"
	for key: String in _pages:
		_pages[key].visible = key == page
	_window.visible = page != "lobby"
	var debug_parent: Control = lobby.utility_row if page == "lobby" else _menu_footer
	if _debug_button.get_parent() != debug_parent:
		_debug_button.reparent(debug_parent)
	lobby.sync_state(_state)
	lobby.set_active(is_open and page == "lobby")
	_page_title.text = "月面采掘" if page == "title" else ("月面前哨站  /  大厅" if page == "lobby" else "月面前哨站  /  收获记录")
	_balance.text = "资金 %d  ·  研究 %d" % [int(_state.bank), int(_state.research_points)]
	var stats: Dictionary = _state.stats
	_equipment.text = "氧气 %ds  ·  背包 %d×%d\n开采 %.2fs  ·  探测 %dm" % [int(stats.get("oxygen", 65)), int(stats.get("bag_columns", 4)), int(stats.get("bag_rows", 4)), float(stats.get("mining_time", 0.9)), int(stats.get("detector_range", 10))]
	for zone: Dictionary in _state.zones:
		if zone.id == _state.selected_zone:
			_zone_name.text = str(zone.name)
			_equipment.text += "\n采掘半径 %dm  ·  矿点 %d 处" % [int(stats.get("activity_radius", 26)), int(zone.get("count", 0))]
	var report: Dictionary = _state.report
	_report_heading.text = "最近一次远征" if report.is_empty() else ("紧急救援" if report.get("emergency", false) else "安全返航")
	_receipt.text = str(_state.receipt) if not str(_state.receipt).is_empty() else "还没有收获记录。\n\n从大厅选择矿区，带回你的第一件发现。"
	_receipt.tooltip_text = _receipt.text
	_status.text = str(_state.message) if str(_state.message).contains("存档") or str(_state.message).contains("未入账") else ""
	_status.visible = not _status.text.is_empty()

func _layout() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var margin := maxi(24, int((viewport_size.x - 1250) * 0.5))
	_window.add_theme_constant_override("margin_left", margin)
	_window.add_theme_constant_override("margin_right", margin)
	_window.add_theme_constant_override("margin_top", 26)
	_window.add_theme_constant_override("margin_bottom", 22)
