class_name NetProtocol
extends Node

## The wire contract. Every message that crosses the network is declared here,
## once, so the client and the relay cannot drift apart.


## Bump this whenever a message changes shape. A client that does not match is
## turned away with a clear reason instead of failing in some subtle way later.
##
## Adding a message counts as changing shape. Godot numbers the RPCs of a script
## by sorting their names, so one new method renumbers every message that sorts
## after it: the two ends have to be deployed together, and a mismatch is caught
## here rather than being decoded as some other message entirely.
const PROTOCOL_VERSION := 4

const DEFAULT_PORT := 8080

## How often the relay pokes each peer, and each peer pokes back.
##
## A CDN or a reverse proxy closes a WebSocket it believes is idle — Cloudflare
## does it at around 100 seconds — and a turn-based game is idle for minutes at
## a time while somebody stares at the board. Nothing above this layer should
## ever have to know that, so the socket is kept warm from down here.
const KEEPALIVE_SECONDS := 30.0

## Per game, not for the whole relay: one popular game must not be able to
## lock every other one out.
const MAX_ROOMS := 10
const MIN_PLAYERS := 2
const MAX_PLAYERS := 4

const MAX_NAME_LENGTH := 16
const MAX_CHAT_LENGTH := 200
const MAX_ROOM_NAME_LENGTH := 24
const MAX_GAME_ID_LENGTH := 32
const MAX_PAYLOAD_BYTES := 4096

const ROOM_CODE_LENGTH := 4
## No I, O, 0 or 1: a room code gets read out loud or typed from a screenshot.
const ROOM_CODE_ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

## How long a peer must wait between creating rooms, so one client cannot fill
## the whole server on its own.
const CREATE_COOLDOWN_MSEC := 2000

const ERR_PROTOCOL := &"protocol"
const ERR_NO_HELLO := &"no_hello"
const ERR_SERVER_FULL := &"server_full"
const ERR_ALREADY_IN_ROOM := &"already_in_room"
const ERR_NOT_IN_ROOM := &"not_in_room"
const ERR_NO_SUCH_ROOM := &"no_such_room"
const ERR_ROOM_FULL := &"room_full"
const ERR_BAD_PASSWORD := &"bad_password"
const ERR_IN_PROGRESS := &"in_progress"
const ERR_NOT_HOST := &"not_host"
const ERR_TOO_FAST := &"too_fast"
const ERR_BAD_REQUEST := &"bad_request"
const ERR_KICKED := &"kicked"

const ERROR_MESSAGES := {
	ERR_PROTOCOL: "This build is out of date. Reload the page to get the current one.",
	ERR_NO_HELLO: "The server did not recognise this session.",
	ERR_SERVER_FULL: "Every room is taken right now. Try again in a minute.",
	ERR_ALREADY_IN_ROOM: "You are already in a room.",
	ERR_NOT_IN_ROOM: "You are not in a room.",
	ERR_NO_SUCH_ROOM: "That room no longer exists.",
	ERR_ROOM_FULL: "That room is full.",
	ERR_BAD_PASSWORD: "Wrong password.",
	ERR_IN_PROGRESS: "That match has already started.",
	ERR_NOT_HOST: "Only the player who created the room can do that.",
	ERR_TOO_FAST: "Slow down a moment before creating another room.",
	ERR_BAD_REQUEST: "The server rejected that request.",
	ERR_KICKED: "The host removed you from that room.",
}

## What the room tells someone the host threw out. It travels as a `room_closed`
## reason, so being kicked and the room closing land on the same code path.
const KICK_REASON := "The host removed you from the room."


static func message_for(code: StringName) -> String:
	return ERROR_MESSAGES.get(code, ERROR_MESSAGES[ERR_BAD_REQUEST])


## Passwords never travel in the clear: the client hashes, the server only ever
## compares hashes. An empty password stays empty, meaning "no password".
static func hash_password(password: String) -> String:
	if password.is_empty():
		return ""
	return password.sha256_text()


# ---------------------------------------------------------------------------
# Client -> server
#
# Every one of these is annotated once, here, and the two projects override the
# `_on_*` handler underneath instead of the RPC itself. Re-annotating an
# override is how the two sides quietly end up with different RPC configs.
# ---------------------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func hello(protocol_version: int, display_name: String, game_id: String) -> void:
	_on_hello(_sender(), protocol_version, display_name, game_id)


@rpc("any_peer", "call_remote", "reliable")
func list_rooms() -> void:
	_on_list_rooms(_sender())


@rpc("any_peer", "call_remote", "reliable")
func create_room(room_name: String, password_hash: String, max_players: int) -> void:
	_on_create_room(_sender(), room_name, password_hash, max_players)


@rpc("any_peer", "call_remote", "reliable")
func join_room(room_id: String, password_hash: String) -> void:
	_on_join_room(_sender(), room_id, password_hash)


@rpc("any_peer", "call_remote", "reliable")
func leave_room() -> void:
	_on_leave_room(_sender())


@rpc("any_peer", "call_remote", "reliable")
func set_ready(value: bool) -> void:
	_on_set_ready(_sender(), value)


## The host closes the room to newcomers. From here on the match is running.
@rpc("any_peer", "call_remote", "reliable")
func start_match() -> void:
	_on_start_match(_sender())


## The match is over and the room is a waiting room again: open to newcomers,
## and with everybody's ready cleared so the next round is agreed to on its own.
@rpc("any_peer", "call_remote", "reliable")
func end_match() -> void:
	_on_end_match(_sender())


## Anything game-specific rides inside here. The relay never looks at it.
@rpc("any_peer", "call_remote", "reliable")
func relay(payload: Dictionary) -> void:
	_on_relay(_sender(), payload)


## The host throws somebody out. Only the relay can actually do it: a client
## asking another client to leave is a request it is free to ignore.
@rpc("any_peer", "call_remote", "reliable")
func kick_member(peer_id: int) -> void:
	_on_kick_member(_sender(), peer_id)


## The answer to `ping`. It carries nothing: its only job is to put bytes on the
## wire in this direction, because a proxy may time out each direction of a
## socket separately.
@rpc("any_peer", "call_remote", "reliable")
func pong() -> void:
	_on_pong(_sender())


# ---------------------------------------------------------------------------
# Server -> client
# ---------------------------------------------------------------------------

@rpc("authority", "call_remote", "reliable")
func welcome(peer_id: int, protocol_version: int) -> void:
	_on_welcome(peer_id, protocol_version)


@rpc("authority", "call_remote", "reliable")
func room_list(rooms: Array) -> void:
	_on_room_list(rooms)


## The whole room, every time it changes. Rooms hold at most four people, so
## resending all of it is cheaper than teaching both sides to patch a diff, and
## it cannot drift out of sync.
@rpc("authority", "call_remote", "reliable")
func room_state(room: Dictionary) -> void:
	_on_room_state(room)


@rpc("authority", "call_remote", "reliable")
func room_closed(reason: String) -> void:
	_on_room_closed(reason)


@rpc("authority", "call_remote", "reliable")
func room_error(code: String, message: String) -> void:
	_on_room_error(code, message)


@rpc("authority", "call_remote", "reliable")
func relayed(from_id: int, payload: Dictionary) -> void:
	_on_relayed(from_id, payload)


## Keeps the socket warm. The relay asks rather than waiting to be asked,
## because this is the half that still works when the other end is a browser
## tab in the background: a frozen tab runs no code and can answer nothing, but
## the bytes still arrive and the connection stays open.
##
## Deliberately nothing times out on silence. Being unanswered is exactly what a
## backgrounded tab looks like, and dropping it would undo the point.
@rpc("authority", "call_remote", "reliable")
func ping() -> void:
	_on_ping()


# ---------------------------------------------------------------------------
# Handlers. Each project overrides only the half it implements.
# ---------------------------------------------------------------------------

func _on_hello(_sender_id: int, _protocol_version: int, _display_name: String, _game_id: String) -> void:
	pass

func _on_list_rooms(_sender_id: int) -> void:
	pass

func _on_create_room(_sender_id: int, _room_name: String, _password_hash: String, _max_players: int) -> void:
	pass

func _on_join_room(_sender_id: int, _room_id: String, _password_hash: String) -> void:
	pass

func _on_leave_room(_sender_id: int) -> void:
	pass

func _on_set_ready(_sender_id: int, _value: bool) -> void:
	pass

func _on_start_match(_sender_id: int) -> void:
	pass

func _on_end_match(_sender_id: int) -> void:
	pass

func _on_kick_member(_sender_id: int, _peer_id: int) -> void:
	pass

func _on_relay(_sender_id: int, _payload: Dictionary) -> void:
	pass

func _on_pong(_sender_id: int) -> void:
	pass

func _on_welcome(_peer_id: int, _protocol_version: int) -> void:
	pass

func _on_room_list(_rooms: Array) -> void:
	pass

func _on_room_state(_room: Dictionary) -> void:
	pass

func _on_room_closed(_reason: String) -> void:
	pass

func _on_room_error(_code: String, _message: String) -> void:
	pass

func _on_relayed(_from_id: int, _payload: Dictionary) -> void:
	pass

func _on_ping() -> void:
	pass


func _sender() -> int:
	return multiplayer.get_remote_sender_id()
