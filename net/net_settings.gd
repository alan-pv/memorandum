class_name NetSettings
extends Resource

## Where the relay lives. One relay serves every game, so the defaults below are
## the published ones and nothing has to be configured to play.


## Use ws:// only over plain http. A page served over https refuses to open a
## ws:// socket (mixed content), so anything published needs wss:// and a real
## certificate, which in turn needs a domain name: an IP will never match one.
@export var url: String = "wss://play.alan-pv.com/ws"

## Keeps one relay usable by several games: rooms are only ever listed to
## clients that asked for the same id, and a room code from another game is
## refused. A new game changes this line and nothing else.
@export var game_id: String = "memorandum"

@export_range(2.0, 30.0, 0.5) var connect_timeout: float = 8.0
