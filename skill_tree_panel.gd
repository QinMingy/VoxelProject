extends CanvasLayer
const TouchScroll = preload("res://touch_scroll.gd")

signal opened
signal closed
signal upgrade_requested(id: String)
signal feedback(event: String)

const UI = preload("res://ui_style.gd")
const Progression = preload("res://progression.gd")
const Palette = preload("res://palette.gd")
const EQUIPMENT_BRANCHES := ["drill", "mining_radius", "oxygen", "oxygen_supply", "boots", "backpack", "detector", "excavation_range"]
const MUSEUM_BRANCHES := ["museum_capacity", "museum_appeal"]
const BRANCHES := ["drill", "mining_radius", "oxygen", "oxygen_supply", "boots", "backpack", "detector", "excavation_range", "museum_capacity", "museum_appeal"]
const ROMAN := ["I", "II", "III", "IV"]
const NODE_SIZE := Vector2(128, 58)
const NODE_X := [148.0, 328.0, 508.0, 688.0]
const FIRST_Y := 44.0
const ROW_GAP := 66.0

class TreeLinks extends Control:

	var levels: Dictionary = {}
	var flashes: Dictionary = {}
	var branches: Array = EQUIPMENT_BRANCHES.duplicate()

	func _draw() -> void:
		# A shared power bus is decorative; prerequisites only run along each row.
		var first := FIRST_Y + NODE_SIZE.y * 0.5
		var last := first + (branches.size() - 1) * ROW_GAP
		draw_line(Vector2(132, first), Vector2(132, last), UI.BORDER, 2.0, true)
		for index in range(branches.size()):
			var id: String = branches[index]
			var y := first + index * ROW_GAP
			var level := int(levels.get(id, 0))
			draw_circle(Vector2(132, y), 4.0, UI.ACCENT if level > 0 else UI.BORDER)
			draw_line(Vector2(132, y), Vector2(NODE_X[0], y), UI.ACCENT if level > 0 else UI.BORDER, 2.0, true)
			var first_flash := float(flashes.get("%s:1" % id, 0.0))
			if first_flash > 0.0:
				draw_line(Vector2(132, y), Vector2(NODE_X[0], y), Color(UI.ACCENT, first_flash * 0.4), 10.0, true)
			var maximum: int = Progression.UPGRADES[id].costs.size()
			for tier in range(2, maximum + 1):
				var begin := Vector2(NODE_X[tier - 2] + NODE_SIZE.x, y)
				var end := Vector2(NODE_X[tier - 1], y)
				var color := UI.ACCENT if level >= tier else (Palette.MOON_BLUE if level == tier - 1 else UI.BORDER)
				draw_line(begin, end, color, 3.0 if level >= tier else 2.0, true)
				var key := "%s:%d" % [id, tier]
				var flash := float(flashes.get(key, 0.0))
				if flash > 0.0:
					draw_line(begin, end, Color(UI.ACCENT, flash * 0.35), 10.0, true)
					draw_line(begin, end, Color(Color.WHITE, flash), 3.0, true)

var is_open := false
var _state: Dictionary = {"bank": 0, "research_points": 0, "upgrades": [], "stats": {}, "message": ""}
var _active_tab := "equipment"
var _tab_buttons: Dictionary = {}
var _rows: Dictionary = {}
var _nodes: Dictionary = {}
var _branch_labels: Dictionary = {}
var _selected_id := "drill"
var _selected_tier := 1
var _pending_id := ""
var _modal: Control
var _window: PanelContainer
var _tree_scroll: ScrollContainer
var _details_scroll: ScrollContainer
var _links: TreeLinks
var _balance: Label
var _detail_name: Label
var _detail_state: Label
var _detail_values: Label
var _detail_description: Label
var _detail_cost: Label
var _buy_button: Button
var _message: Label
var _entrance: Tween
var _node_tweens: Dictionary = {}
var _link_tweens: Dictionary = {}

func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 27

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
		_animate_entrance()
	opened.emit()

func close() -> void:
	if not is_open:
		return
	is_open = false
	if is_instance_valid(_entrance):
		_entrance.kill()
	if is_instance_valid(_modal):
		_modal.hide()
	closed.emit()

func sync_state(data: Dictionary) -> void:
	var previous := {}
	for id: String in _rows:
		previous[id] = int(_rows[id].level)
	for key: String in _state:
		if data.has(key):
			_state[key] = data[key].duplicate(true) if data[key] is Array or data[key] is Dictionary else data[key]
	_rows.clear()
	for row: Dictionary in _state.upgrades:
		var id := str(row.get("id", ""))
		if Progression.UPGRADES.has(id):
			_rows[id] = row
	if data.has("upgrades"):
		_pending_id = ""
	if is_instance_valid(_modal):
		_refresh()
		if is_open:
			for id: String in _rows:
				var level := int(_rows[id].level)
				if previous.has(id) and level > int(previous[id]):
					for tier in range(int(previous[id]) + 1, level + 1):
						_pulse_purchase(id, tier)

func _label(value: String, font_size: int, color: Color = UI.TEXT) -> Label:
	var label := Label.new()
	label.text = value
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

func _build() -> void:
	_modal = Control.new()
	_modal.name = "SkillTreeRoot"
	_modal.theme = UI.theme()
	_modal.mouse_filter = Control.MOUSE_FILTER_STOP
	_modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_modal)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.015, 0.025, 0.045, 0.95)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modal.add_child(shade)
	_window = PanelContainer.new()
	_window.name = "SkillTreeWindow"
	_window.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_window.add_theme_stylebox_override("panel", UI.panel(UI.PANEL, UI.BORDER, 20, 2))
	_modal.add_child(_window)
	var contents := VBoxContainer.new()
	contents.add_theme_constant_override("separation", 12)
	_window.add_child(contents)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	contents.add_child(header)
	var heading := VBoxContainer.new()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_theme_constant_override("separation", 0)
	header.add_child(heading)
	heading.add_child(_label("科技树", 30))
	heading.add_child(_label("升级永久保留", 18, UI.MUTED))
	for tab: String in ["equipment", "museum"]:
		var tab_button := Button.new()
		tab_button.name = "EquipmentTechTab" if tab == "equipment" else "MuseumTechTab"
		tab_button.text = "远征装备" if tab == "equipment" else "博物馆研究"
		tab_button.custom_minimum_size = Vector2(132, 48)
		tab_button.add_theme_font_size_override("font_size", 20)
		tab_button.pressed.connect(set_tab.bind(tab))
		header.add_child(tab_button)
		_tab_buttons[tab] = tab_button
	_balance = _label("资金 0\n研究 0", 22, UI.ACCENT)
	header.add_child(_balance)
	var back := Button.new()
	back.name = "CloseButton"
	back.text = "返回大厅  Esc"
	back.custom_minimum_size = Vector2(170, 48)
	back.focus_mode = Control.FOCUS_ALL
	back.pressed.connect(close)
	header.add_child(back)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	contents.add_child(body)
	_tree_scroll = TouchScroll.new()
	_tree_scroll.name = "SkillTreeScroll"
	_tree_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tree_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree_scroll.follow_focus = true
	body.add_child(_tree_scroll)
	_links = TreeLinks.new()
	_links.name = "TreeCanvas"
	_links.custom_minimum_size = Vector2(854, FIRST_Y + (EQUIPMENT_BRANCHES.size() - 1) * ROW_GAP + NODE_SIZE.y + 12)
	_links.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_links.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_links.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tree_scroll.add_child(_links)
	for tier in range(NODE_X.size()):
		var caption := _label("阶级 " + ROMAN[tier], 18, UI.MUTED)
		caption.position = Vector2(NODE_X[tier], 8)
		caption.size = Vector2(NODE_SIZE.x, 28)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_links.add_child(caption)
	for index in range(BRANCHES.size()):
		var id: String = BRANCHES[index]
		var row_index := index if index < EQUIPMENT_BRANCHES.size() else index - EQUIPMENT_BRANCHES.size()
		var label := _label(str(Progression.UPGRADES[id].name) + "\nLv.0", 20)
		label.position = Vector2(0, FIRST_Y + row_index * ROW_GAP + 3)
		label.size = Vector2(120, NODE_SIZE.y)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_links.add_child(label)
		_branch_labels[id] = label
		var maximum: int = Progression.UPGRADES[id].costs.size()
		for tier in range(1, maximum + 1):
			var button := Button.new()
			button.name = "Skill_%s_%d" % [id, tier]
			button.position = Vector2(NODE_X[tier - 1], FIRST_Y + row_index * ROW_GAP)
			button.size = NODE_SIZE
			button.pivot_offset = NODE_SIZE * 0.5
			button.add_theme_font_size_override("font_size", 18)
			button.focus_mode = Control.FOCUS_ALL
			button.pressed.connect(select_node.bind(id, tier))
			button.mouse_entered.connect(_hover_node.bind(id, tier, true))
			button.mouse_exited.connect(_hover_node.bind(id, tier, false))
			button.focus_entered.connect(_focus_node.bind(id, tier))
			button.focus_exited.connect(_hover_node.bind(id, tier, false))
			_links.add_child(button)
			_nodes[_key(id, tier)] = button
	_details_scroll = TouchScroll.new()
	_details_scroll.name = "SkillDetailsScroll"
	_details_scroll.custom_minimum_size.x = 282
	_details_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_details_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_details_scroll)
	var details := PanelContainer.new()
	details.name = "SkillDetails"
	details.custom_minimum_size.x = 282
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.size_flags_vertical = Control.SIZE_EXPAND_FILL
	details.add_theme_stylebox_override("panel", UI.panel(Palette.INK, UI.BORDER, 16, 2))
	_details_scroll.add_child(details)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	details.add_child(column)
	_detail_name = _label("选择节点", 26)
	_detail_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_name.custom_minimum_size.x = 250
	_detail_name.size.x = 250
	column.add_child(_detail_name)
	_detail_state = _label("", 20, UI.ACCENT)
	column.add_child(_detail_state)
	column.add_child(HSeparator.new())
	_detail_values = _label("", 20)
	_detail_values.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_values.custom_minimum_size.x = 250
	_detail_values.size.x = 250
	column.add_child(_detail_values)
	_detail_description = _label("", 18, UI.MUTED)
	_detail_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_description.custom_minimum_size.x = 250
	_detail_description.size.x = 250
	column.add_child(_detail_description)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)
	_detail_cost = _label("", 22)
	column.add_child(_detail_cost)
	_buy_button = Button.new()
	_buy_button.name = "PurchaseSkillButton"
	_buy_button.custom_minimum_size.y = 54
	_buy_button.add_theme_font_size_override("font_size", 20)
	_buy_button.pressed.connect(request_selected_upgrade)
	column.add_child(_buy_button)
	_message = _label("", 18, UI.WARNING)
	_message.name = "SkillMessage"
	_message.clip_text = true
	_message.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_message.custom_minimum_size.y = 24
	contents.add_child(_message)
	get_viewport().size_changed.connect(_layout_window)
	_layout_window()

func _layout_window() -> void:
	var available := get_viewport().get_visible_rect().size - Vector2(32, 32)
	var extent := available.min(Vector2(1040, 660)).max(Vector2(1, 1))
	_window.offset_left = -extent.x * 0.5
	_window.offset_right = extent.x * 0.5
	_window.offset_top = -extent.y * 0.5
	_window.offset_bottom = extent.y * 0.5

func _key(id: String, tier: int) -> String:
	return "%s:%d" % [id, tier]

func node_state(id: String, tier: int) -> String:
	if not Progression.UPGRADES.has(id) or tier < 1 or tier > Progression.UPGRADES[id].costs.size() or not _rows.has(id):
		return "unavailable"
	var row: Dictionary = _rows[id]
	var level := int(row.level)
	if tier <= level:
		return "purchased"
	if tier > level + 1:
		return "locked"
	if _pending_id == id:
		return "pending"
	if bool(row.get("can_buy", false)):
		return "available"
	var cost: int = Progression.UPGRADES[id].costs[tier - 1]
	if int(_state.bank) < cost:
		return "unaffordable"
	if int(_state.research_points) < _research_cost(id, tier):
		return "research_shortage"
	return "unavailable"

func _state_label(state: String) -> String:
	match state:
		"purchased": return "已装配"
		"available": return "可升级"
		"locked": return "待解锁"
		"unaffordable": return "资金不足"
		"research_shortage": return "研究点不足"
		"pending": return "处理中"
	return "暂不可用"

func _stat_label(id: String, level: int) -> String:
	var value: Variant = Progression.UPGRADES[id]["values"][level]
	match id:
		"drill": return "%.2f 秒 / 次" % float(value)
		"mining_radius": return "每次开采直径 %.2f 米" % (float(value) * 2.0)
		"oxygen": return "%d 秒氧气" % int(value)
		"oxygen_supply": return "密度 ×%.1f\n每趟补氧上限 +%d 秒" % [float(value) / 0.25, int(Progression.OXYGEN_RECOVERY_LIMITS[level])]
		"boots": return "%.2f 米 / 秒" % float(value)
		"backpack": return "%d × %d 格" % [value.x, value.y]
		"detector": return "%d 米 · %s" % [int(value), ["多目标方位", "扩大范围", "埋深区间", "体积回波"][level]]
		"excavation_range": return "采掘半径 %d 米" % int(value)
		"museum_capacity": return "%d 个展台" % int(value)
		"museum_appeal": return "展览收入 ×%.2f" % float(value)
	return ""

func _refresh() -> void:
	_balance.text = "资金 %d\n研究 %d" % [int(_state.bank), int(_state.research_points)]
	var active: Array = EQUIPMENT_BRANCHES if _active_tab == "equipment" else MUSEUM_BRANCHES
	for tab: String in _tab_buttons:
		(_tab_buttons[tab] as Button).add_theme_stylebox_override("normal", UI.panel(Palette.TEAL_SHADOW if tab == _active_tab else Palette.DEEP_SLATE, UI.ACCENT if tab == _active_tab else UI.BORDER, 10, 2))
	var levels := {}
	for id: String in BRANCHES:
		var definition: Dictionary = Progression.UPGRADES[id]
		var level := int(_rows.get(id, {}).get("level", 0))
		levels[id] = level
		(_branch_labels[id] as Label).text = "%s\nLv.%d" % [definition.name, level]
		(_branch_labels[id] as Label).visible = id in active
		for tier in range(1, definition.costs.size() + 1):
			var button: Button = _nodes[_key(id, tier)]
			var state := node_state(id, tier)
			var selected := id == _selected_id and tier == _selected_tier
			button.visible = id in active
			var border := UI.ACCENT if state in ["purchased", "available"] else UI.BORDER
			var fill := Palette.TEAL_SHADOW if state == "purchased" else (Palette.DEEP_SLATE if state == "available" else Palette.INK)
			var style := UI.panel(fill, UI.TEXT if selected else border, 4, 2)
			style.set_border_width_all(2 if selected else 1)
			button.add_theme_stylebox_override("normal", style)
			button.add_theme_stylebox_override("hover", UI.panel(fill, Palette.CYAN_LIGHT, 4, 2))
			button.add_theme_stylebox_override("pressed", UI.panel(fill, UI.TEXT, 4, 2))
			button.add_theme_color_override("font_color", UI.TEXT if state in ["purchased", "available"] else UI.MUTED)
			var research_cost := _research_cost(id, tier)
			var price := "%d 点" % research_cost if research_cost > 0 else "%d" % int(definition.costs[tier - 1])
			button.text = "%s\n已装配" % ROMAN[tier - 1] if state == "purchased" else "%s · %s\n%s" % [ROMAN[tier - 1], price, _state_label(state)]
			button.tooltip_text = "%s %s\n%s → %s\n%s" % [definition.name, ROMAN[tier - 1], _stat_label(id, tier - 1), _stat_label(id, tier), definition.description]
	_links.levels = levels
	_links.branches = active
	_links.custom_minimum_size.y = FIRST_Y + (active.size() - 1) * ROW_GAP + NODE_SIZE.y + 12
	_links.queue_redraw()
	_refresh_details()
	_message.text = str(_state.message) if not str(_state.message).is_empty() else "点选节点查看效果，确认后升级"
	_message.tooltip_text = _message.text

func _refresh_details() -> void:
	var definition: Dictionary = Progression.UPGRADES[_selected_id]
	var state := node_state(_selected_id, _selected_tier)
	var level := int(_rows.get(_selected_id, {}).get("level", 0))
	var cost: int = definition.costs[_selected_tier - 1]
	var research_cost := _research_cost(_selected_id, _selected_tier)
	_detail_name.text = "%s  %s" % [definition.name, ROMAN[_selected_tier - 1]]
	_detail_state.text = _state_label(state)
	_detail_state.add_theme_color_override("font_color", UI.ACCENT if state in ["purchased", "available"] else UI.WARNING)
	_detail_values.text = "当前\n%s\n\n本节点\n%s" % [_stat_label(_selected_id, level), _stat_label(_selected_id, _selected_tier)]
	if _selected_id == "excavation_range":
		var current_radius := int(definition["values"][level])
		var target_radius := int(definition["values"][_selected_tier])
		_detail_values.text = "本节点  半径 %d 米\n地图直径  %d 米\n\n当前已解锁半径 %d 米" % [target_radius, target_radius * 2, current_radius] if state == "purchased" else "当前  半径 %d 米\n本节点  半径 %d 米\n\n地图直径  %d → %d 米" % [current_radius, target_radius, current_radius * 2, target_radius * 2]
	_detail_description.text = str(definition.description)
	_detail_cost.text = "已装配" if state == "purchased" else ("研究消耗  %d 点" % research_cost if research_cost > 0 else "升级花费  %d" % cost)
	_detail_cost.visible = state != "purchased"
	_buy_button.disabled = state != "available" or not _pending_id.is_empty()
	_buy_button.text = "研究  ·  %d 点" % research_cost if research_cost > 0 else "升级  ·  %d" % cost
	match state:
		"purchased": _buy_button.text = "已装配"
		"locked": _buy_button.text = "先升级同路线前阶"
		"unaffordable": _buy_button.text = "还差 %d" % maxi(0, cost - int(_state.bank))
		"research_shortage": _buy_button.text = "还差 %d 研究点" % maxi(0, research_cost - int(_state.research_points))
		"pending": _buy_button.text = "处理中…"
		"unavailable": _buy_button.text = "暂不可升级"

func _research_cost(id: String, tier: int) -> int:
	var costs: Array = Progression.UPGRADES[id].get("research_costs", [])
	return int(costs[tier - 1]) if tier > 0 and tier <= costs.size() else 0

func set_tab(tab: String) -> void:
	if tab not in ["equipment", "museum"]:
		return
	_active_tab = tab
	var active: Array = EQUIPMENT_BRANCHES if tab == "equipment" else MUSEUM_BRANCHES
	if _selected_id not in active:
		_selected_id = str(active[0])
		_selected_tier = mini(int(_rows.get(_selected_id, {}).get("level", 0)) + 1, Progression.UPGRADES[_selected_id].costs.size())
	if is_instance_valid(_modal):
		_refresh()
		_tree_scroll.scroll_vertical = 0
		_tree_scroll.scroll_horizontal = 0
		_details_scroll.scroll_vertical = 0

func select_node(id: String, tier: int) -> void:
	if not Progression.UPGRADES.has(id) or tier < 1 or tier > Progression.UPGRADES[id].costs.size():
		return
	var changed := _selected_id != id or _selected_tier != tier
	_selected_id = id
	_selected_tier = tier
	if is_instance_valid(_modal):
		_refresh()
		_tree_scroll.ensure_control_visible(_nodes[_key(id, tier)])
		_details_scroll.scroll_vertical = 0
	if changed:
		feedback.emit("ui_click")

func request_selected_upgrade() -> void:
	if not is_open or not _pending_id.is_empty():
		return
	if node_state(_selected_id, _selected_tier) != "available":
		feedback.emit("error")
		return
	# Selection never purchases. One explicit request is held until the owner
	# returns upgrade_rows; the panel never changes bank/levels itself.
	_pending_id = _selected_id
	_refresh()
	upgrade_requested.emit(_selected_id)

func _focus_node(id: String, tier: int) -> void:
	select_node(id, tier)
	_hover_node(id, tier, true)

func _hover_node(id: String, tier: int, hovering: bool) -> void:
	var key := _key(id, tier)
	var button: Button = _nodes[key]
	if _node_tweens.has(key) and is_instance_valid(_node_tweens[key]):
		(_node_tweens[key] as Tween).kill()
	var tween := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(button, "scale", Vector2.ONE * (1.035 if hovering else 1.0), 0.13).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_node_tweens[key] = tween

func _animate_entrance() -> void:
	if is_instance_valid(_entrance):
		_entrance.kill()
	_modal.modulate.a = 0.0
	var target_y := _modal.size.y * 0.5 - _window.size.y * 0.5
	_window.position.y = target_y + 16.0
	_entrance = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_parallel(true)
	_entrance.tween_property(_modal, "modulate:a", 1.0, 0.22)
	_entrance.tween_property(_window, "position:y", target_y, 0.26).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _pulse_purchase(id: String, tier: int) -> void:
	var key := _key(id, tier)
	if not _nodes.has(key):
		return
	var button: Button = _nodes[key]
	if _node_tweens.has(key) and is_instance_valid(_node_tweens[key]):
		(_node_tweens[key] as Tween).kill()
	button.scale = Vector2.ONE
	var tween := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(button, "scale", Vector2.ONE * 1.09, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "scale", Vector2.ONE, 0.27).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_node_tweens[key] = tween
	if _link_tweens.has(key) and is_instance_valid(_link_tweens[key]):
		(_link_tweens[key] as Tween).kill()
	_links.flashes[key] = 1.0
	var glow := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	glow.tween_method(func(value: float) -> void:
		_links.flashes[key] = value
		_links.queue_redraw(), 1.0, 0.0, 0.65)
	_link_tweens[key] = glow

func _unhandled_input(event: InputEvent) -> void:
	if is_open and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
