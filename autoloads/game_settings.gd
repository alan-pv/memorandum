extends Node

## Settings and match data that survive a scene change.


var config: GameConfig

var last_result: Dictionary = {}

## The deck the referee shuffled, as the values it sent. Empty offline, where
## every device builds its own.
var online_deck: PackedInt32Array = PackedInt32Array()

var last_difficulty_id: StringName = &"normal"

## What other players see in the lobby. Kept here so it survives the trip
## between the online menu, the room and the match.
var player_name: String = "Player"

var master_volume: float = 1.0
var sfx_volume: float = 0.8

var best_scores: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func start_new_game(new_config: GameConfig) -> void:
	config = new_config
	online_deck = PackedInt32Array()
	last_result = {}


## Same thing for a match that arrives from the network: the config and the
## deck were both decided in the lobby, and the game scene only reads them.
func start_online_game(new_config: GameConfig, deck_values: PackedInt32Array) -> void:
	new_config.online = true
	config = new_config
	online_deck = deck_values
	last_result = {}


func player_count() -> int:
	if config == null:
		return 2
	return config.player_count()



func try_save_record(difficulty_id: StringName, turns: int, seconds: float) -> bool:
	var key := String(difficulty_id)
	var previous: Dictionary = best_scores.get(key, {})
	var previous_turns: int = previous.get("turns", 999999)
	if turns >= previous_turns:
		return false
	best_scores[key] = { "turns": turns, "seconds": seconds }
	return true
