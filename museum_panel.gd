extends CanvasLayer
const TouchScroll = preload("res://touch_scroll.gd")

signal opened
signal closed
signal place_requested(key: String, slot: int)
signal stand_selected(slot: int)
signal zone_selected(zone: int)
signal item_selected(key: String)
signal research_requested
signal feedback(event: String)

const UI = preload("res://ui_style.gd")
const Museum = preload("res://museum.gd")
const Palette = preload("res://palette.gd")

var is_open := false
var selected_key := ""
var selected_stand := -1
var selected_zone := 0
var _state: Dictionary = {"bank": 0, "research_points": 0, "museum": {}, "message": ""}
var _modal: Control
var _left: PanelContainer
var _right: PanelContainer
var _window: PanelContainer
var _balance: Label
var _summary: Label
var _message: Label
var _zone_tabs: Array[Button] = []
var _item_scroll: ScrollContainer
var _item_list: VBoxContainer
var _item_buttons: Dictionary = {}
var _stand_header: Label
var _stand_selection: Label
var _detail_name: Label
var _detail_info: Label
var _detail_bar: ProgressBar
var _detail_xp: Label
var _action_button: Button
var _action_mode := ""
var _income: Label
var _swatches: Dictionary = {}
var _entrance: Tween
var _pending := false

func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 26

func _ready() -> void:
	_build()
	_layout()
	_modal.hide()
	get_viewport().size_changed.connect(_layout)

func open() -> void:
	if is_open:
		return
	is_open = true
	_pending = false
	selected_stand = -1
	selected_key = ""
	_modal.show()
	_refresh()
	_layout()
	_layout.call_deferred()
	if is_instance_valid(_entrance):
		_entrance.kill()
	_modal.modulate.a = 0
	_entrance = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_entrance.tween_property(_modal, "modulate:a", 1.0, 0.2)
	opened.emit()

func close() -> void:
	if not is_open:
		return
	is_open = false
	_pending = false
	if is_instance_valid(_entrance):
		_entrance.kill()
	_modal.hide()
	closed.emit()

func sync_state(data: Dictionary) -> void:
	for key: String in _state:
		if data.has(key):
			_state[key] = data[key].duplicate(true) if data[key] is Dictionary or data[key] is Array else data[key]
	if _pending:
		# A completed install/remove returns the panel to the stand's own view.
		selected_key = ""
	_pending = false
	if is_instance_valid(_modal):
		_refresh()

func _build() -> void:
	_modal = Control.new()
	_modal.name = "MuseumRoot"
	_modal.theme = UI.theme()
	_modal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_modal)

	_left = PanelContainer.new()
	_left.name = "MuseumWindow"
	_left.mouse_filter = Control.MOUSE_FILTER_STOP
	_left.add_theme_stylebox_override("panel", UI.panel(UI.PANEL, UI.BORDER, 16, 2))
	_modal.add_child(_left)
	_window = _left
	var left_column := VBoxContainer.new()
	left_column.add_theme_constant_override("separation", 8)
	_left.add_child(left_column)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	left_column.add_child(header)
	var title := _label("仓库", 28)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(_button("关闭", "CloseButton", close))
	_summary = _label("", 16, UI.MUTED)
	left_column.add_child(_summary)
	_balance = _label("", 18, UI.ACCENT)
	left_column.add_child(_balance)
	var zone_row := HBoxContainer.new()
	zone_row.add_theme_constant_override("separation", 6)
	left_column.add_child(zone_row)
	for zone in range(Museum.ZONE_COUNT):
		var tab := _button(str(Museum.ZONES[zone].label), "ZoneTab_%d" % zone, select_zone.bind(zone))
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.custom_minimum_size.x = 0
		zone_row.add_child(tab)
		_zone_tabs.append(tab)
	_item_scroll = TouchScroll.new()
	_item_scroll.name = "ItemScroll"
	_item_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_item_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_item_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_item_scroll.follow_focus = true
	left_column.add_child(_item_scroll)
	_item_list = _column(_item_scroll, "ItemList")
	_message = _label("", 16, UI.WARNING)
	_message.name = "MuseumMessage"
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.custom_minimum_size.y = 34
	left_column.add_child(_message)
	left_column.add_child(_button("展馆研究", "ResearchButton", func() -> void: research_requested.emit()))

	_right = PanelContainer.new()
	_right.name = "MuseumInfoWindow"
	_right.mouse_filter = Control.MOUSE_FILTER_STOP
	_right.add_theme_stylebox_override("panel", UI.panel(UI.PANEL, UI.BORDER, 16, 2))
	_modal.add_child(_right)
	var right_column := VBoxContainer.new()
	right_column.add_theme_constant_override("separation", 8)
	_right.add_child(right_column)
	var stand_row := HBoxContainer.new()
	stand_row.add_theme_constant_override("separation", 8)
	right_column.add_child(stand_row)
	var prev_button := _button("◀", "PrevStandButton", _step_stand.bind(-1))
	prev_button.custom_minimum_size = Vector2(48, 48)
	stand_row.add_child(prev_button)
	_stand_header = _label("展台", 22, UI.TEXT)
	_stand_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stand_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stand_row.add_child(_stand_header)
	var next_button := _button("▶", "NextStandButton", _step_stand.bind(1))
	next_button.custom_minimum_size = Vector2(48, 48)
	stand_row.add_child(next_button)
	_stand_selection = _label("", 18, UI.MUTED)
	_stand_selection.name = "SelectedStand"
	_stand_selection.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right_column.add_child(_stand_selection)
	var detail := PanelContainer.new()
	detail.add_theme_stylebox_override("panel", UI.panel(Palette.DEEP_SLATE, UI.BORDER, 12, 2))
	right_column.add_child(detail)
	var details := _column(detail, "SelectedItemDetails")
	_detail_name = _label("选择一件藏品", 20)
	_detail_name.name = "SelectedItemName"
	_detail_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child(_detail_name)
	_detail_info = _label("", 17, UI.MUTED)
	_detail_info.name = "SelectedItemInfo"
	_detail_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child(_detail_info)
	_detail_bar = ProgressBar.new()
	_detail_bar.name = "SelectedItemExperience"
	_detail_bar.show_percentage = false
	_detail_bar.custom_minimum_size.y = 10
	_detail_bar.max_value = 1.0
	_detail_bar.add_theme_stylebox_override("background", UI.panel(Palette.INK, Color.TRANSPARENT, 0, 2))
	_detail_bar.add_theme_stylebox_override("fill", UI.panel(UI.ACCENT, Color.TRANSPARENT, 0, 2))
	details.add_child(_detail_bar)
	_detail_xp = _label("", 16, UI.MUTED)
	details.add_child(_detail_xp)
	_income = _label("", 18, UI.ACCENT)
	_income.tooltip_text = "按出发时的陈列计算，随出舱时间累计，65 秒达到本趟上限。至少出舱 10 秒并安全返航才结算；菜单与离线时间不累计。"
	right_column.add_child(_income)
	_action_button = _button("选择展台", "ActionButton", _request_action)
	right_column.add_child(_action_button)

func _column(parent: Node, node_name: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = node_name
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	parent.add_child(box)
	return box

func _label(text: String, size_px: int, color: Color = UI.TEXT) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size_px)
	label.add_theme_color_override("font_color", color)
	return label

func _button(text: String, node_name: String, action: Callable) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.custom_minimum_size.y = 48
	button.add_theme_font_size_override("font_size", 18)
	button.pressed.connect(action)
	return button

func _layout() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var margin := 8.0
	var width := clampf(viewport_size.x * 0.29, 280.0, 360.0)
	width = minf(width, maxf(280.0, (viewport_size.x - margin * 3.0 - 300.0) * 0.5))
	var height := maxf(0.0, viewport_size.y - margin * 2.0)
	_left.position = Vector2(margin, margin)
	_left.size = Vector2(width, height)
	_right.custom_minimum_size = Vector2(width, 0)
	_right.position = Vector2(viewport_size.x - margin - width, margin)
	_right.reset_size()
	if _right.size.y > height:
		_right.size = Vector2(width, height)

func _museum() -> Dictionary:
	return _state.get("museum", {})

func _rows() -> Array:
	return _museum().get("catalogue_rows", [])

func _owned_rows() -> Array:
	var owned: Array = []
	for row: Dictionary in _rows():
		if bool(row.get("owned", false)):
			owned.append(row)
	return owned

func _row_for(key: String) -> Dictionary:
	for row: Dictionary in _rows():
		if str(row.get("key", "")) == key:
			return row
	return {}

func _remove_list_children(list: Control) -> void:
	for child: Node in list.get_children():
		list.remove_child(child)
		child.queue_free()

func _swatch(color: Color) -> Texture2D:
	var key := color.to_html()
	if _swatches.has(key):
		return _swatches[key]
	var image := Image.create(48, 48, false, Image.FORMAT_RGBA8)
	image.fill(color)
	for x in range(48):
		for edge in [0, 1, 46, 47]:
			image.set_pixel(x, edge, Palette.INK)
			image.set_pixel(edge, x, Palette.INK)
	var texture := ImageTexture.create_from_image(image)
	_swatches[key] = texture
	return texture

func _refresh() -> void:
	var museum := _museum()
	var rows := _owned_rows()
	var slots: Array = museum.get("slots", [])
	var capacity := int(museum.get("capacity", 6))
	var exhibits: Dictionary = museum.get("exhibits", {})
	if not selected_key.is_empty() and not exhibits.has(selected_key):
		selected_key = ""
	selected_stand = clampi(selected_stand, -1, maxi(0, capacity - 1))
	if selected_stand >= 0:
		selected_zone = clampi(selected_stand / Museum.ZONE_SIZE, 0, Museum.ZONE_COUNT - 1)
	selected_zone = clampi(selected_zone, 0, maxi(0, (capacity - 1) / Museum.ZONE_SIZE))
	_balance.text = "资金 %d  ·  研究点 %d" % [int(_state.bank), int(_state.research_points)]
	_summary.text = "藏品 %d  ·  陈列 %d / %d" % [rows.size(), int(museum.get("displayed_count", 0)), capacity]
	for zone in range(_zone_tabs.size()):
		var tab := _zone_tabs[zone]
		var unlocked := zone * Museum.ZONE_SIZE < capacity
		tab.disabled = not unlocked
		tab.button_pressed = zone == selected_zone
		tab.text = str(Museum.ZONES[zone].label) if unlocked else "%s · 锁" % str(Museum.ZONES[zone].label)
		tab.add_theme_stylebox_override("normal", UI.panel(Palette.TEAL_SHADOW if zone == selected_zone else Palette.DEEP_SLATE,
			UI.ACCENT if zone == selected_zone else UI.BORDER, 8, 2))
	_remove_list_children(_item_list)
	_item_buttons.clear()
	if rows.is_empty():
		var empty := _label("还没有藏品\n\n出舱带回完整物品，\n安全回舱后再来看看。", 20, UI.MUTED)
		empty.name = "EmptyCollection"
		_item_list.add_child(empty)
	for row: Dictionary in rows:
		var key := str(row.key)
		var level := int(row.get("level", 1))
		var need := int(row.get("need", 0))
		var progress := "已满级" if need <= 0 else "经验 %d / %d" % [int(row.get("xp", 0)), need]
		var slot := int(row.get("slot", -1))
		var where := "已陈列" if slot >= 0 else "未陈列"
		var button := _button("", "Item_" + key, select_item.bind(key))
		button.text = "%s\nLv.%d  ·  %s" % [str(row.get("label", "藏品")), level, progress]
		button.icon = _swatch(row.get("icon_color", Palette.BONE))
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size.y = 72
		button.tooltip_text = where
		button.add_theme_stylebox_override("normal", UI.panel(Palette.TEAL_SHADOW if key == selected_key else Palette.DEEP_SLATE,
			UI.ACCENT if key == selected_key else UI.BORDER, 10, 2))
		if slot >= 0:
			var tag := Label.new()
			tag.name = "ExhibitTag_" + key
			tag.text = "展出中"
			tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
			tag.add_theme_font_size_override("font_size", 14)
			tag.add_theme_color_override("font_color", Palette.CYAN_LIGHT)
			tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			button.add_child(tag)
			tag.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
			tag.offset_left = -72
			tag.offset_right = -12
			tag.offset_top = -12
			tag.offset_bottom = 12
		_item_list.add_child(button)
		_item_buttons[key] = button
	_stand_header.text = Museum.zone_label(selected_zone)
	var stand_key := str(slots[selected_stand]) if selected_stand >= 0 and selected_stand < slots.size() else ""
	_stand_selection.text = str(exhibits.get(stand_key, {}).get("label", "空展台")) if selected_stand >= 0 else "点击 3D 展台选择"
	_income.text = "展览上限  +%d / 趟" % int(museum.get("income", 0))
	_refresh_details()
	_message.text = str(_state.message).get_slice("\n", 0)
	if _message.text.is_empty():
		_message.text = "选中藏品与展台后，展台上会预览模型；安装后计入每趟展览收益。"
	_message.tooltip_text = str(_state.message)
	_layout.call_deferred()
	_notify_stand_selected()

func _notify_stand_selected() -> void:
	# Always publish the current target. The hall de-duplicates identical focus
	# requests itself, so a refresh after an external reset still re-focuses.
	stand_selected.emit(selected_stand)
	zone_selected.emit(selected_zone)
	item_selected.emit(selected_key)

func _refresh_details() -> void:
	var slots: Array = _museum().get("slots", [])
	var stand_key := str(slots[selected_stand]) if selected_stand >= 0 and selected_stand < slots.size() else ""
	var occupied := _row_for(stand_key) if not stand_key.is_empty() else {}
	var staged := _row_for(selected_key) if not selected_key.is_empty() else {}
	_action_mode = ""
	if not staged.is_empty():
		if selected_stand < 0:
			_action_button.text = "选择展台"
			_show_item(staged, "待安装")
		elif stand_key == selected_key:
			_action_mode = "clear"
			_action_button.text = "拆卸"
			_show_item(staged, "已陈列")
		elif stand_key.is_empty():
			_action_mode = "place"
			_action_button.text = "安装"
			_show_item(staged, "待安装")
		else:
			_action_mode = "place"
			_action_button.text = "替换"
			_show_item(staged, "将替换当前藏品")
	elif occupied.is_empty():
		if selected_stand < 0:
			_action_button.text = "选择展台"
			_detail_name.text = "选择一件藏品"
			_detail_info.text = "点击 3D 展台查看陈列，
再从左侧选择藏品安装。"
		else:
			_action_button.text = "空展台"
			_detail_name.text = "空展台"
			_detail_info.text = "从左侧选择藏品后安装到此展台。"
		_detail_bar.value = 0
		_detail_xp.text = ""
	else:
		_action_mode = "clear_display"
		_action_button.text = "拆卸"
		_show_item(occupied, "当前陈列")
	_action_button.disabled = _pending or _action_mode.is_empty()

func _show_item(row: Dictionary, state: String) -> void:
	var level := int(row.get("level", 1))
	var need := int(row.get("need", 0))
	var xp := int(row.get("xp", 0))
	_detail_name.text = "%s  ×%d" % [str(row.get("label", "藏品")), int(row.get("copies", 0))]
	_detail_info.text = "Lv.%d  ·  %s
展台收益 +%d / 趟" % [level, state, int(row.get("income", 0))]
	_detail_bar.max_value = maxi(need, 1)
	_detail_bar.value = xp if need > 0 else 1
	_detail_xp.text = "已满级" if need <= 0 else "经验 %d / %d" % [xp, need]

func select_item(key: String) -> void:
	if not _museum().get("exhibits", {}).has(key):
		return
	selected_key = key
	feedback.emit("ui_click")
	_refresh()

func select_zone(zone: int) -> void:
	var capacity := int(_museum().get("capacity", 6))
	if zone < 0 or zone >= Museum.ZONE_COUNT or zone * Museum.ZONE_SIZE >= capacity:
		return
	selected_zone = zone
	feedback.emit("ui_click")
	_refresh()

func show_warehouse() -> void:
	_refresh()

func inspect_stand(slot: int) -> void:
	var museum := _museum()
	if slot < 0 or slot >= int(museum.get("capacity", 6)):
		return
	selected_stand = slot
	selected_key = ""
	selected_zone = clampi(slot / Museum.ZONE_SIZE, 0, Museum.ZONE_COUNT - 1)
	_refresh()

func _step_stand(direction: int) -> void:
	var capacity := int(_museum().get("capacity", 6))
	if capacity <= 0:
		return
	var next := 0 if direction > 0 else capacity - 1
	if selected_stand >= 0:
		next = posmod(selected_stand + direction, capacity)
	select_stand(next)

func select_stand(slot: int) -> void:
	var capacity := int(_museum().get("capacity", 6))
	if slot < 0 or slot >= capacity:
		return
	selected_stand = slot
	selected_key = ""
	selected_zone = clampi(slot / Museum.ZONE_SIZE, 0, Museum.ZONE_COUNT - 1)
	feedback.emit("ui_click")
	_refresh()

func _request_action() -> void:
	if not is_open or _action_button.disabled or _pending or _action_mode.is_empty():
		return
	_pending = true
	_action_button.disabled = true
	if _action_mode == "place":
		place_requested.emit(selected_key, selected_stand)
	else:
		place_requested.emit("", selected_stand)

func _input(event: InputEvent) -> void:
	if not is_open or not event is InputEventKey:
		return
	if event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		close()
	get_viewport().set_input_as_handled()
