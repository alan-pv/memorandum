extends Node

## Switches screens with a fade to black.


const MAIN_MENU := "res://scenes/main_menu/main_menu.tscn"
const DIFFICULTY_MENU := "res://scenes/difficulty_menu/difficulty_menu.tscn"
const CUSTOM_SETUP := "res://scenes/custom_setup/custom_setup.tscn"
const GAME := "res://scenes/game/game.tscn"
const RESULTS := "res://scenes/results/results_screen.tscn"

const FADE_TIME := 0.22

signal transition_started(target_path: String)
signal transition_finished(target_path: String)

var _fade_layer: CanvasLayer
var _fade_rect: ColorRect
var _is_switching: bool = false
var _history: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_fade_overlay()


func _build_fade_overlay() -> void:
	_fade_layer = CanvasLayer.new()
	_fade_layer.layer = 128
	add_child(_fade_layer)

	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0, 0, 0, 1)
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	# IGNORE, or the fade rect swallows every click in the game.
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.modulate.a = 0.0
	_fade_layer.add_child(_fade_rect)


func go_to(scene_path: String, record_history: bool = true) -> void:
	if _is_switching:
		return
	_is_switching = true
	transition_started.emit(scene_path)

	if record_history:
		var current := get_tree().current_scene
		if current != null and current.scene_file_path != "":
			_history.append(current.scene_file_path)

	await _fade(1.0)
	var error := get_tree().change_scene_to_file(scene_path)
	if error != OK:
		push_error("Could not load scene: %s (error %d)" % [scene_path, error])
	await get_tree().process_frame
	await _fade(0.0)

	_is_switching = false
	transition_finished.emit(scene_path)


func go_back() -> void:
	if _history.is_empty():
		go_to(MAIN_MENU, false)
		return
	var previous: String = _history.pop_back()
	go_to(previous, false)


func clear_history() -> void:
	_history.clear()


func quit_game() -> void:
	await _fade(1.0)
	get_tree().quit()


func _fade(target_alpha: float) -> void:
	var tween := create_tween()
	tween.tween_property(_fade_rect, "modulate:a", target_alpha, FADE_TIME)
	await tween.finished
