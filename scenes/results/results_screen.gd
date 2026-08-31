extends Control

## Final result of the match.


@onready var _title_label: Label = %TitleLabel
@onready var _scores_container: VBoxContainer = %ScoresContainer
@onready var _stats_label: Label = %StatsLabel
@onready var _record_label: Label = %RecordLabel
@onready var _again_button: Button = %AgainButton
@onready var _change_button: Button = %ChangeButton
@onready var _menu_button: Button = %MenuButton


var _was_online: bool = false


func _ready() -> void:
	_was_online = GameSettings.config != null and GameSettings.config.online

	_again_button.pressed.connect(_on_again_pressed)
	_change_button.pressed.connect(_on_change_pressed)
	_menu_button.pressed.connect(_on_menu_pressed)

	_show_result(GameSettings.last_result)

	# "Again" would start a local match with the seats of an online one, and the
	# rest of the table is not here to be asked. Online you go back through the
	# lobby, leaving the room you just played in behind on the way.
	_again_button.visible = not _was_online
	if _was_online:
		_change_button.text = "Back to the lobby"
		_change_button.grab_focus()
	else:
		_again_button.grab_focus()


func _show_result(result: Dictionary) -> void:
	if result.is_empty():
		_title_label.text = "No results"
		_stats_label.text = ""
		_record_label.text = ""
		return

	var names: PackedStringArray = result.get("names", PackedStringArray())
	var scores: Array = result.get("scores", [])
	var winner: int = result.get("winner", -1)

	if winner < 0:
		_title_label.text = "It's a draw!"
	elif winner < names.size():
		_title_label.text = "%s wins!" % names[winner]

	for child in _scores_container.get_children():
		child.queue_free()

	for i in scores.size():
		var line := Label.new()
		var player_name: String = names[i] if i < names.size() else "Player %d" % (i + 1)
		line.text = "%s — %d groups" % [player_name, scores[i]]
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if i == winner:
			line.add_theme_color_override("font_color", Color("b2b2b2ff"))
		else:
			line.add_theme_color_override("font_color", Color("#b2b2b278"))
		_scores_container.add_child(line)

	var turns: int = result.get("turns", 0)
	var seconds: float = result.get("seconds", 0.0)
	_stats_label.text = "%d turns · %02d:%02d" % [turns, int(seconds) / 60, int(seconds) % 60]

	# Seat 0 is only "you" offline: online it is whoever created the room.
	var is_record := not _was_online and winner == 0 and GameSettings.try_save_record(
		GameSettings.last_difficulty_id, turns, seconds
	)
	_record_label.visible = is_record
	_record_label.text = "New record!"


func _on_again_pressed() -> void:
	SceneSwitcher.go_to(SceneSwitcher.GAME, false)


func _on_change_pressed() -> void:
	if _was_online:
		Rooms.leave()
		SceneSwitcher.go_to(SceneSwitcher.ONLINE_MENU, false)
		return
	SceneSwitcher.go_to(SceneSwitcher.DIFFICULTY_MENU, false)


func _on_menu_pressed() -> void:
	if _was_online:
		Rooms.leave()
		Net.disconnect_from_server()
	SceneSwitcher.go_to(SceneSwitcher.MAIN_MENU, false)
