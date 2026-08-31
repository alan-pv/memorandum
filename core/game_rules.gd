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


## Returns the SEAT of the winner, or -1 when the top score is shared.
##
## The seat is the POSITION in the array, not the value stored there: the old
## two-player version answered `scores[0]` / `scores[1]`, so on a 6-4 it said
## "6" and the results screen found no such player and showed no winner.
static func winner_index(scores: Array[int]) -> int:
	if scores.is_empty():
		return -1
	var best: int = scores.max()
	if scores.count(best) > 1:
		return -1
	return scores.find(best)
