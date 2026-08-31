extends Control

## The waiting room: who is here, which bots the host added, and the button
## that freezes the match and sends it to everybody.


const DIFFICULTY_DIR := "res://resources/difficulties"

@onready var _title: Label = %Title
@onready var _code_label: Label = %CodeLabel
@onready var _seat_list: VBoxContainer = %SeatList
@onready var _host_box: VBoxContainer = %HostBox
@onready var _add_bot_button: Button = %AddBotButton
@onready var _remove_bot_button: Button = %RemoveBotButton
@onready var _bot_count_label: Label = %BotCountLabel
@onready var _difficulty_option: OptionButton = %DifficultyOption
@onready var _summary_label: Label = %SummaryLabel
@onready var _status_label: Label = %StatusLabel
@onready var _leave_button: Button = %LeaveButton
@onready var _ready_button: Button = %ReadyButton
@onready var _start_button: Button = %StartButton

var _presets: Array[DifficultyPreset] = []
var _bots: int = 0
## True from the moment we hand the match over, so a room update arriving
## during the fade cannot send us anywhere else.
var _leaving: bool = false


func _ready() -> void:
	if not Rooms.in_room():
		SceneSwitcher.go_to(SceneSwitcher.ONLINE_MENU, false)
		return

	_fill_difficulties()

	_leave_button.pressed.connect(_on_leave_pressed)
	_ready_button.toggled.connect(_on_ready_toggled)
	_start_button.pressed.connect(_on_start_pressed)
	_add_bot_button.pressed.connect(func() -> void: _change_bots(1))
	_remove_bot_button.pressed.connect(func() -> void: _change_bots(-1))
	_difficulty_option.item_selected.connect(func(_i: int) -> void: _refresh())

	Rooms.updated.connect(func(_room: Dictionary) -> void: _refresh())
	Rooms.left.connect(_on_room_left)
	Rooms.failed.connect(_on_room_failed)
	Net.payload_received.connect(_on_payload)

	_refresh()


func _fill_difficulties() -> void:
	_presets = _load_presets()
	_difficulty_option.clear()
	for preset in _presets:
		_difficulty_option.add_item(preset.display_name)
	if _presets.is_empty():
		return
	# Start on whichever difficulty this device last played.
	for i in _presets.size():
		if _presets[i].id == GameSettings.last_difficulty_id:
			_difficulty_option.selected = i
			return
	_difficulty_option.selected = 0


func _load_presets() -> Array[DifficultyPreset]:
	var found: Array[DifficultyPreset] = []
	var dir := DirAccess.open(DIFFICULTY_DIR)
	if dir == null:
		return found
	for file_name in dir.get_files():
		var clean := file_name.trim_suffix(".remap")
		if not clean.ends_with(".tres"):
			continue
		var preset := load("%s/%s" % [DIFFICULTY_DIR, clean]) as DifficultyPreset
		if preset != null:
			found.append(preset)
	return found


func _selected_preset() -> DifficultyPreset:
	if _presets.is_empty():
		return DifficultyPreset.new()
	return _presets[clampi(_difficulty_option.selected, 0, _presets.size() - 1)]


# ---------------------------------------------------------------------------
# View
# ---------------------------------------------------------------------------

func _refresh() -> void:
	if _leaving or not Rooms.in_room():
		return

	var room := Rooms.current
	var members: Array = room.get("members", [])
	var host := Rooms.is_host()

	_title.text = str(room.get("title", "Room"))
	_code_label.text = "Code %s · up to %d players" % [
		str(room.get("id", "—")), int(room.get("max_players", NetProtocol.MAX_PLAYERS))
	]

	# Bots only fill the seats people did not take.
	_bots = clampi(_bots, 0, GameConfig.MAX_PLAYERS - members.size())

	_rebuild_seat_list(members)

	_host_box.visible = host
	_ready_button.visible = not host
	_start_button.visible = host
	_bot_count_label.text = str(_bots)
	_add_bot_button.disabled = members.size() + _bots >= GameConfig.MAX_PLAYERS
	_remove_bot_button.disabled = _bots <= 0

	if not host:
		_ready_button.text = "Ready" if _ready_button.button_pressed else "Not ready"
		_summary_label.text = "Waiting for the host to start."
		_say("")
		return

	var config := _build_config()
	var error := config.validation_error()
	var enough := members.size() >= NetProtocol.MIN_PLAYERS
	var everyone_ready := Rooms.everyone_ready()

	if error.is_empty():
		_summary_label.text = "%d cards · %d groups of %d · %d players" % [
			config.total_cards, config.group_count(), config.group_size, config.player_count()
		]
	else:
		_summary_label.text = "—"

	_start_button.disabled = not error.is_empty() or not everyone_ready

	if not error.is_empty():
		_say(error)
	elif not enough:
		_say("Waiting for another player to join.")
	elif not everyone_ready:
		_say("Waiting for everyone to be ready.")
	else:
		_say("")


func _rebuild_seat_list(members: Array) -> void:
	for child in _seat_list.get_children():
		child.queue_free()

	for member in members:
		_seat_list.add_child(_build_seat_row(
			str(member.get("name", "Player")),
			"Host" if member.get("host", false) else ("Ready" if member.get("ready", false) else "Waiting"),
			int(member.get("id", 0)) == Net.my_peer_id
		))

	var preset := _selected_preset()
	for i in _bots:
		_seat_list.add_child(_build_seat_row("Bot %d" % (i + 1), preset.display_name, false))


func _build_seat_row(seat_name: String, tag: String, is_me: bool) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var label := Label.new()
	label.text = "%s%s" % [seat_name, " (you)" if is_me else ""]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(label)

	var state := Label.new()
	state.text = tag
	state.add_theme_font_size_override("font_size", 14)
	state.add_theme_color_override("font_color", Color("#b2b2b278"))
	row.add_child(state)

	return row


func _say(text: String) -> void:
	_status_label.text = text


# ---------------------------------------------------------------------------
# The match
# ---------------------------------------------------------------------------

## Builds the match from the room: the people in join order first, the host's
## bots after them. Every seat carries the peer that owns it, which is what
## lets the referee tell a legal pick from somebody playing out of turn.
func _build_config() -> GameConfig:
	var preset := _selected_preset()

	var seats: Array[PlayerSlot] = []
	for member in Rooms.current.get("members", []):
		var seat := PlayerSlot.human(str(member.get("name", "Player")))
		seat.peer_id = int(member.get("id", 0))
		seats.append(seat)
	for i in _bots:
		var bot := preset.make_bot_slot("Bot %d" % (i + 1))
		bot.peer_id = Net.my_peer_id
		seats.append(bot)

	var config := preset.to_config(seats)
	# to_config() rebuilds the bot seats from the preset, which loses the peer
	# they belong to. The order is untouched, so stamp them back on.
	for i in config.players.size():
		config.players[i].peer_id = seats[i].peer_id
	config.online = true
	return config


func _change_bots(delta: int) -> void:
	_bots = clampi(_bots + delta, 0, GameConfig.MAX_PLAYERS - Rooms.current.get("members", []).size())
	_refresh()


func _on_start_pressed() -> void:
	if not Rooms.is_host():
		return
	var config := _build_config()
	if not config.is_valid():
		_say(config.validation_error())
		return

	_leaving = true
	GameSettings.last_difficulty_id = _selected_preset().id
	# The payload first, so it is on its way before the room closes to newcomers.
	OnlineMatch.broadcast_start(config)
	Rooms.start_match()
	SceneSwitcher.go_to(SceneSwitcher.GAME, false)


func _on_payload(_from_id: int, payload: Dictionary) -> void:
	if _leaving or Rooms.is_host():
		return
	if str(payload.get("t", "")) != OnlineMatch.T_START:
		return
	if not OnlineMatch.accept_start(payload):
		_say("The host started a match this build cannot play.")
		return
	_leaving = true
	SceneSwitcher.go_to(SceneSwitcher.GAME, false)


func _on_ready_toggled(value: bool) -> void:
	_ready_button.text = "Ready" if value else "Not ready"
	Rooms.set_ready(value)


func _on_leave_pressed() -> void:
	_leaving = true
	Rooms.leave()
	SceneSwitcher.go_to(SceneSwitcher.ONLINE_MENU, false)


func _on_room_left(_reason: String) -> void:
	if _leaving:
		return
	_leaving = true
	SceneSwitcher.go_to(SceneSwitcher.ONLINE_MENU, false)


func _on_room_failed(_code: String, message: String) -> void:
	_say(message)
