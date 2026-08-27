class_name GameConfig
extends Resource

## The settings of a match and their validation.


enum Opponent {
	BOT,   ## One human against the machine.
	HUMAN, ## Two people on the same device, taking turns.
}

@export_range(2, 5, 1) var group_size: int = 2

@export_range(4, 96, 1) var total_cards: int = 16

@export var opponent: Opponent = Opponent.BOT

@export var player_names: PackedStringArray = PackedStringArray(["Player 1", "Bot"])

@export_range(0.2, 3.0, 0.1) var reveal_time: float = 1.0

@export_range(0.0, 1.0, 0.05) var bot_memory: float = 0.5

@export_range(0.0, 2.0, 0.1) var bot_think_time: float = 0.01

@export var early_abort: bool = true


func group_count() -> int:
	if group_size <= 0:
		return 0
	return total_cards / group_size


func is_valid() -> bool:
	if not (group_size >= 2):
		return false
	if not (total_cards >= group_size):
		return false
	if not (total_cards % group_size == 0):
		return false
	if not (group_count() >= 2):
		return false
	return true


func validation_error() -> String:
	if not (group_size >= 2):
		return "A group must contain at least 2 cards."
	if not (total_cards >= group_size):
		return "There must be at least as many cards as one group needs."
	if not (total_cards % group_size == 0):
		return "The card count must be an exact multiple of the group size."
	if not (group_count() >= 2):
		return "One single group is not a game: there must be at least two."
	return ""


func clone() -> GameConfig:
	return duplicate(true) as GameConfig


func _to_string() -> String:
	return "GameConfig(%d cards, groups of %d, %d groups)" % [total_cards, group_size, group_count()]
