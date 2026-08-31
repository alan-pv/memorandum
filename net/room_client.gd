extends Node

## Autoload "Rooms": the lobby seen from a client. Browsing, creating, joining
## and the state of the room you are sitting in.
##
## Game-agnostic on purpose: it carries a room and its members, never a board.


signal list_updated(rooms: Array)
signal joined(room: Dictionary)
signal updated(room: Dictionary)
signal left(reason: String)
signal failed(code: String, message: String)

var current: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Net.room_list_received.connect(_on_room_list)
	Net.room_state_received.connect(_on_room_state)
	Net.room_closed_received.connect(_on_room_closed)
	Net.server_error.connect(_on_server_error)
	Net.disconnected.connect(_on_disconnected)


func in_room() -> bool:
	return not current.is_empty()


func is_host() -> bool:
	if not in_room():
		return false
	for member in current.get("members", []):
		if member.get("id", 0) == Net.my_peer_id:
			return member.get("host", false)
	return false


func member_ids() -> Array[int]:
	var ids: Array[int] = []
	for member in current.get("members", []):
		ids.append(int(member.get("id", 0)))
	return ids


func member_names() -> PackedStringArray:
	var names := PackedStringArray()
	for member in current.get("members", []):
		names.append(str(member.get("name", "Player")))
	return names


func everyone_ready() -> bool:
	var members: Array = current.get("members", [])
	if members.size() < NetProtocol.MIN_PLAYERS:
		return false
	for member in members:
		if not member.get("ready", false):
			return false
	return true


func refresh() -> void:
	if Net.is_online():
		Net.list_rooms.rpc_id(1)


func create(title: String, password: String = "", max_players: int = NetProtocol.MAX_PLAYERS) -> void:
	if Net.is_online():
		Net.create_room.rpc_id(1, title, NetProtocol.hash_password(password), max_players)


func join(room_id: String, password: String = "") -> void:
	if Net.is_online():
		Net.join_room.rpc_id(1, room_id, NetProtocol.hash_password(password))


func leave() -> void:
	if Net.is_online() and in_room():
		Net.leave_room.rpc_id(1)
	_clear("You left the room.")


func set_ready(value: bool) -> void:
	if Net.is_online() and in_room():
		Net.set_ready.rpc_id(1, value)


func start_match() -> void:
	if Net.is_online() and is_host():
		Net.start_match.rpc_id(1)


## Sends a game payload to everyone else in the room. What is inside is the
## game's business; this layer only checks there is somewhere to send it.
func send(payload: Dictionary) -> void:
	if Net.is_online() and in_room():
		Net.relay.rpc_id(1, payload)


func _on_room_list(rooms: Array) -> void:
	list_updated.emit(rooms)


func _on_room_state(room: Dictionary) -> void:
	var was_in := in_room()
	current = room
	if was_in:
		updated.emit(room)
	else:
		joined.emit(room)


func _on_room_closed(reason: String) -> void:
	_clear(reason)


func _on_disconnected() -> void:
	_clear("Lost the connection to the server.")


func _on_server_error(code: String, message: String) -> void:
	failed.emit(code, message)


func _clear(reason: String) -> void:
	if current.is_empty():
		return
	current = {}
	left.emit(reason)
