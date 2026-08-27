class_name PauseMenu
extends Control

## Pause menu layered over the match.


signal resume_requested
signal restart_requested
signal quit_requested

@onready var _resume_button: Button = %ResumeButton
@onready var _restart_button: Button = %RestartButton
@onready var _quit_button: Button = %QuitButton


func _ready() -> void:
	# Without this the buttons stop responding while the tree is paused.
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	visible = false
	_resume_button.pressed.connect(func() -> void: resume_requested.emit())
	_restart_button.pressed.connect(func() -> void: restart_requested.emit())
	_quit_button.pressed.connect(func() -> void: quit_requested.emit())


func open() -> void:
	visible = true
	get_tree().paused = true
	_resume_button.grab_focus()
	modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.15)


func close() -> void:
	get_tree().paused = false
	visible = false
