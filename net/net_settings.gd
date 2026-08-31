class_name NetSettings
extends Resource

## Where the relay lives. Swapping environments is swapping this resource.


## Use ws:// only over plain http. A page served over https refuses to open a
## ws:// socket (mixed content), so anything published needs wss:// and a real
## certificate, which in turn needs a domain name: an IP will never match one.
@export var url: String = "ws://127.0.0.1:8080"

## Keeps one relay usable by several games: rooms are only ever listed to
## clients that asked for the same id.
@export var game_id: String = "memorandum"

@export_range(2.0, 30.0, 0.5) var connect_timeout: float = 8.0

@export var label: String = "Local"


func is_secure() -> bool:
	return url.begins_with("wss://")
