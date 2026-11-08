extends CanvasLayer
const TouchScroll = preload("res://touch_scroll.gd")

signal closed

const UI = preload("res://ui_style.gd")
const Museum = preload("res://museum.gd")
const Palette = preload("res://palette.gd")

var is_open := false
var _modal: Control
var _shade: ColorRect
var _window: PanelContainer
var _title: Label
var _summary: Label
var _rows: VBoxContainer
var _data: Dictionary = {}
var _animations: Array[Dictionary] = []
var _tweens: Array[Tween] = []

func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 32

func _ready() -> void:
	_build()

func open(data: Dictionary) -> void:
	if not is_instance_valid(_modal):
		return
	_data = data.duplicate(true)
	_rebuild()
	_modal.show()
	is_open = true
	_play_open()
	_animate_rows()

func close() -> void:
	if not is_open:
		return
	_kill_tweens()
	is_open = false
	if is_instance_valid(_modal):
		_modal.hide()
	closed.emit()

func _build() -> void:
	_modal = Control.new()
	_modal.name = "SettlementRoot"
	_modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal.theme = UI.theme()
	add_child(_modal)
	var shade := ColorRect.new()
	_shade = shade
	shade.color = Color(0.04, 0.07, 0.11, 0.82)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal.add_child(center)
	_window = PanelContainer.new()
	_window.name = "SettlementWindow"
	_window.custom_minimum_size = Vector2(620, 470)
	_window.add_theme_stylebox_override("panel", UI.panel(UI.PANEL, UI.BORDER, 22))
	center.add_child(_window)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	_window.add_child(column)
	_title = _label("安全返航", 28, UI.TEXT)
	column.add_child(_title)
	_summary = _label("", 18, UI.MUTED)
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_summary)
	column.add_child(HSeparator.new())
	var scroll := TouchScroll.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 270
	column.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 8)
	scroll.add_child(_rows)
	var confirm := Button.new()
	confirm.name = "SettlementConfirm"
	confirm.text = "确认"
	confirm.custom_minimum_size.y = 48
	confirm.pressed.connect(close)
	column.add_child(confirm)
	_modal.visible = false

func _rebuild() -> void:
	_kill_tweens()
	_animations.clear()
	for child: Node in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	var emergency := bool(_data.get("emergency", false))
	_title.text = "紧急救援" if emergency else "安全返航"
	var income := int(_data.get("income", 0))
	var fee := int(_data.get("fee", 0))
	if emergency:
		_summary.text = "氧气耗尽，背包里的物品全部掉落；展馆收入 0、门票 %d。" % fee
	else:
		_summary.text = "展馆收入 %d · 门票 %d · 净收益 %+d" % [income, fee, income - fee]
		if int(_data.get("income_overflow", 0)) > 0:
			_summary.text += "\n余额达到上限，%d 未入账" % int(_data.get("income_overflow", 0))
	var kept: Array = _data.get("kept", [])
	var lost: Array = _data.get("lost", [])
	for change: Dictionary in kept:
		_add_kept_row(change)
	for row: Dictionary in lost:
		_add_lost_row(row)
	if kept.is_empty() and lost.is_empty():
		_rows.add_child(_label("这趟没有带回任何物品。", 18, UI.MUTED))

func _add_kept_row(change: Dictionary) -> void:
	var panel := _row_panel(false)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	var top := HBoxContainer.new()
	box.add_child(top)
	var name_label := _label("%s ×%d" % [str(change.get("label", "藏品")), int(change.get("count", 0))], 20, UI.TEXT)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name_label)
	var state := _label("", 18, UI.ACCENT)
	state.name = "LevelText"
	top.add_child(state)
	var bar := ProgressBar.new()
	bar.name = "Experience"
	bar.show_percentage = false
	bar.custom_minimum_size.y = 10
	bar.max_value = 1.0
	bar.add_theme_stylebox_override("background", UI.panel(Palette.DEEP_SLATE, Color.TRANSPARENT, 0, 2))
	bar.add_theme_stylebox_override("fill", UI.panel(UI.ACCENT, Color.TRANSPARENT, 0, 2))
	box.add_child(bar)
	var xp_label := _label("", 16, UI.MUTED)
	xp_label.name = "ExperienceText"
	box.add_child(xp_label)
	_rows.add_child(panel)
	_animations.append({"change": change, "panel": panel, "bar": bar, "state": state, "xp": xp_label})
	_apply_progress(_animations[-1], float(change.get("copies_before", 0)))

func _add_lost_row(row: Dictionary) -> void:
	var panel := _row_panel(true)
	var line := HBoxContainer.new()
	panel.add_child(line)
	var name_label := _label("%s ×%d" % [str(row.get("label", "物品")), int(row.get("count", 0))], 20, UI.TEXT)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(name_label)
	line.add_child(_label("掉落", 18, UI.DANGER))
	_rows.add_child(panel)

func _row_panel(danger: bool) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = UI.PANEL
	style.border_color = UI.DANGER if danger else UI.BORDER
	style.set_border_width_all(2 if danger else 1)
	style.set_corner_radius_all(2)
	style.corner_detail = 2
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)
	return panel

const ROW_STAGGER := 0.06
const LEVEL_PAUSE := 0.12

func _play_open() -> void:
	_window.reset_size()
	_window.pivot_offset = _window.size * 0.5
	_window.modulate.a = 0.0
	_window.scale = Vector2(0.97, 0.97)
	_shade.color.a = 0.0
	var tween := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(_window, "modulate:a", 1.0, 0.18)
	tween.tween_property(_window, "scale", Vector2.ONE, 0.24)
	tween.tween_property(_shade, "color:a", 0.82, 0.2)
	_tweens.append(tween)

func _animate_rows() -> void:
	for index in range(_animations.size()):
		var anim: Dictionary = _animations[index]
		var change: Dictionary = anim.change
		var from_copies := float(change.get("copies_before", 0))
		var to_copies := float(change.get("copies_after", from_copies))
		var panel: PanelContainer = anim.panel
		panel.modulate.a = 0.0
		var tween := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tween.tween_interval(ROW_STAGGER * float(index))
		tween.tween_property(panel, "modulate:a", 1.0, 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		if to_copies > from_copies:
			var boundaries: Array[float] = []
			for level in range(2, Museum.MAX_LEVEL + 1):
				var boundary := float(Museum.copies_for_level(level))
				if boundary > from_copies and boundary <= to_copies:
					boundaries.append(boundary)
			# Long jumps pause less at each level-up so the whole row stays short.
			var segment_cap := 0.5 if boundaries.size() <= 3 else 0.2
			var cursor := from_copies
			for boundary: float in boundaries:
				_append_segment(tween, anim, cursor, boundary, segment_cap)
				tween.tween_callback(_flash_level.bind(anim))
				tween.tween_interval(LEVEL_PAUSE)
				cursor = boundary
			if cursor < to_copies:
				_append_segment(tween, anim, cursor, to_copies, segment_cap)
		_tweens.append(tween)

func _append_segment(tween: Tween, anim: Dictionary, from_copies: float, to_copies: float, cap: float) -> void:
	var span := to_copies - from_copies
	if span <= 0.0:
		return
	tween.tween_method(func(value: float) -> void: _apply_progress(anim, value),
		from_copies, to_copies, clampf(0.1 * span, 0.12, cap)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _flash_level(anim: Dictionary) -> void:
	var state: Label = anim.state
	state.modulate = Color(1.55, 1.55, 1.35, 1.0)
	var flash := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	flash.tween_property(state, "modulate", Color.WHITE, 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tweens.append(flash)

func _apply_progress(anim: Dictionary, copies: float) -> void:
	var change: Dictionary = anim.change
	var level := Museum.level_for(int(floor(copies)))
	var before := int(change.get("level_before", 1))
	var bar: ProgressBar = anim.bar
	var state: Label = anim.state
	var xp_label: Label = anim.xp
	if level >= Museum.MAX_LEVEL:
		bar.max_value = 1.0
		bar.value = 1.0
		xp_label.text = "已满级"
	else:
		var need := maxi(Museum.need_for(level), 1)
		var base := float(Museum.copies_for_level(level))
		bar.max_value = float(need)
		bar.value = clampf(copies - base, 0.0, float(need))
		xp_label.text = "经验 %d / %d" % [int(floor(bar.value)), need]
	state.text = "Lv.%d" % maxi(level, 1) if level <= before else "Lv.%d → Lv.%d" % [maxi(before, 1), level]

func _kill_tweens() -> void:
	for tween: Tween in _tweens:
		if is_instance_valid(tween):
			tween.kill()
	_tweens.clear()

func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label
