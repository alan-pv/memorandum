class_name CardPalette
extends RefCounted

## Turns a group number into its color.


const SATURATION: float = 0.72
const VALUE: float = 0.90

const HUE_OFFSET: float = 0.08


static func color_for_value(value: int, total_values: int) -> Color:
	if total_values <= 0:
		return Color.WHITE
	var base_hue = float(value - 1) / total_values
	var h = fmod((base_hue + HUE_OFFSET), 1.0)
	return Color.from_hsv(h, SATURATION, VALUE)


static func text_color_for(background: Color) -> Color:
	if background.get_luminance() < 0.5:
		return Color.WHITE
	return Color.BLACK
