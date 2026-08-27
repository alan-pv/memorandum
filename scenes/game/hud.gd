class_name HUD
extends Control

## Scoreboard, turn, groups left and timer.


signal pause_pressed

@onready var _score_container: HBoxContainer = %ScoreContainer
@onready var _remaining_label: Label = %RemainingLabel
@onready var _timer_label: Label = %TimerLabel
@onready var _message_label: Label = %MessageLabel
@onready var _pause_button: Button = %PauseButton

const SCORE_ENTRY_SCENE := preload("res://scenes/game/player_score_entry.tscn")

var _entries: Array[PlayerScoreEntry] = []
var _config: GameConfig


func _ready() -> void:
	_pause_button.pressed.connect(func() -> void: pause_pressed.emit())
	_message_label.text = ""


func setup(config: GameConfig) -> void:
	_config = config
	for entry in _entries:
		entry.queue_free()
	_entries.clear()
	for i in config.player_names.size():
		var entry := SCORE_ENTRY_SCENE.instantiate() as PlayerScoreEntry
		_score_container.add_child(entry)
		entry.setup(config.player_names[i], 0)
		entry.set_active(i == 0, false)
		_entries.append(entry)


func set_score(player_index: int, score: int) -> void:
	if player_index < 0 or player_index >= _entries.size():
		return
	_entries[player_index].set_score(score)


func set_turn(player_index: int) -> void:
	for i in _entries.size():
		_entries[i].set_active(i == player_index)


func set_remaining(groups_left: int) -> void:
	_remaining_label.text = "Groups left: %d" % groups_left


func set_time(seconds: float) -> void:
	var minutes := int(seconds) / 60
	var secs := int(seconds) % 60
	_timer_label.text = "%02d:%02d" % [minutes, secs]


func show_message(text: String, duration: float = 1.2) -> void:
	_message_label.text = text
	_message_label.modulate.a = 1.0
	if duration <= 0.0:
		return
	var tween := create_tween()
	tween.tween_interval(duration)
	tween.tween_property(_message_label, "modulate:a", 0.0, 0.3)
