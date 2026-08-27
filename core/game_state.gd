class_name GameState
extends RefCounted

## The source of truth for the match. Announces everything through signals.


signal card_revealed(index: int, card: CardData)

signal selection_resolved(indices: Array[int], matched: bool, player_index: int)

signal turn_changed(player_index: int)

signal score_changed(player_index: int, score: int)

signal game_finished(winner_index: int)

var config: GameConfig

var cards: Array[CardData] = []

var matched: Array[bool] = []

var selection: Array[int] = []

var scores: Array[int] = []

var current_player: int = 0


func setup(p_config: GameConfig, p_cards: Array[CardData], player_count: int) -> void:
	config = p_config
	cards = p_cards
	matched = []
	matched.resize(cards.size())
	matched.fill(false)
	selection = []
	scores = []
	scores.resize(player_count)
	scores.fill(0)
	current_player = 0


func can_select(index: int) -> bool:
	if index < 0 or index >= cards.size():
		return false
	if matched[index] == true:
		return false
	if selection.has(index):
		return false
	if selection.size() >= config.group_size:
		return false
	return true


func select(index: int) -> void:
	if not can_select(index):
		push_warning("Cannot select that card right now.")
		return
	selection.append(index)
	card_revealed.emit(index, cards[index])


func resolve_selection() -> bool:
	var chosen: Array[CardData] = []
	for i in selection: 
		chosen.append(cards[i])
	var is_match := GameRules.is_match(chosen, config.group_size)
	if is_match:
		for i in selection:
			matched[i] = true
		scores[current_player] += GameRules.points_for_group(config)
		score_changed.emit(current_player, scores[current_player])
	selection_resolved.emit(selection.duplicate(), is_match, current_player)
	return is_match


func clear_selection() -> void:
	selection.clear()


func end_turn(keep_turn: bool) -> void:
	if is_finished():
		game_finished.emit(GameRules.winner_index(scores))
		return

	if keep_turn:
		turn_changed.emit(current_player)
	else:
		current_player = (current_player + 1) % scores.size()
		turn_changed.emit(current_player)


func is_finished() -> bool:
	return GameRules.is_board_cleared(matched)


func available_indices() -> Array[int]:
	var result: Array[int] = []
	for i in cards.size():
		if not matched[i] and not selection.has(i):
			result.append(i)
	return result


func remaining_groups() -> int:
	var left := 0
	for is_matched in matched:
		if not is_matched:
			left += 1
	if config == null or config.group_size <= 0:
		return 0
	return left / config.group_size
