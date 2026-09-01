class_name RoomChat
extends Node

## Carries a ChatPanel's lines over the relay, and narrates who comes and goes.
##
## Nothing here is about memory games: it rides inside the same opaque payload
## every other game message uses, so a new project reuses it by copying this
## file and chat_panel.gd. Drop it under any scene that lives inside a room:
##
##     var chat := RoomChat.new()
##     add_child(chat)
##     chat.attach(panel)
##
## Names come from the room, never from the message, so nobody can put words in
## somebody else's mouth. The text itself is not checked at all — the relay is
## private, and moderating it would mean reading it.


const T_CHAT := "chat"

## Set false where arrivals and departures are noise rather than news.
@export var announce_arrivals: bool = true

var _panel: ChatPanel

## Peer id -> name, as the room looked last time it changed. Departures are the
## reason it holds names at all: by the time somebody is gone, the room no
## longer knows what they were called.
var _known: Dictionary = {}


func _ready() -> void:
	Net.payload_received.connect(_on_payload)
	Rooms.updated.connect(_on_room_updated)
	Rooms.left.connect(_on_room_left)


func attach(panel: ChatPanel) -> void:
	_panel = panel
	_panel.submitted.connect(_on_submitted)
	_known = _snapshot()


## A line from this device: sent to everyone else and shown here at once, so
## typing never feels like it is waiting for a round trip.
func _on_submitted(text: String) -> void:
	Rooms.send({"t": T_CHAT, "text": text.substr(0, NetProtocol.MAX_CHAT_LENGTH)})
	_show(Net.my_peer_id, text)


func _on_payload(from_id: int, payload: Dictionary) -> void:
	if str(payload.get("t", "")) != T_CHAT:
		return
	var text := str(payload.get("text", "")).substr(0, NetProtocol.MAX_CHAT_LENGTH)
	if text.strip_edges().is_empty():
		return
	_show(from_id, text)


func _show(peer_id: int, text: String) -> void:
	if _panel == null:
		return
	var who := Rooms.member_name(peer_id)
	if peer_id == Net.my_peer_id:
		who = "%s (you)" % who
	_panel.push_line(who, text, color_for(peer_id))


## The room is resent whole whenever it changes, so who is new and who is gone
## is a comparison against the room from last time.
func _on_room_updated(_room: Dictionary) -> void:
	var now := _snapshot()
	if _panel != null and announce_arrivals:
		for id: int in now:
			if not _known.has(id):
				_panel.push_system("%s joined." % now[id])
		for id: int in _known:
			if not now.has(id):
				_panel.push_system("%s left." % _known[id])
	_known = now


func _on_room_left(reason: String) -> void:
	_known = {}
	if _panel == null:
		return
	_panel.push_system(reason)
	_panel.set_input_enabled(false)


func _snapshot() -> Dictionary:
	var out: Dictionary = {}
	for member in Rooms.members():
		out[int(member.get("id", 0))] = str(member.get("name", "Player"))
	return out


## A colour per peer, stable for as long as the connection is. Peer ids are big
## random-looking numbers, so the hue is the id wrapped into the circle, kept
## bright enough to read on a dark panel.
static func color_for(peer_id: int) -> Color:
	return Color.from_hsv(float(absi(peer_id) % 360) / 360.0, 0.45, 1.0)
