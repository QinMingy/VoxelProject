extends SceneTree

const SettlementPanel = preload("res://settlement_panel.gd")
const Main = preload("res://main.gd")
const Museum = preload("res://museum.gd")
const UI = preload("res://ui_style.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, context: String) -> void:
	if not condition:
		failures.append(context)
		push_error("SETTLEMENT FAIL: " + context)

func settle(seconds: float = 0.4) -> void:
	await create_timer(seconds, true).timeout
	await process_frame

func capture(filename: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var directory := "res://.build/museum-ui-preview"
	DirAccess.make_dir_recursive_absolute(directory)
	check(root.get_texture().get_image().save_png(directory + "/" + filename + ".png") == OK, "save " + filename)

func kept_change() -> Dictionary:
	return {"key": "crystal_small", "label": "小型晶石", "count": 4,
		"copies_before": 1, "copies_after": 5, "level_before": 1, "level_after": 2}

func safe_payload() -> Dictionary:
	return {"emergency": false, "kept": [kept_change()], "lost": [{"key": "chest", "label": "冒险宝箱", "count": 2}],
		"income": 42, "fee": 0, "net": 42, "income_overflow": 0}

func run() -> void:
	var layer := SettlementPanel.new()
	root.add_child(layer)
	await process_frame
	check(layer.process_mode == Node.PROCESS_MODE_ALWAYS, "settlement layer keeps processing while the base is paused")

	layer.open(safe_payload())
	check(layer.is_open and layer._modal.visible, "safe return opens the settlement window")
	var rows: Array = layer._rows.get_children()
	check(rows.size() == 2, "kept and lost items get one row each")
	var bar := rows[0].find_child("Experience", true, false) as ProgressBar
	var level_text := rows[0].find_child("LevelText", true, false) as Label
	var xp_text := rows[0].find_child("ExperienceText", true, false) as Label
	check(bar != null and level_text != null and xp_text != null, "kept rows carry a level and an experience bar")
	check(level_text.text == "Lv.1", "rows start at the level before collection")
	await settle(1.4)
	check(bar.max_value == float(Museum.need_for(2)) and bar.value == float(Museum.xp_for(5)),
		"bar animates to the real experience after four copies")
	check(level_text.text == "Lv.1 → Lv.2", "level label updates after the level-up")
	check(xp_text.text.contains("2 / 3"), "experience text reports the new requirement")
	var lost_style: StyleBoxFlat = rows[1].get_theme_stylebox("panel")
	check(lost_style.border_color == UI.DANGER and lost_style.border_width_top == 2, "dropped items use a red border")
	check(layer._summary.text.contains("展馆收入 42"), "summary reports the expedition income")
	await capture("settlement-safe-1100")
	layer.close()
	check(not layer.is_open and not layer._modal.visible, "confirm closes the settlement window")

	layer.open({"emergency": true, "kept": [], "lost": [{"key": "hammer", "label": "遗落战锤", "count": 2}],
		"income": 0, "fee": 0, "net": 0, "income_overflow": 0})
	check(layer._title.text == "紧急救援" and layer._summary.text.contains("掉落"), "emergency settlement explains the loss")
	check(layer._rows.get_child_count() == 1, "emergency shows only the lost items")
	var emergency_style: StyleBoxFlat = layer._rows.get_child(0).get_theme_stylebox("panel")
	check(emergency_style.border_color == UI.DANGER, "emergency rows are marked with the same red border")
	await capture("settlement-lost-1100")
	layer.close()

	var game: Node3D = Main.new()
	game.progression = Main.Progression.new("")
	game.appraisal = Main.Appraisal.new("")
	game.wants_mouse_capture = false
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.set_process_unhandled_input(false)
	game.sfx.set_muted(true)
	await settle(0.4)
	game.show_outpost("lobby")
	await settle(0.4)
	game.progression.last_report = {"settlement": safe_payload()}
	game.show_outpost("report")
	check(game.settlement_panel.is_open, "harvest log opens the detailed settlement instead of plain text")
	game.settlement_panel.close()
	check(game.outpost_page == "lobby", "closing the settlement leaves the player in the lobby")
	game.queue_free()
	await process_frame
	if failures.is_empty():
		print("SETTLEMENT_OK animated_experience=true level_update=true red_lost_border=true emergency=true report_route=true")
	quit(0 if failures.is_empty() else 1)
