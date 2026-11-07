extends RefCounted

const TEXT := Color("#edf4fa")
const MUTED := Color("#a8bacb")
const ACCENT := Color("#75e8c5")
const WARNING := Color("#ffb880")
const DANGER := Color("#ff827c")
const PANEL := Color("#101c2a")
const BORDER := Color("#34495d")

static func panel(fill: Color = PANEL, border: Color = BORDER,
		padding: int = 16, radius: int = 12) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = padding
	style.content_margin_bottom = padding
	return style

static func theme() -> Theme:
	var result := Theme.new()
	result.default_font_size = 20
	for kind in ["Label", "Button", "CheckBox", "LineEdit"]:
		result.set_color("font_color", kind, TEXT)
	result.set_color("font_hover_color", "Button", TEXT)
	result.set_color("font_pressed_color", "Button", TEXT)
	result.set_color("font_disabled_color", "Button", Color("#8193a6"))
	result.set_stylebox("normal", "Button", panel(Color("#213347"), BORDER, 10, 8))
	result.set_stylebox("hover", "Button", panel(Color("#2c4658"), ACCENT, 10, 8))
	result.set_stylebox("pressed", "Button", panel(Color("#244d48"), ACCENT, 10, 8))
	result.set_stylebox("disabled", "Button", panel(Color("#182431"), Color("#293b4b"), 10, 8))
	result.set_stylebox("focus", "Button", panel(Color(0, 0, 0, 0), ACCENT, 10, 8))
	result.set_stylebox("normal", "LineEdit", panel(Color("#0a1420"), BORDER, 8, 6))
	result.set_stylebox("focus", "LineEdit", panel(Color(0, 0, 0, 0), ACCENT, 8, 6))
	result.set_stylebox("panel", "TooltipPanel", panel(PANEL, BORDER, 12, 8))
	result.set_font_size("font_size", "TooltipLabel", 18)
	result.set_color("font_color", "TooltipLabel", TEXT)
	return result
