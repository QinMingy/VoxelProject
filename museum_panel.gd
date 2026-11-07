extends CanvasLayer

signal opened
signal closed
signal donate_requested(uid: int)
signal sell_requested(uid: int)
signal place_requested(key: String, slot: int)
signal research_requested
signal feedback(event: String)

const UI = preload("res://ui_style.gd")
const MuseumDisplay = preload("res://museum_display.gd")
const CATEGORY_KEYS := ["crystal_small", "crystal_medium", "crystal_large", "chest", "shield", "hammer"]
const CATEGORY_NAMES := ["小型晶石", "中型晶石", "大型晶石", "冒险宝箱", "冒险者盾牌", "遗落战锤"]

var is_open := false
var selected_uid := -1
var selected_key := ""
var selected_stand := 0
var _tab := "warehouse"
var _state: Dictionary = {"bank": 0, "research_points": 0, "museum": {}, "message": "", "touch_mode": false}
var _modal: Control
var _window: PanelContainer
var _balance: Label
var _summary: Label
var _message: Label
var _warehouse_tab: Button
var _catalogue_tab: Button
var _warehouse_scroll: ScrollContainer
var _catalogue_scroll: ScrollContainer
var _warehouse_list: VBoxContainer
var _catalogue_list: VBoxContainer
var _detail_name: Label
var _detail_info: Label
var _donate_button: Button
var _sell_button: Button
var _place_button: Button
var _clear_button: Button
var _stand_buttons: Array[Button] = []
var _viewport_container: SubViewportContainer
var _viewport: SubViewport
var _display: MuseumDisplay
var _income: Label
var _entrance: Tween
var _pending := false
var _room_pointer_down := false
var _room_pointer_dragged := false
var _room_pointer_start := Vector2.ZERO
var _room_touch_index := -1

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
	_modal.show()
	_refresh()
	_layout()
	_layout.call_deferred()
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_display.set_active(true)
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
	_room_pointer_down = false
	_room_touch_index = -1
	if is_instance_valid(_entrance):
		_entrance.kill()
	_modal.hide()
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_display.set_active(false)
	closed.emit()

func sync_state(data: Dictionary) -> void:
	for key: String in _state:
		if data.has(key):
			_state[key] = data[key].duplicate(true) if data[key] is Dictionary or data[key] is Array else data[key]
	_pending = false
	if is_instance_valid(_modal):
		_refresh()

func _build() -> void:
	_modal = Control.new()
	_modal.name = "MuseumRoot"
	_modal.theme = UI.theme()
	_modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_modal)
	var background := ColorRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.color = Color("#0a1420")
	_modal.add_child(background)
	_window = PanelContainer.new()
	_window.name = "MuseumWindow"
	_window.add_theme_stylebox_override("panel", UI.panel(UI.PANEL, UI.BORDER, 20, 16))
	_modal.add_child(_window)
	var contents := VBoxContainer.new()
	contents.add_theme_constant_override("separation", 12)
	_window.add_child(contents)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	contents.add_child(header)
	var heading := VBoxContainer.new()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_theme_constant_override("separation", 0)
	header.add_child(heading)
	heading.add_child(_label("仓库", 30))
	_summary = _label("", 18, UI.MUTED)
	heading.add_child(_summary)
	_balance = _label("", 22, UI.ACCENT)
	header.add_child(_balance)
	header.add_child(_button("展馆研究", "ResearchButton", func() -> void: research_requested.emit()))
	header.add_child(_button("返回大厅", "CloseButton", close))
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	contents.add_child(body)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 286
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 0.74
	left.add_theme_constant_override("separation", 10)
	body.add_child(left)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	left.add_child(tabs)
	_warehouse_tab = _button("待整理", "WarehouseTab", func() -> void: _select_tab("warehouse"))
	_warehouse_tab.toggle_mode = true
	_warehouse_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.add_child(_warehouse_tab)
	_catalogue_tab = _button("展品", "CatalogueTab", func() -> void: _select_tab("catalogue"))
	_catalogue_tab.toggle_mode = true
	_catalogue_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.add_child(_catalogue_tab)
	_warehouse_scroll = _scroll(left, "WarehouseScroll")
	_warehouse_list = _column(_warehouse_scroll, "WarehouseList")
	_catalogue_scroll = _scroll(left, "CatalogueScroll")
	_catalogue_list = _column(_catalogue_scroll, "CatalogueList")
	var detail := PanelContainer.new()
	detail.add_theme_stylebox_override("panel", UI.panel(Color("#142638"), UI.BORDER, 14, 12))
	left.add_child(detail)
	var details := _column(detail, "SelectedItemDetails")
	_detail_name = _label("选择一件发现", 23)
	_detail_name.name = "SelectedItemName"
	details.add_child(_detail_name)
	_detail_info = _label("", 18, UI.MUTED)
	_detail_info.name = "SelectedItemInfo"
	_detail_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child(_detail_info)
	_donate_button = _button("登记展品", "DonateButton", _request_donate)
	_donate_button.tooltip_text = "展品登记与重复件研究会消耗这件物品。仓库保留品相最好的一件作为展品，研究升级获得研究点。"
	details.add_child(_donate_button)
	_sell_button = _button("出售", "SellButton", _request_sell)
	details.add_child(_sell_button)
	_place_button = _button("放上展台", "PlaceButton", _request_place)
	details.add_child(_place_button)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 1.65
	right.add_theme_constant_override("separation", 10)
	body.add_child(right)
	var room_card := PanelContainer.new()
	room_card.name = "MuseumRoomCard"
	room_card.add_theme_stylebox_override("panel", UI.panel(Color("#58667f"), UI.BORDER, 0, 12))
	room_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	room_card.custom_minimum_size.y = 300
	right.add_child(room_card)
	_viewport_container = SubViewportContainer.new()
	_viewport_container.name = "MuseumRoomView"
	_viewport_container.stretch = true
	_viewport_container.mouse_target = true
	_viewport_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_viewport_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	room_card.add_child(_viewport_container)
	_viewport = SubViewport.new()
	_viewport.name = "MuseumViewport"
	_viewport.size = Vector2i(720, 420)
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_2X
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_viewport_container.add_child(_viewport)
	_display = MuseumDisplay.new()
	_display.name = "MuseumRoom"
	_viewport.add_child(_display)
	_display.slot_requested.connect(select_stand)
	_viewport_container.gui_input.connect(_room_input)
	_viewport.size_changed.connect(_resize_room)
	var room_caption := _label("点击展台选择  ·  拖动转动视角", 18, UI.MUTED)
	right.add_child(room_caption)
	var stands := HBoxContainer.new()
	stands.add_theme_constant_override("separation", 6)
	right.add_child(stands)
	for slot in range(6):
		var button := _button("%02d" % (slot + 1), "Stand_%d" % slot, select_stand.bind(slot))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.x = 0
		stands.add_child(button)
		_stand_buttons.append(button)
	var operations := HBoxContainer.new()
	operations.add_theme_constant_override("separation", 10)
	right.add_child(operations)
	_income = _label("", 20, UI.ACCENT)
	_income.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_income.tooltip_text = "按出发时的陈列计算，随出舱时间累计，65 秒达到本趟上限。至少出舱 10 秒并安全返航才结算；菜单与离线时间不累计。"
	operations.add_child(_income)
	_clear_button = _button("收回仓库", "ClearStandButton", _request_clear)
	operations.add_child(_clear_button)
	_message = _label("", 18, UI.WARNING)
	_message.name = "MuseumMessage"
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.custom_minimum_size.y = 25
	contents.add_child(_message)

func _scroll(parent: Node, node_name: String) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.name = node_name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 120
	parent.add_child(scroll)
	return scroll

func _column(parent: Node, node_name: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = node_name
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 10)
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
	button.custom_minimum_size.y = 46
	button.add_theme_font_size_override("font_size", 20)
	button.pressed.connect(action)
	return button

func _layout() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var width := minf(1440.0, viewport_size.x - 48.0)
	var height := viewport_size.y - 48.0
	_window.size = Vector2(width, height)
	_window.position = (viewport_size - _window.size) * 0.5
	_resize_room.call_deferred()

func _resize_room() -> void:
	if is_instance_valid(_display):
		_display.set_viewport_size(Vector2(_viewport.size))

func _select_tab(tab: String) -> void:
	_tab = tab
	_pending = false
	feedback.emit("ui_click")
	_refresh()

func _museum() -> Dictionary:
	return _state.get("museum", {})

func _warehouse_item() -> Dictionary:
	for item: Dictionary in _museum().get("warehouse", []):
		if int(item.get("uid", -1)) == selected_uid:
			return item
	return {}

func _key_for_item(item: Dictionary) -> String:
	var kind := str(item.get("item_type", "crystal"))
	if kind != "crystal":
		return kind
	var footprint: Vector2i = item.get("footprint", Vector2i.ONE)
	return "crystal_small" if footprint == Vector2i.ONE else ("crystal_large" if footprint == Vector2i(2, 2) else "crystal_medium")

func _item_name(item: Dictionary) -> String:
	return str(item.get("item_name", item.get("label", "未命名藏品")))

func _known(item: Dictionary) -> bool:
	return _museum().get("identified_types", []).has(str(item.get("item_type", "crystal")))

func _worth(item: Dictionary) -> int:
	return roundi(float(item.get("base_value", 0)) * float(100 - int(item.get("wear", 0))) / 100.0)

func _remove_list_children(list: Control) -> void:
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()

func _refresh() -> void:
	var museum := _museum()
	var warehouse: Array = museum.get("warehouse", [])
	var exhibits: Dictionary = museum.get("exhibits", {})
	var slots: Array = museum.get("slots", [])
	var capacity := int(museum.get("capacity", 3))
	selected_stand = clampi(selected_stand, 0, maxi(0, capacity - 1))
	if not _warehouse_item().is_empty():
		pass
	elif not warehouse.is_empty():
		selected_uid = int(warehouse[0].get("uid", -1))
	else:
		selected_uid = -1
	if selected_key.is_empty() or not exhibits.has(selected_key):
		selected_key = str(exhibits.keys()[0]) if not exhibits.is_empty() else ""
	_balance.text = "资金 %d\n研究点 %d" % [int(_state.bank), int(_state.research_points)]
	_summary.text = "展品 %d / 6  ·  陈列 %d / %d" % [exhibits.size(), int(museum.get("displayed_count", _displayed_count(slots))), capacity]
	_warehouse_tab.text = "待整理 %d" % warehouse.size()
	_catalogue_tab.text = "展品 %d / 6" % exhibits.size()
	_warehouse_tab.button_pressed = _tab == "warehouse"
	_catalogue_tab.button_pressed = _tab == "catalogue"
	_warehouse_tab.add_theme_stylebox_override("normal", UI.panel(Color("#23554d") if _tab == "warehouse" else Color("#213347"), UI.ACCENT if _tab == "warehouse" else UI.BORDER, 10, 8))
	_catalogue_tab.add_theme_stylebox_override("normal", UI.panel(Color("#23554d") if _tab == "catalogue" else Color("#213347"), UI.ACCENT if _tab == "catalogue" else UI.BORDER, 10, 8))
	_warehouse_scroll.visible = _tab == "warehouse"
	_catalogue_scroll.visible = _tab == "catalogue"
	_remove_list_children(_warehouse_list)
	if warehouse.is_empty():
		var empty := _label("仓库还没有发现\n\n出舱挖出完整物品，\n安全回舱后再来看看。", 20, UI.MUTED)
		empty.name = "EmptyWarehouse"
		_warehouse_list.add_child(empty)
	for item: Dictionary in warehouse:
		var uid := int(item.get("uid", -1))
		var price := "估价 %d" % _worth(item) if _known(item) else "售价 ？"
		var button := _button("%s\n磨损 %d%%  ·  %s" % [_item_name(item), int(item.get("wear", 0)), price], "WarehouseItem_%d" % uid, select_warehouse_item.bind(uid))
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size.y = 72
		button.add_theme_stylebox_override("normal", UI.panel(Color("#1b3d43") if uid == selected_uid else Color("#182b3c"), UI.ACCENT if uid == selected_uid else UI.BORDER, 10, 9))
		_warehouse_list.add_child(button)
	_remove_list_children(_catalogue_list)
	for index in range(CATEGORY_KEYS.size()):
		var key: String = CATEGORY_KEYS[index]
		var registered := exhibits.has(key)
		var entry: Dictionary = exhibits.get(key, {})
		var position := slots.find(key)
		var status := "展台 %02d" % (position + 1) if position >= 0 else "未陈列"
		var text := "%s\nLv.%d  ·  %s" % [str(entry.get("label", CATEGORY_NAMES[index])), int(entry.get("level", 0)), status] if registered else "未发现\n等待下一次远征"
		var button := _button(text, "Catalogue_" + key, select_exhibit.bind(key))
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size.y = 72
		button.disabled = not registered
		button.add_theme_stylebox_override("normal", UI.panel(Color("#1b3d43") if key == selected_key else Color("#182b3c"), UI.ACCENT if key == selected_key else UI.BORDER, 10, 9))
		_catalogue_list.add_child(button)
	for index in range(_stand_buttons.size()):
		var enabled := index < capacity
		var key := str(slots[index]) if index < slots.size() else ""
		var button := _stand_buttons[index]
		button.disabled = not enabled
		button.text = "%02d%s" % [index + 1, "" if enabled else " · 锁"]
		button.tooltip_text = str(exhibits.get(key, {}).get("label", "空展台")) if enabled else "升级展馆容量后开放"
		button.add_theme_stylebox_override("normal", UI.panel(Color("#23554d") if index == selected_stand else Color("#213347"), UI.ACCENT if index == selected_stand else UI.BORDER, 6, 8))
	_clear_button.disabled = _pending or selected_stand >= slots.size() or str(slots[selected_stand]).is_empty()
	_income.text = "展览上限  +%d / 趟" % int(museum.get("income", 0))
	_display.set_collection(museum)
	_display.select_stand(selected_stand)
	_refresh_details()
	_message.text = str(_state.message).get_slice("\n", 0)
	if _message.text.is_empty():
		_message.text = "登记展品获得研究点；重复件可研究升级，出售则换取现金。"
	_message.tooltip_text = str(_state.message)
	_layout.call_deferred()

func _displayed_count(slots: Array) -> int:
	var count := 0
	for key: Variant in slots:
		if not str(key).is_empty():
			count += 1
	return count

func _refresh_details() -> void:
	_donate_button.visible = _tab == "warehouse"
	_sell_button.visible = _tab == "warehouse"
	_place_button.visible = _tab == "catalogue"
	if _tab == "catalogue":
		var exhibits: Dictionary = _museum().get("exhibits", {})
		var entry: Dictionary = exhibits.get(selected_key, {})
		var item: Dictionary = entry.get("item", {})
		_detail_name.text = str(entry.get("label", "等待新的发现"))
		_detail_info.text = "Lv.%d  ·  累计研究 %d 件\n磨损 %d%%  ·  已登记展品" % [int(entry.get("level", 1)), int(entry.get("count", 1)), int(item.get("wear", 0))] if not entry.is_empty() else "完整带回并登记物品后，\n它会出现在仓库的展品列表中。"
		_place_button.text = "放到展台 %02d" % (selected_stand + 1)
		_place_button.disabled = _pending or entry.is_empty()
		return
	var item := _warehouse_item()
	_donate_button.disabled = _pending or item.is_empty()
	_sell_button.disabled = _pending or item.is_empty()
	if item.is_empty():
		_detail_name.text = "选择一件发现"
		_detail_info.text = "登记后可用于布展，\n出售换取下一趟的资金。"
		_donate_button.text = "登记展品"
		_sell_button.text = "出售"
		return
	_detail_name.text = _item_name(item)
	var price := "估价 %d" % _worth(item) if _known(item) else "售价？ · 首次出售或登记后揭晓"
	_detail_info.text = "磨损 %d%%  ·  完整度 %d%%\n%s" % [int(item.get("wear", 0)), 100 - int(item.get("wear", 0)), price]
	var exhibits: Dictionary = _museum().get("exhibits", {})
	var entry: Dictionary = exhibits.get(_key_for_item(item), {})
	_donate_button.text = "登记展品  +1 研究点"
	if not entry.is_empty():
		if int(entry.get("level", 1)) < int(_museum().get("max_level", 3)):
			_donate_button.text = "研究升级  Lv.%d → %d" % [int(entry.level), int(entry.level) + 1]
		else:
			var current_item: Dictionary = entry.get("item", {})
			if int(item.get("wear", 0)) < int(current_item.get("wear", 0)):
				_donate_button.text = "替换更好品相"
			else:
				_donate_button.text = "展品已满级"
				_donate_button.disabled = true
	_sell_button.text = "出售  %d" % _worth(item) if _known(item) else "出售并鉴定"

func select_warehouse_item(uid: int) -> void:
	selected_uid = uid
	_tab = "warehouse"
	feedback.emit("ui_click")
	_refresh()

func show_warehouse() -> void:
	_tab = "warehouse"
	_refresh()

func inspect_stand(slot: int) -> void:
	var museum := _museum()
	if slot < 0 or slot >= int(museum.get("capacity", 3)):
		return
	selected_stand = slot
	_tab = "catalogue"
	var slots: Array = museum.get("slots", [])
	var key := str(slots[slot]) if slot < slots.size() else ""
	if not key.is_empty() and museum.get("exhibits", {}).has(key):
		selected_key = key
	_refresh()

func select_exhibit(key: String) -> void:
	if not _museum().get("exhibits", {}).has(key):
		return
	selected_key = key
	_tab = "catalogue"
	feedback.emit("ui_click")
	_refresh()

func select_stand(slot: int) -> void:
	var capacity := int(_museum().get("capacity", 3))
	if slot < 0 or slot >= capacity:
		return
	selected_stand = slot
	feedback.emit("ui_click")
	_refresh()

func _request_donate() -> void:
	if not is_open or _donate_button.disabled or _pending:
		return
	_pending = true
	_refresh_details()
	donate_requested.emit(selected_uid)

func _request_sell() -> void:
	if not is_open or _sell_button.disabled or _pending:
		return
	_pending = true
	_refresh_details()
	sell_requested.emit(selected_uid)

func _request_place() -> void:
	if not is_open or _place_button.disabled or _pending:
		return
	_pending = true
	_refresh_details()
	place_requested.emit(selected_key, selected_stand)

func _request_clear() -> void:
	if not is_open or _clear_button.disabled or _pending:
		return
	_pending = true
	_clear_button.disabled = true
	place_requested.emit("", selected_stand)

func _room_input(event: InputEvent) -> void:
	if not is_open or event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		_room_pointer_dragged = _room_pointer_dragged or event.position.distance_to(_room_pointer_start) > 6.0
		if _room_pointer_dragged:
			_display.orbit(-event.relative.x * 0.003)
		_viewport_container.accept_event()
	elif event is InputEventScreenDrag:
		if _room_touch_index >= 0 and event.index != _room_touch_index:
			return
		_room_pointer_dragged = true
		_display.orbit(-event.relative.x * 0.003)
		_viewport_container.accept_event()
	elif event is InputEventScreenTouch:
		if event.pressed and _room_touch_index < 0:
			_room_touch_index = event.index
			_begin_room_pointer(event.position)
		elif not event.pressed and event.index == _room_touch_index:
			_end_room_pointer(event.position)
			_room_touch_index = -1
		_viewport_container.accept_event()
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_begin_room_pointer(event.position)
			else:
				_end_room_pointer(event.position)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_display.zoom(-0.35)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_display.zoom(0.35)
		_viewport_container.accept_event()

func _begin_room_pointer(at: Vector2) -> void:
	_room_pointer_down = true
	_room_pointer_dragged = false
	_room_pointer_start = at

func _end_room_pointer(at: Vector2) -> void:
	if _room_pointer_down and not _room_pointer_dragged and at.distance_to(_room_pointer_start) <= 6.0:
		var ratio := Vector2(_viewport.size) / _viewport_container.size.max(Vector2.ONE)
		_display.handle_pointer(at * ratio)
	_room_pointer_down = false

func _input(event: InputEvent) -> void:
	if not is_open or not event is InputEventKey:
		return
	if event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		close()
	get_viewport().set_input_as_handled()
