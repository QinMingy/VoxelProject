extends CanvasLayer

const UI = preload("res://ui_style.gd")

signal opened
signal closed
signal upgrade_requested(id: String)
signal zone_selected(id: String)
signal deploy_requested
signal trial_requested

var is_open := false
var _state: Dictionary = {
	"bank": 0, "upgrades": [], "zones": [], "selected_zone": "",
	"stats": {}, "receipt": "", "message": "",
}
var _modal: Control
var _balance: Label
var _equipment: Label
var _upgrade_list: VBoxContainer
var _zone_list: VBoxContainer
var _zone_details: Label
var _deploy_button: Button
var _trial_button: Button
var _receipt: Label
var _message: Label
var _upgrade_controls: Dictionary = {}
var _zone_controls: Dictionary = {}
var _zone_group := ButtonGroup.new()


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 25


func _ready() -> void:
	_build()
	_refresh()
	_modal.visible = is_open


func open() -> void:
	if is_open:
		return
	is_open = true
	if is_instance_valid(_modal):
		_modal.show()
		_refresh()
	opened.emit()


func close() -> void:
	if not is_open:
		return
	is_open = false
	if is_instance_valid(_modal):
		_modal.hide()
	closed.emit()


func sync_state(data: Dictionary) -> void:
	for key: String in _state:
		if data.has(key):
			_state[key] = data[key]
	if is_instance_valid(_modal):
		_refresh()


func _build() -> void:
	_modal = Control.new()
	_modal.name = "BaseRoot"
	_modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal.mouse_filter = Control.MOUSE_FILTER_STOP
	_modal.theme = _make_theme()
	add_child(_modal)
	var shade := ColorRect.new()
	shade.name = "Backdrop"
	shade.color = Color(0.015, 0.025, 0.045, 0.91)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal.add_child(shade)
	var window := PanelContainer.new()
	window.name = "BaseWindow"
	_modal.add_child(window)
	window.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	window.offset_left = -510
	window.offset_right = 510
	window.offset_top = -334
	window.offset_bottom = 334
	window.add_theme_stylebox_override("panel", UI.panel(UI.PANEL, UI.BORDER, 20))
	var content := _column(window, "Content", 10)
	var header := HBoxContainer.new()
	header.name = "Header"
	header.add_theme_constant_override("separation", 18)
	content.add_child(header)
	var heading := _column(header, "Heading", 0)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(_label("月面前哨站", 30, "Title"))
	var subtitle := _label("", 18, "Subtitle")
	subtitle.hide()
	heading.add_child(subtitle)
	_balance = _label("$ 0", 34, "Bank")
	_balance.add_theme_color_override("font_color", UI.ACCENT)
	header.add_child(_balance)
	header.add_child(_button("返回  Esc", "CloseButton", close))
	_equipment = _label("", 18, "EquipmentStats")
	_equipment.hide()
	content.add_child(_equipment)
	content.add_child(HSeparator.new())
	var body := HBoxContainer.new()
	body.name = "Body"
	body.add_theme_constant_override("separation", 18)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(body)
	var shop := _column(body, "Shop", 8)
	shop.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shop.size_flags_stretch_ratio = 1.25
	var shop_title := _label("装备升级", 22, "ShopTitle")
	shop_title.tooltip_text = "永久升级，不占背包。悬停装备可查看说明。"
	shop_title.mouse_filter = Control.MOUSE_FILTER_PASS
	shop.add_child(shop_title)
	var shop_hint := _label("", 18, "ShopHelp")
	shop_hint.hide()
	shop.add_child(shop_hint)
	var shop_scroll := ScrollContainer.new()
	shop_scroll.name = "UpgradeScroll"
	shop_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shop_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	shop.add_child(shop_scroll)
	_upgrade_list = _column(shop_scroll, "UpgradeList", 4)
	_upgrade_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var expedition := _column(body, "Expedition", 8)
	expedition.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	expedition.size_flags_stretch_ratio = 1.0
	expedition.add_child(_label("选择矿区", 22, "ZonesTitle"))
	var zone_scroll := ScrollContainer.new()
	zone_scroll.name = "ZoneScroll"
	zone_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	zone_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	expedition.add_child(zone_scroll)
	_zone_list = _column(zone_scroll, "ZoneList", 10)
	_zone_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_zone_details = _label("请选择矿区", 18, "SelectedZoneDetails")
	_zone_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_zone_details.max_lines_visible = 1
	_zone_details.custom_minimum_size.y = 26
	_zone_details.mouse_filter = Control.MOUSE_FILTER_PASS
	_zone_details.add_theme_color_override("font_color", UI.MUTED)
	expedition.add_child(_zone_details)
	_deploy_button = _button("出发", "DeployButton", _request_deploy)
	_deploy_button.custom_minimum_size.y = 52
	_deploy_button.add_theme_font_size_override("font_size", 22)
	_deploy_button.add_theme_stylebox_override("normal", UI.panel(Color("#23554d"), UI.ACCENT, 10, 8))
	expedition.add_child(_deploy_button)
	_trial_button = _button("24 秒试玩", "TrialButton", _request_trial)
	_trial_button.tooltip_text = "使用选中的矿区，照常扣除门票；本趟氧气限时 24 秒。"
	expedition.add_child(_trial_button)
	var fee_help := _label("", 18, "FeeHelp")
	fee_help.hide()
	expedition.add_child(fee_help)
	var receipt_box := PanelContainer.new()
	receipt_box.name = "Settlement"
	receipt_box.add_theme_stylebox_override("panel", UI.panel(Color("#152638"), UI.BORDER, 8, 8))
	content.add_child(receipt_box)
	_receipt = _label("", 20, "Receipt")
	_receipt.mouse_filter = Control.MOUSE_FILTER_PASS
	_receipt.clip_text = true
	_receipt.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_receipt.max_lines_visible = 1
	_receipt.custom_minimum_size.y = 28
	receipt_box.add_child(_receipt)
	_message = _label("", 18, "Message")
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.max_lines_visible = 2
	_message.mouse_filter = Control.MOUSE_FILTER_PASS
	_message.add_theme_color_override("font_color", UI.WARNING)
	content.add_child(_message)


func _refresh() -> void:
	var bank := int(_state.bank)
	_balance.text = "$ %d" % bank
	var stats: Dictionary = _state.stats
	var columns := int(stats.get("bag_columns", 4))
	var rows := int(stats.get("bag_rows", 4))
	_equipment.text = "已装背包 %d × %d · %d 格   |   开采 %.2f 秒   氧气 %.0f 秒   移速 %.1f m/s   探测 Lv.%d" % [
		columns, rows, columns * rows, float(stats.get("mining_time", 0.9)),
		float(stats.get("oxygen", 0.0)), float(stats.get("walk_speed", 0.0)), int(stats.get("detector_level", 0))]
	_refresh_upgrades(bank)
	_refresh_zones(bank)
	var receipt_text := str(_state.receipt)
	_receipt.text = "结算 · " + receipt_text.get_slice("\n", 0) if not receipt_text.is_empty() else "暂无结算"
	_receipt.tooltip_text = receipt_text
	_message.text = str(_state.message)
	if not _is_warning(_message.text):
		for line: String in receipt_text.split("\n"):
			if _is_warning(line):
				_message.text = line
				break
	_message.tooltip_text = _message.text
	# These hints duplicate controls already visible in the base; keep warnings intact.
	_message.visible = _is_warning(_message.text) or _message.text.contains("不足") or _message.text.contains("临时试玩")


func _is_warning(text: String) -> bool:
	for word: String in ["失败", "无法", "损坏", "未入账", "未保存", "丢失", "警告"]:
		if text.contains(word):
			return true
	return false


func _refresh_upgrades(bank: int) -> void:
	var present: Array[String] = []
	for row: Dictionary in _state.upgrades:
		var id := str(row.get("id", ""))
		if id.is_empty():
			continue
		present.append(id)
		if not _upgrade_controls.has(id):
			_create_upgrade(id)
		var widgets: Dictionary = _upgrade_controls[id]
		var level := int(row.get("level", 0))
		var maximum := int(row.get("max_level", 0))
		var complete := level >= maximum
		var cost := maxi(0, int(row.get("cost", 0)))
		var can_buy := bool(row.get("can_buy", false)) and bank >= cost and not complete
		widgets.title.text = "%s  %d / %d" % [str(row.get("name", id)), level, maximum]
		widgets.effect.text = str(row.get("current", "—"))
		if not complete:
			widgets.effect.text += "  →  " + str(row.get("next", "—"))
		widgets.description.text = str(row.get("description", ""))
		widgets.card.tooltip_text = widgets.description.text + "\n" + widgets.effect.text
		widgets.buy.tooltip_text = widgets.description.text
		widgets.buy.disabled = not can_buy
		if complete:
			widgets.buy.text = "已满级"
		elif bank < cost:
			widgets.buy.text = "$ %d · 不足" % cost
			widgets.buy.tooltip_text += "\n余额不足，还差 $ %d" % (cost - bank)
		else:
			widgets.buy.text = "$ %d" % cost if can_buy else "$ %d · 锁定" % cost
		widgets.effect.add_theme_color_override("font_color", UI.ACCENT if can_buy else UI.MUTED)
	for id: String in _upgrade_controls.keys():
		if id not in present:
			_upgrade_controls[id].card.queue_free()
			_upgrade_controls.erase(id)


func _create_upgrade(id: String) -> void:
	var card := PanelContainer.new()
	card.name = "Upgrade_" + id
	card.add_theme_stylebox_override("panel", UI.panel(Color("#172739"), UI.BORDER, 6, 9))
	_upgrade_list.add_child(card)
	var fields := _column(card, "Fields", 2)
	fields.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override("separation", 6)
	fields.add_child(line)
	var title := _label("", 22, "UpgradeTitle_" + id)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(title)
	var buy := _button("", "Buy_" + id, _request_upgrade.bind(id))
	buy.custom_minimum_size = Vector2(152, 44)
	buy.add_theme_font_size_override("font_size", 20)
	buy.add_theme_stylebox_override("normal", UI.panel(Color("#24473f"), Color("#507d70"), 5, 7))
	buy.add_theme_stylebox_override("hover", UI.panel(Color("#2a5a4e"), UI.ACCENT, 5, 7))
	buy.add_theme_stylebox_override("pressed", UI.panel(Color("#21483e"), UI.ACCENT, 5, 7))
	buy.add_theme_stylebox_override("disabled", UI.panel(Color("#1b2a3c"), UI.BORDER, 5, 7))
	line.add_child(buy)
	var effect := _label("", 18, "UpgradeEffect_" + id)
	effect.clip_text = true
	effect.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	fields.add_child(effect)
	var description := _label("", 18, "UpgradeDescription_" + id)
	description.hide()
	fields.add_child(description)
	_upgrade_controls[id] = {"card": card, "title": title, "effect": effect, "description": description, "buy": buy}


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
		widgets.title.text = ("● " if chosen else "") + str(zone.get("name", id))
		widgets.title.add_theme_color_override("font_color", UI.ACCENT if chosen else UI.TEXT)
		var fee := maxi(0, int(zone.get("fee", 0)))
		widgets.fee.text = "免费" if fee == 0 else "门票 $ %d" % fee
		widgets.fee.add_theme_color_override("font_color", UI.ACCENT if bank >= fee else UI.WARNING)
		var tag := str(zone.get("tag", zone.get("type", "")))
		var info := str(zone.get("description", ""))
		widgets.description.text = {"meadow": "大小均衡 · 浅层", "salvage": "小件密集 · 露头多", "deep": "大件偏多 · 埋藏深"}.get(id, tag)
		widgets.button.tooltip_text = info
		if chosen:
			selected = zone
	for id: String in _zone_controls.keys():
		if id not in present:
			_zone_controls[id].button.queue_free()
			_zone_controls.erase(id)
	var fee := maxi(0, int(selected.get("fee", 0)))
	var affordable := not selected.is_empty() and bank >= fee
	_deploy_button.disabled = not affordable
	_trial_button.disabled = not affordable
	if selected.is_empty():
		_deploy_button.text = "出发"
		_trial_button.text = "24 秒试玩"
		_zone_details.text = "请选择矿区"
		return
	var fee_text := "免费" if fee == 0 else "$ %d" % fee
	_deploy_button.text = "出发  ·  " + fee_text
	_trial_button.text = "24 秒试玩  ·  " + fee_text
	_zone_details.text = "扣门票 $ %d · 剩余 $ %d" % [fee, bank - fee] if affordable else "余额不足 · 还差 $ %d" % (fee - bank)
	_zone_details.add_theme_color_override("font_color", UI.MUTED if affordable else UI.WARNING)
	_zone_details.tooltip_text = str(selected.get("name", ""))
	if selected.has("count"):
		_zone_details.tooltip_text += " · 晶石 %s 颗" % str(selected.count)


func _create_zone(id: String) -> void:
	var button := _button("", "Zone_" + id, _select_zone.bind(id))
	button.custom_minimum_size.y = 76
	button.toggle_mode = true
	button.button_group = _zone_group
	_zone_list.add_child(button)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(margin)
	var lines := _column(margin, "Labels", 2)
	lines.alignment = BoxContainer.ALIGNMENT_CENTER
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var header := HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lines.add_child(header)
	var title := _label("", 22, "ZoneTitle_" + id)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var fee := _label("", 20, "ZoneFee_" + id)
	header.add_child(fee)
	var description := _label("", 18, "ZoneDescription_" + id)
	description.add_theme_color_override("font_color", UI.MUTED)
	lines.add_child(description)
	_zone_controls[id] = {"button": button, "title": title, "fee": fee, "description": description}


func _request_upgrade(id: String) -> void:
	if is_open and _upgrade_controls.has(id) and not _upgrade_controls[id].buy.disabled:
		upgrade_requested.emit(id)


func _select_zone(id: String) -> void:
	if not is_open or not _zone_controls.has(id):
		return
	_state.selected_zone = id
	_refresh_zones(int(_state.bank))
	zone_selected.emit(id)


func _request_deploy() -> void:
	if is_open and not _deploy_button.disabled:
		deploy_requested.emit()


func _request_trial() -> void:
	if is_open and not _trial_button.disabled:
		trial_requested.emit()


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
	button.custom_minimum_size.y = 46
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	return button


func _style(fill: Color, border: Color, padding: int) -> StyleBoxFlat:
	return UI.panel(fill, border, padding)


func _make_theme() -> Theme:
	return UI.theme()
