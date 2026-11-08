extends RefCounted

const Palette = preload("res://palette.gd")

const TEXT := Palette.CREAM
const MUTED := Palette.PALE_STONE
const ACCENT := Palette.CYAN
const WARNING := Palette.AMBER
const DANGER := Palette.SKIN_SHADOW
const PANEL := Palette.INK
const BORDER := Palette.SLATE

static func panel(fill: Color = PANEL, border: Color = BORDER,
		padding: int = 16, radius: int = 2) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 3
	style.set_corner_radius_all(radius)
	style.corner_detail = 2
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
	result.set_color("font_disabled_color", "Button", Palette.DUST)
	result.set_stylebox("normal", "Button", panel(Palette.DEEP_SLATE, BORDER, 10, 2))
	result.set_stylebox("hover", "Button", panel(Palette.SLATE, ACCENT, 10, 2))
	result.set_stylebox("pressed", "Button", panel(Palette.TEAL_SHADOW, ACCENT, 10, 2))
	result.set_stylebox("disabled", "Button", panel(Palette.INK, Palette.DEEP_SLATE, 10, 2))
	result.set_stylebox("focus", "Button", panel(Color(0, 0, 0, 0), ACCENT, 10, 2))
	result.set_stylebox("normal", "LineEdit", panel(Palette.INK, BORDER, 8, 2))
	result.set_stylebox("focus", "LineEdit", panel(Color(0, 0, 0, 0), ACCENT, 8, 2))
	result.set_stylebox("panel", "TooltipPanel", panel(PANEL, BORDER, 12, 2))
	result.set_font_size("font_size", "TooltipLabel", 18)
	result.set_color("font_color", "TooltipLabel", TEXT)
	return result
