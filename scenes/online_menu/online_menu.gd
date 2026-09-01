extends Control

## Two steps in one screen: first your name and the connection, then the rooms.
## The list only exists once you are online, so it is never shown empty and
## unexplained: until the relay answers, the name step is all there is.


const REFRESH_SECONDS := 3.0

@onready var _connect_step: VBoxContainer = %ConnectStep
@onready var _rooms_step: VBoxContainer = %RoomsStep
@onready var _name_field: LineEdit = %NameField
@onready var _connect_button: Button = %ConnectButton
@onready var _status_label: Label = %StatusLabel
@onready var _identity_label: Label = %IdentityLabel
@onready var _change_name_button: Button = %ChangeNameButton
@onready var _refresh_button: Button = %RefreshButton
@onready var _room_list: VBoxContainer = %RoomList
@onready var _join_panel: PanelContainer = %JoinPanel
@onready var _join_label: Label = %JoinLabel
@onready var _join_password_field: LineEdit = %JoinPasswordField
@onready var _join_confirm_button: Button = %JoinConfirmButton
@onready var _join_cancel_button: Button = %JoinCancelButton
@onready var _room_name_field: LineEdit = %RoomNameField
@onready var _room_password_field: LineEdit = %RoomPasswordField
@onready var _max_players_option: OptionButton = %MaxPlayersOption
@onready var _create_button: Button = %CreateButton
@onready var _back_button: Button = %BackButton

var _rooms: Array = []
var _pending_room_id: String = ""
var _refresh_timer: Timer


func _ready() -> void:
	_name_field.text = GameSettings.player_name

	_fill_max_players()
	_build_refresh_timer()

	_connect_button.pressed.connect(_on_connect_pressed)
	_name_field.text_submitted.connect(func(_t: String) -> void: _on_connect_pressed())
	_change_name_button.pressed.connect(_on_change_name_pressed)
	_refresh_button.pressed.connect(func() -> void: Rooms.refresh())
	_create_button.pressed.connect(_on_create_pressed)
	_back_button.pressed.connect(_on_back_pressed)
	_join_confirm_button.pressed.connect(_on_join_confirmed)
	_join_cancel_button.pressed.connect(func() -> void: _close_join_panel())
	_join_password_field.text_submitted.connect(func(_t: String) -> void: _on_join_confirmed())

	Net.state_changed.connect(_on_net_state_changed)
	Net.connection_failed.connect(_on_connection_failed)
	Rooms.list_updated.connect(_on_list_updated)
	Rooms.joined.connect(_on_joined)
	Rooms.failed.connect(_on_room_failed)

	_close_join_panel()
	# Whatever ended the last room — the host leaving, or being thrown out of it
	# — happened on a screen that is already gone. This is where it gets said.
	_say(Rooms.last_left_reason)
	Rooms.last_left_reason = ""
	_refresh_view()

	# Coming back from a room leaves the connection open: pick the list up again.
	if Net.is_online():
		Rooms.refresh()
	else:
		_name_field.grab_focus()


func _fill_max_players() -> void:
	_max_players_option.clear()
	for count in range(NetProtocol.MIN_PLAYERS, NetProtocol.MAX_PLAYERS + 1):
		_max_players_option.add_item("%d players" % count)
	_max_players_option.selected = _max_players_option.item_count - 1


func _build_refresh_timer() -> void:
	_refresh_timer = Timer.new()
	_refresh_timer.wait_time = REFRESH_SECONDS
	_refresh_timer.timeout.connect(func() -> void: Rooms.refresh())
	add_child(_refresh_timer)


# ---------------------------------------------------------------------------
# Connecting
# ---------------------------------------------------------------------------

func _on_connect_pressed() -> void:
	if Net.is_online():
		return
	GameSettings.player_name = _clean_name()
	_name_field.text = GameSettings.player_name

	var settings := NetSettings.new()
	_say("Connecting to %s..." % settings.url)
	Net.connect_to_server(settings, GameSettings.player_name)
	_refresh_view()


## Back to the name step. The relay ties the name to the connection, so
## changing it means dropping and greeting it again.
func _on_change_name_pressed() -> void:
	Net.disconnect_from_server()
	_name_field.grab_focus()


func _clean_name() -> String:
	var typed := _name_field.text.strip_edges()
	return typed.substr(0, NetProtocol.MAX_NAME_LENGTH) if not typed.is_empty() else "Player"


func _on_net_state_changed(_state: int) -> void:
	if Net.is_online():
		_say("Connected.")
		_room_name_field.placeholder_text = "%s's room" % GameSettings.player_name
		Rooms.refresh()
	elif Net.state == Net.State.OFFLINE:
		_rooms = []
		_say("Not connected.")
	_refresh_view()


func _on_connection_failed(reason: String) -> void:
	_say(reason)
	_refresh_view()


# ---------------------------------------------------------------------------
# The list
# ---------------------------------------------------------------------------

func _on_list_updated(rooms: Array) -> void:
	_rooms = rooms
	_rebuild_room_list()


func _rebuild_room_list() -> void:
	for child in _room_list.get_children():
		child.queue_free()

	if not Net.is_online():
		return

	if _rooms.is_empty():
		var empty := Label.new()
		empty.text = "No rooms yet. Create one."
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_theme_color_override("font_color", Color("#b2b2b278"))
		_room_list.add_child(empty)
		return

	for room in _rooms:
		_room_list.add_child(_build_room_row(room))


func _build_room_row(room: Dictionary) -> Control:
	var players: int = int(room.get("players", 0))
	var max_players: int = int(room.get("max_players", NetProtocol.MAX_PLAYERS))
	var locked: bool = room.get("locked", false)
	var running: bool = room.get("in_progress", false)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var title := Label.new()
	title.text = str(room.get("title", "Room"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(title)

	var lock := Label.new()
	lock.text = "locked" if locked else ""
	lock.custom_minimum_size = Vector2(56, 0)
	lock.add_theme_font_size_override("font_size", 13)
	lock.add_theme_color_override("font_color", Color("#b2b2b278"))
	row.add_child(lock)

	var host := Label.new()
	host.text = str(room.get("host", "?"))
	host.add_theme_color_override("font_color", Color("#b2b2b278"))
	host.custom_minimum_size = Vector2(120, 0)
	host.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(host)

	var count := Label.new()
	count.text = "%d/%d" % [players, max_players]
	count.custom_minimum_size = Vector2(44, 0)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(count)

	var join := Button.new()
	join.custom_minimum_size = Vector2(90, 0)
	if running:
		join.text = "Playing"
		join.disabled = true
	elif players >= max_players:
		join.text = "Full"
		join.disabled = true
	else:
		join.text = "Join"
		join.pressed.connect(_on_join_pressed.bind(room))
	row.add_child(join)

	return row


# ---------------------------------------------------------------------------
# Joining and creating
# ---------------------------------------------------------------------------

func _on_join_pressed(room: Dictionary) -> void:
	_pending_room_id = str(room.get("id", ""))
	if _pending_room_id.is_empty():
		return
	if not room.get("locked", false):
		Rooms.join(_pending_room_id)
		return
	_join_label.text = "Password for %s" % str(room.get("title", "the room"))
	_join_password_field.text = ""
	_join_panel.visible = true
	_join_password_field.grab_focus()


func _on_join_confirmed() -> void:
	if _pending_room_id.is_empty():
		return
	Rooms.join(_pending_room_id, _join_password_field.text)
	_close_join_panel()


func _close_join_panel() -> void:
	_join_panel.visible = false
	_join_password_field.text = ""


func _on_create_pressed() -> void:
	if not Net.is_online():
		_say("Connect first.")
		return
	var title := _room_name_field.text.strip_edges()
	if title.is_empty():
		title = "%s's room" % GameSettings.player_name
	Rooms.create(
		title,
		_room_password_field.text,
		NetProtocol.MIN_PLAYERS + _max_players_option.selected
	)


func _on_joined(_room: Dictionary) -> void:
	SceneSwitcher.go_to(SceneSwitcher.ROOM_LOBBY, false)


func _on_room_failed(_code: String, message: String) -> void:
	_say(message)


func _on_back_pressed() -> void:
	Net.disconnect_from_server()
	SceneSwitcher.go_to(SceneSwitcher.MAIN_MENU, false)


# ---------------------------------------------------------------------------
# View
# ---------------------------------------------------------------------------

func _refresh_view() -> void:
	var online := Net.is_online()
	var busy := Net.state == Net.State.CONNECTING or Net.state == Net.State.HANDSHAKING

	_connect_step.visible = not online
	_rooms_step.visible = online

	_connect_button.disabled = busy
	_connect_button.text = "Connecting..." if busy else "Next"
	_name_field.editable = not busy
	_identity_label.text = "as %s" % GameSettings.player_name

	if online:
		_refresh_timer.start()
	else:
		_refresh_timer.stop()
		_close_join_panel()

	_rebuild_room_list()


func _say(text: String) -> void:
	_status_label.text = text
	_status_label.visible = not text.is_empty()
