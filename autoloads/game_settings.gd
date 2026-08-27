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
	load_preferences()


func start_new_game(new_config: GameConfig) -> void:
	config = new_config
	last_result = {}


func player_count() -> int:
	return 2


func save_preferences() -> void:
	SaveManager.save_data({
		"last_difficulty_id": String(last_difficulty_id),
		"master_volume": master_volume,
		"sfx_volume": sfx_volume,
		"best_scores": best_scores,
	})


func load_preferences() -> void:
	var data := SaveManager.load_data()
	if data.is_empty():
		return
	last_difficulty_id = StringName(data.get("last_difficulty_id", "normal"))
	master_volume = float(data.get("master_volume", 1.0))
	sfx_volume = float(data.get("sfx_volume", 0.8))
	best_scores = data.get("best_scores", {})


func try_save_record(difficulty_id: StringName, turns: int, seconds: float) -> bool:
	var key := String(difficulty_id)
	var previous: Dictionary = best_scores.get(key, {})
	var previous_turns: int = previous.get("turns", 999999)
	if turns >= previous_turns:
		return false
	best_scores[key] = { "turns": turns, "seconds": seconds }
	save_preferences()
	return true
