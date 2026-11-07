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
var _known_types: Dictionary = {}
var _last_sales: Dictionary = {}
var _catalogue_loaded := false

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

static func _catalogue_id(type_id: String) -> String:
	# Keep the original section so existing crystal discoveries are retained.
	return TYPE_ID if type_id in ["", "crystal", TYPE_ID] else type_id

func is_known(type_id: String = "crystal") -> bool:
	var entry := _catalogue_id(type_id)
	return known if entry == TYPE_ID else bool(_known_types.get(entry, false))

func price_label(inspected: bool, type_id: String = "crystal") -> String:
	if not is_known(type_id):
		return "售价 ？ · 首次出售后揭晓"
	if not inspected:
		return "估价待检查 · 继续清理表面"
	return "预计售价 %d" % sale_value()

func record_sale() -> Error:
	return record_item_sale("crystal")

func record_item_sale(type_id: String = "crystal", value: int = -1, persist: bool = true) -> Error:
	if not _catalogue_loaded:
		load_catalogue()
	var entry := _catalogue_id(type_id)
	var amount := sale_value() if value < 0 else value
	_known_types[entry] = true
	_last_sales[entry] = maxi(0, amount)
	if entry == TYPE_ID:
		known = true
		last_sale = maxi(0, amount)
	return save_catalogue() if persist else OK

func load_catalogue() -> void:
	_catalogue_loaded = true
	if catalogue_path.is_empty():
		return
	var config := ConfigFile.new()
	if config.load(catalogue_path) != OK:
		return
	_known_types.clear()
	_last_sales.clear()
	known = false
	last_sale = 0
	for section: String in config.get_sections():
		var entry := _catalogue_id(section)
		_known_types[entry] = config.get_value(section, "identified", false) == true
		_last_sales[entry] = maxi(int(config.get_value(section, "last_sale", 0)), 0)
		if entry == TYPE_ID:
			known = bool(_known_types[entry])
			last_sale = int(_last_sales[entry])

func save_catalogue() -> Error:
	if catalogue_path.is_empty():
		return OK
	var directory_error := DirAccess.make_dir_recursive_absolute(catalogue_path.get_base_dir())
	if directory_error != OK:
		return directory_error
	var config := ConfigFile.new()
	for entry: String in _known_types:
		if entry == TYPE_ID:
			continue
		config.set_value(entry, "identified", bool(_known_types[entry]))
		config.set_value(entry, "last_sale", int(_last_sales.get(entry, 0)))
	config.set_value(TYPE_ID, "identified", known)
	config.set_value(TYPE_ID, "last_sale", last_sale)
	return config.save(catalogue_path)

func reset_catalogue() -> Error:
	_catalogue_loaded = true
	_known_types.clear()
	_last_sales.clear()
	known = false
	last_sale = 0
	return save_catalogue()
