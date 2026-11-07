extends SceneTree

const Crystal = preload("res://crystal.gd")
const Detector = preload("res://detector.gd")
const RadarPanel = preload("res://detector_panel.gd")
const UI = preload("res://ui_style.gd")
const OUT := "res://.demo-data/radar-overlap-preview"
var objects: Array[Crystal] = []
var panels: Array[RadarPanel] = []
var failed := false

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, description: String) -> void:
	if not condition:
		failed = true
		push_error("RADAR OVERLAP FAIL: " + description)
		quit(1)
		assert(condition, description)

func label(parent: Node, text: String, at: Vector2, size_px: int = 24) -> void:
	var node := Label.new()
	node.text = text
	node.position = at
	node.add_theme_font_size_override("font_size", size_px)
	node.add_theme_color_override("font_color", UI.TEXT)
	parent.add_child(node)

func specimen(position: Vector3) -> Crystal:
	var node := Crystal.new()
	root.add_child(node)
	node.position = position
	objects.append(node)
	return node

func make_panel(at: Vector2, horizontal_distance: float) -> RadarPanel:
	var panel := RadarPanel.new()
	root.add_child(panel)
	check(panel.display_mode == RadarPanel.Mode.CIRCLE, "standalone HUD defaults to circle")
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	panel.position = at
	panel.size = Vector2(RadarPanel.CIRCLE_WIDTH, RadarPanel.CIRCLE_HEIGHT)
	var close := specimen(Vector3(horizontal_distance, -1.5, 0))
	var front := specimen(Vector3(0, -1.0, -5))
	var outside := specimen(Vector3(0, -11, 0))
	panel.set_reading(Detector.sample(Vector3.ZERO, Vector3.FORWARD, [close, front, outside], null, 0))
	panel.set_enabled(true)
	check(panel.marker_layout().size() == 2, "only the two physically in-range objects appear")
	var expected := RadarPanel.RADAR_CENTER + Vector2(54.0 * horizontal_distance / 10.0, 0)
	check((panel.marker_layout()[0].position as Vector2).is_equal_approx(expected), "close item reaches its true near-centre position")
	panels.append(panel)
	return panel

func run() -> void:
	root.size = Vector2i(1100, 720)
	var backdrop := ColorRect.new()
	backdrop.color = Color("#0b1522")
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(backdrop)
	label(backdrop, "圆形雷达 · 中央回波检查", Vector2(72, 60), 34)
	label(backdrop, "左：目标在脚下；右：水平偏移 0.2 米", Vector2(72, 118), 24)
	var centred := make_panel(Vector2(150, 220), 0.0)
	make_panel(Vector2(620, 220), 0.2)
	label(backdrop, "绿色回波可与白色箭头重合，位置不再被推离圆心。", Vector2(72, 500), 24)
	label(backdrop, "两侧均保留前方目标；超过探测范围的深埋目标不显示。", Vector2(72, 548), 21)
	for frame in range(8):
		await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var screenshot := root.get_texture().get_image()
		var point := Vector2i(centred.global_position + RadarPanel.RADAR_CENTER)
		var colour := screenshot.get_pixelv(point)
		check(colour.g > colour.r + 0.08 and colour.g > colour.b + 0.02, "centre echo remains visibly green through the player-arrow outline")
		check(DirAccess.make_dir_recursive_absolute(OUT) == OK, "create visual evidence directory")
		check(screenshot.save_png(OUT + "/circle-centre-overlap.png") == OK, "save native overlap screenshot")
	for panel in panels:
		panel.queue_free()
	for object in objects:
		object.queue_free()
	backdrop.queue_free()
	await process_frame
	print("RADAR_OVERLAP_OK exact_centre=true near_centre=true out_of_range_hidden=true visible_echo=true")
	quit(1 if failed else 0)
