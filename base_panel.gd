extends CanvasLayer
const TouchScroll = preload("res://touch_scroll.gd")

const UI = preload("res://ui_style.gd")
const Palette = preload("res://palette.gd")

signal opened
signal closed
signal zone_selected(id: String)
signal deploy_requested

var is_open := false
var _state: Dictionary = {
	"bank": 0, "zones": [], "selected_zone": "", "stats": {},
}
var _modal: Control
var _window: PanelContainer
var _balance: Label
var _zone_list: VBoxContainer
var _selected_name: Label
var _zone_details: Label
var _zone_scope: Label
var _entry_fee: Label
var _deploy_button: Button
var _message: Label
var _zone_controls: Dictionary = {}
var _zone_group := ButtonGroup.new()
var _entrance_tween: Tween


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 25


func _ready() -> void:
	_build()
	_refresh()
	_layout()
	_layout.call_deferred()
	get_viewport().size_changed.connect(_layout)
	_modal.visible = is_open


func _process(_delta: float) -> void:
	if not is_open or not is_instance_valid(_window):
		return
	# A hidden Container does not finish text wrapping until shown. Reconcile
	# its requested bounds after that layout pass, including repeated lobby visits.
	var viewport_size := get_viewport().get_visible_rect().size
	var requested_size := Vector2(minf(1040.0, maxf(640.0, viewport_size.x - 64.0)), minf(620.0, maxf(480.0, viewport_size.y - 64.0)))
	if not _window.size.is_equal_approx(requested_size) or not _window.position.is_equal_approx((viewport_size - requested_size) * 0.5):
		_layout()


func open() -> void:
	if is_open:
		return
	is_open = true
	if is_instance_valid(_modal):
		_refresh()
		_layout()
		_modal.show()
		_animate_open()
		_layout.call_deferred()
	opened.emit()


func close() -> void:
	if not is_open:
		return
	is_open = false
	if is_instance_valid(_entrance_tween):
		_entrance_tween.kill()
	if is_instance_valid(_modal):
		_modal.hide()
		_modal.modulate.a = 1.0
	# The caller owns navigation and pause state; closed returns to its lobby.
	closed.emit()


func sync_state(data: Dictionary) -> void:
	for key: String in _state:
		if data.has(key):
			_state[key] = data[key]
	if is_instance_valid(_modal):
		_refresh()
		_layout.call_deferred()


func _build() -> void:
	_modal = Control.new()
	_modal.name = "BaseRoot"
	_modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal.mouse_filter = Control.MOUSE_FILTER_STOP
	_modal.theme = UI.theme()
	add_child(_modal)
	var shade := ColorRect.new()
	shade.name = "Backdrop"
	shade.color = Color(0.015, 0.025, 0.045, 0.94)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal.add_child(shade)
	_window = PanelContainer.new()
	_window.name = "BaseWindow"
	_window.add_theme_stylebox_override("panel", UI.panel(UI.PANEL, UI.BORDER, 26, 2))
	_modal.add_child(_window)
	_window.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	var content := _column(_window, "Content", 18)
	var header := HBoxContainer.new()
	header.name = "Header"
	header.add_theme_constant_override("separation", 24)
	content.add_child(header)
	var title := _label("选择矿区", 34, "Title")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_balance = _label("$ 0", 30, "Bank")
	_balance.add_theme_color_override("font_color", UI.ACCENT)
	header.add_child(_balance)
	header.add_child(_button("返回大厅", "CloseButton", close))
	content.add_child(HSeparator.new())
	var body := HBoxContainer.new()
	body.name = "Body"
	body.add_theme_constant_override("separation", 24)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(body)
	var choices := _column(body, "Expedition", 12)
	choices.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choices.size_flags_stretch_ratio = 1.15
	var section := _label("目的地", 22, "ZonesTitle")
	section.add_theme_color_override("font_color", UI.MUTED)
	choices.add_child(section)
	var zone_scroll := TouchScroll.new()
	zone_scroll.name = "ZoneScroll"
	zone_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	zone_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	choices.add_child(zone_scroll)
	_zone_list = _column(zone_scroll, "ZoneList", 12)
	_zone_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var details := PanelContainer.new()
	details.name = "ZoneDetailCard"
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.size_flags_stretch_ratio = 1.0
	details.add_theme_stylebox_override("panel", UI.panel(Palette.DEEP_SLATE, UI.BORDER, 24, 2))
	body.add_child(details)
	var fields := _column(details, "Details", 18)
	var eyebrow := _label("本次远征", 20, "ExpeditionLabel")
	eyebrow.add_theme_color_override("font_color", UI.MUTED)
	fields.add_child(eyebrow)
	_selected_name = _label("请选择矿区", 30, "SelectedZoneName")
	_selected_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fields.add_child(_selected_name)
	_zone_details = _label("", 22, "SelectedZoneDetails")
	_zone_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_zone_details.add_theme_color_override("font_color", UI.MUTED)
	fields.add_child(_zone_details)
	_zone_scope = _label("", 20, "ZoneScope")
	_zone_scope.add_theme_color_override("font_color", UI.ACCENT)
	fields.add_child(_zone_scope)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	fields.add_child(spacer)
	_entry_fee = _label("", 24, "EntryFee")
	_entry_fee.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fields.add_child(_entry_fee)
	_message = _label("", 20, "Message")
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fields.add_child(_message)
	_deploy_button = _button("开始远征", "DeployButton", _request_deploy)
	_deploy_button.custom_minimum_size.y = 62
	_deploy_button.add_theme_font_size_override("font_size", 24)
	_deploy_button.add_theme_stylebox_override("normal", UI.panel(Palette.TEAL_SHADOW, UI.ACCENT, 12, 2))
	_deploy_button.add_theme_stylebox_override("hover", UI.panel(Palette.TEAL_SHADOW, Palette.CYAN_LIGHT, 12, 2))
	fields.add_child(_deploy_button)
	var fee_help := _label("出发时扣除门票", 20, "FeeHelp")
	fee_help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fee_help.add_theme_color_override("font_color", UI.MUTED)
	fields.add_child(fee_help)


func _layout() -> void:
	if not is_instance_valid(_window):
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var width := minf(1040.0, maxf(640.0, viewport_size.x - 64.0))
	var height := minf(620.0, maxf(480.0, viewport_size.y - 64.0))
	# Set both axes together after wrapping text has a usable width. Updating four
	# offsets separately can retain an oversized pre-layout minimum height.
	_window.size = Vector2(width, height)
	_window.position = (viewport_size - _window.size) * 0.5


func _animate_open() -> void:
	if is_instance_valid(_entrance_tween):
		_entrance_tween.kill()
	_modal.modulate.a = 0.0
	_entrance_tween = create_tween()
	_entrance_tween.tween_property(_modal, "modulate:a", 1.0, 0.18)


func _refresh() -> void:
	var bank := maxi(0, int(_state.bank))
	_balance.text = "$ %d" % bank
	_refresh_zones(bank)


func _refresh_zones(bank: int) -> void:
	var present: Array[String] = []
	var selected: Dictionary = {}
	for zone: Dictionary in _state.zones:
		var id := str(zone.get("id", ""))
		if id.is_empty():
			continue
		present.append(id)
		if not _zone_controls.has(id):
			_create_zone(id)
		var widgets: Dictionary = _zone_controls[id]
		var chosen := id == str(_state.selected_zone)
		widgets.button.set_pressed_no_signal(chosen)
		widgets.button.add_theme_stylebox_override("normal", UI.panel(Palette.TEAL_SHADOW if chosen else Palette.DEEP_SLATE, UI.ACCENT if chosen else UI.BORDER, 12, 2))
		widgets.button.add_theme_stylebox_override("pressed", UI.panel(Palette.TEAL_SHADOW, UI.ACCENT, 12, 2))
		widgets.title.text = str(zone.get("name", id))
		widgets.title.add_theme_color_override("font_color", UI.ACCENT if chosen else UI.TEXT)
		var fee := maxi(0, int(zone.get("fee", 0)))
		widgets.fee.text = "免费" if fee == 0 else "$ %d" % fee
		widgets.fee.add_theme_color_override("font_color", UI.ACCENT if bank >= fee else UI.WARNING)
		widgets.description.text = {"meadow": "大小均衡 · 浅层埋藏", "salvage": "小件密集 · 露头较多", "deep": "大件偏多 · 深层埋藏"}.get(id, str(zone.get("tag", "探索矿区")))
		widgets.button.tooltip_text = str(zone.get("description", ""))
		if chosen:
			selected = zone
	for id: String in _zone_controls.keys():
		if id not in present:
			_zone_controls[id].button.queue_free()
			_zone_controls.erase(id)
	_deploy_button.disabled = selected.is_empty()
	if selected.is_empty():
		_selected_name.text = "请选择矿区"
		_zone_details.text = "选择一个目的地，准备出发。"
		_zone_scope.text = ""
		_entry_fee.text = ""
		_message.hide()
		_deploy_button.text = "开始远征"
		return
	_selected_name.text = str(selected.get("name", "矿区"))
	_zone_details.text = str(selected.get("description", ""))
	var radius := int(selected.get("activity_radius", _state.stats.get("activity_radius", 26)))
	_zone_scope.text = "半径 %dm  ·  矿点 %d 处" % [radius, int(selected.get("count", 0))]
	var fee := maxi(0, int(selected.get("fee", 0)))
	var affordable := bank >= fee
	_deploy_button.disabled = not affordable
	_entry_fee.text = "免费进入" if fee == 0 else "门票  $ %d" % fee
	_entry_fee.add_theme_color_override("font_color", UI.ACCENT if affordable else UI.WARNING)
	_deploy_button.text = "开始远征" if affordable else "余额不足"
	_message.text = "出发后余额  $ %d" % (bank - fee) if affordable else "还差  $ %d" % (fee - bank)
	_message.add_theme_color_override("font_color", UI.MUTED if affordable else UI.WARNING)
	_message.show()
	_deploy_button.tooltip_text = "进入%s" % _selected_name.text if affordable else _message.text


func _create_zone(id: String) -> void:
	var button := _button("", "Zone_" + id, _select_zone.bind(id))
	button.custom_minimum_size.y = 112
	button.toggle_mode = true
	button.button_group = _zone_group
	_zone_list.add_child(button)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(margin)
	var lines := _column(margin, "Labels", 8)
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lines.add_child(header)
	var title := _label("", 26, "ZoneTitle_" + id)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var fee := _label("", 22, "ZoneFee_" + id)
	header.add_child(fee)
	var description := _label("", 20, "ZoneDescription_" + id)
	description.add_theme_color_override("font_color", UI.MUTED)
	lines.add_child(description)
	_zone_controls[id] = {"button": button, "title": title, "fee": fee, "description": description}


func _select_zone(id: String) -> void:
	if not is_open or not _zone_controls.has(id):
		return
	_state.selected_zone = id
	_refresh_zones(maxi(0, int(_state.bank)))
	zone_selected.emit(id)


func _request_deploy() -> void:
	if is_open and not _deploy_button.disabled:
		deploy_requested.emit()


func _input(event: InputEvent) -> void:
	if not is_open or not event is InputEventKey:
		return
	if event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		if event.pressed and not event.echo:
			close()
	elif event.keycode == KEY_G or event.physical_keycode == KEY_G:
		get_viewport().set_input_as_handled()


func _unhandled_input(_event: InputEvent) -> void:
	if is_open:
		get_viewport().set_input_as_handled()


func _column(parent: Node, node_name: String, separation: int) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.name = node_name
	column.add_theme_constant_override("separation", separation)
	parent.add_child(column)
	return column


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
	button.custom_minimum_size.y = 48
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	return button
