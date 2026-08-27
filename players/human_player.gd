class_name HumanPlayer
extends Player

## Human player: waits for a valid click on the board.


var _waiting: bool = false
var _state: GameState = null


func request_pick(state: GameState) -> void:
	_state = state
	_waiting = true


func on_card_clicked(index: int) -> void:
	if not _waiting:
		return
	if _state == null or not _state.can_select(index):
		return
	_waiting = false
	picked.emit(index)


func cancel_pick() -> void:
	_waiting = false
