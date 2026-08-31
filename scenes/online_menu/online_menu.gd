extends Control

## The lobby browser: connect to a relay, look at the rooms, make one or join one.


const NET_SETTINGS_DIR := "res://resources/net"
const REFRESH_SECONDS := 3.0

@onready var _name_field: LineEdit = %NameField
@onready var _server_option: OptionButton = %ServerOption
@onready var _connect_button: Button = %ConnectButton
@onready var _status_label: Label = %StatusLabel
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

var _servers: Array[NetSettings] = []
var _rooms: Array = []
var _pending_room_id: String = ""
var _refresh_timer: Timer


func _ready() -> void:
	_name_field.text = GameSettings.player_name
	_room_name_field.placeholder_text = "%s's room" % GameSettings.player_name

	_fill_servers()
	_fill_max_players()
	_build_refresh_timer()

	_connect_button.pressed.connect(_on_connect_pressed)
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
	_refresh_view()

	# Coming back from a room leaves the connection open: pick the list up again.
	if Net.is_online():
		Rooms.refresh()


func _fill_servers() -> void:
	_servers = _load_servers()
	_server_option.clear()
	for settings in _servers:
		_server_option.add_item(settings.label)
	if not _servers.is_empty():
		_server_option.selected = 0
	# Reconnecting to a different relay would drop the room we are browsing.
	_server_option.disabled = _servers.size() < 2


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


## Every relay the build knows about, so switching environments is picking one
## from a list instead of editing a URL.
func _load_servers() -> Array[NetSettings]:
	var found: Array[NetSettings] = []
	var dir := DirAccess.open(NET_SETTINGS_DIR)
	if dir == null:
		push_error("No network settings in %s" % NET_SETTINGS_DIR)
		return found
	for file_name in dir.get_files():
		var clean := file_name.trim_suffix(".remap")
		if not clean.ends_with(".tres"):
			continue
		var settings := load("%s/%s" % [NET_SETTINGS_DIR, clean]) as NetSettings
		if settings != null:
			found.append(settings)
	found.sort_custom(func(a: NetSettings, b: NetSettings) -> bool: return a.label < b.label)
	return found


# ---------------------------------------------------------------------------
# Connecting
# ---------------------------------------------------------------------------

func _on_connect_pressed() -> void:
	if Net.is_online():
		Net.disconnect_from_server()
		return
	if _servers.is_empty():
		_say("This build has no relay configured.")
		return

	GameSettings.player_name = _clean_name()
	_name_field.text = GameSettings.player_name

	var settings := _servers[maxi(0, _server_option.selected)]
	_say("Connecting to %s..." % settings.url)
	Net.connect_to_server(settings, GameSettings.player_name)


func _clean_name() -> String:
	var typed := _name_field.text.strip_edges()
	return typed.substr(0, NetProtocol.MAX_NAME_LENGTH) if not typed.is_empty() else "Player"


func _on_net_state_changed(_state: int) -> void:
	if Net.is_online():
		_say("Connected as %s." % GameSettings.player_name)
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

	_connect_button.text = "Disconnect" if online else "Connect"
	_connect_button.disabled = busy
	_name_field.editable = not online and not busy
	_refresh_button.disabled = not online
	_create_button.disabled = not online
	_room_name_field.editable = online
	_room_password_field.editable = online
	_max_players_option.disabled = not online

	if online:
		_refresh_timer.start()
	else:
		_refresh_timer.stop()
		_close_join_panel()

	_rebuild_room_list()


func _say(text: String) -> void:
	_status_label.text = text
