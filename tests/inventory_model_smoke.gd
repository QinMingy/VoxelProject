extends SceneTree

const Inventory = preload("res://inventory.gd")
const InventoryPanel = preload("res://inventory_panel.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var bag := Inventory.new(3, 2)
	var original := {"id": 10, "label": "长晶石", "footprint": Vector2i(1, 2), "wear": 25, "base_value": 400, "world_id": 111}
	assert(bag.try_add(original))
	original.wear = 65
	original.footprint = Vector2i(9, 9)
	assert(bag.get_item(10).wear == 25 and bag.used_cells() == 2, "pickup freezes item data")
	assert(not bag.try_add({"id": 10, "footprint": Vector2i.ONE}), "duplicate ID rejected")
	assert(bag.move_item(10, Vector2i(1, 0), true), "rotate long item into horizontal row")
	assert(bag.get_item(10).rotated)
	var before: Dictionary = bag.get_item(10)
	assert(not bag.move_item(10, Vector2i(2, 1), true), "out-of-bounds placement rejected")
	assert(bag.get_item(10) == before, "invalid move keeps original placement")
	assert(bag.try_add({"id": 11, "footprint": Vector2i.ONE, "wear": 0, "base_value": 100}))
	assert(not bag.can_place({"footprint": Vector2i(2, 2)}, Vector2i.ZERO, false), "overlap blocked")
	assert(not bag.can_place({"footprint": Vector2i.ONE}, Vector2i(-1, 0), false), "negative placement blocked")
	var long_second := {"id": 12, "footprint": Vector2i(1, 2), "wear": 5, "base_value": 400}
	assert(bag.try_add(long_second), "first fit tries rotated orientation when vertical spaces are blocked")
	assert(bag.get_item(12).rotated)
	assert(bag.used_cells() == 5)
	assert(bag.try_add({"id": 13, "footprint": Vector2i.ONE, "wear": 60, "base_value": 100}))
	assert(bag.used_cells() == 6)
	assert(not bag.try_add({"id": 14, "footprint": Vector2i.ONE}), "full pack rejects pickup without mutation")
	var discarded := bag.remove_item(13)
	assert(discarded.id == 13 and discarded.wear == 60)
	assert(bag.try_add({"id": 14, "footprint": Vector2i.ONE, "wear": 0, "base_value": 600}), "discard frees a slot for better loot")
	var snapshot := bag.get_item(14)
	snapshot.wear = 99
	assert(bag.get_item(14).wear == 0, "read snapshots cannot change frozen value")
	assert(bag.item_at(Vector2i(1, 0)).id == 10)
	bag.clear()
	assert(bag.used_cells() == 0 and bag.items.is_empty())
	assert(bag.try_add({"id": 20, "label": "晶石", "footprint": Vector2i(1, 2), "wear": 10, "base_value": 400}))
	var panel := InventoryPanel.new()
	root.add_child(panel)
	panel.open(bag, false, 18.0, {"id": 21, "label": "大晶石", "footprint": Vector2i(2, 2), "wear": 20, "base_value": 800})
	panel._on_cell_clicked(Vector2i.ZERO)
	assert(panel.selected_id == 20)
	assert(panel._details.text.contains("估价 400"), "selected item shows its catalogue price")
	assert(panel._pending_info.text.contains("估价 800"), "pending item shows its catalogue price")
	paused = true
	var rotate := InputEventKey.new()
	rotate.physical_keycode = KEY_R
	rotate.pressed = true
	panel._input(rotate)
	assert(panel.preview_rotated, "rotation remains available while paused")
	panel.refresh(true)
	assert(panel._details.text.contains("估价 400"), "known selection keeps the catalogue price")
	var close_key := InputEventKey.new()
	close_key.physical_keycode = KEY_B
	close_key.pressed = true
	panel._input(close_key)
	assert(not panel.is_open and bag.items.size() == 1, "close retains inventory")
	paused = false
	panel.queue_free()
	await process_frame
	print("INVENTORY_OK bounds overlap rotations full_pack discard_replace immutable_values paused_panel visible_prices")
	quit(0)
