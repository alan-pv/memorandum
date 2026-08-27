class_name GameRules
extends RefCounted

## The rulebook: which groups count and who wins.


static func is_match(cards: Array[CardData], group_size: int) -> bool:
	if cards.is_empty():
		return false
	if group_size > cards.size():
		return false
	for card in cards:
		if card.value != cards[0].value:
			return false
	return true


static func is_selection_viable(cards: Array[CardData]) -> bool:
	var size := cards.size()
	if size == 0 or size == 1:
		return true
	for card in cards:
		if card.value != cards[0].value:
			return false
	return true


static func points_for_group(config: GameConfig) -> int:
	return 1


static func is_board_cleared(matched: Array[bool]) -> bool:
	return not matched.has(false)


static func winner_index(scores: Array[int]) -> int:
	if (scores[0] > scores[1]):
		return scores[0]
	if (scores[0] < scores[1]):
		return scores[1]
	return -1
