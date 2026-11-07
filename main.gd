extends Node3D

class MiningRing extends Control:
	var fraction := 0.0

	func _draw() -> void:
		draw_arc(Vector2.ZERO, 21, 0, TAU, 48, Color("#283b51"), 5, true)
		if fraction > 0:
			draw_arc(Vector2.ZERO, 21, -PI / 2, -PI / 2 + TAU * fraction, 48, Color("#6df1d9"), 5, true)

const Terrain = preload("res://terrain.gd")
const Suit = preload("res://suit.gd")
const Crystal = preload("res://crystal.gd")
const AdventureItems = preload("res://adventure_items.gd")
const Appraisal = preload("res://appraisal.gd")
const Inventory = preload("res://inventory.gd")
const InventoryPanel = preload("res://inventory_panel.gd")
const GMPanel = preload("res://gm_panel.gd")
const Progression = preload("res://progression.gd")
const BasePanel = preload("res://base_panel.gd")
const OutpostPanel = preload("res://outpost_panel.gd")
const SkillTreePanel = preload("res://skill_tree_panel.gd")
const MuseumPanel = preload("res://museum_panel.gd")
const Detector = preload("res://detector.gd")
const DetectorPanel = preload("res://detector_panel.gd")
const ActivityBoundary = preload("res://activity_boundary.gd")
const VoxelMovement = preload("res://voxel_movement.gd")
const UI = preload("res://ui_style.gd")
const FirstPersonRig = preload("res://first_person_rig.gd")
const TouchControls = preload("res://touch_controls.gd")
const GameAudio = preload("res://game_audio.gd")
const LANDER := Vector3(-5.7, 0.0, 4.9)
const CRYSTAL_COUNT := 72
const CRYSTAL_SCALE := 0.44
const CAMERA_OFFSET := Vector3(0.68, 0, 2.7)
const DRILL_REACH := 1.65
const ROUND_SECONDS := 65.0
const TRIAL_SECONDS := 24.0
const WALK_SPEED := 3.35
const HATCH_REACH := 2.05
const EYE_HEIGHT := 1.04
const OXYGEN_PER_GRAIN := 0.02
const BRUSH_NAMES := ["球形", "平铲", "钻头"]

var terrain: Terrain
var activity_boundary: ActivityBoundary
var boundary_warning: Label
var world_environment: WorldEnvironment
var suit: Suit
var locomotion := VoxelMovement.new()
var crystal: Crystal
var crystals: Array[Crystal] = []
var carried_crystals: Array[Crystal] = []
var inventory := Inventory.new(4, 4)
var inventory_panel: InventoryPanel
var inventory_open := false
var gm_panel: GMPanel
var gm_open := false
var gm_resume_mouse_capture := true
var progression: Progression
var base_panel: BasePanel
var outpost_panel: OutpostPanel
var skill_tree_panel: SkillTreePanel
var museum_panel: MuseumPanel
var outpost_page := ""
var _outpost_transition := false
var _gm_return_page := ""
var base_open := false
var auto_open_base := true
var profile_transient := false
var base_resume_mouse_capture := true
var walk_speed := WALK_SPEED
var detector_level := 0
var detector_reading: Dictionary = {}
var detector_panel: DetectorPanel
var radar_mode := DetectorPanel.Mode.CIRCLE
var oxygen_card: PanelContainer
var trip_zone: Dictionary = {}
var trip_fee := 0
var trip_id := 0
var trip_elapsed := 0.0
var resume_mouse_capture := true
var pending_pickup: Crystal
# Compatibility view for existing smoke checks; inventory owns the actual snapshots.
var packed_specimens: Array[int]:
	get:
		var conditions: Array[int] = []
		for item in inventory.items:
			conditions.append(item.wear)
		return conditions
var nearest_signal: Crystal
var crystal_scan_time := 0.0
var map_random := RandomNumberGenerator.new()
var adventure_trial := false
var wants_mouse_capture := true
var touch_mode := OS.has_feature("mobile")
var touch_controls: TouchControls
var sfx: GameAudio
var input_focused := true
var capture_guard_until := 0
var show_performance := false
var carrying_cluster := false
var delivered_clusters := 0
var appraisal := Appraisal.new()
var cluster_seen := false
var cluster_inspected := false
var specimen_title: Label
var specimen_info: Label
var specimen_card: PanelContainer
var receipt := ""
var camera: Camera3D
var first_person := false
var first_person_rig: FirstPersonRig
var drill_target := Vector3.ZERO
var hud: Label
var hud_surface: Control
var hint: Label
var oxygen_bar: ProgressBar
var resource_line: Label
var return_hint: Label
var action_label: Label
var action_card: PanelContainer
var notice: Label
var notice_card: PanelContainer
var debug_label: Label
var help_card: PanelContainer
var help_text: Label
var exposure_bar: ProgressBar
var show_help := false
var last_hud_message := ""
var notice_until := 0
var ring: MiningRing
var cursor: MeshInstance3D
var progress := 0.0
var oxygen := ROUND_SECONDS
var oxygen_limit := ROUND_SECONDS
var mining_time := 0.9
var oxygen_grains := 0
var oxygen_recovered := 0.0
var oxygen_recovery_limit := 6.0
var pending_oxygen_grains := 0
var pickup_count := 0.0
var pickup_time := 0.0
var pickup_label: Label
var bank: int:
	get:
		return progression.bank if progression != null else 0
	set(value):
		if progression != null:
			progression.bank = maxi(value, 0)
var upgrades: int:
	get:
		return int(progression.levels.get("drill", 0)) if progression != null else 0
var on_moon := false
var was_interact := false
var was_pickup := false
var was_upgrade := false
var message := "欢迎来到月面前哨站"
var view_yaw := -PI * 0.5
var view_pitch := 0.74
var camera_anchor := Vector3.ZERO
var reticle: Label
var brush := 0
var fragments: Array[Dictionary] = []
var grain := BoxMesh.new()
var dust := StandardMaterial3D.new()
var ore := StandardMaterial3D.new()
var pickup_material := StandardMaterial3D.new()
var flight_rng := RandomNumberGenerator.new()

func _ready() -> void:
	var quick_adventure := OS.get_cmdline_user_args().has("--adventure-trial")
	if quick_adventure:
		progression = Progression.new("")
		appraisal = Appraisal.new("")
		auto_open_base = false
	get_window().title = "月面采掘 · 冒险遗物试挖" if quick_adventure else "月面采掘 · 展览馆大厅"
	sfx = GameAudio.new()
	add_child(sfx)
	if progression == null:
		progression = Progression.new()
	var profile_error := progression.load_profile()
	if profile_error != OK:
		progression = Progression.new("")
		profile_transient = true
		message = "成长存档读取失败，原文件已保留；本次临时试玩不保存"
	receipt = str(progression.last_report.get("text", ""))
	apply_progression()
	appraisal.load_catalogue()
	_sync_museum_catalogue()
	var world := WorldEnvironment.new()
	world_environment = world
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#283143")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#a5b7dc")
	env.ambient_light_energy = 0.7
	# Depth fog is cheap in the Compatibility renderer and leaves nearby ore clear.
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color("#283143")
	env.fog_light_energy = 1.0
	env.fog_sun_scatter = 0.0
	env.fog_density = 1.0
	env.fog_depth_begin = 10.0
	env.fog_depth_end = 28.0
	env.fog_depth_curve = 0.85
	world.environment = env
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58, -33, 0)
	sun.light_color = Color("#fff0d5")
	sun.light_energy = 1.45
	sun.shadow_enabled = true
	add_child(sun)
	terrain = Terrain.new()
	terrain.set_oxygen_supply_density(float(progression.stats().oxygen_supply_density))
	terrain.set_activity_radius(float(progression.stats().activity_radius))
	add_child(terrain)
	activity_boundary = ActivityBoundary.new()
	activity_boundary.set_radius(float(progression.stats().activity_radius))
	add_child(activity_boundary)
	suit = Suit.new()
	add_child(suit)
	suit.position = LANDER + Vector3(1.1, 0, -0.4)
	suit.rotation.y = view_yaw
	build_lander()
	camera = Camera3D.new()
	camera.fov = 62.0
	camera.far = 90.0
	add_child(camera)
	camera.current = true
	first_person_rig = FirstPersonRig.new()
	camera.add_child(first_person_rig)
	first_person_rig.hide()
	camera_anchor = Vector3(suit.position.x, 0.95, suit.position.z)
	update_camera()
	if DisplayServer.get_name() != "headless":
		get_window().focus_entered.connect(_on_window_focus_entered)
		get_window().focus_exited.connect(_on_window_focus_exited)
		if not auto_open_base:
			call_deferred("capture_mouse")
	grain.size = Vector3.ONE * 0.055
	dust.albedo_color = Color("#858ba0")
	ore.albedo_color = Color("#58e8db")
	ore.emission_enabled = true
	ore.emission = Color("#48b9ac")
	ore.emission_energy_multiplier = 0.6
	pickup_material.albedo_color = Color("#8dfff0")
	pickup_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cursor = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.98
	torus.outer_radius = 1.0
	torus.rings = 24
	torus.ring_segments = 6
	cursor.mesh = torus
	cursor.material_override = ore
	add_child(cursor)
	build_hud()
	touch_controls = TouchControls.new()
	add_child(touch_controls)
	touch_controls.look_changed.connect(_on_touch_look)
	touch_controls.action_pressed.connect(_on_touch_action)
	inventory_panel = InventoryPanel.new()
	add_child(inventory_panel)
	inventory_panel.set_catalogue_query(appraisal.is_known)
	inventory_panel.closed.connect(close_inventory)
	inventory_panel.drop_requested.connect(drop_inventory_item)
	inventory_panel.pending_requested.connect(collect_pending_item)
	inventory_panel.feedback.connect(_sound)
	gm_panel = GMPanel.new()
	add_child(gm_panel)
	gm_panel.opened.connect(_on_gm_opened)
	gm_panel.closed.connect(_on_gm_closed)
	gm_panel.action_requested.connect(_on_gm_action)
	gm_panel.technology_requested.connect(_on_gm_technology)
	gm_panel.cleanup_changed.connect(_on_gm_cleanup_changed)
	gm_panel.brush_selected.connect(_on_gm_brush_selected)
	gm_panel.performance_changed.connect(_on_gm_performance_changed)
	gm_panel.radar_mode_selected.connect(set_radar_mode)
	gm_panel.touch_mode_changed.connect(set_touch_mode)
	gm_panel.audio_enabled_changed.connect(func(enabled: bool) -> void:
		sfx.set_muted(not enabled)
		sync_gm_state())
	sync_gm_state()
	base_panel = BasePanel.new()
	add_child(base_panel)
	base_panel.opened.connect(_on_base_opened)
	base_panel.closed.connect(_on_base_closed)
	base_panel.zone_selected.connect(select_zone)
	base_panel.deploy_requested.connect(func() -> void: start_trip(false))
	skill_tree_panel = SkillTreePanel.new()
	add_child(skill_tree_panel)
	skill_tree_panel.opened.connect(_on_base_opened)
	skill_tree_panel.closed.connect(_on_base_closed)
	skill_tree_panel.upgrade_requested.connect(purchase_upgrade)
	skill_tree_panel.feedback.connect(_sound)
	museum_panel = MuseumPanel.new()
	add_child(museum_panel)
	museum_panel.opened.connect(_on_base_opened)
	museum_panel.closed.connect(_on_base_closed)
	museum_panel.donate_requested.connect(on_museum_donate)
	museum_panel.sell_requested.connect(on_museum_sell)
	museum_panel.place_requested.connect(on_museum_place)
	museum_panel.research_requested.connect(open_museum_research)
	museum_panel.feedback.connect(_sound)
	outpost_panel = OutpostPanel.new()
	add_child(outpost_panel)
	outpost_panel.opened.connect(_on_base_opened)
	outpost_panel.closed.connect(_on_base_closed)
	outpost_panel.navigate_requested.connect(show_outpost)
	outpost_panel.debug_requested.connect(open_outpost_gm)
	outpost_panel.display_slot_requested.connect(open_lobby_stand)
	sfx.bind_ui(self)
	if touch_mode:
		set_touch_mode(true)
	else:
		_sync_touch_state()
	update_hud()
	if auto_open_base:
		call_deferred("show_outpost", "title")
	if quick_adventure:
		call_deferred("_start_quick_adventure")
	if DisplayServer.get_name() != "headless":
		prewarm_effects()

func _start_quick_adventure() -> void:
	_on_gm_action("adventure_trial")
	var occupied := 0
	for item in crystals:
		occupied += item.get_world_cells().size()
	print("ADVENTURE_READY items=%d occupied_cells=%d transient_progress=true" % [crystals.size(), occupied])

func prewarm_effects() -> void:
	# Compile effect materials during startup instead of on the first mining hit.
	var preview := SubViewport.new()
	preview.size = Vector2i(32, 32)
	preview.own_world_3d = true
	preview.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(preview)
	# Fog changes the shader variant, so prewarm against the actual scene environment.
	var warm_environment := WorldEnvironment.new()
	warm_environment.environment = world_environment.environment.duplicate()
	preview.add_child(warm_environment)
	var light := DirectionalLight3D.new()
	light.shadow_enabled = true
	preview.add_child(light)
	var warm_camera := Camera3D.new()
	warm_camera.position = Vector3(0, 0, 3)
	preview.add_child(warm_camera)
	warm_camera.current = true
	var materials := [dust, pickup_material, ore]
	for index in range(materials.size()):
		var instance := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3.ONE * 0.5
		instance.mesh = box
		instance.material_override = materials[index]
		instance.position.x = (index - 1) * 0.7
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		preview.add_child(instance)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	preview.queue_free()

func build_lander() -> void:
	var hull := CylinderMesh.new()
	hull.top_radius = 0.57
	hull.bottom_radius = 0.85
	hull.height = 1.15
	hull.radial_segments = 8
	part(hull, LANDER + Vector3.UP * 1.0, Color("#d2d9e5"))
	var beacon := SphereMesh.new()
	beacon.radius = 0.2
	beacon.height = 0.4
	part(beacon, LANDER + Vector3.UP * 1.72, Color("#47d4b8"))
	for x in [-0.78, 0.78]:
		for z in [-0.65, 0.65]:
			var foot := BoxMesh.new()
			foot.size = Vector3(0.29, 0.46, 0.29)
			part(foot, LANDER + Vector3(x, 0.24, z), Color("#72829b"))
	var pad := CylinderMesh.new()
	pad.height = 0.065
	pad.top_radius = 1.32
	pad.bottom_radius = 1.32
	part(pad, LANDER + Vector3.UP * 0.04, Color("#46596d"))

func part(mesh: Mesh, at: Vector3, color: Color) -> void:
	var node := MeshInstance3D.new()
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	node.mesh = mesh
	node.material_override = material
	node.position = at
	add_child(node)

func build_hud() -> void:
	var overlay := CanvasLayer.new()
	add_child(overlay)
	var surface := Control.new()
	hud_surface = surface
	surface.name = "MiningHUD"
	surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	surface.theme = UI.theme()
	overlay.add_child(surface)
	detector_panel = DetectorPanel.new()
	surface.add_child(detector_panel)
	detector_panel.set_enabled(false)
	boundary_warning = hud_label("", 22, UI.DANGER)
	surface.add_child(boundary_warning)
	boundary_warning.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	boundary_warning.offset_left = -195
	boundary_warning.offset_right = 195
	boundary_warning.offset_top = 24
	boundary_warning.offset_bottom = 64
	boundary_warning.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boundary_warning.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	boundary_warning.add_theme_constant_override("outline_size", 3)
	boundary_warning.add_theme_color_override("font_outline_color", UI.PANEL)
	boundary_warning.hide()
	var status := hud_panel(surface, "OxygenCard")
	oxygen_card = status
	status.position = Vector2(24, 24)
	status.custom_minimum_size.x = 320
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 8)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status.add_child(stack)
	var oxygen_row := HBoxContainer.new()
	stack.add_child(oxygen_row)
	var caption := hud_label("O₂  氧气", 20, UI.MUTED)
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	oxygen_row.add_child(caption)
	hud = hud_label("65 s", 42)
	hud.name = "OxygenValue"
	oxygen_row.add_child(hud)
	oxygen_bar = hud_bar()
	stack.add_child(oxygen_bar)
	return_hint = hud_label("", 20, UI.MUTED)
	stack.add_child(return_hint)
	stack.add_child(HSeparator.new())
	resource_line = hud_label("", 20)
	stack.add_child(resource_line)
	hint = hud_label("WASD 移动  ·  空格 跳跃  ·  H 按键", 18, UI.MUTED)
	var keys := hud_panel(surface, "KeyStrip")
	keys.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	keys.offset_left = 24
	keys.offset_top = -64
	keys.offset_bottom = -24
	keys.add_theme_stylebox_override("panel", UI.panel(UI.PANEL, UI.BORDER, 8, 8))
	keys.add_child(hint)
	keys.hide()
	help_card = hud_panel(surface, "KeyHelp")
	help_card.position = Vector2(24, 244)
	var help := hud_label("操作\n\nWASD  移动     空格  跳跃\n左键长按  开采氧矿 / 挖土\nF  收集晶石     E  回舱\nV  第一 / 第三人称\nB  背包     M  基地\nEsc  释放鼠标\nG  调试     H  收起", 20)
	help_text = help
	help_card.add_child(help)
	help_card.hide()
	action_card = hud_panel(surface, "ContextAction")
	action_card.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	action_card.offset_left = -230
	action_card.offset_right = 230
	action_card.offset_top = -118
	action_card.offset_bottom = -62
	action_card.add_theme_stylebox_override("panel", UI.panel(UI.PANEL, UI.BORDER, 12))
	action_label = hud_label("", 24)
	action_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	action_card.add_child(action_label)
	notice_card = hud_panel(surface, "Notice")
	notice_card.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	notice_card.offset_left = -300
	notice_card.offset_right = 300
	notice_card.offset_top = -188
	notice_card.offset_bottom = -132
	notice_card.add_theme_stylebox_override("panel", UI.panel(UI.PANEL, UI.BORDER, 10))
	notice = hud_label("", 20, UI.WARNING)
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice.max_lines_visible = 2
	notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notice_card.add_child(notice)
	notice_card.hide()
	debug_label = hud_label("", 18, UI.ACCENT)
	surface.add_child(debug_label)
	debug_label.position = Vector2(24, 244)
	debug_label.add_theme_constant_override("outline_size", 3)
	debug_label.add_theme_color_override("font_outline_color", UI.PANEL)
	debug_label.hide()
	ring = MiningRing.new()
	ring.hide()
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	surface.add_child(ring)
	reticle = hud_label("+", 22)
	reticle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reticle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	reticle.size = Vector2(24, 24)
	reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	surface.add_child(reticle)
	pickup_label = hud_label("", 28, UI.ACCENT)
	pickup_label.add_theme_constant_override("outline_size", 3)
	pickup_label.add_theme_color_override("font_outline_color", UI.PANEL)
	pickup_label.hide()
	surface.add_child(pickup_label)
	var card := hud_panel(surface, "SpecimenCard")
	specimen_card = card
	card.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	card.offset_left = -344
	card.offset_right = -24
	card.offset_top = 24 + DetectorPanel.HEIGHT + 16
	var details := VBoxContainer.new()
	details.add_theme_constant_override("separation", 8)
	details.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(details)
	specimen_title = hud_label("", 26)
	details.add_child(specimen_title)
	exposure_bar = hud_bar()
	details.add_child(exposure_bar)
	specimen_info = hud_label("", 22)
	specimen_info.custom_minimum_size.x = 280
	specimen_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child(specimen_info)
	detector_panel.set_display_mode(radar_mode)
	_layout_detector_hud()

func _layout_detector_hud() -> void:
	var compass := radar_mode == DetectorPanel.Mode.COMPASS
	oxygen_card.position.y = 144.0 if compass else 24.0
	help_card.position.y = 364.0 if compass else 244.0
	debug_label.position.y = 364.0 if compass else 244.0
	specimen_card.offset_top = 144.0 if compass else 24.0 + DetectorPanel.CIRCLE_HEIGHT + 16.0
	boundary_warning.offset_top = 144.0 if compass else 24.0
	boundary_warning.offset_bottom = boundary_warning.offset_top + 40.0

func set_radar_mode(mode: int) -> void:
	radar_mode = clampi(mode, DetectorPanel.Mode.COMPASS, DetectorPanel.Mode.CIRCLE)
	detector_panel.set_display_mode(radar_mode)
	_layout_detector_hud()
	sync_gm_state()

func hud_label(text: String, font_size: int, color: Color = UI.TEXT) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func hud_panel(parent: Node, node_name: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = node_name
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", UI.panel())
	parent.add_child(panel)
	return panel

func hud_bar() -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size.y = 8
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("background", UI.panel(Color("#293c4a"), Color.TRANSPARENT, 0, 4))
	bar.add_theme_stylebox_override("fill", UI.panel(UI.ACCENT, Color.TRANSPARENT, 0, 4))
	return bar

func _unhandled_input(event: InputEvent) -> void:
	if inventory_open or gm_open or base_open:
		return
	if touch_mode and (event is InputEventMouse or event is InputEventScreenTouch or event is InputEventScreenDrag):
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_M:
		open_base()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode in [KEY_B, KEY_TAB, KEY_I]:
		open_inventory()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F3:
		show_performance = not show_performance
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_H:
		show_help = not show_help
		help_card.visible = show_help
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_V:
		set_first_person(not first_person)
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F9 and not on_moon:
		reset_appraisal_catalogue()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		wants_mouse_capture = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode >= KEY_1 and event.physical_keycode <= KEY_3:
		var selected := int(event.physical_keycode) - int(KEY_1)
		if selected != brush:
			brush = selected
			progress = 0.0
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			wants_mouse_capture = true
			capture_mouse()
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if Time.get_ticks_msec() < capture_guard_until:
			return
		view_yaw -= event.relative.x * 0.003
		view_pitch = clampf(view_pitch + event.relative.y * 0.003, -1.45 if first_person else -0.50, 1.45 if first_person else 1.14)

func capture_mouse() -> void:
	if touch_mode or inventory_open or gm_open or base_open or not wants_mouse_capture or DisplayServer.get_name() == "headless" or not get_window().has_focus():
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Input.warp_mouse(get_viewport().get_visible_rect().get_center())
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	locomotion.sync_jump_input(Input.is_physical_key_pressed(KEY_SPACE))
	capture_guard_until = Time.get_ticks_msec() + 100

func _on_window_focus_entered() -> void:
	input_focused = true
	_sync_touch_state()
	if wants_mouse_capture:
		call_deferred("capture_mouse")

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		_on_window_focus_exited()
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		_on_window_focus_entered()

func _on_window_focus_exited() -> void:
	input_focused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	progress = 0.0
	_suspend_controls()

func _sound(event: String) -> void:
	if is_instance_valid(sfx):
		sfx.play_event(event)

func _suspend_controls() -> void:
	if is_instance_valid(touch_controls):
		touch_controls.release_all()
		touch_controls.set_gameplay_active(false)
	if is_instance_valid(sfx):
		sfx.stop_gameplay_loops()

func _sync_touch_state() -> void:
	if is_instance_valid(touch_controls):
		touch_controls.set_enabled(touch_mode)
		touch_controls.set_gameplay_active(input_focused and not (inventory_open or gm_open or base_open))

func set_touch_mode(enabled: bool) -> void:
	_suspend_controls()
	touch_mode = enabled
	progress = 0.0
	locomotion.sync_jump_input(false)
	wants_mouse_capture = not enabled
	resume_mouse_capture = not enabled
	gm_resume_mouse_capture = not enabled
	base_resume_mouse_capture = not enabled
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_sync_touch_state()
	help_text.text = "触屏操作\n\n左摇杆  移动\n右侧滑动  转动视角\n按住开采并拖动  边挖边看\n拾取  收集松动晶石\n交互  舱边返回 / 整备\n背包内点选、放置、旋转\n再次点击帮助收起" if enabled else "操作\n\nWASD  移动     空格  跳跃\n左键长按  开采氧矿 / 挖土\nF  收集晶石     E  回舱\nV  第一 / 第三人称\nB  背包     M  基地\nEsc  释放鼠标\nG  调试     H  收起"
	if not enabled and not (inventory_open or gm_open or base_open):
		call_deferred("capture_mouse")
	sync_gm_state()
	update_hud()
	sync_base_state()

func _on_touch_look(delta: Vector2) -> void:
	if not touch_mode or not input_focused or inventory_open or gm_open or base_open:
		return
	view_yaw -= delta.x * 0.003
	view_pitch = clampf(view_pitch + delta.y * 0.003, -1.45 if first_person else -0.50, 1.45 if first_person else 1.14)

func _on_touch_action(action: String) -> void:
	if not touch_mode or not input_focused or inventory_open or gm_open or base_open:
		return
	_sound("ui_click")
	match action:
		"pickup": pick_up_cluster()
		"interact":
			if suit.position.distance_to(LANDER) < HATCH_REACH:
				if on_moon: settle(false)
				else: open_base()
			else: _sound("error")
		"backpack": open_inventory()
		"view": set_first_person(not first_person)
		"help":
			show_help = not show_help
			update_hud()
		"base": open_base()

func set_first_person(enabled: bool) -> void:
	first_person = enabled
	view_pitch = clampf(view_pitch, -1.45 if first_person else -0.50, 1.45 if first_person else 1.14)
	progress = 0.0
	ring.hide()
	first_person_rig.set_drilling(false)
	camera_anchor = suit.position + Vector3.UP * (EYE_HEIGHT if first_person else 0.95)
	update_camera()
	update_crystal_targets()
	update_hud()

func update_camera() -> void:
	var view := Basis(Vector3.UP, view_yaw) * Basis(Vector3.RIGHT, -view_pitch)
	suit.visible = not first_person
	first_person_rig.visible = first_person
	camera.fov = 74.0 if first_person else 62.0
	camera.near = 0.04 if first_person else 0.05
	if first_person:
		camera_anchor = suit.position + Vector3.UP * EYE_HEIGHT
		camera.transform = Transform3D(view, camera_anchor)
		return
	var offset := view * CAMERA_OFFSET
	var distance := offset.length()
	var direction := offset / distance
	var obstruction := terrain.raycast_voxels(camera_anchor, direction, distance)
	if not obstruction.is_empty():
		var contact: Vector3 = obstruction.position
		distance = maxf(0.0, camera_anchor.distance_to(contact) - 0.10)
	camera.transform = Transform3D(view, camera_anchor + direction * distance)

func aim_at_terrain() -> Dictionary:
	var hit := terrain.raycast_voxels(camera.position, -camera.basis.z, DRILL_REACH + 0.45 if first_person else 6.1)
	if hit.is_empty():
		return {}
	var point: Vector3 = hit.position
	var normal: Vector3 = hit.normal
	var distance := Vector2(point.x - suit.position.x, point.z - suit.position.z).length()
	if distance > DRILL_REACH or (normal.y > 0.5 and distance < 0.30):
		return {}
	return hit

func has_clearance(x: float, z: float, feet: float) -> bool:
	return locomotion.has_clearance(terrain, x, z, feet)

func constrain_suit_position(at: Vector3) -> Vector3:
	var destination := activity_boundary.clamp_position(at)
	var from_lander := Vector3(destination.x - LANDER.x, 0, destination.z - LANDER.z)
	if from_lander.length_squared() < 0.83 * 0.83:
		var outward := from_lander.normalized() if not from_lander.is_zero_approx() else Vector3.RIGHT
		var edge := LANDER + outward * 0.83
		destination.x = edge.x
		destination.z = edge.z
	return destination

func move_suit(movement: Vector3, delta: float, jump_held: bool = false) -> void:
	var was_grounded := locomotion.grounded
	var old_vertical := locomotion.vertical_speed
	suit.position = locomotion.step(terrain, suit.position, movement * walk_speed, delta,
		jump_held, constrain_suit_position)
	if was_grounded and not locomotion.grounded and locomotion.vertical_speed > 0.0:
		_sound("jump")
	elif not was_grounded and locomotion.grounded and old_vertical < -1.0:
		_sound("land")

func _physics_process(delta: float) -> void:
	if inventory_open or gm_open or base_open or not input_focused:
		return
	if on_moon:
		trip_elapsed += delta
	var action := Input.is_physical_key_pressed(KEY_E)
	var near := suit.position.distance_to(LANDER) < HATCH_REACH
	if near:
		if action and not was_interact:
			if on_moon:
				settle(false)
			else:
				open_base()
	was_interact = action
	var pickup := Input.is_physical_key_pressed(KEY_F)
	if pickup and not was_pickup:
		pick_up_cluster()
	was_pickup = pickup
	if inventory_open or base_open:
		return
	var upgrading := Input.is_physical_key_pressed(KEY_U)
	if not on_moon and near and upgrading and not was_upgrade:
		open_base()
	was_upgrade = upgrading
	if base_open:
		return
	var input := Vector2(
		float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W))
	)
	if touch_mode:
		input = touch_controls.movement_vector()
	var yaw_basis := Basis(Vector3.UP, view_yaw)
	var right := yaw_basis.x
	var down := yaw_basis.z
	var movement := (right * input.x + down * input.y).limit_length()
	var captured := touch_mode or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var old_position := suit.position
	move_suit(movement, delta, touch_controls.jump_held() if touch_mode else captured and Input.is_physical_key_pressed(KEY_SPACE))
	sfx.set_walking(locomotion.grounded and Vector2(suit.position.x - old_position.x, suit.position.z - old_position.z).length_squared() > 0.000001, walk_speed / WALK_SPEED)
	if first_person:
		update_camera()
	var hit := aim_at_terrain() if on_moon else {}
	var can_mine := not hit.is_empty() and terrain.is_activity_cell(hit.cell)
	var target: Vector3 = hit.get("position", Vector3.ZERO)
	var normal: Vector3 = hit.get("normal", Vector3.UP)
	var drilling := can_mine and (touch_controls.mining_held() if touch_mode else captured and Time.get_ticks_msec() >= capture_guard_until and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT))
	sfx.set_drilling(drilling, clampf(0.9 / mining_time, 0.85, 1.4))
	cursor.visible = can_mine
	if can_mine:
		cursor.position = target + normal * 0.035
		cursor.quaternion = Quaternion(Vector3.UP, normal)
		cursor.scale = Vector3.ONE * terrain.brush_radius(brush)
	var facing := target - suit.position if can_mine else -down
	suit.rotation.y = atan2(-facing.x, -facing.z)
	reticle.modulate = Color("#6df1d9") if can_mine else Color("#f4f6ff")
	suit.animate(delta, movement.length_squared() > 0.01, drilling, not locomotion.grounded)
	first_person_rig.animate(delta, movement.length_squared() > 0.01 and locomotion.grounded, drilling)
	if on_moon:
		oxygen = maxf(0.0, oxygen - delta)
		if oxygen > 0.0 and oxygen <= 8.0:
			_sound("oxygen_critical")
		elif oxygen <= 18.0:
			_sound("oxygen_low")
		if oxygen <= 0.0:
			settle(true)
			return
	if drilling:
		progress += delta
		if progress >= mining_time:
			progress -= mining_time
			var found: int = terrain.mine_at(target, normal, brush)
			if terrain.last_removed > 0:
				_sound("dig")
				burst(target + normal * 0.08, found)
				update_crystal_targets()
	else:
		progress = 0.0
	drill_target = target
	ring.visible = drilling
	if drilling:
		ring.fraction = progress / mining_time
		ring.queue_redraw()
	update_fragments(delta)
	crystal_scan_time -= delta
	if on_moon and crystal_scan_time <= 0.0:
		crystal_scan_time = 0.15
		update_crystal_targets()
	update_hud()

func _process(delta: float) -> void:
	if inventory_open or gm_open or base_open:
		return
	if on_moon:
		process_soil_cleanup()
	terrain.update_focus(suit.position)
	activity_boundary.update_player(suit.position)
	var edge_distance := activity_boundary.edge_distance(suit.position)
	boundary_warning.visible = edge_distance < ActivityBoundary.WARNING_DISTANCE
	boundary_warning.modulate.a = activity_boundary.warning_strength
	boundary_warning.text = "活动边界 · 请折返" if edge_distance < 0.7 else "接近边界 · %.1f m" % edge_distance
	if on_moon and edge_distance < 0.7:
		_sound("boundary_warning")
	var anchor_height := suit.position.y + 0.95
	var desired_anchor := Vector3(suit.position.x, anchor_height, suit.position.z)
	camera_anchor = camera_anchor.lerp(desired_anchor, 1.0 - exp(-16.0 * delta))
	update_camera()
	reticle.position = get_viewport().get_visible_rect().size * 0.5 - reticle.size * 0.5
	if ring.visible:
		ring.position = camera.unproject_position(drill_target) + Vector2(0, 16)
	pickup_label.visible = pickup_time > 0.0 and (first_person or not camera.is_position_behind(suit.position))
	if pickup_label.visible:
		if first_person:
			pickup_label.position = get_viewport().get_visible_rect().size * 0.5 + Vector2(-pickup_label.size.x * 0.5, 64)
		else:
			pickup_label.position = camera.unproject_position(suit.position + Vector3.UP * 1.55) - Vector2(pickup_label.size.x * 0.5, 12)

func start_trip(short_oxygen: bool) -> void:
	if on_moon:
		return
	var entry := progression.pay_entry(progression.selected_zone, adventure_trial)
	if not entry.ok:
		message = str(entry.message)
		sync_base_state()
		return
	trip_zone = entry.zone.duplicate(true)
	trip_fee = int(entry.fee)
	trip_id = int(entry.trip_id)
	trip_elapsed = 0.0
	if base_open:
		_close_outpost_for_departure()
	apply_progression()
	# Range and target population are a snapshot for this expedition.
	activity_boundary.set_radius(float(trip_zone.get("activity_radius", progression.stats().activity_radius)))
	terrain.set_activity_radius(activity_boundary.radius)
	terrain.reset_terrain()
	oxygen_grains = 0
	oxygen_recovered = 0.0
	pending_oxygen_grains = 0
	pickup_count = 0.0
	pickup_time = 0.0
	suit.position = LANDER + Vector3(1.1, 0, -0.4)
	suit.position.y = terrain.height_at(suit.position.x, suit.position.z)
	locomotion.reset(Input.is_physical_key_pressed(KEY_SPACE))
	camera_anchor = suit.position + Vector3.UP * 0.95
	update_camera()
	spawn_crystals()
	cluster_seen = false
	cluster_inspected = false
	receipt = ""
	carrying_cluster = false
	oxygen_limit = TRIAL_SECONDS if short_oxygen else float(progression.stats().oxygen)
	oxygen = oxygen_limit
	on_moon = true
	_sound("deploy")
	_sync_touch_state()
	if short_oxygen and not crystals.is_empty():
		var direction := crystals[0].position - suit.position
		view_yaw = atan2(-direction.x, -direction.z)
		view_pitch = 0.24
		update_camera()
	update_crystal_targets()
	message = "遗物试挖 · 舱前有宝箱、盾牌和战锤" if adventure_trial else "%s · 已出舱" % trip_zone.name

func spawn_crystals(seed_value: int = -1) -> void:
	terrain.clear_crystals()
	for item in crystals:
		remove_child(item)
		item.queue_free()
	crystals.clear()
	carried_crystals.clear()
	inventory.clear()
	pending_pickup = null
	crystal = null
	nearest_signal = null
	if seed_value >= 0:
		map_random.seed = seed_value
	else:
		map_random.randomize()
	var zone := trip_zone if not trip_zone.is_empty() else progression.get_zone(progression.selected_zone)
	var item_count := 3 if adventure_trial else int(zone.count)
	# Three nearby crystal sizes remain an accessible starter sample. Relics
	# then scale with the actual deployed area's population, not a fixed six.
	var relic_slots: Dictionary = {}
	if not adventure_trial:
		var relic_count := mini(int(zone.get("relic_count", 3)), item_count - 3)
		for index in range(mini(3, relic_count)):
			relic_slots[index + 3] = index
		var extra_slots: Array[int] = []
		for index in range(6, item_count):
			extra_slots.append(index)
		for index in range(extra_slots.size() - 1, 0, -1):
			var other := map_random.randi_range(0, index)
			var swap := extra_slots[index]
			extra_slots[index] = extra_slots[other]
			extra_slots[other] = swap
		for index in range(maxi(0, relic_count - 3)):
			relic_slots[extra_slots[index]] = (index + 3) % AdventureItems.ITEMS.size()
	for index in range(item_count):
		var site := Vector3.ZERO
		var best_site := Vector3.ZERO
		var best_clearance := -1.0
		for attempt in range(192):
			if index < 14 and attempt < 64:
				var angle := map_random.randf_range(0.0, TAU)
				var radius := map_random.randf_range(4.0, 8.0) if index < 3 else map_random.randf_range(8.0, 16.0)
				site = LANDER + Vector3(cos(angle), 0, sin(angle)) * radius
			else:
				var angle := map_random.randf_range(0.0, TAU)
				var radius := sqrt(map_random.randf()) * (activity_boundary.radius - 1.5)
				site = Vector3(cos(angle), 0, sin(angle)) * radius
			site.x = snappedf(site.x, Terrain.CELL_SIZE)
			site.z = snappedf(site.z, Terrain.CELL_SIZE)
			if not terrain.is_in_activity_area(site, 1.5):
				continue
			var clearance := Vector2(site.x - LANDER.x, site.z - LANDER.z).length()
			for other in crystals:
				clearance = minf(clearance, Vector2(other.position.x - site.x, other.position.z - site.z).length())
			if clearance > best_clearance:
				best_clearance = clearance
				best_site = site
			if clearance >= 2.8:
				break
		site = best_site
		if adventure_trial:
			site = LANDER + [Vector3(-0.5, 0, -3.4), Vector3(2.0, 0, -4.0), Vector3(4.5, 0, -4.2)][index]
		var item := Crystal.new()
		item.position = site
		add_child(item)
		# Read the lowest surface under the specimen so 'fully buried' remains true on slopes.
		var surface := terrain.height_at(site.x, site.z)
		for offset in [Vector2(-0.3, 0), Vector2(0.3, 0), Vector2(0, -0.3), Vector2(0, 0.3)]:
			surface = minf(surface, terrain.height_at(site.x + offset.x, site.z + offset.y))
		var burial := map_random.randf_range(float(zone.burial[0]), float(zone.burial[1]))
		if index < 2 or map_random.randf() < float(zone.exposed):
			burial = -0.12
		var roll := map_random.randf()
		var weights: Array = zone.size_weights
		var size_tier := 0 if roll < float(weights[0]) else (1 if roll < float(weights[0]) + float(weights[1]) else 2)
		if index < 3:
			size_tier = index
		# Keep the first three legacy crystals as a comparison and for existing smoke fixtures.
		var adventure_index := index if adventure_trial else int(relic_slots.get(index, -1))
		if adventure_index >= 0:
			var definition := AdventureItems.definition(adventure_index)
			var orientation := Vector3(map_random.randi_range(0, 3), map_random.randi_range(0, 3), map_random.randi_range(0, 3)) * (PI * 0.5)
			if adventure_trial:
				orientation = [Vector3.ZERO, Vector3(-PI * 0.5, 0, 0), Vector3(0, 0, PI * 0.5)][index]
				burial = [-0.18, 0.0, 0.125][index]
			if not item.setup_adventure(AdventureItems.source_scene(adventure_index), definition, orientation, surface, burial):
				push_error("遗物体素化失败：" + str(definition.label))
				remove_child(item)
				item.queue_free()
				continue
			# Evaluate every occupied column so the requested cover also holds on sloping ground.
			var ceiling := INF
			for local_cell: Vector3i in item._geometry.cells:
				var local_top := (float(local_cell.y) + 1.0) * Terrain.CELL_SIZE
				var horizontal := item.position + Vector3(local_cell.x + 0.5, 0, local_cell.z + 0.5) * Terrain.CELL_SIZE
				ceiling = minf(ceiling, terrain.height_at(horizontal.x, horizontal.z) - burial - local_top)
			item.position.y = floorf((ceiling - Terrain.WORLD_MIN.y) / Terrain.CELL_SIZE) * Terrain.CELL_SIZE + Terrain.WORLD_MIN.y
		else:
			item.setup_site(surface, burial, [0.30, 0.42, 0.54][size_tier])
		if not item.embed_in(terrain):
			push_warning("晶石占位失败，跳过重叠或越界矿点")
			remove_child(item)
			item.queue_free()
			continue
		var wear_range: Array = zone.get("wear_range", [0, Appraisal.MAX_WEAR])
		item.wear_percent = map_random.randi_range(int(wear_range[0]), int(wear_range[1]))
		item.set_wear(float(item.wear_percent) / 100.0)
		item.is_exposed(terrain)
		item.set_markers_visible(false)
		item.visible = false
		crystals.append(item)

func update_crystal_targets() -> void:
	var candidate: Crystal = null
	var best_score := INF
	nearest_signal = null
	for item in crystals:
		if item.collected:
			continue
		var distance_squared := suit.position.distance_squared_to(item.position)
		# Coarse distant surfaces must never accidentally reveal a buried specimen.
		item.visible = on_moon and item.discovered and distance_squared < 36.0 * 36.0
		item.set_markers_visible(false)
		if distance_squared > 6.0 * 6.0:
			continue
		var was_discovered := item.discovered
		var was_loose := item.is_loose()
		if item.is_exposed(terrain):
			item.discovered = true
			item.visible = on_moon
			item.refresh_exposure(terrain)
			if on_moon and not was_discovered:
				_sound("crystal_exposed")
			if on_moon and not was_loose and item.is_loose():
				_sound("crystal_loose")
			var offset := (item.position - suit.position).normalized()
			var alignment := offset.dot(-camera.global_basis.z)
			var score := sqrt(distance_squared) + (1.0 - alignment) * 1.8
			if score < best_score:
				best_score = score
				candidate = item
	crystal = candidate
	cluster_seen = crystal != null
	cluster_inspected = crystal != null and crystal.inspected
	if crystal != null:
		appraisal.wear_percent = crystal.wear_percent
		appraisal.base_value = crystal.base_value
		crystal.set_markers_visible(true)
	var had_signal := bool(detector_reading.get("available", false))
	detector_reading = Detector.sample(suit.position, -camera.global_basis.z, crystals, terrain, detector_level) if on_moon else {}
	if not had_signal and bool(detector_reading.get("available", false)):
		_sound("radar_ping")
	nearest_signal = detector_reading.get("target")
	detector_panel.set_reading(detector_reading)
	detector_panel.set_enabled(on_moon)

func pick_up_cluster() -> void:
	update_crystal_targets()
	if not on_moon or crystal == null or crystal.collected or not crystal.is_loose():
		_sound("error")
		return
	if suit.position.distance_to(crystal.position) > 1.85:
		return
	if not collect_crystal(crystal):
		_sound("error")
		message = "背包放不下，整理或丢弃后再装入"
		open_inventory(crystal)

func specimen_data(item: Crystal) -> Dictionary:
	return {"id": item.get_instance_id(), "world_id": item.get_instance_id(),
		"label": item.size_label, "footprint": item.footprint,
		"item_type": item.item_type, "item_name": item.item_name, "icon_color": item.icon_color,
		"wear": item.wear_percent, "base_value": item.base_value}

func collect_crystal(item: Crystal) -> bool:
	if not on_moon or item == null or item.collected or not item.is_loose() or suit.position.distance_to(item.position) > 1.85:
		return false
	if not inventory.try_add(specimen_data(item)):
		return false
	carried_crystals.append(item)
	carrying_cluster = true
	cluster_seen = true
	cluster_inspected = true
	item.store_in_inventory()
	_sound("crystal_pickup")
	message = "已装入 %s · 共 %d 件，可继续寻找或回舱入库" % [item.item_name, packed_specimens.size()]
	update_crystal_targets()
	return true

func open_inventory(pending: Crystal = null) -> void:
	if inventory_open or gm_open or base_open:
		return
	inventory_open = true
	_suspend_controls()
	_sound("menu_open")
	gm_panel.set_available(false)
	pending_pickup = pending
	resume_mouse_capture = wants_mouse_capture
	wants_mouse_capture = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	progress = 0.0
	ring.hide()
	cursor.hide()
	reticle.hide()
	boundary_warning.hide()
	var pending_data := specimen_data(pending) if pending != null else {}
	inventory_panel.open(inventory, appraisal.known, oxygen, pending_data)
	get_tree().paused = true

func close_inventory() -> void:
	inventory_open = false
	_sync_touch_state()
	_sound("menu_close")
	gm_panel.set_available(true)
	pending_pickup = null
	get_tree().paused = false
	reticle.show()
	wants_mouse_capture = resume_mouse_capture
	was_pickup = Input.is_physical_key_pressed(KEY_F)
	was_interact = Input.is_physical_key_pressed(KEY_E)
	locomotion.sync_jump_input(Input.is_physical_key_pressed(KEY_SPACE))
	update_hud()
	if wants_mouse_capture:
		call_deferred("capture_mouse")

func _on_gm_opened() -> void:
	gm_open = true
	_suspend_controls()
	_sound("menu_open")
	gm_resume_mouse_capture = wants_mouse_capture
	wants_mouse_capture = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	progress = 0.0
	ring.hide()
	cursor.hide()
	reticle.hide()
	boundary_warning.hide()
	sync_gm_state()
	get_tree().paused = true

func _on_gm_closed() -> void:
	gm_open = false
	_sync_touch_state()
	_sound("menu_close")
	get_tree().paused = false
	reticle.show()
	wants_mouse_capture = gm_resume_mouse_capture
	was_pickup = Input.is_physical_key_pressed(KEY_F)
	was_interact = Input.is_physical_key_pressed(KEY_E)
	was_upgrade = Input.is_physical_key_pressed(KEY_U)
	locomotion.sync_jump_input(Input.is_physical_key_pressed(KEY_SPACE))
	progress = 0.0
	update_hud()
	if wants_mouse_capture:
		call_deferred("capture_mouse")
	if not _gm_return_page.is_empty():
		var previous_page := _gm_return_page
		_gm_return_page = ""
		if not on_moon:
			show_outpost(previous_page)

func sync_gm_state() -> void:
	if gm_panel == null:
		return
	var stats := terrain.debug_stats()
	gm_panel.sync_state({
		"cleanup_enabled": terrain.cleanup_enabled,
		"cleanup_max_cells": terrain.cleanup_max_cells,
		"brush": brush, "show_performance": show_performance,
		"radar_mode": radar_mode,
		"touch_mode": touch_mode,
		"audio_enabled": not sfx.muted,
		"on_moon": on_moon, "oxygen": oxygen, "mining_time": mining_time,
		"bank": bank, "research_points": progression.research_points,
		"technology_rows": progression.upgrade_rows(),
		"debug_progression_allowed": not on_moon and progression.active_trip.is_empty() and inventory.items.is_empty(),
		"cleanup_status": "累计清理 %d 格 · 候选 %d 格 · 邻域任务 %d" % [int(stats.get("cleanup_removed", 0)), int(stats.get("cleanup_pending", 0)), int(stats.get("cleanup_scans", 0))],
		"message": message,
	})

func _on_gm_cleanup_changed(enabled: bool, max_cells: int) -> void:
	terrain.set_fragment_cleanup(enabled, max_cells)
	message = "小孤立土块清理：%s，整块最多 %d 格" % ["开启" if enabled else "关闭", terrain.cleanup_max_cells]
	sync_gm_state()

func _on_gm_technology(action: String, upgrade_id: String, value: int) -> void:
	if not gm_open:
		return
	# The owner checks this independently of disabled UI controls. Shrinking a
	# live backpack or changing a departing expedition's snapshot would lose data.
	if on_moon or not progression.active_trip.is_empty() or not inventory.items.is_empty():
		message = "请先完成返航并清空现场背包，再调整局外科技"
		_sound("error")
		sync_gm_state()
		return
	var result := progression.apply_debug_change(action, upgrade_id, value)
	message = str(result.get("message", "科技调试未完成"))
	if bool(result.get("ok", false)):
		apply_progression()
		sync_base_state()
		_sound("purchase")
	else:
		_sound("error")
	update_hud()
	sync_gm_state()

func _on_gm_brush_selected(index: int) -> void:
	brush = clampi(index, 0, BRUSH_NAMES.size() - 1)
	progress = 0.0
	message = "GM 笔刷：" + BRUSH_NAMES[brush]
	sync_gm_state()

func _on_gm_performance_changed(enabled: bool) -> void:
	show_performance = enabled
	update_hud()
	sync_gm_state()

func _on_gm_action(action: String) -> void:
	match action:
		"cleanup_nearby":
			if not on_moon:
				message = "出舱后可以检查身边的小孤立土块"
			elif terrain.cleanup_enabled:
				terrain.queue_fragment_cleanup_near(suit.position, 2.0)
				message = "已安排检查身边 2 米，关闭 GM 后分帧清理"
			else:
				message = "请先开启小孤立土块清理"
		"refill_oxygen":
			if on_moon:
				oxygen = oxygen_limit
				message = "GM 氧气已补满（%d 秒）" % int(oxygen_limit)
		"return_to_lander":
			suit.position = LANDER + Vector3(1.1, 0, -0.4)
			suit.position.y = terrain.height_at(suit.position.x, suit.position.z)
			locomotion.reset(Input.is_physical_key_pressed(KEY_SPACE))
			camera_anchor = suit.position + Vector3.UP * 0.95
			update_camera()
			message = "GM 已回到舱边，按 E 再结算"
		"speed_up":
			mining_time = maxf(0.06, mining_time * 0.7)
			progress = 0.0
			message = "GM 每次开采 %.2f 秒" % mining_time
		"reset_speed":
			mining_time = float(progression.stats().mining_time)
			progress = 0.0
			message = "GM 已恢复到当前电镐等级的开采速度"
		"start_trip", "start_trial":
			if not on_moon:
				adventure_trial = false
				start_trip(action == "start_trial")
		"adventure_trial":
			if not on_moon:
				adventure_trial = true
				start_trip(true)
				if on_moon:
					gm_panel.close()
				else:
					adventure_trial = false
		"reset_catalogue":
			if not on_moon:
				reset_appraisal_catalogue()
	update_hud()
	sync_gm_state()

func apply_progression() -> void:
	var stats := progression.stats()
	mining_time = float(stats.mining_time)
	oxygen_recovery_limit = float(stats.oxygen_recovery_limit)
	walk_speed = float(stats.walk_speed)
	detector_level = int(stats.detector_level)
	if terrain != null:
		terrain.set_mining_radius(float(stats.mining_radius))
		terrain.set_oxygen_supply_density(float(stats.oxygen_supply_density))
	inventory.columns = int(stats.bag_columns)
	inventory.rows = int(stats.bag_rows)
	if not on_moon:
		oxygen_limit = float(stats.oxygen)
		oxygen = oxygen_limit

func open_base() -> void:
	if on_moon or inventory_open or gm_open or base_open:
		return
	show_outpost("lobby")

func show_outpost(page: String) -> void:
	if on_moon or inventory_open or gm_open or page not in ["title", "lobby", "zones", "skills", "report", "museum"]:
		return
	if base_open and outpost_page == page:
		return
	_outpost_transition = true
	base_panel.close()
	skill_tree_panel.close()
	museum_panel.close()
	outpost_panel.close()
	outpost_page = page
	sync_base_state()
	match page:
		"zones": base_panel.open()
		"skills":
			skill_tree_panel.set_tab("equipment")
			skill_tree_panel.open()
		"museum":
			museum_panel.show_warehouse()
			museum_panel.open()
		_: outpost_panel.open(page)
	_outpost_transition = false
	update_hud()

func _on_base_opened() -> void:
	if not base_open:
		base_resume_mouse_capture = wants_mouse_capture
	base_open = true
	_suspend_controls()
	_sound("menu_open")
	wants_mouse_capture = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	gm_panel.set_available(false)
	progress = 0.0
	ring.hide()
	cursor.hide()
	reticle.hide()
	boundary_warning.hide()
	sync_base_state()
	get_tree().paused = true

func _on_base_closed() -> void:
	if _outpost_transition:
		return
	# Closing a subpage returns to the lobby, never to an unpaused mine.
	show_outpost("title" if outpost_page == "lobby" else "lobby")

func open_outpost_gm() -> void:
	if not base_open or on_moon or gm_open or inventory_open:
		return
	_gm_return_page = outpost_page
	_close_outpost_for_departure(false)
	gm_panel.open()

func open_museum_research() -> void:
	show_outpost("skills")
	skill_tree_panel.set_tab("museum")

func open_lobby_stand(slot: int) -> void:
	if not base_open or outpost_page != "lobby" or on_moon:
		return
	var capacity := int(progression.museum_summary().get("capacity", 3))
	if slot < 0 or slot >= 6:
		return
	if slot >= capacity:
		open_museum_research()
		return
	show_outpost("museum")
	museum_panel.inspect_stand(slot)

func _close_outpost_for_departure(restore_pointer: bool = true) -> void:
	_outpost_transition = true
	base_panel.close()
	skill_tree_panel.close()
	museum_panel.close()
	outpost_panel.close()
	_outpost_transition = false
	base_open = false
	outpost_page = ""
	_sync_touch_state()
	_sound("menu_close")
	get_tree().paused = false
	gm_panel.set_available(true)
	reticle.show()
	wants_mouse_capture = base_resume_mouse_capture
	was_interact = Input.is_physical_key_pressed(KEY_E)
	was_upgrade = Input.is_physical_key_pressed(KEY_U)
	locomotion.sync_jump_input(Input.is_physical_key_pressed(KEY_SPACE))
	update_hud()
	if restore_pointer and wants_mouse_capture:
		call_deferred("capture_mouse")

func sync_base_state() -> void:
	if base_panel == null:
		return
	var museum_summary := progression.museum_summary()
	# Legacy catalogue knowledge is still valid. Merge it for presentation without
	# rewriting a migrated profile merely because the player opened a menu.
	for kind: String in ["crystal", "chest", "shield", "hammer"]:
		if appraisal.is_known(kind) and kind not in museum_summary.identified_types:
			museum_summary.identified_types.append(kind)
	var state := {"bank": bank, "research_points": progression.research_points, "museum": museum_summary, "upgrades": progression.upgrade_rows(),
		"zones": progression.zones(), "selected_zone": progression.selected_zone,
		"stats": progression.stats(), "receipt": receipt, "report": progression.last_report, "touch_mode": touch_mode,
		"message": ("临时试玩不保存 · 原成长存档异常，文件已保留。\n" if profile_transient else "") + message}
	base_panel.sync_state(state)
	if skill_tree_panel != null:
		skill_tree_panel.sync_state(state)
	if outpost_panel != null:
		outpost_panel.sync_state(state)
	if museum_panel != null:
		museum_panel.sync_state(state)

func _sync_museum_catalogue() -> void:
	if progression == null or appraisal == null:
		return
	var changed := false
	for kind: String in progression.museum_summary().get("identified_types", []):
		if not appraisal.is_known(kind):
			appraisal.record_item_sale(kind, 0, false)
			changed = true
	if changed:
		appraisal.save_catalogue()

func _finish_museum_action(result: Dictionary) -> void:
	message = str(result.get("message", "操作未完成"))
	if bool(result.get("ok", false)):
		# Keep the legacy appraisal cache's last-sale detail. The profile remains
		# the owner of the atomic sale and identification, even if this cache fails.
		if result.has("item") and result.has("income"):
			var record: Dictionary = result.item
			var cache_error := appraisal.record_item_sale(str(record.get("item_type", "crystal")), int(result.income))
			if cache_error != OK:
				message += " · 资金已保存，鉴定缓存稍后恢复"
		_sync_museum_catalogue()
		_sound("purchase")
	else:
		_sound("error")
	sync_base_state()
	update_hud()

func on_museum_donate(uid: int) -> void:
	if not on_moon:
		_finish_museum_action(progression.donate_item(uid))

func on_museum_sell(uid: int) -> void:
	if not on_moon:
		_finish_museum_action(progression.sell_item(uid))

func on_museum_place(key: String, slot: int) -> void:
	if not on_moon:
		_finish_museum_action(progression.place_exhibit(key, slot))

func purchase_upgrade(upgrade_id: String) -> void:
	if on_moon:
		return
	var result := progression.buy_upgrade(upgrade_id)
	message = str(result.message)
	if result.ok:
		apply_progression()
		_sound("purchase")
	else:
		_sound("error")
	update_hud()
	sync_base_state()

func select_zone(zone_id: String) -> void:
	if on_moon:
		return
	if progression.select_zone(zone_id):
		var selected := progression.get_zone(zone_id)
		message = "已选择 %s · 出发时扣除门票 %d" % [selected.name, int(selected.fee)]
	else:
		message = "矿区选择失败，请检查存档状态"
	sync_base_state()

func reset_appraisal_catalogue() -> void:
	var result: Dictionary = progression.reset_identification()
	if not result.ok:
		message = str(result.message)
		return
	var reset_error := appraisal.reset_catalogue()
	receipt = ""
	message = "图鉴已重置，下次出售或入馆重新鉴定" if reset_error == OK else "图鉴已在本次试玩重置，本地保存失败"

func process_soil_cleanup() -> void:
	var result := terrain.process_fragment_cleanup()
	var recovered := int(result.get("ore", 0))
	if recovered > 0:
		gain_oxygen(recovered)
	if int(result.get("removed", 0)) > 0:
		update_crystal_targets()

func drop_inventory_item(item_id: int) -> void:
	var record := inventory.get_item(item_id)
	if record.is_empty():
		return
	var item: Crystal = instance_from_id(int(record.world_id)) as Crystal
	if not is_instance_valid(item):
		return
	var heading := Basis(Vector3.UP, view_yaw)
	var ground := suit.position - heading.z * 0.75 + heading.x * 0.55
	# Leave room for the whole shape and the nearby safe-placement candidates.
	var horizontal := Vector2(ground.x, ground.z).limit_length(activity_boundary.radius - 1.25)
	ground.x = horizontal.x
	ground.z = horizontal.y
	ground.y = terrain.support_height(ground.x, ground.z, suit.position.y + 0.55)
	item.set_wear(float(record.wear) / 100.0)
	if not item.drop_at(ground):
		_sound("error")
		message = "脚边没有容纳整件物品的空位，请换个位置再丢弃"
		inventory_panel.set_notice(message)
		return
	inventory.remove_item(item_id)
	_sound("crystal_drop")
	carried_crystals.erase(item)
	item.visible = true
	carrying_cluster = not carried_crystals.is_empty()
	message = "已将 %s 放在脚边，可再次按 F 拾取" % record.label
	update_crystal_targets()
	inventory_panel.refresh(appraisal.known)
	inventory_panel.set_notice(message)

func collect_pending_item() -> void:
	if not is_instance_valid(pending_pickup):
		inventory_panel.set_pending_item({})
		return
	if collect_crystal(pending_pickup):
		inventory_panel.close()
	else:
		inventory_panel.refresh(appraisal.known)
		inventory_panel.set_notice("仍然放不下：尝试旋转、调整位置，或丢弃其他物品。")

func settle(emergency: bool) -> void:
	if not on_moon:
		return
	_suspend_controls()
	# Cargo, cash, exhibition income and the completed trip are committed together.
	# A failed write leaves the live backpack intact for an explicit retry.
	var result := progression.settle_expedition(trip_id, inventory.items.duplicate(true), emergency, trip_elapsed,
		{"oxygen_grains": oxygen_grains, "oxygen_recovered": oxygen_recovered})
	if not bool(result.get("ok", false)):
		message = str(result.get("message", "回舱存档失败")) + " · 物品仍在背包，关闭背包后可重试回舱"
		_sound("error")
		if not inventory_open and not gm_open:
			open_inventory()
		inventory_panel.set_notice(message)
		return
	_sound("rescue" if emergency else "safe_extract")
	pending_oxygen_grains = 0
	pickup_count = 0.0
	pickup_time = 0.0
	for item in fragments:
		item.node.queue_free()
	fragments.clear()
	receipt = str(result.get("report", {}).get("text", ""))
	message = str(result.get("message", "已回到前哨站"))
	var stored_count := int(result.get("stored", 0))
	delivered_clusters += stored_count
	carrying_cluster = false
	terrain.clear_crystals()
	for item in crystals:
		item.hide()
	carried_crystals.clear()
	inventory.clear()
	crystal = null
	nearest_signal = null
	on_moon = false
	trip_id = 0
	trip_elapsed = 0.0
	adventure_trial = false
	oxygen = float(progression.stats().oxygen)
	suit.position = LANDER + Vector3(1.1, 0, -0.4)
	locomotion.reset(Input.is_physical_key_pressed(KEY_SPACE))
	camera_anchor = Vector3(suit.position.x, 0.95, suit.position.z)
	update_camera()
	detector_panel.set_enabled(false)
	update_hud()
	if auto_open_base:
		show_outpost("lobby")
	else:
		_sync_touch_state()

func upgrade_cost() -> int:
	for row: Dictionary in progression.upgrade_rows():
		if row.id == "drill":
			return int(row.cost)
	return 0

func relative_bearing(point: Vector3) -> String:
	var offset := point - suit.position
	var heading := Basis(Vector3.UP, view_yaw)
	var angle := atan2(offset.dot(heading.x), offset.dot(-heading.z))
	if absf(angle) < 0.26:
		return "前方"
	if absf(angle) > 2.75:
		return "身后"
	return "向右转" if angle > 0 else "向左转"

func update_hud() -> void:
	hud_surface.visible = not base_open
	var lander_distance := Vector2(suit.position.x - LANDER.x, suit.position.z - LANDER.z).length()
	var return_seconds := ceili(maxf(0.0, lander_distance - HATCH_REACH) / walk_speed) + 1
	var urgent := on_moon and oxygen <= return_seconds + 3
	hud.text = "%02d s" % ceili(oxygen)
	hud.modulate = UI.DANGER if urgent else UI.TEXT
	oxygen_bar.value = clampf(oxygen / maxf(1.0, oxygen_limit), 0.0, 1.0) * 100.0
	var oxygen_fill := oxygen_bar.get_theme_stylebox("fill") as StyleBoxFlat
	oxygen_fill.bg_color = UI.DANGER if urgent else UI.ACCENT
	return_hint.text = "回舱 %s · 约 %d 秒" % [relative_bearing(LANDER), return_seconds] if on_moon else "前哨站 · 氧气已补满"
	return_hint.add_theme_color_override("font_color", UI.WARNING if urgent else UI.MUTED)
	resource_line.text = "背包 %d/%d  补氧 %.1f/%.0fs" % [inventory.used_cells(), inventory.columns * inventory.rows, oxygen_recovered, oxygen_recovery_limit]
	hint.text = "WASD 移动  ·  空格 跳跃  ·  H 按键"
	help_card.visible = show_help and not inventory_open and not gm_open and not base_open
	action_label.text = ""
	if on_moon:
		if suit.position.distance_to(LANDER) < HATCH_REACH:
			action_label.text = "E  返航入库"
		elif crystal != null and crystal.is_loose() and suit.position.distance_to(crystal.position) <= 1.85:
			action_label.text = "F  拾取 " + crystal.item_name
		elif cursor.visible:
			action_label.text = "长按左键  开采"
	else:
		action_label.text = "E / M  基地整备"
	if not touch_mode and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		action_label.text = "点击画面  继续"
	action_card.visible = not touch_mode and (show_help or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED) and not action_label.text.is_empty() and not inventory_open and not gm_open and not base_open
	if message != last_hud_message:
		last_hud_message = message
		notice_until = Time.get_ticks_msec() + 4500
		notice.text = message.get_slice("\n", 0)
	notice_card.visible = on_moon and not message.is_empty() and Time.get_ticks_msec() < notice_until and not inventory_open and not gm_open and not base_open
	detector_panel.set_enabled(on_moon)
	debug_label.visible = show_performance and not show_help and not inventory_open and not gm_open and not base_open
	if show_performance:
		debug_label.text = "%d FPS · %.0f MB\n笔刷 %s · %.2f s/次" % [Engine.get_frames_per_second(), Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, BRUSH_NAMES[brush], mining_time]
		var cleanup_stats := terrain.debug_stats()
		debug_label.text += "\n清理 %d 格 · %.2f ms" % [int(cleanup_stats.cleanup_removed), float(cleanup_stats.cleanup_last_usec) / 1000.0]
	update_specimen_card()

func update_specimen_card() -> void:
	specimen_card.visible = on_moon and crystal != null and not inventory_open and not gm_open and not base_open
	if not on_moon or crystal == null:
		specimen_info.text = ""
		return
	specimen_title.text = "%s  %d×%d" % [crystal.size_label, crystal.footprint.x, crystal.footprint.y]
	specimen_title.modulate = UI.ACCENT if crystal.is_loose() else UI.TEXT
	exposure_bar.value = crystal.exposure_ratio * 100.0
	if crystal.is_loose():
		specimen_info.text = "已松动 · 可收集\n"
	elif crystal.exposure_ratio >= Crystal.RELEASE_EXPOSURE:
		specimen_info.text = "暴露达标 · 清开顶部\n"
	else:
		specimen_info.text = "暴露 %d%% / 80%%\n" % roundi(crystal.exposure_ratio * 100)
	specimen_info.text += "磨损 %d%%\n" % appraisal.wear_percent if cluster_inspected else "%s\n" % appraisal.condition_name()
	if not appraisal.is_known(crystal.item_type):
		specimen_info.text += "售价 ？"
	elif not cluster_inspected:
		specimen_info.text += "估价待检查"
	else:
		specimen_info.text += "预计售价 %d" % appraisal.sale_value()

func burst(at: Vector3, found: int) -> void:
	var carriers := mini(found, 8)
	pending_oxygen_grains += found
	for index in range(23):
		var node := MeshInstance3D.new()
		node.mesh = grain
		var mineral := index < carriers
		node.material_override = pickup_material if mineral else dust
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.position = at + Vector3(flight_rng.randf_range(-0.34, 0.34), 0.06, flight_rng.randf_range(-0.34, 0.34))
		node.scale *= flight_rng.randf_range(1.65, 2.35) if mineral else flight_rng.randf_range(0.55, 1.3)
		add_child(node)
		var velocity := Vector3(flight_rng.randf_range(-1.2, 1.2), flight_rng.randf_range(1.1, 2.5), flight_rng.randf_range(-1.2, 1.2))
		var credit := 0
		if mineral:
			credit = floori(float((index + 1) * found) / carriers) - floori(float(index * found) / carriers)
		fragments.append({"node": node, "origin": node.position, "velocity": velocity, "age": 0.0, "credit": credit, "duration": 0.64 + index * 0.035 if mineral else 0.65})

func update_fragments(delta: float) -> void:
	pickup_time = maxf(0.0, pickup_time - delta)
	if pickup_time == 0.0:
		pickup_count = 0.0
	for index in range(fragments.size() - 1, -1, -1):
		var item := fragments[index]
		var node: MeshInstance3D = item.node
		item.age += delta
		if item.credit > 0:
			var origin: Vector3 = item.origin
			var velocity: Vector3 = item.velocity
			var lift := origin + Vector3(velocity.x * 0.17, 0.47, velocity.z * 0.17)
			var destination := camera.to_global(Vector3(0.16, -0.20, -0.45)) if first_person else suit.to_global(Vector3(0.15, 0.8, 0.32))
			if item.age < 0.22:
				node.position = origin.lerp(lift, 1.0 - pow(1.0 - item.age / 0.22, 2.0))
			else:
				var pull := clampf((item.age - 0.22) / (item.duration - 0.22), 0.0, 1.0)
				node.position = lift.lerp(destination, pull * pull) + Vector3.UP * sin(pull * PI) * 0.27
			node.rotation.y += delta * 8.0
		else:
			item.velocity.y -= 7.0 * delta
			node.position += item.velocity * delta
			node.scale *= pow(0.48, delta)
		if item.age >= item.duration:
			if item.credit > 0:
				pending_oxygen_grains = maxi(0, pending_oxygen_grains - int(item.credit))
				gain_oxygen(int(item.credit))
			node.queue_free()
			fragments.remove_at(index)

func gain_oxygen(grains: int) -> float:
	if not on_moon or grains <= 0:
		return 0.0
	var allowance := maxf(0.0, oxygen_recovery_limit - oxygen_recovered)
	var restored := minf(minf(float(grains) * OXYGEN_PER_GRAIN, maxf(0.0, oxygen_limit - oxygen)), allowance)
	oxygen = minf(oxygen_limit, oxygen + restored)
	oxygen_grains += grains
	_sound("oxygen_pickup")
	oxygen_recovered += restored
	pickup_time = 1.1
	if restored > 0.0:
		pickup_count += restored
		pickup_label.text = ("+%.2f 秒氧气" if pickup_count < 0.1 else "+%.1f 秒氧气") % pickup_count
	else:
		pickup_count = 0.0
		pickup_label.text = "补氧额度已用尽" if allowance <= 0.00001 else "氧气已满"
	pickup_label.reset_size()
	return restored
