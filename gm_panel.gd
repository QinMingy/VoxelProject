extends CanvasLayer
const TouchScroll = preload("res://touch_scroll.gd")

signal opened
signal closed
signal action_requested(action: String)
signal cleanup_changed(enabled: bool, max_cells: int)
signal brush_selected(index: int)
signal performance_changed(enabled: bool)
signal radar_mode_selected(index: int)
signal touch_mode_changed(enabled: bool)
signal audio_enabled_changed(enabled: bool)
signal technology_requested(action: String, upgrade_id: String, value: int)

const UI = preload("res://ui_style.gd")
const Palette = preload("res://palette.gd")
const DEFAULT_CLEANUP_MAX_CELLS := 9
const BRUSH_NAMES := ["球形", "宽铲", "窄钻"]
const RADAR_MODES := ["方位条", "圆形盘"]
const BASE_ACTIONS := ["start_trip", "start_trial", "adventure_trial", "reset_catalogue"]
const MOON_ACTIONS := ["cleanup_nearby", "refill_oxygen"]
const CLEANUP_HELP := "只清理格数达标的完整孤立土块。相连土层和晶石会保留。"

var is_open := false
var _available := true
var _state: Dictionary = {
	"cleanup_enabled": true,
	"cleanup_max_cells": DEFAULT_CLEANUP_MAX_CELLS,
	"brush": 0,
	"radar_mode": 1,
	"touch_mode": false,
	"audio_enabled": true,
	"show_performance": false,
	"on_moon": false,
	"oxygen": 0.0,
	"mining_time": 0.0,
	"cleanup_status": "等待清理任务",
	"message": "",
	"bank": 0,
	"research_points": 0,
	"technology_rows": [],
	"debug_progression_allowed": false,
}
var _entry: Button
var _modal: Control
var _status: Label
var _cleanup_check: CheckBox
var _cleanup_limit: SpinBox
var _cleanup_status: Label
var _performance_check: CheckBox
var _touch_mode_check: CheckBox
var _audio_enabled_check: CheckBox
var _message: Label
var _brush_buttons: Array[Button] = []
var _radar_buttons: Array[Button] = []
var _action_buttons: Dictionary = {}
var _window: PanelContainer
var _runtime_scroll: ScrollContainer
var _technology_scroll: ScrollContainer
var _technology_fields: VBoxContainer
var _technology_balance: Label
var _technology_notice: Label
var _technology_spins: Dictionary = {}
var _technology_labels: Dictionary = {}
var _technology_buttons: Array[Button] = []
var _technology_current_levels: Dictionary = {}
var _technology_ids: Array[String] = []
var _technology_pending := false
var _runtime_tab: Button
var _technology_tab: Button
var _active_tab := "runtime"


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 30


func _ready() -> void:
	_build()
	_sync_controls()
	_modal.visible = is_open
	get_viewport().size_changed.connect(_layout)
	_layout()


func open() -> void:
	if is_open or not _available:
		return
	is_open = true
	if is_instance_valid(_modal):
		_modal.show()
		_sync_controls()
	opened.emit()


func close() -> void:
	if not is_open:
		return
	# Commit a typed threshold before the game resumes, including G/Esc closes.
	if is_instance_valid(_cleanup_limit):
		_cleanup_limit.apply()
		_cleanup_limit.get_line_edit().release_focus()
	is_open = false
	_technology_pending = false
	if is_instance_valid(_modal):
		_modal.hide()
		_sync_controls()
	closed.emit()


func set_available(available: bool) -> void:
	_available = available
	if is_instance_valid(_entry):
		_entry.disabled = not available
		_entry.visible = available and not is_open
		_entry.tooltip_text = "" if available else "整理背包时暂不可用"


func sync_state(data: Dictionary) -> void:
	for key: String in _state:
		if data.has(key):
			_state[key] = data[key]
	_state.cleanup_max_cells = clampi(int(_state.cleanup_max_cells), 1, 64)
	_state.brush = clampi(int(_state.brush), 0, BRUSH_NAMES.size() - 1)
	_state.radar_mode = clampi(int(_state.radar_mode), 0, RADAR_MODES.size() - 1)
	_technology_pending = false
	if is_instance_valid(_modal):
		_sync_controls()


func _build() -> void:
	var surface := Control.new()
	surface.name = "GMRoot"
	surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	surface.theme = UI.theme()
	add_child(surface)

	_modal = Control.new()
	_modal.name = "GMModal"
	_modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal.mouse_filter = Control.MOUSE_FILTER_STOP
	surface.add_child(_modal)
	var shade := ColorRect.new()
	shade.name = "Backdrop"
	shade.color = Color(0.01, 0.02, 0.04, 0.82)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modal.add_child(shade)

	var panel := PanelContainer.new()
	_window = panel
	panel.name = "GMWindow"
	_modal.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -464
	panel.offset_right = 464
	panel.offset_top = -302
	panel.offset_bottom = 302
	panel.add_theme_stylebox_override("panel", UI.panel(UI.PANEL, UI.BORDER, 20))
	var content := _column(panel, "Content", 10)

	var header := HBoxContainer.new()
	header.name = "Header"
	content.add_child(header)
	var title := _label("GM 调试", 30, "Title")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var resume := _button("继续采掘", "CloseButton", close)
	resume.custom_minimum_size.x = 124.0
	header.add_child(resume)

	_status = _label("", 18, "SessionStatus")
	_status.add_theme_color_override("font_color", UI.ACCENT)
	content.add_child(_status)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	content.add_child(tabs)
	_runtime_tab = _button("采掘调试", "RuntimeDebugTab", _show_tab.bind("runtime"))
	_runtime_tab.toggle_mode = true
	_runtime_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.add_child(_runtime_tab)
	_technology_tab = _button("科技调试", "TechnologyDebugTab", _show_tab.bind("technology"))
	_technology_tab.toggle_mode = true
	_technology_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.add_child(_technology_tab)
	var scroll := TouchScroll.new()
	_runtime_scroll = scroll
	scroll.name = "OptionsScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	var columns := HBoxContainer.new()
	columns.name = "Columns"
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 16)
	scroll.add_child(columns)
	var left := _card(columns, "CleanupAndBrushes")
	var right := _card(columns, "RuntimeActions")
	_build_cleanup(left)
	_build_actions(right)
	_build_technology(content)
	_show_tab(_active_tab)

	_message = _label("", 18, "Message")
	_message.add_theme_color_override("font_color", UI.WARNING)
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_message)

	_entry = _button("G  调试", "GMEntryButton", _toggle)
	surface.add_child(_entry)
	_entry.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_entry.offset_left = -150
	_entry.offset_top = -68
	_entry.offset_right = -24
	_entry.offset_bottom = -24

func _layout() -> void:
	if _window == null:
		return
	var available := get_viewport().get_visible_rect().size - Vector2(32, 32)
	var dimensions := Vector2(minf(928, available.x), minf(660, available.y))
	_window.offset_left = -dimensions.x * 0.5
	_window.offset_right = dimensions.x * 0.5
	_window.offset_top = -dimensions.y * 0.5
	_window.offset_bottom = dimensions.y * 0.5

func _build_technology(parent: VBoxContainer) -> void:
	_technology_scroll = TouchScroll.new()
	_technology_scroll.name = "TechnologyScroll"
	_technology_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_technology_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(_technology_scroll)
	var contents := _column(_technology_scroll, "TechnologyContents", 12)
	contents.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_technology_notice = _label("直接修改当前存档；仅舱内可用。设置等级不扣费，科技归零保留资金和仓库物品。", 18, "TechnologyNotice")
	_technology_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_technology_notice.add_theme_color_override("font_color", UI.WARNING)
	contents.add_child(_technology_notice)
	_technology_balance = _label("", 20, "TechnologyBalance")
	contents.add_child(_technology_balance)
	var resources := HBoxContainer.new()
	resources.add_theme_constant_override("separation", 8)
	contents.add_child(resources)
	resources.add_child(_technology_button("资金 +1000", "DebugCash1000", "grant_cash", "", 1000))
	resources.add_child(_technology_button("资金 +10000", "DebugCash10000", "grant_cash", "", 10000))
	resources.add_child(_technology_button("研究点 +10", "DebugResearch10", "grant_research", "", 10))
	var bulk := HBoxContainer.new()
	bulk.add_theme_constant_override("separation", 8)
	contents.add_child(bulk)
	bulk.add_child(_technology_button("全部科技归零", "DebugTechnologyReset", "reset_levels"))
	bulk.add_child(_technology_button("全部科技满级", "DebugTechnologyMax", "max_levels"))
	contents.add_child(HSeparator.new())
	_technology_fields = _column(contents, "TechnologyLevels", 8)
	_technology_fields.size_flags_horizontal = Control.SIZE_EXPAND_FILL

func _technology_button(text: String, node_name: String, action: String, id: String = "", value: int = 0) -> Button:
	var button := _button(text, node_name, _request_technology.bind(action, id, value))
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_technology_buttons.append(button)
	return button

func _show_tab(tab: String) -> void:
	_active_tab = tab if tab == "technology" else "runtime"
	_runtime_scroll.visible = _active_tab == "runtime"
	_technology_scroll.visible = _active_tab == "technology"
	_runtime_tab.set_pressed_no_signal(_active_tab == "runtime")
	_technology_tab.set_pressed_no_signal(_active_tab == "technology")

func _sync_technology() -> void:
	var rows: Array = _state.technology_rows
	var ids: Array[String] = []
	for row: Dictionary in rows:
		ids.append(str(row.id))
	if ids != _technology_ids:
		_technology_ids = ids
		for child in _technology_fields.get_children():
			_technology_fields.remove_child(child)
			child.queue_free()
		_technology_spins.clear()
		_technology_labels.clear()
		_technology_current_levels.clear()
		# The first five controls are resource grants and bulk operations.
		_technology_buttons.resize(5)
		for row: Dictionary in rows:
			var id := str(row.id)
			var line := HBoxContainer.new()
			line.name = "Technology_" + id
			line.add_theme_constant_override("separation", 12)
			_technology_fields.add_child(line)
			var label := _label("", 18, "TechnologyDescription_" + id)
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			line.add_child(label)
			_technology_labels[id] = label
			var target := SpinBox.new()
			target.name = "TechnologyLevel_" + id
			target.min_value = 0
			target.max_value = int(row.max_level)
			target.step = 1
			target.rounded = true
			target.prefix = "Lv."
			target.custom_minimum_size = Vector2(116, 48)
			target.select_all_on_focus = true
			line.add_child(target)
			_technology_spins[id] = target
			var apply := _button("设置等级", "DebugSetLevel_" + id, _request_level.bind(id))
			apply.custom_minimum_size.x = 110
			line.add_child(apply)
			_technology_buttons.append(apply)
	var available := not bool(_state.on_moon) and bool(_state.debug_progression_allowed) and not _technology_pending
	for row: Dictionary in rows:
		var id := str(row.id)
		var spin: SpinBox = _technology_spins[id]
		var level := int(row.level)
		if int(_technology_current_levels.get(id, -1)) != level:
			spin.set_value_no_signal(level)
			_technology_current_levels[id] = level
		spin.editable = available
		(_technology_labels[id] as Label).text = "%s  ·  当前 Lv.%d / %d\n%s" % [str(row.name), level, int(row.max_level), str(row.current)]
	for button in _technology_buttons:
		button.disabled = not available or rows.is_empty()
	_technology_balance.text = "资金 %d   ·   研究点 %d" % [int(_state.bank), int(_state.research_points)]
	_technology_notice.text = "直接修改当前存档；设置等级不扣费，科技归零保留资金和仓库物品。"
	if not bool(_state.debug_progression_allowed) or bool(_state.on_moon):
		_technology_notice.text += "\n当前不可调整，请先安全返航并结算远征。"
	elif _technology_pending:
		_technology_notice.text += "\n正在保存……"

func _request_level(id: String) -> void:
	var spin: SpinBox = _technology_spins.get(id)
	if spin == null:
		return
	spin.apply()
	_request_technology("set_level", id, roundi(spin.value))

func _request_technology(action: String, id: String = "", value: int = 0) -> void:
	if not is_open or bool(_state.on_moon) or not bool(_state.debug_progression_allowed) or _technology_pending:
		return
	_technology_pending = true
	_sync_technology()
	technology_requested.emit(action, id, value)


func _build_cleanup(parent: VBoxContainer) -> void:
	parent.add_child(_label("孤立土块清理", 22, "CleanupTitle"))
	_cleanup_check = CheckBox.new()
	_cleanup_check.name = "CleanupEnabled"
	_cleanup_check.text = "自动清理"
	_cleanup_check.custom_minimum_size.y = 48.0
	_cleanup_check.tooltip_text = CLEANUP_HELP
	_cleanup_check.focus_mode = Control.FOCUS_NONE
	_cleanup_check.toggled.connect(_on_cleanup_toggled)
	parent.add_child(_cleanup_check)
	var threshold_row := HBoxContainer.new()
	threshold_row.name = "ThresholdRow"
	threshold_row.add_theme_constant_override("separation", 10)
	parent.add_child(threshold_row)
	var threshold_label := _label("每块最多", 20, "ThresholdLabel")
	threshold_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	threshold_row.add_child(threshold_label)
	_cleanup_limit = SpinBox.new()
	_cleanup_limit.name = "CleanupMaxCells"
	_cleanup_limit.min_value = 1
	_cleanup_limit.max_value = 64
	_cleanup_limit.step = 1
	_cleanup_limit.rounded = true
	_cleanup_limit.suffix = "格"
	_cleanup_limit.custom_minimum_size = Vector2(134, 48)
	_cleanup_limit.tooltip_text = CLEANUP_HELP
	_cleanup_limit.select_all_on_focus = true
	_cleanup_limit.set_value_no_signal(DEFAULT_CLEANUP_MAX_CELLS)
	_cleanup_limit.value_changed.connect(_on_cleanup_limit_changed)
	threshold_row.add_child(_cleanup_limit)
	_cleanup_limit.get_line_edit().name = "ThresholdInput"
	parent.add_child(_action_button("清理附近", "cleanup_nearby"))
	_cleanup_status = _label("", 18, "CleanupStatus")
	_cleanup_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_cleanup_status.add_theme_color_override("font_color", UI.MUTED)
	parent.add_child(_cleanup_status)
	parent.add_child(HSeparator.new())
	parent.add_child(_label("挖掘笔刷", 22, "BrushTitle"))
	var brushes := HBoxContainer.new()
	brushes.name = "Brushes"
	brushes.add_theme_constant_override("separation", 8)
	parent.add_child(brushes)
	var group := ButtonGroup.new()
	for index in range(BRUSH_NAMES.size()):
		var button := _button(BRUSH_NAMES[index], "Brush%d" % index, _on_brush_pressed.bind(index))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.toggle_mode = true
		button.button_group = group
		brushes.add_child(button)
		_brush_buttons.append(button)
	_performance_check = CheckBox.new()
	_performance_check.name = "ShowPerformance"
	_performance_check.text = "显示性能统计"
	_performance_check.custom_minimum_size.y = 48.0
	_performance_check.focus_mode = Control.FOCUS_NONE
	_performance_check.toggled.connect(_on_performance_toggled)
	parent.add_child(_performance_check)


func _build_actions(parent: VBoxContainer) -> void:
	_touch_mode_check = CheckBox.new()
	_touch_mode_check.name = "TouchMode"
	_touch_mode_check.text = "触控模式"
	_touch_mode_check.custom_minimum_size.y = 48.0
	_touch_mode_check.focus_mode = Control.FOCUS_NONE
	_touch_mode_check.tooltip_text = "左手移动；右手按住开采并拖动转向。电脑可用鼠标试用。"
	_touch_mode_check.toggled.connect(_on_touch_mode_toggled)
	parent.add_child(_touch_mode_check)
	_audio_enabled_check = CheckBox.new()
	_audio_enabled_check.name = "AudioEnabled"
	_audio_enabled_check.text = "音效"
	_audio_enabled_check.custom_minimum_size.y = 48.0
	_audio_enabled_check.focus_mode = Control.FOCUS_NONE
	_audio_enabled_check.toggled.connect(_on_audio_enabled_toggled)
	parent.add_child(_audio_enabled_check)
	parent.add_child(_label("雷达样式", 22, "RadarModeTitle"))
	var radar_row := HBoxContainer.new()
	radar_row.name = "RadarModes"
	radar_row.add_theme_constant_override("separation", 8)
	parent.add_child(radar_row)
	var radar_group := ButtonGroup.new()
	for index in range(RADAR_MODES.size()):
		var button := _button(RADAR_MODES[index], "RadarMode%d" % index, _on_radar_mode_pressed.bind(index))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.toggle_mode = true
		button.button_group = radar_group
		radar_row.add_child(button)
		_radar_buttons.append(button)
	parent.add_child(HSeparator.new())
	parent.add_child(_label("本局测试", 22, "RuntimeTitle"))
	var first_row := HBoxContainer.new()
	first_row.name = "TripActions"
	first_row.add_theme_constant_override("separation", 8)
	parent.add_child(first_row)
	first_row.add_child(_action_button("氧气补满", "refill_oxygen"))
	first_row.add_child(_action_button("返回舱边", "return_to_lander"))
	var speed_row := HBoxContainer.new()
	speed_row.name = "SpeedActions"
	speed_row.add_theme_constant_override("separation", 8)
	parent.add_child(speed_row)
	speed_row.add_child(_action_button("电镐提速", "speed_up"))
	speed_row.add_child(_action_button("电镐恢复", "reset_speed"))
	parent.add_child(HSeparator.new())
	parent.add_child(_label("舱内测试", 22, "BaseTitle"))
	parent.add_child(_action_button("开始新矿区", "start_trip"))
	parent.add_child(_action_button("24 秒撤离试炼", "start_trial"))
	parent.add_child(_action_button("冒险遗物试挖", "adventure_trial"))
	parent.add_child(_action_button("重置估价图鉴", "reset_catalogue"))


func _sync_controls() -> void:
	_cleanup_check.set_pressed_no_signal(bool(_state.cleanup_enabled))
	# Avoid replacing partially typed text during frequent runtime status syncs.
	if int(_cleanup_limit.value) != int(_state.cleanup_max_cells):
		_cleanup_limit.set_value_no_signal(int(_state.cleanup_max_cells))
	_performance_check.set_pressed_no_signal(bool(_state.show_performance))
	_touch_mode_check.set_pressed_no_signal(bool(_state.touch_mode))
	_audio_enabled_check.set_pressed_no_signal(bool(_state.audio_enabled))
	for index in range(_brush_buttons.size()):
		_brush_buttons[index].set_pressed_no_signal(index == int(_state.brush))
	for index in range(_radar_buttons.size()):
		_radar_buttons[index].set_pressed_no_signal(index == int(_state.radar_mode))
	var on_moon := bool(_state.on_moon)
	for action: String in _action_buttons:
		var button: Button = _action_buttons[action]
		button.disabled = (on_moon and action in BASE_ACTIONS) or (not on_moon and action in MOON_ACTIONS)
		button.tooltip_text = ""
		if button.disabled:
			button.tooltip_text = "仅舱内可用" if action in BASE_ACTIONS else "仅月面可用"
		elif action == "cleanup_nearby":
			button.tooltip_text = CLEANUP_HELP
		elif action == "return_to_lander":
			button.tooltip_text = "保留本趟物品和剩余氧气"
	var location := "月面" if on_moon else "舱内"
	var mining_time := float(_state.mining_time)
	var speed_text := "%.2f 秒 / 次" % mining_time if mining_time > 0.0 else "—"
	_status.text = "%s · 已暂停  |  氧气 %.1f 秒  |  开采 %s" % [location, maxf(0.0, float(_state.oxygen)), speed_text]
	_cleanup_status.text = str(_state.cleanup_status)
	_message.text = str(_state.message)
	_message.visible = not _message.text.is_empty()
	_entry.text = "G  关闭" if is_open else "G  调试"
	_sync_technology()
	set_available(_available)


func _toggle() -> void:
	if is_open:
		close()
	else:
		open()


func _request_action(action: String) -> void:
	if not is_open:
		return
	var button: Button = _action_buttons.get(action)
	if button == null or button.disabled:
		return
	_cleanup_limit.apply()
	action_requested.emit(action)


func _on_cleanup_toggled(enabled: bool) -> void:
	_state.cleanup_enabled = enabled
	cleanup_changed.emit(enabled, int(_cleanup_limit.value))


func _on_cleanup_limit_changed(value: float) -> void:
	var cells := clampi(roundi(value), 1, 64)
	_state.cleanup_max_cells = cells
	cleanup_changed.emit(_cleanup_check.button_pressed, cells)


func _on_brush_pressed(index: int) -> void:
	if int(_state.brush) == index:
		return
	_state.brush = index
	brush_selected.emit(index)


func _on_performance_toggled(enabled: bool) -> void:
	_state.show_performance = enabled
	performance_changed.emit(enabled)


func _on_touch_mode_toggled(enabled: bool) -> void:
	if bool(_state.touch_mode) == enabled:
		return
	_state.touch_mode = enabled
	touch_mode_changed.emit(enabled)


func _on_audio_enabled_toggled(enabled: bool) -> void:
	if bool(_state.audio_enabled) == enabled:
		return
	_state.audio_enabled = enabled
	audio_enabled_changed.emit(enabled)


func _on_radar_mode_pressed(index: int) -> void:
	var mode := clampi(index, 0, RADAR_MODES.size() - 1)
	if int(_state.radar_mode) == mode:
		return
	_state.radar_mode = mode
	for button_index in range(_radar_buttons.size()):
		_radar_buttons[button_index].set_pressed_no_signal(button_index == mode)
	radar_mode_selected.emit(mode)


func _input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var is_g: bool = event.physical_keycode == KEY_G or event.keycode == KEY_G
	var is_escape: bool = event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE
	if (is_g and (_available or is_open)) or (is_escape and is_open):
		get_viewport().set_input_as_handled()
		if event.pressed and not event.echo:
			if is_escape:
				close()
			else:
				_toggle()


func _unhandled_input(_event: InputEvent) -> void:
	if is_open:
		# GUI gets numeric typing and clicks first; unused input cannot reach gameplay.
		get_viewport().set_input_as_handled()


func _column(parent: Node, node_name: String, separation: int) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.name = node_name
	column.add_theme_constant_override("separation", separation)
	parent.add_child(column)
	return column


func _card(parent: Node, node_name: String) -> VBoxContainer:
	var card := PanelContainer.new()
	card.name = node_name
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", UI.panel(Palette.INK, UI.BORDER, 14))
	parent.add_child(card)
	return _column(card, "Fields", 8)


func _label(text: String, font_size: int, node_name: String) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _button(text: String, node_name: String, callback: Callable) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.custom_minimum_size.y = 48.0
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	return button


func _action_button(text: String, action: String) -> Button:
	var button := _button(text, action, _request_action.bind(action))
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_action_buttons[action] = button
	return button
