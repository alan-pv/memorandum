extends Control

## Manual match configuration.


@onready var _group_size_spin: SpinBox = %GroupSizeSpin
@onready var _total_cards_spin: SpinBox = %TotalCardsSpin
@onready var _summary_label: Label = %SummaryLabel
@onready var _error_label: Label = %ErrorLabel
@onready var _bot_memory_slider: HSlider = %BotMemorySlider
@onready var _bot_memory_label: Label = %BotMemoryLabel
@onready var _start_button: Button = %StartButton
@onready var _fix_button: Button = %FixButton
@onready var _back_button: Button = %BackButton

var config: GameConfig


func _ready() -> void:
	config = GameSettings.config if GameSettings.config != null else GameConfig.new()

	_group_size_spin.value = config.group_size
	_total_cards_spin.value = config.total_cards
	_bot_memory_slider.value = config.bot_memory
	_bot_memory_slider.visible = config.opponent == GameConfig.Opponent.BOT
	_bot_memory_label.visible = _bot_memory_slider.visible

	_group_size_spin.value_changed.connect(_on_value_changed)
	_total_cards_spin.value_changed.connect(_on_value_changed)
	_bot_memory_slider.value_changed.connect(_on_value_changed)
	_start_button.pressed.connect(_on_start_pressed)
	_fix_button.pressed.connect(_on_fix_pressed)
	_back_button.pressed.connect(_on_back_pressed)

	_refresh()


func _on_value_changed(_v: float) -> void:
	_refresh()


func _refresh() -> void:
	config.group_size = int(_group_size_spin.value)
	config.total_cards = int(_total_cards_spin.value)
	config.bot_memory = _bot_memory_slider.value

	_bot_memory_label.text = "Bot memory: %d%%" % roundi(config.bot_memory * 100.0)

	var error := config.validation_error()
	var valid := config.is_valid()

	_error_label.text = error
	_error_label.visible = not error.is_empty()
	_fix_button.visible = not valid
	_start_button.disabled = not valid

	if valid:
		_summary_label.text = "%d cards · %d groups of %d matching" % [
			config.total_cards, config.group_count(), config.group_size
		]
	else:
		_summary_label.text = "—"


func _on_fix_pressed() -> void:
	var group_size := maxi(2, int(_group_size_spin.value))
	var total := int(_total_cards_spin.value)
	var lower := total - (total % group_size)
	var upper := lower + group_size
	var fixed := upper if (total - lower) > (upper - total) else lower
	if fixed < group_size * 2:
		fixed = group_size * 2
	_total_cards_spin.value = fixed
	_refresh()


func _on_start_pressed() -> void:
	if not config.is_valid():
		return
	GameSettings.last_difficulty_id = &"custom"
	GameSettings.start_new_game(config)
	SceneSwitcher.go_to(SceneSwitcher.GAME)


func _on_back_pressed() -> void:
	SceneSwitcher.go_to(SceneSwitcher.DIFFICULTY_MENU, false)
