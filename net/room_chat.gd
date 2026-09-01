class_name RoomChat
extends Node

## Carries a ChatPanel's lines over the relay, and narrates who comes and goes.
##
## Nothing here is about memory games: it rides inside the same opaque payload
## every other game message uses, so a new project reuses it by copying this
## file, chat_panel.gd and chat_dock.gd. One line puts a chat in the corner of
## any screen that lives inside a room:
##
##     RoomChat.spawn(self)
##
## Or wire it to a panel you placed yourself:
##
##     var chat := RoomChat.new()
##     add_child(chat)
##     chat.attach(panel)
##
## Names come from the room, never from the message, so nobody can put words in
## somebody else's mouth. The text itself is not checked at all — the relay is
## private, and moderating it would mean reading it.


const T_CHAT := "chat"

## How much of the conversation is carried between screens.
const HISTORY_LIMIT := 60

## Set false where arrivals and departures are noise rather than news.
@export var announce_arrivals: bool = true

## Everything said in this room so far. It is static because a panel dies with
## its screen and a conversation does not: walking from the lobby into the
## match and back out to the results finds the chat where it was left. Emptied
## when the room is.
static var _history: Array[Dictionary] = []

var _panel: ChatPanel

## Peer id -> name, as the room looked last time it changed. Departures are the
## reason it holds names at all: by the time somebody is gone, the room no
## longer knows what they were called.
var _known: Dictionary = {}


func _ready() -> void:
	Net.payload_received.connect(_on_payload)
	Rooms.updated.connect(_on_room_updated)
	Rooms.left.connect(_on_room_left)


## Everything at once: a folding chat in the corner of `host`, a carrier under
## it, and whatever was already said back on screen.
static func spawn(host: Node, open: bool = true) -> ChatDock:
	var dock := ChatDock.new()
	dock.start_open = open
	host.add_child(dock)

	var carrier := RoomChat.new()
	dock.add_child(carrier)
	carrier.attach(dock.panel)

	# A backlog is not news: whoever just opened this screen has read it.
	dock.clear_unread()
	return dock


func attach(panel: ChatPanel) -> void:
	_panel = panel
	_panel.submitted.connect(_on_submitted)
	_known = _snapshot()
	_replay()


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
	var who := Rooms.member_name(peer_id)
	if peer_id == Net.my_peer_id:
		who = "%s (you)" % who
	_say(who, text, color_for(peer_id))


## The room is resent whole whenever it changes, so who is new and who is gone
## is a comparison against the room from last time.
func _on_room_updated(_room: Dictionary) -> void:
	var now := _snapshot()
	if announce_arrivals:
		for id: int in now:
			if not _known.has(id):
				_say_system("%s joined." % now[id])
		for id: int in _known:
			if not now.has(id):
				_say_system("%s left." % _known[id])
	_known = now


## The room is over, and so is what was said in it: the next one starts empty.
func _on_room_left(reason: String) -> void:
	_known = {}
	_history.clear()
	if _panel == null:
		return
	_panel.push_system(reason)
	_panel.set_input_enabled(false)


# ---------------------------------------------------------------------------
# The conversation
#
# Every line goes through here: once into the history that outlives the screen,
# once onto the panel that is on it right now.
# ---------------------------------------------------------------------------

func _say(who: String, text: String, color: Color) -> void:
	_remember({"who": who, "text": text, "color": color})
	if _panel != null:
		_panel.push_line(who, text, color)


func _say_system(text: String) -> void:
	_remember({"text": text})
	if _panel != null:
		_panel.push_system(text)


static func _remember(line: Dictionary) -> void:
	_history.append(line)
	while _history.size() > HISTORY_LIMIT:
		_history.remove_at(0)


## A panel that just appeared catches up with the room. An empty history means
## this is the first screen of the room, so it gets the greeting instead.
func _replay() -> void:
	if _history.is_empty():
		_say_system("You are in room %s." % str(Rooms.current.get("id", "—")))
		return
	for line: Dictionary in _history:
		if not line.has("who"):
			_panel.push_system(str(line["text"]))
			continue
		var color: Color = line["color"]
		_panel.push_line(str(line["who"]), str(line["text"]), color)


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
