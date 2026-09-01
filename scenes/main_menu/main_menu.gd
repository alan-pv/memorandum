extends Control

## Title screen.


@onready var _play_button: Button = %PlayButton
@onready var _online_button: Button = %OnlineButton
@onready var _how_to_button: Button = %HowToButton
@onready var _audio_button: Button = %AudioButton
@onready var _quit_button: Button = %QuitButton
@onready var _help_panel: Control = %HelpPanel
@onready var _close_help_button: Button = %CloseHelpButton

var _audio_panel: AudioSettings


func _ready() -> void:
	_play_button.pressed.connect(_on_play_pressed)
	_online_button.pressed.connect(_on_online_pressed)
	_how_to_button.pressed.connect(func() -> void: _set_help_visible(true))
	_close_help_button.pressed.connect(func() -> void: _set_help_visible(false))
	_quit_button.pressed.connect(_on_quit_pressed)
	_audio_button.pressed.connect(_on_audio_pressed)

	_build_audio_panel()
	_help_panel.visible = false
	_play_button.grab_focus()
	SceneSwitcher.clear_history()


## The same overlay the pause menu uses. It is built here rather than dropped
## into the scene so that reusing it anywhere else is two lines and no .tscn.
func _build_audio_panel() -> void:
	_audio_panel = AudioSettings.new()
	_audio_panel.closed.connect(func() -> void: _audio_button.grab_focus())
	add_child(_audio_panel)


func _on_audio_pressed() -> void:
	_audio_panel.open()


func _intro_config() -> Dictionary:
	return {"labels": false, "buttons": true, "panels": false}


func _on_play_pressed() -> void:
	SceneSwitcher.go_to(SceneSwitcher.DIFFICULTY_MENU)


func _on_online_pressed() -> void:
	SceneSwitcher.go_to(SceneSwitcher.ONLINE_MENU)


func _on_quit_pressed() -> void:
	SceneSwitcher.quit_game()


func _set_help_visible(value: bool) -> void:
	_help_panel.visible = value
	if value:
		_close_help_button.grab_focus()
	else:
		_play_button.grab_focus()
