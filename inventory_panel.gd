extends CanvasLayer

signal closed
signal drop_requested(item_id: int)
signal pending_requested
signal feedback(event: String)

const Inventory = preload("res://inventory.gd")
const UI = preload("res://ui_style.gd")

class InventoryGrid extends Control:
	signal cell_clicked(cell: Vector2i)
	const CELL := 73.0
	var cell_size := CELL
	var inventory: RefCounted
	var selected_id := -1
	var preview_rotated := false
	var hover_cell := Vector2i(-1, -1)
	var known := false

	func fit_dimensions(columns: int, rows: int) -> void:
		cell_size = minf(CELL, minf(365.0 / maxi(1, columns), 320.0 / maxi(1, rows)))
		custom_minimum_size = Vector2(columns, rows) * cell_size
		queue_redraw()

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_exited.connect(func() -> void:
			hover_cell = Vector2i(-1, -1)
			queue_redraw())

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseMotion:
			hover_cell = Vector2i(floori(event.position.x / cell_size), floori(event.position.y / cell_size))
			queue_redraw()
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			cell_clicked.emit(Vector2i(floori(event.position.x / cell_size), floori(event.position.y / cell_size)))
			accept_event()

	func _draw() -> void:
		if inventory == null:
			return
		var font := get_theme_default_font()
		for y in range(inventory.rows):
			for x in range(inventory.columns):
				var rect := Rect2(Vector2(x, y) * cell_size + Vector2(2, 2), Vector2.ONE * (cell_size - 4))
				draw_style_box(_tile_style(Color("#0a1521"), UI.BORDER, 1), rect)
		for item: Dictionary in inventory.items:
			var size := Inventory.footprint(item, item.rotated)
			var rect := Rect2(Vector2(item.pos) * cell_size + Vector2(4, 4), Vector2(size) * cell_size - Vector2(8, 8))
			var selected := int(item.id) == selected_id
			var color := Color("#264743") if selected else Color("#1a2e3e")
			var border := UI.ACCENT if selected else Color("#4a6779")
			var line_width := 3 if selected else 1
			draw_style_box(_tile_style(color, border, line_width), rect)
			# The silhouette and price stay readable even in a 64 px one-cell item.
			# Wear, name and footprint belong to the selected item's detail panel.
			var radius := minf(17.0, rect.size.x * 0.17)
			var center := rect.position + Vector2(rect.size.x * 0.5, rect.size.y * 0.36)
			var gem := PackedVector2Array([center + Vector2(0, -radius), center + Vector2(radius * 0.72, -radius * 0.15), center + Vector2(radius * 0.52, radius * 0.65), center + Vector2(0, radius), center + Vector2(-radius * 0.72, radius * 0.15), center + Vector2(-radius * 0.52, -radius * 0.65)])
			draw_colored_polygon(gem, UI.ACCENT if selected else Color("#8cabc5"))
			draw_line(center + Vector2(0, -radius), center + Vector2(-radius * 0.2, radius * 0.25), Color("#d5fff1"), 1.5, true)
			var price := str(roundi(float(item.base_value) * (100 - int(item.wear)) / 100.0)) if known else "?"
			draw_string(font, rect.position + Vector2(3, rect.size.y - 7), price, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 6, 20, UI.TEXT)
		if selected_id >= 0 and hover_cell.x >= 0 and hover_cell.y >= 0:
			var selected: Dictionary = inventory.get_item(selected_id)
			if not selected.is_empty():
				var valid: bool = inventory.can_place(selected, hover_cell, preview_rotated, selected_id)
				var tint := Color(0.38, 0.94, 0.68, 0.22) if valid else Color(1.0, 0.30, 0.32, 0.25)
				var rect := Rect2(Vector2(hover_cell) * cell_size + Vector2(2, 2), Vector2(Inventory.footprint(selected, preview_rotated)) * cell_size - Vector2(4, 4))
				draw_rect(rect, tint)
				draw_rect(rect, Color("#80f2b9") if valid else Color("#ff7483"), false, 3.0)

	static func _tile_style(fill: Color, border: Color, line_width: int) -> StyleBoxFlat:
		var style := StyleBoxFlat.new()
		style.bg_color = fill
		style.border_color = border
		style.set_border_width_all(line_width)
		style.set_corner_radius_all(7)
		return style

var is_open := false
var inventory: RefCounted
var known := false
var pending_item: Dictionary = {}
var selected_id := -1
var preview_rotated := false
var _root_control: Control
var _grid: InventoryGrid
var _usage: Label
var _details: Label
var _pending_info: Label
var _drop_button: Button
var _rotate_button: Button
var _pending_button: Button
var _notice: Label
var _status: Label

func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_root_control.hide()

func _build() -> void:
	_root_control = Control.new()
	_root_control.theme = UI.theme()
	_root_control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root_control.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root_control)
	var shade := ColorRect.new()
	shade.color = Color(0.01, 0.02, 0.04, 0.78)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root_control.add_child(shade)
	var panel := PanelContainer.new()
	panel.name = "InventoryWindow"
	_root_control.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -500
	panel.offset_right = 500
	panel.offset_top = -324
	panel.offset_bottom = 324
	panel.add_theme_stylebox_override("panel", UI.panel(UI.PANEL, UI.BORDER, 24))
	var contents := VBoxContainer.new()
	contents.add_theme_constant_override("separation", 16)
	panel.add_child(contents)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 18)
	contents.add_child(header)
	var title := _label("采集背包", 30)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_status = _label("氧气已暂停", 20)
	_status.modulate = UI.ACCENT
	header.add_child(_status)
	var close_button := _button("继续  [B / Esc]", close)
	header.add_child(close_button)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 28)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	contents.add_child(body)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 365
	left.add_theme_constant_override("separation", 14)
	body.add_child(left)
	_usage = _label("", 22)
	left.add_child(_usage)
	_grid = InventoryGrid.new()
	_grid.name = "InventoryGrid"
	_grid.fit_dimensions(Inventory.COLUMNS, Inventory.ROWS)
	_grid.clip_contents = true
	_grid.cell_clicked.connect(_on_cell_clicked)
	left.add_child(_grid)
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 440
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 12)
	body.add_child(right)
	_details = _label("点选晶石查看详情", 22)
	_details.custom_minimum_size.y = 140
	_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_details)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	right.add_child(actions)
	_rotate_button = _button("旋转  [R]", _on_rotate)
	_rotate_button.name = "RotateButton"
	_rotate_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(_rotate_button)
	_drop_button = _button("丢弃  [Delete]", _on_drop)
	_drop_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_drop_button.add_theme_color_override("font_color", UI.WARNING)
	actions.add_child(_drop_button)
	_pending_info = _label("", 20)
	_pending_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pending_info.modulate = UI.WARNING
	right.add_child(_pending_info)
	_pending_button = _button("装入待拾取晶石", func() -> void: pending_requested.emit())
	right.add_child(_pending_button)
	var help := _label("点选 / 放置  ·  R 旋转  ·  右键取消  ·  Delete 丢弃", 18)
	help.modulate = UI.MUTED
	contents.add_child(help)
	_notice = _label("", 18)
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notice.custom_minimum_size.y = 24
	_notice.modulate = UI.WARNING
	contents.add_child(_notice)

func _label(value: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _button(value: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = value
	button.custom_minimum_size.y = 48
	button.add_theme_font_size_override("font_size", 20)
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	return button

func open(model: RefCounted, is_known: bool, oxygen_remaining: float, waiting_item: Dictionary = {}) -> void:
	inventory = model
	known = is_known
	pending_item = waiting_item.duplicate(true)
	selected_id = -1
	preview_rotated = false
	is_open = true
	_status.text = "氧气暂停 · %02d 秒" % ceili(oxygen_remaining)
	_notice.text = ""
	_root_control.show()
	_grid.fit_dimensions(inventory.columns, inventory.rows)
	_grid.inventory = inventory
	refresh(known)

func close() -> void:
	if not is_open:
		return
	is_open = false
	_root_control.hide()
	selected_id = -1
	closed.emit()

func refresh(is_known: bool) -> void:
	known = is_known
	if inventory == null:
		return
	_grid.inventory = inventory
	_grid.fit_dimensions(inventory.columns, inventory.rows)
	_grid.known = known
	_grid.selected_id = selected_id
	_grid.preview_rotated = preview_rotated
	_grid.queue_redraw()
	_usage.text = "%d / %d 格   ·   %d 件" % [inventory.used_cells(), inventory.columns * inventory.rows, inventory.items.size()]
	var selected: Dictionary = inventory.get_item(selected_id)
	_drop_button.disabled = selected.is_empty()
	_rotate_button.disabled = selected.is_empty()
	if selected.is_empty():
		_details.text = "点选晶石查看详情"
	else:
		var size := Inventory.footprint(selected, preview_rotated)
		_details.text = "%s\n磨损 %d%%\n%s\n占格 %d × %d" % [selected.get("label", "晶石"), int(selected.wear), _price_text(selected), size.x, size.y]
	_pending_button.visible = not pending_item.is_empty()
	_pending_info.visible = not pending_item.is_empty()
	if not pending_item.is_empty():
		var size: Vector2i = pending_item.get("footprint", Vector2i.ONE)
		_pending_info.text = "待拾取 · %s\n%d × %d 格  ·  磨损 %d%%\n%s" % [pending_item.get("label", "晶石"), size.x, size.y, int(pending_item.wear), _price_text(pending_item)]

func set_pending_item(item: Dictionary) -> void:
	pending_item = item.duplicate(true)
	refresh(known)

func set_pending(item: Dictionary) -> void:
	set_pending_item(item)

func set_notice(value: String) -> void:
	_notice.text = value

func _price_text(item: Dictionary) -> String:
	if not known:
		return "估价 ? · 未鉴定"
	var price := roundi(float(item.base_value) * (100 - int(item.wear)) / 100.0)
	return "估价 %d" % price

func _on_cell_clicked(cell: Vector2i) -> void:
	var clicked: Dictionary = inventory.item_at(cell)
	if selected_id < 0:
		if not clicked.is_empty():
			selected_id = int(clicked.id)
			preview_rotated = clicked.rotated
			feedback.emit("ui_click")
	else:
		if inventory.move_item(selected_id, cell, preview_rotated):
			feedback.emit("ui_click")
			_notice.text = "已放置"
			selected_id = -1
		elif not clicked.is_empty() and int(clicked.id) != selected_id:
			selected_id = int(clicked.id)
			preview_rotated = clicked.rotated
			_notice.text = "已选择 · 点击空位放置"
		else:
			_notice.text = "空间不足 · 旋转或腾出空位"
			feedback.emit("error")
	refresh(known)

func _on_rotate() -> void:
	if selected_id < 0 or inventory.get_item(selected_id).is_empty():
		return
	preview_rotated = not preview_rotated
	feedback.emit("rotate")
	_notice.text = "已旋转 · 点击空位放置"
	refresh(known)

func _on_drop() -> void:
	if selected_id < 0 or inventory.get_item(selected_id).is_empty():
		return
	var item_id := selected_id
	selected_id = -1
	_notice.text = ""
	drop_requested.emit(item_id)
	var still_stored: bool = not inventory.get_item(item_id).is_empty()
	if still_stored:
		selected_id = item_id
	if _notice.text.is_empty():
		_notice.text = "未丢弃 · 物品仍在背包中" if still_stored else "已丢到脚边 · 可再次拾取"
	refresh(known)

func _input(event: InputEvent) -> void:
	if not is_open:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		selected_id = -1
		refresh(known)
		get_viewport().set_input_as_handled()
	elif event is InputEventKey:
		if event.pressed and not event.echo:
			if event.keycode == KEY_ESCAPE or event.physical_keycode in [KEY_B, KEY_TAB, KEY_I]:
				close()
			elif event.physical_keycode == KEY_R and selected_id >= 0:
				_on_rotate()
			elif event.keycode == KEY_DELETE:
				_on_drop()
		get_viewport().set_input_as_handled()
