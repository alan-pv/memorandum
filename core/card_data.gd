class_name CardData
extends Resource

## The data of a card: number, color and which copy of the group it is.


@export var value: int = 0

@export var color: Color = Color.WHITE

@export var copy_index: int = 0


func _init(p_value: int = 0, p_color: Color = Color.WHITE, p_copy_index: int = 0) -> void:
	value = p_value
	color = p_color
	copy_index = p_copy_index


func get_label() -> String:
	return str(value)


func _to_string() -> String:
	return "CardData(value=%d, copy=%d)" % [value, copy_index]
