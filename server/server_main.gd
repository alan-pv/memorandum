extends Node

## Headless entry point for the relay. Reads the command line and starts listening.
##
##   godot --headless --path server/ -- --port=8080 --bind=127.0.0.1
##
## It binds to localhost by default: in production the reverse proxy in front of
## it is what terminates TLS and faces the internet. Pass --bind=* only when
## testing straight against the socket.


const DEFAULT_BIND := "127.0.0.1"
const HEARTBEAT_SECONDS := 300.0

var _uptime: float = 0.0
var _since_heartbeat: float = 0.0


func _ready() -> void:
	var arguments := _parse_arguments()
	var port: int = int(arguments.get("port", NetProtocol.DEFAULT_PORT))
	var bind_address: String = str(arguments.get("bind", DEFAULT_BIND))

	print("[relay] Godot room relay, protocol v%d" % NetProtocol.PROTOCOL_VERSION)
	print("[relay] up to %d rooms, %d players each" % [
		NetProtocol.MAX_ROOMS, NetProtocol.MAX_PLAYERS
	])

	if Net.start_server(port, bind_address) != OK:
		print("[relay] could not listen on %s:%d, giving up" % [bind_address, port])
		get_tree().quit(1)
		return

	print("[relay] listening on ws://%s:%d" % [bind_address, port])


func _process(delta: float) -> void:
	_uptime += delta
	_since_heartbeat += delta
	if _since_heartbeat < HEARTBEAT_SECONDS:
		return
	_since_heartbeat = 0.0
	print("[relay] up %d min · %d peers · %d rooms" % [
		int(_uptime / 60.0), Net.peer_count(), Net.room_count()
	])


## Accepts --key=value and --flag, both before and after the `--` separator.
func _parse_arguments() -> Dictionary:
	var parsed: Dictionary = {}
	var all := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	for argument in all:
		if not argument.begins_with("--"):
			continue
		var body := argument.substr(2)
		var split := body.split("=", true, 1)
		parsed[split[0]] = split[1] if split.size() > 1 else true
	return parsed
