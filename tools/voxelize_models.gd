extends SceneTree

# Batch voxel export for model assets.
# Usage: Godot --headless --path . -s tools/voxelize_models.gd -- --pack assets/adventure
# Writes <pack>/voxel/<id>.json plus <pack>/voxel/catalog.json. Exits 1 on any failure.

const VoxelModel = preload("res://voxel_model.gd")
const AdventureItems = preload("res://adventure_items.gd")
const Comments = preload("res://museum_visitor_comments.gd")

const DEFAULT_SIZE := 1.25
const FORMAT_MODEL := "moon-voxel-v1"
const FORMAT_CATALOG := "moon-voxel-catalog-v1"

var failures := 0

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var pack := "res://assets/adventure"
	var args := OS.get_cmdline_user_args()
	for index in range(args.size()):
		if args[index] == "--pack" and index + 1 < args.size():
			pack = args[index + 1]
	if not pack.begins_with("res://") and not pack.begins_with("user://"):
		pack = "res://" + pack.trim_prefix("./")
	var out_dir := pack.path_join("voxel")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var entries: Array = []
	var files: Array = []
	for file: String in DirAccess.get_files_at(pack):
		if file.ends_with(".glb") or file.ends_with(".gltf"):
			files.append(pack.path_join(file))
	# One record per catalogue entry, so the same model can ship at several sizes
	# (e.g. chest and a scaled-up large chest); untouched files get a default entry.
	var covered := {}
	for item: Dictionary in AdventureItems.ITEMS:
		var scene_path := str(item.get("scene", ""))
		if files.has(scene_path):
			covered[scene_path] = true
			entries.append(_export_model(scene_path, out_dir, item))
	for file_path: String in files:
		if not covered.has(file_path):
			entries.append(_export_model(file_path, out_dir, {}))
	var catalog := {
		"format": FORMAT_CATALOG,
		"cell_size": VoxelModel.CELL_SIZE,
		"pack": pack,
		"models": entries,
		"missing": _missing_fields(entries),
	}
	_write_json(out_dir.path_join("catalog.json"), catalog)
	print("VOXEL_CATALOG models=%d failures=%d missing=%s" % [entries.size(), failures, str(catalog.missing)])
	quit(1 if failures > 0 else 0)

func _export_model(path: String, out_dir: String, meta: Dictionary) -> Dictionary:
	var scene: PackedScene = load(path)
	if scene == null:
		failures += 1
		return {"id": path.get_file().get_basename(), "source": path, "ok": false, "error": "scene did not import"}
	var id := str(meta.get("id", path.get_file().get_basename()))
	var target_size := float(meta.get("size", DEFAULT_SIZE))
	var canonical := VoxelModel.sample_scene(scene, Basis.IDENTITY, target_size)
	if canonical.is_empty():
		failures += 1
		return {"id": id, "source": path, "ok": false, "error": "voxelisation failed"}
	var lattice := _on_lattice(canonical)
	var orientations := _verify_orientations(scene, canonical, target_size)
	var bounds: AABB = canonical.diagnostics.rotated_bounds
	var record := {
		"format": FORMAT_MODEL,
		"id": id,
		"label": meta.get("label"),
		"source": path,
		"source_sha256": FileAccess.get_sha256(ProjectSettings.globalize_path(path)),
		"cell_size": VoxelModel.CELL_SIZE,
		"target_size": target_size,
		"target_size_source": "catalogue" if meta.has("size") else "default",
		"registered": not meta.is_empty(),
		"footprint": _footprint(meta),
		"value": meta.get("value"),
		"color": (meta.get("color") as Color).to_html() if meta.has("color") else null,
		"counts": {
			"occupied": canonical.cells.size(),
			"surface": int(canonical.diagnostics.surface_cells),
			"interior": int(canonical.diagnostics.filled_cells),
			"boundary_faces": canonical.exterior.size(),
		},
		"bounds_cells": {
			"position": _vector3i(floori(bounds.position.x / VoxelModel.CELL_SIZE), floori(bounds.position.y / VoxelModel.CELL_SIZE), floori(bounds.position.z / VoxelModel.CELL_SIZE)),
			"size": _vector3i(ceili(bounds.size.x / VoxelModel.CELL_SIZE), ceili(bounds.size.y / VoxelModel.CELL_SIZE), ceili(bounds.size.z / VoxelModel.CELL_SIZE)),
		},
		"palette": _palette(canonical),
		"cells": _cells(canonical),
		"face_colors": _face_colors(canonical),
		"lattice": lattice,
		"orientations": orientations,
		"comments_registered": Comments.REACTIONS.has(id),
		"ok": lattice and orientations.ok,
	}
	if not record.ok:
		failures += 1
	_write_json(out_dir.path_join(id + ".json"), record)
	return {
		"id": id, "source": path, "registered": record.registered, "ok": record.ok,
		"counts": record.counts, "bounds_cells": record.bounds_cells,
		"palette": record.palette, "lattice": lattice, "orientations": orientations,
		"comments_registered": record.comments_registered,
	}

func _missing_fields(entries: Array) -> Dictionary:
	var result := {}
	for entry: Dictionary in entries:
		var gaps: Array = []
		if not bool(entry.registered):
			gaps.append_array(["label", "footprint", "value", "color"])
		if not bool(entry.comments_registered):
			gaps.append("comments")
		if not bool(entry.ok):
			gaps.append("validation")
		if not gaps.is_empty():
			result[str(entry.id)] = gaps
	return result

func _footprint(meta: Dictionary) -> Variant:
	if not meta.has("footprint"):
		return null
	var footprint: Vector2i = meta.footprint
	return [footprint.x, footprint.y]

func _vector3i(x: int, y: int, z: int) -> Array:
	return [x, y, z]

func _palette(canonical: Dictionary) -> Array:
	var unique := {}
	for color: Color in canonical.cell_colors.values():
		unique[color.to_html()] = true
	var result: Array = unique.keys()
	result.sort()
	return result

func _cells(canonical: Dictionary) -> Array:
	var result: Array = []
	for cell: Vector3i in canonical.cells:
		result.append([cell.x, cell.y, cell.z, (canonical.cell_colors[cell] as Color).to_html()])
	return result

func _face_colors(canonical: Dictionary) -> Array:
	var result: Array = []
	for face: Vector4i in canonical.face_colors:
		result.append([face.x, face.y, face.z, face.w, (canonical.face_colors[face] as Color).to_html()])
	return result

func _on_lattice(canonical: Dictionary) -> bool:
	var vertices: PackedVector3Array = (canonical.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for vertex in vertices:
		var grid := vertex / VoxelModel.CELL_SIZE
		if not grid.is_equal_approx(grid.round()):
			return false
	return true

func _verify_orientations(scene: PackedScene, canonical: Dictionary, target_size: float) -> Dictionary:
	var seen := {}
	var canonical_cells := {}
	for cell: Vector3i in canonical.cells:
		canonical_cells[cell] = true
	var count := 0
	var cells_ok := true
	var faces_ok := true
	var palette_ok := true
	for x in range(4):
		for y in range(4):
			for z in range(4):
				var turns := Vector3i(x, y, z)
				var rotation := VoxelModel.orthogonal_basis(turns)
				if seen.has(str(rotation)):
					continue
				seen[str(rotation)] = true
				count += 1
				var rotated := VoxelModel.sample_orthogonal_scene(scene, turns, target_size)
				if rotated.is_empty():
					cells_ok = false
					continue
				cells_ok = cells_ok and rotated.cells.size() == canonical.cells.size()
				faces_ok = faces_ok and rotated.exterior.size() == canonical.exterior.size()
				palette_ok = palette_ok and rotated.face_colors.size() == canonical.face_colors.size()
				var inverse := rotation.transposed()
				for cell: Vector3i in rotated.cells:
					var original := Vector3i((inverse * (Vector3(cell) + Vector3.ONE * 0.5) - Vector3.ONE * 0.5).round())
					if not canonical_cells.has(original):
						cells_ok = false
	return {
		"count": count, "cells_consistent": cells_ok,
		"faces_consistent": faces_ok, "palette_consistent": palette_ok,
		"ok": count == 24 and cells_ok and faces_ok and palette_ok,
	}

func _write_json(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "  "))
	file.close()
	print("VOXEL_WRITE ", path)
