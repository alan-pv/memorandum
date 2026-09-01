extends Control

## The waiting room: who is here, the board the host is putting together, the
## chat, and the button that freezes the match and sends it to everybody.
##
## Only the host decides anything. What they choose is broadcast as a `setup`
## payload so the others can see the table they are about to sit at — it is a
## preview and nothing more: the config that actually gets played is the one
## that travels with the deck when the match starts.


const DIFFICULTY_DIR := "res://resources/difficulties"

## The outline of the ready button, and the tag beside your name in the list.
const READY_GREEN := Color(0.24, 0.78, 0.44)

const READY_STATES := ["normal", "hover", "pressed", "focus"]

@onready var _title: Label = %Title
@onready var _code_label: Label = %CodeLabel
@onready var _seat_list: VBoxContainer = %SeatList
@onready var _host_box: VBoxContainer = %HostBox
@onready var _add_bot_button: Button = %AddBotButton
@onready var _remove_bot_button: Button = %RemoveBotButton
@onready var _bot_count_label: Label = %BotCountLabel
@onready var _difficulty_option: OptionButton = %DifficultyOption
@onready var _cards_spin: SpinBox = %CardsSpin
@onready var _group_spin: SpinBox = %GroupSpin
@onready var _chat_holder: VBoxContainer = %ChatHolder
@onready var _summary_label: Label = %SummaryLabel
@onready var _status_label: Label = %StatusLabel
@onready var _leave_button: Button = %LeaveButton
@onready var _ready_button: Button = %ReadyButton
@onready var _start_button: Button = %StartButton

var _presets: Array[DifficultyPreset] = []

## The table as this client understands it. The host fills it from its own
## controls; everybody else from the setup the host sends.
var _bots: int = 0
var _cards: int = 0
var _group: int = 2
var _difficulty_name: String = ""

## True from the moment we hand the match over, so a room update arriving
## during the fade cannot send us anywhere else.
var _leaving: bool = false

## Set while the board controls are being corrected in code, so snapping a
## value does not read as the host having typed it.
var _syncing: bool = false

var _chat: ChatPanel


func _ready() -> void:
	if not Rooms.in_room():
		SceneSwitcher.go_to(SceneSwitcher.ONLINE_MENU, false)
		return

	_fill_difficulties()
	_build_chat()

	_leave_button.pressed.connect(_on_leave_pressed)
	_ready_button.toggled.connect(_on_ready_toggled)
	_start_button.pressed.connect(_on_start_pressed)
	_add_bot_button.pressed.connect(func() -> void: _change_bots(1))
	_remove_bot_button.pressed.connect(func() -> void: _change_bots(-1))
	_difficulty_option.item_selected.connect(_on_difficulty_selected)
	_cards_spin.value_changed.connect(_on_board_changed)
	_group_spin.value_changed.connect(_on_board_changed)

	Rooms.updated.connect(func(_room: Dictionary) -> void: _refresh())
	Rooms.left.connect(_on_room_left)
	Rooms.failed.connect(_on_room_failed)
	Net.payload_received.connect(_on_payload)

	if Rooms.is_host():
		_seed_board(true)
	else:
		# Walking in after a match, nothing about the room has changed, so no
		# update is coming to carry the host's table along with it. Ask.
		Rooms.send({"t": OnlineMatch.T_SETUP, "ask": true})
	_paint_ready_button(false)
	_refresh()


## The chat is two reusable pieces bolted together: a panel that only knows how
## to show lines, and a carrier that only knows how to move them. Neither has
## ever heard of a memory game, so both go to the next project as they are.
func _build_chat() -> void:
	_chat = ChatPanel.new()
	_chat.title = "Chat"
	_chat.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_chat_holder.add_child(_chat)

	var carrier := RoomChat.new()
	add_child(carrier)
	carrier.attach(_chat)
	_chat.push_system("You are in room %s." % str(Rooms.current.get("id", "—")))


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
# The board the host is building
#
# The difficulty seeds the numbers; from there they are the host's to change.
# The pair is only legal when the cards divide into whole groups and there are
# at least as many groups as players, so instead of letting the host build
# something invalid and then complaining, the controls snap to the nearest
# board that works.
# ---------------------------------------------------------------------------

## The difficulty seeds the board — except right after a match, where the table
## that was just played is the one most likely to be played again.
func _seed_board(after_a_match: bool = false) -> void:
	var preset := _selected_preset()
	var cards := preset.total_cards
	var group := preset.group_size
	if after_a_match and not GameSettings.last_online_board.is_empty():
		cards = int(GameSettings.last_online_board.get("cards", cards))
		group = int(GameSettings.last_online_board.get("group", group))
	# Read once: a room created later starts from its difficulty again.
	GameSettings.last_online_board = {}

	_syncing = true
	_group_spin.value = group
	_cards_spin.value = cards
	_syncing = false
	_snap_board()


func _on_difficulty_selected(_index: int) -> void:
	_seed_board()
	_refresh()


func _on_board_changed(_value: float) -> void:
	if _syncing:
		return
	_snap_board()
	_refresh()


func _snap_board() -> void:
	var group := clampi(int(_group_spin.value), 2, 5)
	var seats := maxi(_seat_count(), NetProtocol.MIN_PLAYERS)
	# Every player must be able to take a group, and one group is not a game.
	var lowest := group * maxi(seats, 2)
	var highest := 96 - (96 % group)
	var total := int(_cards_spin.value)
	total -= total % group

	_syncing = true
	_group_spin.value = group
	_cards_spin.step = group
	_cards_spin.min_value = lowest
	_cards_spin.max_value = highest
	_cards_spin.value = clampi(total, lowest, highest)
	_syncing = false

	_group = group
	_cards = int(_cards_spin.value)


func _seat_count() -> int:
	return mini(Rooms.members().size() + _bots, GameConfig.MAX_PLAYERS)


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

	if host:
		# Bots only fill the seats people did not take.
		_bots = clampi(_bots, 0, GameConfig.MAX_PLAYERS - members.size())
		_difficulty_name = _selected_preset().display_name
		_snap_board()

	_rebuild_seat_list(members)

	_host_box.visible = host
	_ready_button.visible = not host
	_start_button.visible = host
	_bot_count_label.text = str(_bots)
	_add_bot_button.disabled = members.size() + _bots >= GameConfig.MAX_PLAYERS
	_remove_bot_button.disabled = _bots <= 0

	if not host:
		_summary_label.text = _summary_text(members.size())
		_say("")
		return

	_broadcast_setup()

	var config := _build_config()
	var error := config.validation_error()
	var enough := members.size() >= NetProtocol.MIN_PLAYERS
	var everyone_ready := Rooms.everyone_ready()

	_summary_label.text = _summary_text(members.size()) if error.is_empty() else "—"
	_start_button.disabled = not error.is_empty() or not everyone_ready

	if not error.is_empty():
		_say(error)
	elif not enough:
		_say("Waiting for another player to join.")
	elif not everyone_ready:
		_say("Waiting for everyone to be ready.")
	else:
		_say("")


## The same sentence on every screen, so what the host is building is never a
## surprise to the people about to play it.
func _summary_text(people: int) -> String:
	if _cards <= 0 or _group <= 0:
		return "Waiting for the host to choose a board."
	var line := "%d cards · %d groups of %d · %d players" % [
		_cards, _cards / _group, _group, people + _bots
	]
	if not _difficulty_name.is_empty():
		line = "%s · %s" % [_difficulty_name, line]
	return line


func _rebuild_seat_list(members: Array) -> void:
	for child in _seat_list.get_children():
		child.queue_free()

	var host := Rooms.is_host()
	for member in members:
		var id := int(member.get("id", 0))
		var is_me := id == Net.my_peer_id
		var row := _build_seat_row(
			str(member.get("name", "Player")),
			"Host" if member.get("host", false) else ("Ready" if member.get("ready", false) else "Waiting"),
			is_me,
			READY_GREEN if member.get("ready", false) else Color("#b2b2b278")
		)
		# Only the host can throw anybody out, and never themselves.
		if host and not is_me:
			row.add_child(_build_kick_button(id, str(member.get("name", "Player"))))
		_seat_list.add_child(row)

	for i in _bots:
		_seat_list.add_child(_build_seat_row(
			"Bot %d" % (i + 1), _difficulty_name, false, Color("#b2b2b278")
		))


func _build_seat_row(seat_name: String, tag: String, is_me: bool, tag_color: Color) -> HBoxContainer:
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
	state.add_theme_color_override("font_color", tag_color)
	row.add_child(state)

	return row


func _build_kick_button(peer_id: int, seat_name: String) -> Button:
	var button := Button.new()
	button.text = "Kick"
	button.tooltip_text = "Remove %s from the room" % seat_name
	button.add_theme_font_size_override("font_size", 14)
	button.pressed.connect(func() -> void: Rooms.kick(peer_id))
	return button


## Green while you are ready. The label is always the thing pressing it does,
## so "Ready" means "get ready" and it turns into "Not ready" once you are.
func _paint_ready_button(is_ready: bool) -> void:
	_ready_button.text = "Not ready" if is_ready else "Ready"

	for state in READY_STATES:
		if not is_ready:
			_ready_button.remove_theme_stylebox_override(state)
			continue
		var box := _ready_button.get_theme_stylebox(state).duplicate() as StyleBoxFlat
		if box == null:
			continue
		box.border_color = READY_GREEN
		_ready_button.add_theme_stylebox_override(state, box)

	if is_ready:
		_ready_button.add_theme_color_override("font_pressed_color", READY_GREEN)
		_ready_button.add_theme_color_override("font_hover_pressed_color", READY_GREEN)
	else:
		_ready_button.remove_theme_color_override("font_pressed_color")
		_ready_button.remove_theme_color_override("font_hover_pressed_color")


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
	# The preset only seeded the board: what gets played is what the host left
	# in the controls.
	config.group_size = _group
	config.total_cards = _cards
	# to_config() rebuilds the bot seats from the preset, which loses the peer
	# they belong to. The order is untouched, so stamp them back on.
	for i in config.players.size():
		config.players[i].peer_id = seats[i].peer_id
	config.online = true
	return config


## Host -> everyone: the table as it stands. Sent on every change and on every
## room update, so somebody who just walked in sees it without having to ask.
func _broadcast_setup() -> void:
	Rooms.send({
		"t": OnlineMatch.T_SETUP,
		"cards": _cards,
		"group": _group,
		"bots": _bots,
		"difficulty": _difficulty_name,
	})


func _change_bots(delta: int) -> void:
	_bots = clampi(_bots + delta, 0, GameConfig.MAX_PLAYERS - Rooms.members().size())
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


func _on_payload(from_id: int, payload: Dictionary) -> void:
	if _leaving:
		return
	var kind := str(payload.get("t", ""))
	var asking := bool(payload.get("ask", false))

	# The one thing the host listens for: somebody arriving and asking what is
	# on the table. Everything else in the lobby travels host -> everyone.
	if Rooms.is_host():
		if kind == OnlineMatch.T_SETUP and asking:
			_broadcast_setup()
		return

	if from_id != Rooms.host_id() or asking:
		return

	match kind:
		OnlineMatch.T_SETUP:
			_cards = maxi(int(payload.get("cards", 0)), 0)
			_group = maxi(int(payload.get("group", 2)), 2)
			_bots = clampi(int(payload.get("bots", 0)), 0, GameConfig.MAX_PLAYERS)
			_difficulty_name = str(payload.get("difficulty", ""))
			_refresh()
		OnlineMatch.T_START:
			if not OnlineMatch.accept_start(payload):
				_say("The host started a match this build cannot play.")
				return
			_leaving = true
			SceneSwitcher.go_to(SceneSwitcher.GAME, false)


func _on_ready_toggled(value: bool) -> void:
	_paint_ready_button(value)
	Rooms.set_ready(value)


func _on_leave_pressed() -> void:
	_leaving = true
	Rooms.leave()
	SceneSwitcher.go_to(SceneSwitcher.ONLINE_MENU, false)


## Being thrown out arrives here exactly like the room closing: the reason is
## the only difference, and the online menu shows it.
func _on_room_left(_reason: String) -> void:
	if _leaving:
		return
	_leaving = true
	SceneSwitcher.go_to(SceneSwitcher.ONLINE_MENU, false)


func _on_room_failed(_code: String, message: String) -> void:
	_say(message)
