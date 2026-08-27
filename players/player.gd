class_name Player
extends Node

## Common contract for a player: request_pick(state) -> picked(index) signal.


signal picked(index: int)

var player_index: int = 0

var display_name: String = "Player"

var is_human: bool = true


func setup(p_index: int, p_name: String, _config: GameConfig) -> void:
	player_index = p_index
	display_name = p_name


func request_pick(_state: GameState) -> void:
	push_error("%s does not implement request_pick()" % get_class())


func observe(_index: int, _card: CardData) -> void:
	pass


func forget(_indices: Array[int]) -> void:
	pass


func cancel_pick() -> void:
	pass
