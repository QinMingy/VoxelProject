extends SceneTree

const Main = preload("res://main.gd")
const OUT := "res://.demo-data/test-artifacts/first-person-oxygen"
const SEED := 11235
const PREVIEW_SITE := Vector3(6.25, 0.0, 1.25)

var game: Main
var preview := false

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, description: String) -> void:
	if not ok:
		push_error("FIRST PERSON / OXYGEN FAIL: " + description)
		quit(1)
		assert(ok, description)

func key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		root.push_input(event, true)

func assert_view(first: bool) -> void:
	check(game.first_person == first, "V selects the expected view")
	check(game.suit.visible == not first and game.first_person_rig.visible == first,
		"body and camera-mounted tool use mutually exclusive visibility")
	check(is_equal_approx(game.camera.fov, 74.0 if first else 62.0), "camera applies the view FOV")
	if first:
		check(game.camera.position.is_equal_approx(game.suit.position + Vector3.UP * Main.EYE_HEIGHT),
			"first-person camera follows the player's actual eye position")

func shot(name: String) -> void:
	var intended_hit := aim_at_soil()
	var intended_point: Vector3 = intended_hit.position
	var intended_camera := game.camera.transform
	var intended_suit := game.suit.position
	var intended_yaw := game.view_yaw
	var intended_pitch := game.view_pitch
	for frame in range(45):
		game._process(1.0 / 60.0)
		await process_frame
	await RenderingServer.frame_post_draw
	var final_hit := aim_at_soil()
	var final_point: Vector3 = final_hit.position
	check(game.camera.transform.is_equal_approx(intended_camera) and game.suit.position.is_equal_approx(intended_suit)
		and is_equal_approx(game.view_yaw, intended_yaw) and is_equal_approx(game.view_pitch, intended_pitch),
		"native input does not move the preview camera or player")
	check(final_hit.cell == intended_hit.cell and final_point.is_equal_approx(intended_point),
		"preview still aims at the intended soil voxel")
	print("VIEW_PREVIEW %s camera=%s yaw=%.6f pitch=%.6f suit=%s center_hit=%s" % [
		name, game.camera.position, game.view_yaw, game.view_pitch, game.suit.position, final_point
	])
	var path := OUT + "/" + name + ".png"
	check(root.get_texture().get_image().save_png(path) == OK, "save actual camera frame " + name)

func pose(first: bool, at: Vector3) -> void:
	at.y = game.terrain.height_at(at.x, at.z)
	game.suit.position = at
	game.view_yaw = -PI * 0.5
	game.view_pitch = 0.74
	game.set_first_person(first)
	game._process(1.0 / 60.0)
	assert_view(first)

func aim_at_soil() -> Dictionary:
	var hit := game.aim_at_terrain()
	check(not hit.is_empty() and hit.material == "soil" and game.terrain.is_soil_cell(hit.cell),
		"live camera reticle finds an occupied soil voxel")
	if not hit.is_empty():
		var point: Vector3 = hit.position
		var center := root.get_visible_rect().get_center()
		check(game.camera.unproject_position(point).distance_to(center) < 1.0,
			"voxel hit projects to the on-screen reticle")
	return hit

func dig(hit: Dictionary) -> int:
	var found := game.terrain.mine_at(hit.position, hit.normal, 0)
	check(game.terrain.last_removed > 0 and not game.terrain.is_soil_cell(hit.cell),
		"the reticle hit can excavate the actual voxel")
	return found

func check_first_person_ray_length() -> void:
	var at := game.suit.position + Vector3.RIGHT * 1.50
	at.y = game.terrain.height_at(at.x, at.z) - 0.001
	var offset := at - game.camera.position
	game.view_pitch = atan2(-offset.y, offset.x)
	game.update_camera()
	var hit := aim_at_soil()
	var point: Vector3 = hit.position
	check(game.camera.position.distance_to(point) > Main.DRILL_REACH,
		"first-person ray reaches the ground within the gameplay's horizontal mining range")
	game.view_pitch = 0.74
	game.update_camera()

func drain_fragments() -> void:
	for frame in range(90):
		game.update_fragments(1.0 / 60.0)
	check(game.pending_oxygen_grains == 0 and game.fragments.is_empty(), "all airborne grains arrive")

func run() -> void:
	create_timer(25.0).timeout.connect(func() -> void: quit(2))
	preview = OS.get_cmdline_user_args().has("--preview") and DisplayServer.get_name() != "headless"
	if preview:
		DirAccess.make_dir_recursive_absolute(OUT)
	root.size = Vector2i(1100, 720)
	game = Main.new()
	game.progression = Main.Progression.new("")
	game.progression.bank = 250
	game.appraisal = Main.Appraisal.new("")
	game.auto_open_base = false
	game.wants_mouse_capture = false
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	await process_frame

	assert_view(false)
	var keys := game.find_child("KeyStrip", true, false) as Control
	check(not game.help_card.is_visible_in_tree() and (keys == null or not keys.is_visible_in_tree()),
		"startup has no permanent keyboard hints")
	key(KEY_H)
	check(game.help_card.is_visible_in_tree(), "H shows the help card")
	key(KEY_H)
	check(not game.help_card.is_visible_in_tree() and (keys == null or not keys.is_visible_in_tree()),
		"H hides the help card without bringing back the permanent strip")
	key(KEY_V)
	assert_view(true)
	game.open_base()
	check(game.base_open and paused, "base menu opens and pauses")
	key(KEY_V)
	assert_view(true)
	game.start_trip(false)
	check(game.on_moon and not game.base_open and not paused and game.trip_id > 0, "real departure closes the lobby and creates a valid settlement ledger")
	game.gm_panel.open()
	check(game.gm_open and paused, "debug menu opens and pauses")
	key(KEY_V)
	assert_view(true)
	game.gm_panel.close()
	game.open_inventory()
	check(game.inventory_open and paused, "inventory opens and pauses")
	key(KEY_V)
	assert_view(true)
	game.inventory_panel.close()
	key(KEY_V)
	assert_view(false)

	game.terrain.set_oxygen_supply_density(0.25)
	game.terrain.reset_terrain(SEED)
	game.terrain.set_fragment_cleanup(false, 9)
	if preview:
		# The native pointer may move while the mesh settles. Key bindings have
		# already been exercised above, so only the preview is isolated from it.
		game.set_process_unhandled_input(false)
		root.grab_focus()
		await process_frame
		game.wants_mouse_capture = true
		game.capture_mouse()
		check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "native preview captures the mouse")
		game.update_hud()
		check(not game.action_card.is_visible_in_tree(), "native play hides contextual keyboard hints by default")
		check(PREVIEW_SITE.distance_to(Main.LANDER) >= 5.0, "preview is clear of the lander")
		pose(false, PREVIEW_SITE)
		await shot("third-person")
		pose(true, PREVIEW_SITE)
		await shot("first-person")

	# The shoulder offset makes the two starter-deposit approaches differ in Z.
	pose(false, Vector3(-4.65, 0.0, 4.50))
	var third_hit := aim_at_soil()
	dig(third_hit)

	game.terrain.reset_terrain(SEED)
	game.terrain.set_fragment_cleanup(false, 9)
	pose(true, Vector3(-4.65, 0.0, 5.18))
	check_first_person_ray_length()
	var first_hit := aim_at_soil()
	var found := dig(first_hit)
	check(found > 0, "the real first-person excavation releases oxygen ore")
	var location: Vector3 = first_hit.position
	game.oxygen = 12.0
	var wallet := game.bank
	game.burst(location, found)
	check(game.pending_oxygen_grains == found and game.oxygen_grains == 0 and game.oxygen == 12.0,
		"excavated grains stay pending during their flight")
	game.update_fragments(0.15)
	check(game.oxygen == 12.0, "oxygen is granted on arrival instead of at launch")
	drain_fragments()
	var expected := minf(float(found) * Main.OXYGEN_PER_GRAIN, game.oxygen_limit - 12.0)
	check(is_equal_approx(game.oxygen, 12.0 + expected) and is_equal_approx(game.oxygen_recovered, expected),
		"arriving ore restores oxygen")
	check(game.oxygen_grains == found and game.bank == wallet, "absorbed ore does not produce money")
	game.oxygen = game.oxygen_limit - Main.OXYGEN_PER_GRAIN * 0.5
	game.burst(location, found)
	drain_fragments()
	check(is_equal_approx(game.oxygen, game.oxygen_limit), "ore arrival caps oxygen at capacity")
	check(is_equal_approx(game.oxygen_recovered, expected + Main.OXYGEN_PER_GRAIN * 0.5),
		"recovery records only oxygen actually added")
	check(game.gain_oxygen(2) == 0.0 and is_equal_approx(game.oxygen, game.oxygen_limit),
		"already full oxygen stays full")

	var recovered := game.oxygen_recovered
	var collected := game.oxygen_grains
	game.burst(location, found)
	game.settle(false)
	var report: Dictionary = game.progression.last_report
	check(not game.on_moon and game.pending_oxygen_grains == 0 and game.fragments.is_empty(),
		"returning to base clears unabsorbed ore")
	check(game.bank == wallet and int(report.income) == 0, "oxygen-only trip has no payout")
	check(int(report.oxygen_grains) == collected and is_equal_approx(float(report.oxygen_recovered), recovered),
		"settlement includes actual pickup, excluding airborne grains")
	check(game.gain_oxygen(20) == 0.0, "base cannot use a moon pickup")
	check(game.progression.museum_state.warehouse.is_empty() and game.progression.museum_state.exhibits.is_empty(), "oxygen-only excursion creates neither persistent cargo nor fabricated exhibits")
	game.sfx.set_muted(true)
	await create_timer(0.10, true).timeout
	game.queue_free()
	await process_frame
	await create_timer(0.25, true).timeout
	print("FIRST_PERSON_OXYGEN_OK cameras=true reticle_voxels=true help=true menus=true real_ore=%d cap=true settlement=true preview=%s" % [found, preview])
	quit()
