extends Control

## Table setup and difficulty selection.


@export var presets: Array[DifficultyPreset] = []

@onready var _seats_holder: HBoxContainer = %SeatsHolder
@onready var _preset_container: VBoxContainer = %PresetContainer
@onready var _custom_button: Button = %CustomButton
@onready var _back_button: Button = %BackButton

var _seats_editor: PlayerSlotsEditor


func _ready() -> void:
	_custom_button.pressed.connect(_on_custom_pressed)
	_back_button.pressed.connect(_on_back_pressed)

	_build_seats_editor()
	_build_preset_buttons()


func _build_seats_editor() -> void:
	_seats_editor = PlayerSlotsEditor.new()
	# The preset owns bot difficulty on this screen, so no per-bot slider here.
	_seats_editor.show_bot_tuning = false
	_seats_holder.add_child(_seats_editor)

	# Declared typed on its own line: a ternary that can yield a bare []
	# would hand setup() a plain Array and blow up on the typed parameter.
	var starting: Array[PlayerSlot] = []
	if GameSettings.config != null:
		starting = GameSettings.config.players
	if not starting.is_empty():
		_seats_editor.setup(starting)


func _build_preset_buttons() -> void:
	for child in _preset_container.get_children():
		child.queue_free()

	if presets.is_empty():
		presets = _load_presets_from_disk()

	if presets.is_empty():
		var warning := Label.new()
		warning.text = "No difficulties assigned.\nDrag the .tres files from resources/difficulties/\ninto the 'Presets' field in the inspector."
		warning.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_preset_container.add_child(warning)
		return

	for preset in presets:
		var button := Button.new()
		button.text = preset.display_name
		button.custom_minimum_size = Vector2(280, 52)
		button.pressed.connect(_on_preset_pressed.bind(preset))
		_preset_container.add_child(button)

	_preset_container.get_child(0).grab_focus()


func _on_preset_pressed(preset: DifficultyPreset) -> void:
	var config := preset.to_config(_seats_editor.seats)
	if not config.is_valid():
		push_warning("That table cannot be played: " + config.validation_error())
		return
	GameSettings.last_difficulty_id = preset.id
	GameSettings.start_new_game(config)
	SceneSwitcher.go_to(SceneSwitcher.GAME)


func _on_custom_pressed() -> void:
	var base := GameConfig.new()
	base.players = _seats_editor.seats.duplicate()
	GameSettings.config = base
	SceneSwitcher.go_to(SceneSwitcher.CUSTOM_SETUP)


func _on_back_pressed() -> void:
	SceneSwitcher.go_to(SceneSwitcher.MAIN_MENU, false)


func _load_presets_from_disk() -> Array[DifficultyPreset]:
	var found: Array[DifficultyPreset] = []
	var dir := DirAccess.open("res://resources/difficulties")
	if dir == null:
		return found
	for file_name in dir.get_files():
		var clean := file_name.trim_suffix(".remap")
		if not clean.ends_with(".tres"):
			continue
		var preset := load("res://resources/difficulties/%s" % clean) as DifficultyPreset
		if preset != null:
			found.append(preset)
	return found
