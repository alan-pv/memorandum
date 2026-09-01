class_name PlayerSlotsEditor
extends VBoxContainer

## Picks how many sit at the table and who each of them is.


signal slots_changed(seats: Array[PlayerSlot])

const KIND_LABELS := ["Human", "Bot"]

## Seat 0 is the person holding the device: it cannot become a bot.
@export var lock_first_seat: bool = true

@export var show_bot_tuning: bool = true

var seats: Array[PlayerSlot] = []

var _count_row: HBoxContainer
var _count_buttons: Array[Button] = []
var _seat_rows: HBoxContainer
## Where a fresh bot comes from, so the difficulty preset decides how sharp it is.
var _bot_factory: Callable = func() -> PlayerSlot: return PlayerSlot.bot("Bot")


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	_build_skeleton()
	if seats.is_empty():
		var starting: Array[PlayerSlot] = [PlayerSlot.human("You"), _bot_factory.call()]
		set_seats(starting)
	else:
		_refresh()


func setup(starting_seats: Array[PlayerSlot], bot_factory: Callable = Callable()) -> void:
	if bot_factory.is_valid():
		_bot_factory = bot_factory
	set_seats(starting_seats)


func set_seats(new_seats: Array[PlayerSlot]) -> void:
	seats = new_seats.duplicate()
	_rename_default_seats()
	if is_node_ready():
		_refresh()


func _build_skeleton() -> void:
	_count_row = HBoxContainer.new()
	_count_row.add_theme_constant_override("separation", 8)
	_count_row.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(_count_row)

	var caption := Label.new()
	caption.text = "Players"
	_count_row.add_child(caption)

	_count_buttons.clear()
	for count in range(GameConfig.MIN_PLAYERS, GameConfig.MAX_PLAYERS + 1):
		var button := Button.new()
		button.text = str(count)
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(32, 0)
		# bind() freezes the count into the callback, so every button knows its own.
		button.pressed.connect(_on_count_pressed.bind(count))
		_count_row.add_child(button)
		_count_buttons.append(button)

	_seat_rows = HBoxContainer.new()
	_seat_rows.add_theme_constant_override("separation", 6)
	add_child(_seat_rows)


func _on_count_pressed(count: int) -> void:
	if count == seats.size():
		_refresh()
		return
	while seats.size() > count:
		seats.pop_back()
	while seats.size() < count:
		seats.append(_bot_factory.call())
	_rename_default_seats()
	_refresh()
	slots_changed.emit(seats)


## Rebuilds every seat row from scratch. Cheaper to reason about than patching
## rows in place: a seat that turns from human into bot changes which controls
## it needs, and hiding a control would still leave a hole in the layout.
func _refresh() -> void:
	for i in _count_buttons.size():
		_count_buttons[i].button_pressed = seats.size() == GameConfig.MIN_PLAYERS + i

	for child in _seat_rows.get_children():
		child.queue_free()

	for i in seats.size():
		_seat_rows.add_child(_build_seat_row(i))


func _build_seat_row(index: int) -> Control:
	var slot := seats[index]

	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var tag := Label.new()
	tag.text = "P%d" % (index + 1)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.custom_minimum_size = Vector2(10, 0)
	row.add_child(tag)

	var kind_picker := OptionButton.new()
	for label in KIND_LABELS:
		kind_picker.add_item(label)
	kind_picker.selected = 1 if slot.is_bot() else 0
	kind_picker.custom_minimum_size = Vector2(32, 0)
	kind_picker.disabled = index == 0 and lock_first_seat
	kind_picker.item_selected.connect(_on_kind_selected.bind(index))
	row.add_child(kind_picker)


	if slot.is_bot() and show_bot_tuning:
		row.add_child(_build_memory_control(index, slot))

	return row


func _build_memory_control(index: int, slot: PlayerSlot) -> Control:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(64, 0)

	var caption := Label.new()
	caption.text = "Memory: %s" % slot.memory_label()
	caption.add_theme_font_size_override("font_size", 13)
	box.add_child(caption)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = slot.bot_memory
	slider.value_changed.connect(_on_memory_changed.bind(index, caption))
	box.add_child(slider)

	return box


func _on_kind_selected(choice: int, index: int) -> void:
	var was_bot := seats[index].is_bot()
	var wants_bot := choice == 1
	if was_bot == wants_bot:
		return

	seats[index] = _bot_factory.call() if wants_bot else PlayerSlot.human("Player")
	_rename_default_seats()
	_refresh()
	slots_changed.emit(seats)


func _on_memory_changed(value: float, index: int, caption: Label) -> void:
	seats[index].bot_memory = value
	caption.text = "Memory: %s" % seats[index].memory_label()
	slots_changed.emit(seats)


## Numbers the seats: "You", "Player 2"... and "Bot", "Bot 2"... Names are not
## editable here, so every seat is renamed whenever the table changes.
func _rename_default_seats() -> void:
	var bots := 0
	var humans := 0
	for i in seats.size():
		var slot := seats[i]
		if slot.is_bot():
			bots += 1
			slot.display_name = "Bot" if bots == 1 else "Bot %d" % bots
		else:
			humans += 1
			slot.display_name = "You" if i == 0 else "Player %d" % humans
