extends Node

## Settings and match data that survive a scene change.


var config: GameConfig

var last_result: Dictionary = {}

var last_difficulty_id: StringName = &"normal"
var master_volume: float = 1.0
var sfx_volume: float = 0.8

var best_scores: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func start_new_game(new_config: GameConfig) -> void:
	config = new_config
	last_result = {}


func player_count() -> int:
	return 2



func try_save_record(difficulty_id: StringName, turns: int, seconds: float) -> bool:
	var key := String(difficulty_id)
	var previous: Dictionary = best_scores.get(key, {})
	var previous_turns: int = previous.get("turns", 999999)
	if turns >= previous_turns:
		return false
	best_scores[key] = { "turns": turns, "seconds": seconds }
	return true
