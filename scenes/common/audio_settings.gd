class_name AudioSettings
extends Control

## A volume slider per audio bus, as an overlay that can be dropped on any
## screen. It builds itself from the buses the project actually has, so a game
## that adds a Music bus gets a Music slider without touching this file:
##
##     var panel := AudioSettings.new()
##     add_child(panel)
##     panel.open()
##
## Reading and writing goes through AudioManager, which owns the levels and
## remembers them between runs.


signal closed

## Which buses get a row, in order. Leave it empty to show every bus there is.
@export var buses: PackedStringArray = PackedStringArray(["Master", "Music", "SFX"])

@export var title: String = "Audio"

## Covers whatever is behind, and closes when clicked.
@export var dim_color: Color = Color(0.117, 0.117, 0.117, 0.745)

var _rows: VBoxContainer
var _sliders: Dictionary = {}
var _amounts: Dictionary = {}


func _ready() -> void:
	# Usable over a paused game, and never dragged into a scene's intro anim.
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("no_intro")
	# Anchors alone leave a control built in code at its birth size of nothing,
	# and a CenterContainer centred inside nothing sits in the top left corner.
	# The offsets are what actually give it the screen.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	_build()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = dim_color
	# Full rect, not centred: this one is the veil over everything behind, and
	# it is what a click outside the panel lands on.
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(_on_dim_input)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(420, 0)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)

	var caption := Label.new()
	caption.text = title
	caption.add_theme_font_size_override("font_size", 30)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(caption)

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 10)
	box.add_child(_rows)

	var close_button := Button.new()
	close_button.text = "Back"
	close_button.pressed.connect(close)
	box.add_child(close_button)


func open() -> void:
	_rebuild_rows()
	visible = true


func close() -> void:
	if not visible:
		return
	visible = false
	AudioManager.save_settings()
	closed.emit()


# ---------------------------------------------------------------------------
# Rows
#
# Rebuilt on every open rather than kept in sync: the buses are the truth, and
# reading them again is cheaper than remembering to follow them.
# ---------------------------------------------------------------------------

func _rebuild_rows() -> void:
	for child in _rows.get_children():
		child.queue_free()
	_sliders.clear()
	_amounts.clear()

	for bus_name in _bus_list():
		_rows.add_child(_build_row(bus_name))


func _bus_list() -> PackedStringArray:
	var available := AudioManager.bus_names()
	if buses.is_empty():
		return available
	var wanted := PackedStringArray()
	for bus_name in buses:
		if available.has(bus_name):
			wanted.append(bus_name)
	return wanted


func _build_row(bus_name: String) -> Control:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 4)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	row.add_child(header)

	var label := Label.new()
	label.text = bus_name
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(label)

	var amount := Label.new()
	amount.custom_minimum_size = Vector2(56, 0)
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	amount.add_theme_color_override("font_color", Color("#b2b2b2"))
	header.add_child(amount)
	_amounts[bus_name] = amount

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = AudioManager.bus_volume(bus_name)
	slider.value_changed.connect(_on_volume_changed.bind(bus_name))
	slider.drag_ended.connect(_on_drag_ended)
	row.add_child(slider)
	_sliders[bus_name] = slider

	_update_amount(bus_name, slider.value)
	return row


func _on_volume_changed(value: float, bus_name: String) -> void:
	AudioManager.set_bus_volume(bus_name, value)
	_update_amount(bus_name, value)


## Writing to disk on every pixel of a drag is a lot of writes for nothing, so
## the level is only kept once the handle is let go.
func _on_drag_ended(changed: bool) -> void:
	if changed:
		AudioManager.save_settings()


## A slider at the bottom is the way to silence something now, so the number is
## all a row needs to say.
func _update_amount(bus_name: String, value: float) -> void:
	var label: Label = _amounts.get(bus_name)
	if label == null:
		return
	label.text = "%d%%" % roundi(value * 100.0)


func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		close()
