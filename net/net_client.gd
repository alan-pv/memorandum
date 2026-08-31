extends NetProtocol

## Autoload "Net": the socket, the handshake and the connection state machine.
## Knows about connecting, not about rooms or about memory games.


signal state_changed(state: State)
signal connected
signal connection_failed(reason: String)
signal disconnected
signal server_error(code: String, message: String)

signal room_list_received(rooms: Array)
signal room_state_received(room: Dictionary)
signal room_closed_received(reason: String)
signal payload_received(from_id: int, payload: Dictionary)

enum State {
	OFFLINE,      ## No socket at all.
	CONNECTING,   ## The socket is being opened.
	HANDSHAKING,  ## Socket open, waiting for the server to accept our version.
	ONLINE,       ## Greeted and usable.
}

var state: State = State.OFFLINE
var settings: NetSettings
var display_name: String = "Player"
var my_peer_id: int = 0

var _timeout_left: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	multiplayer.connected_to_server.connect(_on_socket_opened)
	multiplayer.connection_failed.connect(_on_socket_failed)
	multiplayer.server_disconnected.connect(_on_socket_closed)


func connect_to_server(p_settings: NetSettings, p_display_name: String) -> void:
	if state != State.OFFLINE:
		disconnect_from_server()

	settings = p_settings
	display_name = p_display_name

	var peer := WebSocketMultiplayerPeer.new()
	var error := peer.create_client(settings.url)
	if error != OK:
		_set_state(State.OFFLINE)
		connection_failed.emit("Could not open a socket to %s." % settings.url)
		return

	multiplayer.multiplayer_peer = peer
	_timeout_left = settings.connect_timeout
	set_process(true)
	_set_state(State.CONNECTING)


func disconnect_from_server() -> void:
	set_process(false)
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	my_peer_id = 0
	if state != State.OFFLINE:
		_set_state(State.OFFLINE)
		disconnected.emit()


func is_online() -> bool:
	return state == State.ONLINE


## The whole handshake has one clock. Without it a server that accepts the TCP
## connection and then says nothing leaves the player staring at a spinner.
func _process(delta: float) -> void:
	if state == State.ONLINE or state == State.OFFLINE:
		set_process(false)
		return
	_timeout_left -= delta
	if _timeout_left > 0.0:
		return
	set_process(false)
	var reason := "The server at %s did not answer in time." % settings.url
	disconnect_from_server()
	connection_failed.emit(reason)


func _on_socket_opened() -> void:
	_set_state(State.HANDSHAKING)
	hello.rpc_id(1, PROTOCOL_VERSION, display_name, settings.game_id)


func _on_socket_failed() -> void:
	set_process(false)
	multiplayer.multiplayer_peer = null
	_set_state(State.OFFLINE)
	connection_failed.emit("Could not reach %s." % settings.url)


func _on_socket_closed() -> void:
	set_process(false)
	multiplayer.multiplayer_peer = null
	my_peer_id = 0
	_set_state(State.OFFLINE)
	disconnected.emit()


func _set_state(value: State) -> void:
	if state == value:
		return
	state = value
	state_changed.emit(state)


# --- Server -> client ------------------------------------------------------

func _on_welcome(peer_id: int, protocol_version: int) -> void:
	my_peer_id = peer_id
	if protocol_version != PROTOCOL_VERSION:
		var reason := message_for(ERR_PROTOCOL)
		disconnect_from_server()
		connection_failed.emit(reason)
		return
	set_process(false)
	_set_state(State.ONLINE)
	connected.emit()


func _on_room_list(rooms: Array) -> void:
	room_list_received.emit(rooms)


func _on_room_state(room: Dictionary) -> void:
	room_state_received.emit(room)


func _on_room_closed(reason: String) -> void:
	room_closed_received.emit(reason)


func _on_room_error(code: String, message: String) -> void:
	server_error.emit(code, message)


func _on_relayed(from_id: int, payload: Dictionary) -> void:
	payload_received.emit(from_id, payload)


## Answering is the whole contribution: it is what keeps the client -> server
## half of the socket from being timed out by whatever proxy sits in between.
func _on_ping() -> void:
	pong.rpc_id(1)
