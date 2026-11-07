extends RefCounted

const TYPE_ID := "moon_crystal_cluster"
const BASE_VALUE := 400
const MAX_WEAR := 65

var wear_percent := 0
var base_value := BASE_VALUE
var known := false
var last_sale := 0
var catalogue_path: String
var random := RandomNumberGenerator.new()

func _init(path: String = "@default") -> void:
	catalogue_path = ("res://.demo-data/catalogue.cfg" if OS.has_feature("editor") else "user://catalogue.cfg") if path == "@default" else path
	random.randomize()

func roll_specimen() -> void:
	# The specimen's condition is fixed on entry, never rerolled at sale.
	wear_percent = random.randi_range(0, MAX_WEAR)

func integrity() -> int:
	return 100 - wear_percent

func sale_value() -> int:
	return roundi(base_value * float(integrity()) / 100.0)

func condition_name() -> String:
	if wear_percent <= 10:
		return "近乎完好"
	if wear_percent <= 25:
		return "轻微磨损"
	if wear_percent <= 50:
		return "明显磨损"
	return "严重磨损"

func price_label(inspected: bool) -> String:
	if not known:
		return "售价 ？ · 首次出售后揭晓"
	if not inspected:
		return "估价待检查 · 继续清理表面"
	return "预计售价 %d" % sale_value()

func record_sale() -> Error:
	known = true
	last_sale = sale_value()
	return save_catalogue()

func load_catalogue() -> void:
	if catalogue_path.is_empty():
		return
	var config := ConfigFile.new()
	if config.load(catalogue_path) != OK:
		return
	known = config.get_value(TYPE_ID, "identified", false) == true
	last_sale = maxi(int(config.get_value(TYPE_ID, "last_sale", 0)), 0)

func save_catalogue() -> Error:
	if catalogue_path.is_empty():
		return OK
	var directory_error := DirAccess.make_dir_recursive_absolute(catalogue_path.get_base_dir())
	if directory_error != OK:
		return directory_error
	var config := ConfigFile.new()
	config.set_value(TYPE_ID, "identified", known)
	config.set_value(TYPE_ID, "last_sale", last_sale)
	return config.save(catalogue_path)

func reset_catalogue() -> Error:
	known = false
	last_sale = 0
	return save_catalogue()
