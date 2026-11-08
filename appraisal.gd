extends RefCounted

# Crystal price helper. Wear and first-time identification were removed with the
# experience-based collection, so the displayed value is the catalogue value.
const BASE_VALUE := 400

var base_value := BASE_VALUE
var known := true
var catalogue_path := ""

func _init(path: String = "") -> void:
	catalogue_path = path

func roll_specimen() -> void:
	pass

func integrity() -> int:
	return 100

func sale_value() -> int:
	return base_value

func is_known(_type_id: String = "crystal") -> bool:
	return true

func price_label(inspected: bool, _type_id: String = "crystal") -> String:
	if not inspected:
		return "估价待检查 · 继续清理表面"
	return "预计售价 %d" % sale_value()

func load_catalogue() -> void:
	pass

func save_catalogue() -> Error:
	return OK

func reset_catalogue() -> Error:
	return OK
