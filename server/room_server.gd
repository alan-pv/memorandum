extends NetProtocol

## The relay: peers, rooms, passwords and message forwarding.
## It knows nothing about any particular game.


signal server_started(port: int)
signal peers_changed(count: int)

## Everything a connected client is, from the relay's point of view.
class PeerInfo:
	var id: int = 0
	var display_name: String = "Player"
	var game_id: String = ""
	var room_id: String = ""
	var ready: bool = false
	var greeted: bool = false
	## False from the moment the socket drops. Sending to a peer the multiplayer
	## layer has already forgotten is an error, not a silent no-op.
	var connected: bool = true
	var last_create_msec: int = -NetProtocol.CREATE_COOLDOWN_MSEC


class Room:
	var id: String = ""
	var title: String = "Room"
	var game_id: String = ""
	var password_hash: String = ""
	var max_players: int = NetProtocol.MAX_PLAYERS
	var host_id: int = 0
	var members: Array[int] = []
	var in_progress: bool = false


## The only reason a room ever closes on someone: the room outlives every
## member but the host, and the host is the referee.
const ROOM_CLOSED_REASON := "The host left, so the match is over."

var _peers: Dictionary = {}
var _rooms: Dictionary = {}
var _peer: WebSocketMultiplayerPeer

var _since_keepalive: float = 0.0


func start_server(port: int, bind_address: String = "127.0.0.1") -> Error:
	_peer = WebSocketMultiplayerPeer.new()
	var error := _peer.create_server(port, bind_address)
	if error != OK:
		push_error("Could not listen on %s:%d (error %d)" % [bind_address, port, error])
		return error

	multiplayer.multiplayer_peer = _peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	server_started.emit(port)
	return OK


func peer_count() -> int:
	return _peers.size()


func room_count() -> int:
	return _rooms.size()


# ---------------------------------------------------------------------------
# Connection lifecycle
# ---------------------------------------------------------------------------

func _on_peer_connected(id: int) -> void:
	var info := PeerInfo.new()
	info.id = id
	_peers[id] = info
	welcome.rpc_id(id, id, PROTOCOL_VERSION)
	peers_changed.emit(_peers.size())
	print("[relay] peer %d connected (%d online)" % [id, _peers.size()])


func _on_peer_disconnected(id: int) -> void:
	var info := _peer_info(id)
	if info != null:
		info.connected = false
	_remove_from_room(id)
	_peers.erase(id)
	peers_changed.emit(_peers.size())
	print("[relay] peer %d disconnected (%d online)" % [id, _peers.size()])


## Every peer gets poked on the same clock. A client answers with `pong`, which
## is why nothing here reads the answer: the point is the traffic, not the
## reply, and a peer that stays quiet is a browser tab in the background rather
## than a peer worth dropping.
func _process(delta: float) -> void:
	if _peers.is_empty():
		return
	_since_keepalive += delta
	if _since_keepalive < NetProtocol.KEEPALIVE_SECONDS:
		return
	_since_keepalive = 0.0
	for id: int in _peers:
		var info: PeerInfo = _peers[id]
		if info.connected:
			ping.rpc_id(id)


# ---------------------------------------------------------------------------
# Requests
#
# Everything below arrives from a client that may have been modified, so no
# argument is trusted: each one is range-checked or trimmed before use, and a
# request that fails is answered with an error rather than ignored.
# ---------------------------------------------------------------------------

func _on_hello(sender_id: int, protocol_version: int, display_name: String, game_id: String) -> void:
	var info := _peer_info(sender_id)
	if info == null:
		return
	if protocol_version != PROTOCOL_VERSION:
		_fail(sender_id, ERR_PROTOCOL)
		# Give the message a moment to leave before the socket closes.
		await get_tree().create_timer(0.2).timeout
		if multiplayer.multiplayer_peer != null:
			multiplayer.multiplayer_peer.disconnect_peer(sender_id)
		return

	info.display_name = _clean_text(display_name, MAX_NAME_LENGTH, "Player")
	info.game_id = _clean_text(game_id, MAX_GAME_ID_LENGTH, "unknown")
	info.greeted = true
	_send_room_list(sender_id)


func _on_list_rooms(sender_id: int) -> void:
	if _require_greeted(sender_id) == null:
		return
	_send_room_list(sender_id)


func _on_create_room(sender_id: int, room_name: String, password_hash: String, max_players: int) -> void:
	var info := _require_greeted(sender_id)
	if info == null:
		return
	if not info.room_id.is_empty():
		_fail(sender_id, ERR_ALREADY_IN_ROOM)
		return
	if _rooms.size() >= MAX_ROOMS:
		_fail(sender_id, ERR_SERVER_FULL)
		return

	var now := Time.get_ticks_msec()
	if now - info.last_create_msec < CREATE_COOLDOWN_MSEC:
		_fail(sender_id, ERR_TOO_FAST)
		return

	var code := _make_room_code()
	if code.is_empty():
		_fail(sender_id, ERR_SERVER_FULL)
		return

	var room := Room.new()
	room.id = code
	room.title = _clean_text(room_name, MAX_ROOM_NAME_LENGTH, "%s's room" % info.display_name)
	room.game_id = info.game_id
	# A hash is 64 hex characters or nothing at all. Anything else is a client
	# sending junk, and the room simply ends up with no password.
	room.password_hash = password_hash if password_hash.length() == 64 else ""
	room.max_players = clampi(max_players, MIN_PLAYERS, MAX_PLAYERS)
	room.host_id = sender_id
	room.members = [sender_id]

	_rooms[code] = room
	info.room_id = code
	info.ready = true
	info.last_create_msec = now

	print("[relay] room %s created by %d (%s)" % [code, sender_id, room.game_id])
	_send_room_state(room)
	_broadcast_room_list()


func _on_join_room(sender_id: int, room_id: String, password_hash: String) -> void:
	var info := _require_greeted(sender_id)
	if info == null:
		return
	if not info.room_id.is_empty():
		_fail(sender_id, ERR_ALREADY_IN_ROOM)
		return

	var room: Room = _rooms.get(room_id.strip_edges().to_upper())
	if room == null:
		_fail(sender_id, ERR_NO_SUCH_ROOM)
		return
	if room.in_progress:
		_fail(sender_id, ERR_IN_PROGRESS)
		return
	if room.members.size() >= room.max_players:
		_fail(sender_id, ERR_ROOM_FULL)
		return
	if room.password_hash != password_hash:
		_fail(sender_id, ERR_BAD_PASSWORD)
		return

	room.members.append(sender_id)
	info.room_id = room.id
	info.ready = false

	print("[relay] peer %d joined room %s (%d/%d)" % [
		sender_id, room.id, room.members.size(), room.max_players
	])
	_send_room_state(room)
	_broadcast_room_list()


func _on_leave_room(sender_id: int) -> void:
	if _require_greeted(sender_id) == null:
		return
	_remove_from_room(sender_id)


func _on_set_ready(sender_id: int, value: bool) -> void:
	var info := _require_greeted(sender_id)
	if info == null:
		return
	var room := _room_of(sender_id)
	if room == null:
		_fail(sender_id, ERR_NOT_IN_ROOM)
		return
	info.ready = value
	_send_room_state(room)


func _on_start_match(sender_id: int) -> void:
	if _require_greeted(sender_id) == null:
		return
	var room := _room_of(sender_id)
	if room == null:
		_fail(sender_id, ERR_NOT_IN_ROOM)
		return
	if room.host_id != sender_id:
		_fail(sender_id, ERR_NOT_HOST)
		return
	if room.members.size() < MIN_PLAYERS:
		_fail(sender_id, ERR_BAD_REQUEST)
		return

	room.in_progress = true
	print("[relay] room %s started with %d players" % [room.id, room.members.size()])
	_send_room_state(room)
	_broadcast_room_list()


## Forwards a game payload to everyone else in the sender's room. The relay
## never reads inside it: that is the whole point of being game-agnostic.
func _on_relay(sender_id: int, payload: Dictionary) -> void:
	if _require_greeted(sender_id) == null:
		return
	var room := _room_of(sender_id)
	if room == null:
		_fail(sender_id, ERR_NOT_IN_ROOM)
		return
	# Godot refuses to decode Objects from the network by default, so a payload
	# can only hold plain data. What is left to check is that it is not huge.
	if var_to_bytes(payload).size() > MAX_PAYLOAD_BYTES:
		_fail(sender_id, ERR_BAD_REQUEST)
		return

	for member in room.members:
		if member != sender_id:
			relayed.rpc_id(member, sender_id, payload)


# ---------------------------------------------------------------------------
# Room bookkeeping
# ---------------------------------------------------------------------------

func _remove_from_room(peer_id: int) -> void:
	var info := _peer_info(peer_id)
	if info == null or info.room_id.is_empty():
		return
	var room: Room = _rooms.get(info.room_id)
	info.room_id = ""
	info.ready = false
	if room == null:
		return

	room.members.erase(peer_id)

	# The host is the referee: without them the match has no rules engine, so
	# the room goes away instead of limping on.
	if room.members.is_empty() or room.host_id == peer_id:
		for member in room.members:
			var other := _peer_info(member)
			if other != null:
				other.room_id = ""
				other.ready = false
			room_closed.rpc_id(member, ROOM_CLOSED_REASON)
		_rooms.erase(room.id)
		print("[relay] room %s closed" % room.id)
	else:
		_send_room_state(room)

	_broadcast_room_list()


func _room_of(peer_id: int) -> Room:
	var info := _peer_info(peer_id)
	if info == null or info.room_id.is_empty():
		return null
	return _rooms.get(info.room_id)


## Four letters from an alphabet with no lookalikes, retried until it does not
## collide. With 32^4 codes and at most 10 rooms, a collision is a curiosity.
func _make_room_code() -> String:
	for attempt in 32:
		var code := ""
		for i in ROOM_CODE_LENGTH:
			code += ROOM_CODE_ALPHABET[randi() % ROOM_CODE_ALPHABET.length()]
		if not _rooms.has(code):
			return code
	return ""


# ---------------------------------------------------------------------------
# Outgoing views
# ---------------------------------------------------------------------------

## What everyone in the lobby is allowed to see. The password hash is never in
## here: browsing a list must not hand out anything worth cracking.
func _room_summary(room: Room) -> Dictionary:
	return {
		"id": room.id,
		"title": room.title,
		"game_id": room.game_id,
		"host": _display_name_of(room.host_id),
		"players": room.members.size(),
		"max_players": room.max_players,
		"locked": not room.password_hash.is_empty(),
		"in_progress": room.in_progress,
	}


## The full room, for the people actually inside it.
func _room_detail(room: Room) -> Dictionary:
	var members: Array = []
	for id in room.members:
		var info := _peer_info(id)
		members.append({
			"id": id,
			"name": info.display_name if info != null else "Player",
			"ready": info.ready if info != null else false,
			"host": id == room.host_id,
		})
	var detail := _room_summary(room)
	detail["members"] = members
	return detail


func _send_room_state(room: Room) -> void:
	var detail := _room_detail(room)
	for member in room.members:
		room_state.rpc_id(member, detail)


func _send_room_list(peer_id: int) -> void:
	var info := _peer_info(peer_id)
	if info == null or not info.connected:
		return
	var summaries: Array = []
	for room: Room in _rooms.values():
		# Each game only ever sees its own rooms, so one relay can serve them all.
		if room.game_id == info.game_id:
			summaries.append(_room_summary(room))
	room_list.rpc_id(peer_id, summaries)


## Only peers sitting in the lobby need a refreshed list; people already inside
## a room are looking at the room, not at the browser.
func _broadcast_room_list() -> void:
	for id: int in _peers:
		var info: PeerInfo = _peers[id]
		if info.greeted and info.room_id.is_empty():
			_send_room_list(id)


# ---------------------------------------------------------------------------
# Guards
# ---------------------------------------------------------------------------

func _peer_info(peer_id: int) -> PeerInfo:
	return _peers.get(peer_id)


func _display_name_of(peer_id: int) -> String:
	var info := _peer_info(peer_id)
	return info.display_name if info != null else "Player"


func _require_greeted(peer_id: int) -> PeerInfo:
	var info := _peer_info(peer_id)
	if info == null:
		return null
	if not info.greeted:
		_fail(peer_id, ERR_NO_HELLO)
		return null
	return info


func _fail(peer_id: int, code: StringName) -> void:
	room_error.rpc_id(peer_id, String(code), message_for(code))


## Free text from a client: collapse whitespace, drop control characters, cut it
## to length, and fall back when nothing usable is left.
func _clean_text(text: String, max_length: int, fallback: String) -> String:
	var cleaned := ""
	for character in text:
		if character.unicode_at(0) >= 32:
			cleaned += character
	cleaned = cleaned.strip_edges().substr(0, max_length).strip_edges()
	return fallback if cleaned.is_empty() else cleaned
