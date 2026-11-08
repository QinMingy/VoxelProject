extends SceneTree

const Main = preload("res://main.gd")
const Crystal = preload("res://crystal.gd")
const Items = preload("res://adventure_items.gd")
var game: Node3D
var failed := false

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, why: String) -> void:
	if not ok:
		failed = true
		push_error("ADVENTURE LOOT FAIL: " + why)
		quit(1)
		assert(ok, why)

func uncover(item: Node3D) -> void:
	var middle: Vector3 = item.position + item.get_local_bounds().get_center()
	var bounds: AABB = item.get_local_bounds()
	var reach := bounds.size * 0.5 + Vector3.ONE * 0.25
	# Actual brush operations surrounding the protected object; no fake ready flags.
	for y in range(12, -13, -1):
		for x in range(-3, 4):
			for z in range(-3, 4):
				game.terrain.mine_at(middle + Vector3(float(x) * reach.x / 3.0, float(y) * 0.125, float(z) * reach.z / 3.0), Vector3.UP, 0)
		item.refresh_exposure(game.terrain)
		if item.is_loose():
			return
	check(false, "surrounding real soil excavation releases " + item.item_type)

func run() -> void:
	game = Main.new()
	game.progression = Main.Progression.new("")
	game.appraisal = Main.Appraisal.new("")
	game.auto_open_base = false
	game.wants_mouse_capture = false
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.set_process_unhandled_input(false)
	game.adventure_trial = true
	var started := Time.get_ticks_usec()
	game.start_trip(true)
	var generation_ms := float(Time.get_ticks_usec() - started) / 1000.0
	check(game.crystals.size() == 3, "trial creates exactly three real adventure props")
	var results := []
	for index in range(3):
		var item: Node3D = game.crystals[index]
		check(item.item_type == str(Items.ITEMS[index].id), "trial contains each distinct item kind")
		var turns: Vector3 = item.source_rotation / (PI * 0.5)
		check(turns.is_equal_approx(turns.round()) and item.basis.is_equal_approx(Basis.IDENTITY), "gameplay burial is restricted to exact quarter-turns on the shared grid")
		var canonical := Main.Crystal.VoxelModel.sample_orthogonal_scene(Items.source_scene(index), Vector3i.ZERO, float(Items.ITEMS[index].size))
		check(item.get_world_cells().size() == canonical.cells.size() and item._geometry.exterior.size() == canonical.exterior.size(), "quarter-turn burial preserves the accepted frontal shape and its face count")
		check(not item.get_world_cells().is_empty(), "voxelized prop occupies material cells")
		var bounds: AABB = item.get_local_bounds()
		check(bounds.size.length() > 0.7, "prop has a visible three dimensional silhouette")
		var exterior_count := 0
		var occupied := {}
		for cell: Vector3i in item.get_world_cells():
			occupied[cell] = true
			check(game.terrain.crystal_owner_at(cell) == item.get_instance_id() and not game.terrain.is_soil_cell(cell), "soil and item never overlap")
		for cell: Vector3i in occupied:
			for step: Vector3i in Crystal.STEPS:
				if not occupied.has(cell + step):
					exterior_count += 1
		check(exterior_count == item._geometry.exterior.size(), "exposure denominator counts boundary faces, including repeated neighboring cells")
		var original_price: int = item.base_value
		uncover(item)
		check(item.is_loose() and item.wants_outline(), "excavation exposes and outlines collectible prop")
		var cells: Array[Vector3i] = item.get_world_cells()
		game.suit.position = item.position + Vector3(0.7, 0.4, 0.7)
		check(game.collect_crystal(item), "whole prop goes into real grid inventory")
		for cell in cells:
			check(not game.terrain.is_solid_cell(cell), "pickup leaves only its exact voxel shape as air")
		var record: Dictionary = game.inventory.get_item(item.get_instance_id())
		check(record.item_type == item.item_type and record.item_name == item.item_name, "inventory preserves per-kind name and identity")
		check(record.base_value == original_price and record.footprint == Items.ITEMS[index].footprint, "price and bag footprint use metadata, not rotated cell count")
		check(game.appraisal.is_known(item.item_type), "item price is known without a separate identification step")
		if index == 0:
			var destination: Vector3 = Main.LANDER + Vector3(-2.0, 0, 0)
			destination.y = game.terrain.height_at(destination.x, destination.z)
			check(item.drop_at(destination), "negative-origin rotated prop can be placed on cleared supported soil")
			game.inventory.remove_item(item.get_instance_id())
			game.carried_crystals.erase(item)
			game.suit.position = item.position + Vector3(0.7, 0.4, 0.7)
			check(game.collect_crystal(item), "dropped prop can be picked up again")
		results.append({"kind": item.item_type, "cells": cells.size(), "faces": exterior_count, "sampling": item.voxel_diagnostics})
	check(game.inventory.items.size() == 3, "all three trial items fit in starter bag")
	game.settle(false)
	if game.settlement_panel.is_open:
		game.settlement_panel.close()
	var archived := 0
	for key: String in game.progression.museum_state.items:
		archived += int(game.progression.museum_state.items[key].copies)
	check(game.bank == 150 and archived == 3, "safe return archives three real props without automatically converting them into money")
	game.progression.bank = 0
	game.gm_panel.open()
	check(paused and game.gm_open, "GM opens and pauses before testing the actual trial button")
	game.gm_panel._action_buttons.adventure_trial.pressed.emit()
	check(game.on_moon and not paused and not game.gm_open and game.crystals.size() == 3, "actual GM trial button starts the three-prop expedition and resumes controls")
	check(game.trip_fee == 0 and game.bank == 0, "GM demonstration never charges an entrance fee")
	if not failed:
		print("ADVENTURE_LOOT_OK generation_ms=%.1f rotated_shared_grid=true excavation=true pickup_cavity=true drop=true auto_archived=true details=%s" % [generation_ms, str(results)])
	game.sfx.set_muted(true)
	await create_timer(0.10, true).timeout
	game.queue_free()
	await process_frame
	await create_timer(0.25).timeout
	quit(1 if failed else 0)
