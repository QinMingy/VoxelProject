extends SceneTree

const Progression = preload("res://progression.gd")
const SkillTree = preload("res://skill_tree_panel.gd")
var failed := false
var requested: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, why: String) -> void:
	if not ok:
		failed = true
		push_error("SKILL TREE FAIL: " + why)
		quit(1)
		assert(ok, why)

func data(profile: RefCounted, message: String = "") -> Dictionary:
	return {"bank": profile.bank, "research_points": profile.research_points, "upgrades": profile.upgrade_rows(), "stats": profile.stats(), "message": message}

func touch_scroll(panel: CanvasLayer) -> void:
	# Godot 4.7's ScrollContainer consumes touch-emulated mouse events, not
	# raw ScreenDrag events. Parse through Input so that native route is tested.
	ProjectSettings.set_setting("input_devices/pointing/emulate_touch_from_mouse", true)
	Input.emulate_touch_from_mouse = true
	Input.emulate_mouse_from_touch = true
	panel._tree_scroll.scroll_vertical = 0
	panel._tree_scroll.scroll_horizontal = 0
	await process_frame
	var rect: Rect2 = panel._tree_scroll.get_global_rect()
	var position := rect.position + Vector2(20, rect.size.y - 40)
	var press := InputEventScreenTouch.new()
	press.index = 0
	press.position = position
	press.pressed = true
	Input.parse_input_event(press)
	await process_frame
	for step in range(10):
		var drag := InputEventScreenDrag.new()
		drag.index = 0
		drag.relative = Vector2(0, -20)
		position += drag.relative
		drag.position = position
		Input.parse_input_event(drag)
		await process_frame
	var release := InputEventScreenTouch.new()
	release.index = 0
	release.position = position
	release.pressed = false
	Input.parse_input_event(release)
	await process_frame
	check(panel._tree_scroll.scroll_vertical > 0, "a touch drag scrolls the equipment tree while the game is paused")

func run() -> void:
	root.size = Vector2i(1100, 720)
	var profile := Progression.new("")
	var first_drill_cost := int(Progression.UPGRADES.drill.costs[0])
	var first_range_cost := int(Progression.UPGRADES.excavation_range.costs[0])
	var first_radius_cost := int(Progression.UPGRADES.mining_radius.costs[0])
	var first_research_cost := int(Progression.UPGRADES.museum_appeal.research_costs[0])
	profile.bank = 10000
	var initial_bank: int = profile.bank
	var panel := SkillTree.new()
	root.add_child(panel)
	panel.sync_state(data(profile))
	panel.upgrade_requested.connect(func(id: String) -> void: requested.append(id))
	panel.open()
	check(panel.is_open and not paused, "opening panel leaves pause ownership with the caller")
	check(panel._nodes.size() == 30 and SkillTree.EQUIPMENT_BRANCHES.size() == 8, "eight equipment branches and two museum branches expose thirty tier nodes")
	check(panel.node_state("excavation_range", 1) == "available" and panel.node_state("excavation_range", 2) == "locked", "range upgrades follow their own affordable tier chain")
	panel.select_node("excavation_range", 1)
	check(panel._detail_values.text.contains("半径 14 米") and panel._detail_values.text.contains("半径 18 米") and panel._detail_values.text.contains("28 → 36"), "range details distinguish radius and map diameter")
	check(profile.bank == initial_bank and requested.is_empty(), "inspecting range preserves the balance")
	check(panel.node_state("drill", 1) == "available", "funded drill node is available")
	check(panel.node_state("oxygen", 1) == "available", "funded oxygen node has its independent chain")
	check(panel.node_state("detector", 1) == "available", "detector is independent of drill purchases")
	check(panel.node_state("drill", 2) == "locked", "later tiers require their own predecessor")
	panel.select_node("drill", 1)
	check(profile.bank == initial_bank and requested.is_empty(), "selecting or focusing a node never purchases")
	panel.request_selected_upgrade()
	panel.request_selected_upgrade()
	check(requested == ["drill"] and panel.node_state("drill", 1) == "pending", "repeated clicks cannot duplicate an outstanding request")
	check(profile.bank == initial_bank and profile.levels.drill == 0, "panel cannot charge or upgrade its owner profile")
	check(profile.buy_upgrade("drill").ok, "real owner purchases through the progression transaction")
	panel.sync_state(data(profile, "电镐已装配"))
	check(profile.bank == initial_bank - first_drill_cost and panel.node_state("drill", 1) == "purchased", "owner acknowledgement charges the configured price and marks exactly the purchased node")
	check(panel.node_state("drill", 2) == "available" and panel.node_state("oxygen", 1) == "available", "no invented cross-branch prerequisite")
	check(panel._buy_button.disabled and panel._link_tweens.has("drill:1"), "purchased selection cannot buy next tier automatically and triggers its connection animation")
	profile.bank = 0
	panel.sync_state(data(profile))
	check(panel.node_state("drill", 2) == "unaffordable" and panel.node_state("oxygen", 1) == "unaffordable", "unfunded next nodes are disabled without hiding their effects")
	profile.bank = 5000
	panel.sync_state(data(profile))
	panel.select_node("drill", 3)
	panel.request_selected_upgrade()
	check(requested.size() == 1 and panel._buy_button.disabled, "locked future node cannot skip its predecessor")
	panel.select_node("oxygen", 1)
	check(not panel._buy_button.disabled and panel._detail_values.text.contains("%d 秒" % int(Progression.UPGRADES.oxygen["values"][1])), "independent oxygen node displays its configured effect")
	var blocked := data(profile)
	for row: Dictionary in blocked.upgrades:
		if row.id == "oxygen":
			row.can_buy = false
	panel.sync_state(blocked)
	check(panel.node_state("oxygen", 1) == "unavailable" and panel._buy_button.disabled, "save-blocked upgrades remain unavailable even with funds")
	panel.sync_state(data(profile))
	panel.close()
	check(not panel.is_open and not paused, "closing does not pause or unpause the owner")
	paused = true
	panel.open()
	await create_timer(0.35, true).timeout
	check(paused and is_equal_approx(panel._modal.modulate.a, 1.0), "entrance tween runs while the game is paused")
	panel.select_node("oxygen", 1)
	check(profile.buy_upgrade("oxygen").ok, "second real upgrade uses its own chain")
	panel.sync_state(data(profile, "氧气瓶已装配"))
	check(panel._link_tweens.has("oxygen:1"), "purchase feedback is based on a real level increase")
	await create_timer(0.8, true).timeout
	check(paused and (panel._nodes["oxygen:1"] as Button).scale.is_equal_approx(Vector2.ONE), "purchase pulse completes while paused")
	panel.select_node("excavation_range", 1)
	var before_range_cash: int = profile.bank
	check(profile.buy_upgrade("excavation_range").ok, "owner buys range using the same progression transaction")
	panel.sync_state(data(profile, "勘探范围已装配"))
	check(profile.bank == before_range_cash - first_range_cost and panel.node_state("excavation_range", 1) == "purchased", "range acknowledgement charges exactly its configured cost")
	check(panel._link_tweens.has("excavation_range:1") and panel._detail_values.text.contains("半径 18 米"), "range purchase animates its link and refreshes displayed size")
	await create_timer(0.8, true).timeout
	panel.select_node("mining_radius", 1)
	var radius_before := float(profile.stats().mining_radius)
	var radius_next := float(Progression.UPGRADES.mining_radius["values"][1])
	check(panel._detail_name.text.contains("开采范围") and panel._detail_values.text.contains("直径 %.2f 米" % (radius_before * 2.0)) and panel._detail_values.text.contains("直径 %.2f 米" % (radius_next * 2.0)), "digging size shows per-hit tool diameter instead of map radius")
	check(panel.node_state("mining_radius", 1) == "available" and panel.node_state("mining_radius", 2) == "locked", "tool size has its own sequential upgrade chain")
	var before_radius_cash: int = profile.bank
	var before_map_radius := float(profile.stats().activity_radius)
	panel.request_selected_upgrade()
	check(requested == ["drill", "mining_radius"], "the new branch sends the correct purchase request")
	check(profile.buy_upgrade("mining_radius").ok, "owner buys digging size through the real transaction")
	panel.sync_state(data(profile, "开采范围已装配"))
	check(profile.bank == before_radius_cash - first_radius_cost and is_equal_approx(profile.stats().mining_radius, radius_next), "new size purchase charges once and increases actual radius")
	check(is_equal_approx(profile.stats().activity_radius, before_map_radius), "tool radius upgrade does not expand the map")
	check(panel._link_tweens.has("mining_radius:1") and panel.node_state("mining_radius", 1) == "purchased", "new branch retains purchase animation and acknowledgement")
	await create_timer(0.8, true).timeout
	panel.set_tab("museum")
	check(panel._nodes["museum_capacity:1"].visible and not panel._nodes["drill:1"].visible, "museum tab separates its nodes from expedition equipment")
	panel.select_node("museum_appeal", 1)
	check(panel.node_state("museum_appeal", 1) == "research_shortage" and panel._buy_button.disabled, "cash alone cannot buy research-only museum upgrades")
	profile.research_points = first_research_cost + 3
	panel.sync_state(data(profile))
	var before_appeal_cash: int = profile.bank
	check(profile.buy_upgrade("museum_appeal").ok, "real museum research purchase succeeds with points")
	panel.sync_state(data(profile, "展馆吸引力研究完成"))
	check(profile.bank == before_appeal_cash and profile.research_points == 3 and panel.node_state("museum_appeal", 1) == "purchased", "museum research consumes points without debiting cash")
	await create_timer(0.8, true).timeout
	for resolution in [Vector2i(960, 540), Vector2i(1100, 720), Vector2i(1600, 720)]:
		# Exercise actual small layout coordinates, rather than letting the
		# project's canvas stretch turn 960x540 into a 1280x720 virtual viewport.
		root.content_scale_size = resolution
		root.size = resolution
		await process_frame
		await process_frame
		var viewport := Rect2(Vector2.ZERO, Vector2(resolution))
		print("SKILL_LAYOUT ", resolution, " window=", panel._window.get_global_rect(), " minimum=", panel._window.get_combined_minimum_size())
		check(viewport.encloses(panel._window.get_global_rect()), "window fits the target viewport")
		for tab: String in ["equipment", "museum"]:
			panel.set_tab(tab)
			await process_frame
			await process_frame
			var branches: Array = SkillTree.EQUIPMENT_BRANCHES if tab == "equipment" else SkillTree.MUSEUM_BRANCHES
			for id: String in branches:
				var node: Button = panel._nodes["%s:1" % id]
				panel.select_node(id, 1)
				await process_frame
				await process_frame
				check(panel._tree_scroll.get_global_rect().encloses(node.get_global_rect()), "scrolling reaches every branch including the eighth equipment row")
			check(panel._window.get_global_rect().encloses(panel._tree_scroll.get_global_rect()) and panel._window.get_global_rect().encloses(panel._details_scroll.get_global_rect()), "scroll viewports remain within the fitted window")
		panel.set_tab("equipment")
		await process_frame
		await process_frame
		panel._tree_scroll.ensure_control_visible(panel._nodes["excavation_range:3"])
		await process_frame
		await process_frame
		check(panel._tree_scroll.scroll_vertical > 0, "eighth equipment branch uses vertical scroll instead of increasing the window height")
		check(panel._tree_scroll.get_global_rect().encloses((panel._nodes["excavation_range:3"] as Button).get_global_rect()), "last node is reachable horizontally and vertically")
		await touch_scroll(panel)
		check(requested == ["drill", "mining_radius"], "scroll gestures never purchase a selected upgrade")
		panel.select_node("mining_radius", 2)
		await process_frame
		await process_frame
		panel._details_scroll.ensure_control_visible(panel._buy_button)
		await process_frame
		await process_frame
		check(panel._details_scroll.get_global_rect().encloses(panel._buy_button.get_global_rect()), "short screens can scroll to the explicit purchase button")
		panel._details_scroll.scroll_vertical = 0
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			DirAccess.make_dir_recursive_absolute("res://.build/skill-tree-preview")
			check(root.get_texture().get_image().save_png("res://.build/skill-tree-preview/skill-tree-%d.png" % resolution.x) == OK, "save native skill-tree screenshot")
	panel.close()
	check(paused, "panel close preserves the owner's paused state")
	paused = false
	panel.queue_free()
	await process_frame
	if not failed:
		print("SKILL_TREE_OK independent_chains=true owner_only_charge=true pending_guard=true locked_levels=true paused_animations=true mining_radius=true scroll_eight_branches=true fits_960_1100_1600=true")
	quit(1 if failed else 0)
