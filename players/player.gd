class_name Player
extends Node

## Common contract for a player: request_pick(state) -> picked(index) signal.


signal picked(index: int)

var player_index: int = 0

var display_name: String = "Player"

var is_human: bool = true


func setup(p_index: int, slot: PlayerSlot) -> void:
	player_index = p_index
	display_name = slot.display_name


func request_pick(_state: GameState) -> void:
	push_error("%s does not implement request_pick()" % get_class())


## A click on the board reaches every seat; only the one waiting for it cares.
## Routing it to all of them is what keeps `if player is HumanPlayer` out of
## game.gd, and it is how the same click works offline and online.
func on_card_clicked(_index: int) -> void:
	pass


func observe(_index: int, _card: CardData) -> void:
	pass


func forget(_indices: Array[int]) -> void:
	pass


func cancel_pick() -> void:
	pass
