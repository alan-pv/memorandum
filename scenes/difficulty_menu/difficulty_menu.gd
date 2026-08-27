extends Control

## Opponent and difficulty selection.


@export var presets: Array[DifficultyPreset] = []

@onready var _preset_container: VBoxContainer = %PresetContainer
@onready var _vs_bot_button: Button = %VsBotButton
@onready var _vs_human_button: Button = %VsHumanButton
@onready var _custom_button: Button = %CustomButton
@onready var _back_button: Button = %BackButton

var _opponent: GameConfig.Opponent = GameConfig.Opponent.BOT


func _ready() -> void:
	_vs_bot_button.pressed.connect(_select_opponent.bind(GameConfig.Opponent.BOT))
	_vs_human_button.pressed.connect(_select_opponent.bind(GameConfig.Opponent.HUMAN))
	_vs_human_button.pressed.connect(_on_custom_pressed)
	_custom_button.pressed.connect(_on_custom_pressed)
	_back_button.pressed.connect(_on_back_pressed)

	_select_opponent(GameConfig.Opponent.BOT)
	_build_preset_buttons()


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


func _select_opponent(value: GameConfig.Opponent) -> void:
	_opponent = value
	_vs_bot_button.button_pressed = value == GameConfig.Opponent.BOT
	_vs_human_button.button_pressed = value == GameConfig.Opponent.HUMAN


func _on_preset_pressed(preset: DifficultyPreset) -> void:
	GameSettings.last_difficulty_id = preset.id
	GameSettings.save_preferences()
	GameSettings.start_new_game(preset.to_config(_opponent))
	SceneSwitcher.go_to(SceneSwitcher.GAME)


func _on_custom_pressed() -> void:
	var base := GameConfig.new()
	base.opponent = _opponent
	if _opponent == GameConfig.Opponent.HUMAN:
		base.player_names = PackedStringArray(["Player 1", "Player 2"])
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
