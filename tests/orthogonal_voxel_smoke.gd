extends SceneTree

const VoxelModel = preload("res://voxel_model.gd")
const FIXTURES := [
	{"file": "chest", "size": 1.0},
	{"file": "shield", "size": 1.125},
	{"file": "warhammer", "size": 1.25},
]
var failed := false


func _initialize() -> void:
	call_deferred("run")


func require(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error("ORTHOGONAL VOXEL FAIL: " + message)


func rotate_cell(cell: Vector3i, rotation: Basis) -> Vector3i:
	return Vector3i((rotation * (Vector3(cell) + Vector3.ONE * 0.5) - Vector3.ONE * 0.5).round())


func orientations() -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	var unique := {}
	for x in range(4):
		for y in range(4):
			for z in range(4):
				var turns := Vector3i(x, y, z)
				var rotation := VoxelModel.orthogonal_basis(turns)
				var key := str(rotation)
				if not unique.has(key):
					unique[key] = true
					result.append(turns)
	require(result.size() == 24, "quarter-turn Euler combinations produce exactly 24 cube orientations")
	return result


func verify(canonical: Dictionary, rotated: Dictionary, rotation: Basis, label: String) -> void:
	require(rotated.cells.size() == canonical.cells.size(), label + " preserves exact occupied cell count")
	require(rotated.exterior.size() == canonical.exterior.size(), label + " preserves exact boundary-face count")
	require(rotated.face_colors.size() == canonical.face_colors.size(), label + " preserves every painted boundary face")
	var occupied := {}
	for cell: Vector3i in rotated.cells:
		occupied[cell] = true
	var inverse := rotation.transposed()
	var canonical_cells := {}
	for cell: Vector3i in canonical.cells:
		canonical_cells[cell] = true
	for cell: Vector3i in rotated.cells:
		var original := rotate_cell(cell, inverse)
		require(canonical_cells.has(original), label + " inverse rotation restores original occupancy with no holes")
		require(rotated.cell_colors[cell] == canonical.cell_colors[original], label + " inverse rotation restores cell palette")
	var faces := 0
	for cell: Vector3i in occupied:
		for step: Vector3i in VoxelModel.STEPS:
			if not occupied.has(cell + step):
				faces += 1
	require(faces == rotated.exterior.size(), label + " exposure samples count actual exterior faces")
	for face: Vector4i in rotated.face_colors:
		var original := rotate_cell(Vector3i(face.x, face.y, face.z), inverse)
		var normal := Vector3i((inverse * Vector3(VoxelModel.STEPS[face.w])).round())
		var side := VoxelModel.STEPS.find(normal)
		var original_face := Vector4i(original.x, original.y, original.z, side)
		require(canonical.face_colors.has(original_face), label + " every painted face has exactly one original")
		require(rotated.face_colors[face] == canonical.face_colors.get(original_face), label + " front/back paint survives orientation round trip")
	var vertices: PackedVector3Array = rotated.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for vertex in vertices:
		var lattice := vertex / VoxelModel.CELL_SIZE
		require(lattice.is_equal_approx(lattice.round()), label + " rendered corners remain on shared lattice")


func run() -> void:
	var turns := orientations()
	var details := []
	for definition: Dictionary in FIXTURES:
		var scene: PackedScene = load("res://assets/adventure/%s.glb" % definition.file)
		var canonical := VoxelModel.sample_orthogonal_scene(scene, Vector3i.ZERO, float(definition.size))
		require(not canonical.is_empty(), "sample canonical " + str(definition.file))
		if canonical.is_empty():
			continue
		var started := Time.get_ticks_usec()
		for turn in turns:
			var result := VoxelModel.sample_orthogonal_scene(scene, turn, float(definition.size))
			verify(canonical, result, VoxelModel.orthogonal_basis(turn), "%s %s" % [definition.file, turn])
		var complete_turn := VoxelModel.sample_orthogonal_scene(scene, Vector3i(0, 4, 0), float(definition.size))
		require(complete_turn.cell_colors == canonical.cell_colors and complete_turn.face_colors == canonical.face_colors, "four quarter turns restore exact cell and face palettes")
		details.append({"source": definition.file, "cells": canonical.cells.size(), "faces": canonical.exterior.size(), "canonical_sample_us": canonical.diagnostics.canonical_sample_us, "all_24_checks_us": Time.get_ticks_usec() - started})
	if not failed:
		print("ORTHOGONAL_VOXEL_OK sources=3 orientations=24 exact_count=true no_holes=true face_palette_roundtrip=true four_turns_restore=true details=", details)
	quit(1 if failed else 0)
