extends SceneTree

# A separate non-rendering viewport exercises the real visitor scene without
# creating Main, loading a player profile, or touching production save files.
const Lobby = preload("res://museum_lobby.gd")
const Comments = preload("res://museum_visitor_comments.gd")
const Progression = preload("res://progression.gd")
const STEP := 0.1

var room: Node3D
var viewport: SubViewport
var profile: RefCounted
var summary: Dictionary
var baseline: Dictionary

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, description: String) -> void:
	if not condition:
		push_error("MUSEUM VISITORS FAIL: " + description)
		quit(1)
		assert(condition, description)

func profile_snapshot() -> Dictionary:
	return {"bank": profile.bank, "research": profile.research_points,
		"levels": profile.levels.duplicate(true), "museum": profile.museum_state.duplicate(true),
		"trip": profile.active_trip.duplicate(true), "serial": profile.trip_serial,
		"report": profile.last_report.duplicate(true)}

func visitor_positions() -> Array[Vector3]:
	var result: Array[Vector3] = []
	for visitor: Node3D in room.visitors:
		result.append(visitor.position)
	return result

func legal_comments(entry: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for variant in range(32):
		var text: String = Comments.comment_for(entry, variant)
		if text not in result:
			result.append(text)
	return result

func check_current_comment() -> void:
	var panels := room.find_children("*", "PanelContainer", true, false)
	var visible_count := 0
	for panel: PanelContainer in panels:
		if panel.is_visible_in_tree():
			visible_count += 1
	check(panels.size() == 1 and visible_count <= 1, "the standalone visitor scene owns one shared speech bubble")
	check(room.bubble_visible == (visible_count == 1), "public bubble state matches the actual displayed panel")
	if not room.bubble_visible:
		return
	check(not room.bubble_text.is_empty() and room._bubble_label.text == room.bubble_text,
		"a visible bubble presents its current comment")
	check(room.bubble_visitor >= 0 and room.bubble_visitor < room.visitors.size(),
		"a visible bubble belongs to one real visitor")
	var speaker: Dictionary = room._visitor_states[room.bubble_visitor]
	check(speaker.phase == "view", "a visitor comments while viewing rather than while walking between exhibits")
	if room.displayed_keys.is_empty():
		check(room.bubble_slot == -1, "an empty museum comment does not invent a displayed item")
		var empty_options: Array[String] = []
		for variant in range(32):
			empty_options.append(Comments.empty_comment(variant))
		check(room.bubble_text in empty_options, "empty hall uses an empty-collection comment")
		return
	var slot: int = room.bubble_slot
	check(int(speaker.target_slot) == slot, "the speaking visitor is viewing the commented exhibit")
	check(slot >= 0 and slot < int(summary.capacity), "comment references an unlocked exhibition slot")
	var key: String = summary.slots[slot]
	check(not key.is_empty() and room.displayed_keys.has(key) and summary.exhibits.has(key),
		"only a currently displayed owned exhibit can receive a comment")
	check(room.bubble_text in legal_comments(summary.exhibits[key]),
		"bubble wording comes from the actual slot specimen, wear and research level")

func check_visitor_clearance() -> void:
	for visitor: Node3D in room.visitors:
		for base: MeshInstance3D in room._bases:
			var box: AABB = base.mesh.get_aabb()
			var local: Vector3 = base.to_local(visitor.global_position)
			var footprint := Rect2(Vector2(box.position.x, box.position.z), Vector2(box.size.x, box.size.z))
			check(not footprint.has_point(Vector2(local.x, local.z)), "visitor walks around solid pedestal bodies")

func advance(seconds: float) -> Dictionary:
	var starts := visitor_positions()
	var moved: Array[bool] = []
	for index in range(room.visitors.size()):
		moved.append(false)
	var activations := 0
	var hidden_frames := 0
	var was_visible: bool = room.bubble_visible
	var slots: Dictionary = {}
	for step in range(ceili(seconds / STEP)):
		room._process(STEP)
		check_current_comment()
		check_visitor_clearance()
		if room.bubble_visible:
			if not was_visible:
				activations += 1
			slots[room.bubble_slot] = true
		else:
			hidden_frames += 1
		was_visible = room.bubble_visible
		for index in range(room.visitors.size()):
			if room.visitors[index].position.distance_to(starts[index]) > 0.2:
				moved[index] = true
	check(profile_snapshot() == baseline, "visitor animation and comments never mutate progression or collection")
	return {"activations": activations, "hidden_frames": hidden_frames, "moved": moved, "slots": slots.keys()}

func wait_for_bubble() -> void:
	for step in range(2400):
		room._process(STEP)
		if room.bubble_visible:
			check_current_comment()
			return
	check(false, "an active hall eventually produces a periodic visitor comment")

func create_collection() -> void:
	var cargo: Array[Dictionary] = []
	for category: Dictionary in Progression.Museum.CATEGORIES:
		var item: Dictionary = category.duplicate(true)
		item["wear"] = 5 + cargo.size() * 10
		cargo.append(item)
	var trip: Dictionary = profile.pay_entry("meadow", true)
	check(trip.ok, "isolated collection starts a valid fixture expedition")
	check(profile.settle_expedition(int(trip.trip_id), cargo, false, 65.0).ok,
		"six canonical item categories enter the actual warehouse ledger")
	for item: Dictionary in profile.museum_state.warehouse.duplicate(true):
		check(profile.donate_item(int(item.uid)).ok, "fixture registers a real collected item")
	check(profile.museum_state.exhibits.size() == 6, "fixture owns all six actual collectible categories")
	baseline = profile_snapshot()
	summary = profile.museum_summary()
	room.set_collection(summary)

func check_comment_semantics() -> void:
	var distinct: Dictionary = {}
	for category: Dictionary in Progression.Museum.CATEGORIES:
		var entry: Dictionary = summary.exhibits[category.key].duplicate(true)
		entry.level = 1
		entry.bestwear = 10
		entry.item.wear = 10
		var ordinary: String = Comments.comment_for(entry, 0)
		check(not ordinary.is_empty(), "every real category has meaningful comment text")
		distinct[ordinary] = true
		entry.bestwear = 60
		entry.item.wear = 60
		check(Comments.comment_for(entry, 0) != ordinary, "poor condition changes this category's comment")
		entry.bestwear = 10
		entry.item.wear = 10
		entry.level = 3
		check(Comments.comment_for(entry, 0) != ordinary, "research level changes this category's comment")
		# Excellent/worn items must retain observations about their actual form,
		# rather than all becoming the same condition template with a new noun.
		for wear: int in [0, 60]:
			entry.bestwear = wear
			entry.item.wear = wear
			var options := legal_comments(entry)
			check(options.size() >= 2, "this category has rotating observations at either condition extreme")
			var characteristic_found := false
			for text: String in options:
				for reaction: String in Comments.REACTIONS[category.key]:
					if text.contains(reaction):
						characteristic_found = true
			check(characteristic_found, "condition commentary retains an observation specific to the item category")
	check(distinct.size() == 6, "small/medium/large crystals, chest, shield and hammer have distinct comments")
	check(profile_snapshot() == baseline, "comment selection is a read-only operation")

func run() -> void:
	profile = Progression.new("")
	profile.bank = 5000
	baseline = profile_snapshot()
	summary = profile.museum_summary()
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.size = Vector2i(1100, 600)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(viewport)
	room = Lobby.new()
	viewport.add_child(room)
	await process_frame
	room.set_collection(summary)
	room.set_active(true)
	# Advance deterministically; the production _process implementation is still
	# used, but render/frame scheduling cannot add unmeasured elapsed time.
	room.set_process(false)
	check(profile.profile_path.is_empty(), "all fixture transactions stay in memory")
	check(room.find_child("LobbyAstronaut", true, false) == null, "the exhibition has no controllable protagonist")
	check(room.visitors.size() >= 3, "at least three real visitors populate the hall")
	check(room.displayed_keys.is_empty() and room._models.is_empty(), "fresh hall does not fabricate collected exhibits")
	var empty_result := advance(120.0)
	check(empty_result.activations >= 2 and empty_result.hidden_frames > 0,
		"empty-gallery comments appear periodically and clear between appearances")
	check(empty_result.slots == [-1], "empty-gallery bubbles never name a nonexistent stand")
	for moved: bool in empty_result.moved:
		check(moved, "each visitor changes position rather than acting as a static decoration")

	create_collection()
	check_comment_semantics()
	check(room.displayed_keys.size() == 3 and summary.exhibits.size() == 6,
		"test distinguishes three displayed exhibits from six owned categories")
	check(not room.bubble_visible and room.bubble_text.is_empty(), "changing collection clears the old empty-hall comment")
	var populated_result := advance(180.0)
	check(populated_result.activations >= 3 and populated_result.hidden_frames > 0,
		"real exhibit comments recur with quiet gaps")
	check(populated_result.slots.size() >= 2, "comments cover different displayed objects")
	wait_for_bubble()
	var current_text: String = room.bubble_text
	var current_slot: int = room.bubble_slot
	room.set_collection(profile.museum_summary())
	check(room.bubble_visible and room.bubble_text == current_text and room.bubble_slot == current_slot,
		"an unchanged state refresh does not continuously restart a periodic comment")

	room.set_active(false)
	check(not room.bubble_visible, "closing the hall hides a live bubble immediately")
	var stopped_clock: float = room._comment_clock
	var stopped_positions := visitor_positions()
	for step in range(100):
		room._process(STEP)
	check(room._comment_clock == stopped_clock and visitor_positions() == stopped_positions,
		"inactive hall advances neither visitor movement nor the comment clock")
	check(not room.bubble_visible, "inactive hall never creates a new bubble")
	room.set_active(true)
	room.set_process(false)
	wait_for_bubble()

	# Keep all six collection entries, but only display a previously hidden type.
	# A stale comment or a random comment chosen from owned items now fails.
	for slot in range(int(summary.capacity)):
		check(profile.place_exhibit("", slot).ok, "clear the old display through the real placement ledger")
	check(profile.place_exhibit("hammer", 1).ok, "display one previously unshown owned artifact")
	baseline = profile_snapshot()
	summary = profile.museum_summary()
	room.set_collection(summary)
	check(not room.bubble_visible and room.bubble_text.is_empty(), "rearranging displays removes the prior exhibit comment immediately")
	check(room.displayed_keys == ["hammer"], "only the newly displayed artifact is present")
	var changed_result := advance(180.0)
	check(changed_result.activations >= 2 and changed_result.slots == [1],
		"subsequent bubbles refer only to the newly displayed slot")
	check(profile_snapshot() == baseline and profile.profile_path.is_empty(),
		"visitors never change resources, wear, levels, records or save ownership")
	room.set_active(false)
	viewport.queue_free()
	await process_frame
	print("MUSEUM_VISITORS_OK no_protagonist=true roaming=true canonical_categories=true wear_level_comments=true displayed_only=true periodic_single_bubble=true inactive_frozen=true rearrange_clears=true memory_only=true")
	quit(0)
