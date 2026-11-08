extends SceneTree

const Progression = preload("res://progression.gd")
const GMPanel = preload("res://gm_panel.gd")
const OUT := "res://.build/gm-technology-smoke"
var requests: Array = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, description: String) -> void:
	if not condition:
		push_error("GM TECHNOLOGY FAIL: " + description)
		quit(1)
		assert(condition, description)

func snapshot(profile: RefCounted) -> Dictionary:
	return {"bank": profile.bank, "research": profile.research_points, "levels": profile.levels.duplicate(true),
		"museum": profile.museum_state.duplicate(true), "trip": profile.active_trip.duplicate(true),
		"serial": profile.trip_serial, "zone": profile.selected_zone, "report": profile.last_report.duplicate(true)}

func panel_state(profile: RefCounted, on_moon: bool = false) -> Dictionary:
	return {"bank": profile.bank, "research_points": profile.research_points,
		"technology_rows": profile.upgrade_rows(), "on_moon": on_moon,
		"debug_progression_allowed": not on_moon and profile.active_trip.is_empty()}

func run() -> void:
	check(DirAccess.make_dir_recursive_absolute(OUT) == OK, "create test-owned directory")
	var path := OUT + "/profile-%d.cfg" % OS.get_process_id()
	var profile := Progression.new(path)
	check(profile.apply_debug_change("grant_cash", "", 1000).ok and profile.bank == 1150, "cash grant uses current balance")
	check(profile.apply_debug_change("grant_cash", "", 10000).ok and profile.bank == 11150, "large cash grant persists")
	check(profile.apply_debug_change("grant_research", "", 10).ok and profile.research_points == 10, "research grant persists")
	var original_bank: int = profile.bank
	var original_research: int = profile.research_points
	check(profile.apply_debug_change("set_level", "drill", 3).ok, "direct max drill level skips purchase charges")
	check(profile.stats().mining_time == 0.30 and profile.bank == original_bank and profile.research_points == original_research,
		"direct level sets actual gameplay value and preserves currencies")
	check(profile.apply_debug_change("set_level", "drill", 0).ok and profile.stats().mining_time == 0.9, "single technology can return to baseline")
	var before := snapshot(profile)
	for operation: Array in [["unknown", "", 0], ["set_level", "missing", 1], ["set_level", "drill", -1],
		["set_level", "backpack", 3], ["grant_cash", "", 0], ["grant_research", "", -1],
		["grant_cash", "", Progression.MAX_BANK], ["grant_research", "", Progression.MAX_BANK]]:
		check(not profile.apply_debug_change(operation[0], operation[1], operation[2]).ok, "invalid debug request is rejected")
		check(snapshot(profile) == before, "invalid request leaves all data unchanged")
	var trip: Dictionary = profile.pay_entry("meadow", true)
	check(trip.ok, "fixture starts a real valid expedition")
	before = snapshot(profile)
	for action: String in ["grant_cash", "grant_research", "set_level", "reset_levels", "max_levels"]:
		check(not profile.apply_debug_change(action, "drill", 1).ok and snapshot(profile) == before,
			"unsettled expedition blocks " + action)
	var cargo: Array[Dictionary] = []
	for category: Dictionary in Progression.Museum.CATEGORIES:
		cargo.append(category.duplicate(true))
	check(profile.settle_expedition(int(trip.trip_id), cargo, false, 65.0).ok, "fixture cargo enters the collection through settlement")
	check(profile.apply_debug_change("max_levels").ok, "bulk maximum uses valid per-technology caps")
	for id: String in Progression.UPGRADES:
		check(profile.levels[id] == Progression.UPGRADES[id].costs.size(), "correct maximum for " + id)
	var keys: Array = profile.museum_state.items.keys()
	for index in range(mini(keys.size(), int(profile.stats().museum_capacity))):
		check(profile.place_exhibit(keys[index], index).ok, "place preserved exhibits up to capacity")
	var before_exhibits: Dictionary = profile.museum_state.items.duplicate(true)
	var downgrade: Dictionary = profile.apply_debug_change("set_level", "museum_capacity", 0)
	check(downgrade.ok and downgrade.returned_exhibits == 2, "capacity downgrade returns only the overflow displays")
	check(profile.museum_state.items == before_exhibits and profile.museum_summary().displayed_count == 6,
		"downgrade preserves every registered item and keeps valid first slots")
	for index in range(6, 48):
		check(profile.museum_state.slots[index] == "", "locked slots are cleared for valid reload")
	var research_before_reset: int = profile.research_points
	check(profile.apply_debug_change("reset_levels").ok, "bulk baseline succeeds")
	for level: int in profile.levels.values():
		check(level == 0, "all technology levels reset")
	check(profile.bank == original_bank and profile.research_points == research_before_reset and profile.museum_state.items == before_exhibits,
		"technology reset does not reset cash, research or collection")
	var loaded := Progression.new(path)
	check(loaded.load_profile() == OK and snapshot(loaded) == snapshot(profile), "debug-modified profile reloads with identical valid data")
	var blocked_path := OUT + "/blocked-target-%d" % OS.get_process_id()
	check(DirAccess.make_dir_recursive_absolute(blocked_path) == OK, "create write-failure fixture")
	var blocked := Progression.new(blocked_path)
	before = snapshot(blocked)
	check(not blocked.apply_debug_change("max_levels").ok and snapshot(blocked) == before, "disk failure cannot mutate technology in memory")
	check(not blocked.apply_debug_change("grant_cash", "", 1000).ok and snapshot(blocked) == before, "disk failure cannot mutate cash in memory")
	var corrupt_path := OUT + "/corrupt-%d.cfg" % OS.get_process_id()
	var corrupt := ConfigFile.new()
	corrupt.set_value("profile", "version", 999)
	check(corrupt.save(corrupt_path) == OK, "create corrupt test-owned profile")
	var bytes_before := FileAccess.get_file_as_bytes(corrupt_path)
	var guarded := Progression.new(corrupt_path)
	check(guarded.load_profile() != OK, "corrupt profile activates existing save guard")
	before = snapshot(guarded)
	check(not guarded.apply_debug_change("grant_research", "", 10).ok and snapshot(guarded) == before,
		"GM cannot bypass a blocked profile")
	check(FileAccess.get_file_as_bytes(corrupt_path) == bytes_before, "GM leaves corrupt original bytes untouched")

	var panel := GMPanel.new()
	root.add_child(panel)
	panel.sync_state(panel_state(profile))
	panel.technology_requested.connect(func(action: String, id: String, value: int) -> void: requests.append([action, id, value]))
	panel.open()
	panel._show_tab("technology")
	await process_frame
	await process_frame
	check(panel._technology_spins.size() == Progression.UPGRADES.size(), "one direct level editor per real technology")
	var spinner: SpinBox = panel._technology_spins.drill
	spinner.value = 2
	await process_frame
	panel.sync_state(panel_state(profile))
	check(spinner.value == 2, "unrelated refresh preserves draft target level")
	(panel.find_child("DebugSetLevel_drill", true, false) as Button).pressed.emit()
	(panel.find_child("DebugSetLevel_drill", true, false) as Button).pressed.emit()
	check(requests == [["set_level", "drill", 2]], "panel delegates desired level once pending acknowledgement")
	check(profile.levels.drill == 0, "UI never mutates the progression owner")
	check(profile.apply_debug_change("set_level", "drill", 2).ok, "owner acknowledges real change")
	panel.sync_state(panel_state(profile))
	check(spinner.value == 2 and not (panel.find_child("DebugSetLevel_drill", true, false) as Button).disabled,
		"owner acknowledgement refreshes level and re-enables actions")
	panel.sync_state(panel_state(profile, true))
	for button: Button in panel._technology_buttons:
		check(button.disabled, "all technology debug actions disable on moon")
	panel._request_technology("grant_cash", "", 1000)
	check(requests.size() == 1, "moon-side requests cannot escape UI guard")
	panel.sync_state(panel_state(profile))
	for resolution: Vector2i in [Vector2i(960, 540), Vector2i(1100, 720), Vector2i(1600, 720)]:
		root.content_scale_size = resolution
		root.size = resolution
		await process_frame
		await process_frame
		check(root.get_visible_rect().grow(1).encloses(panel._window.get_global_rect()), "GM fits true logical viewport " + str(resolution))
		check(panel._technology_scroll.size.y > 100, "technology list retains scrollable area")
		panel._technology_scroll.ensure_control_visible(panel._technology_spins.museum_appeal)
		await process_frame
		check(panel._technology_scroll.get_global_rect().grow(1).encloses((panel._technology_spins.museum_appeal as SpinBox).get_global_rect()), "last technology remains reachable by scrolling")
	panel.close()
	panel.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(corrupt_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(blocked_path))
	print("GM_TECHNOLOGY_OK direct_levels=true grants=true bulk=true capacity_safe=true transaction_failure=true corrupt_guard=true reload=true ui_pending=true moon_disabled=true layout_960_1100_1600=true")
	quit(0)
