class_name DifficultyPreset
extends Resource

## A difficulty as an editable resource (.tres).


@export var id: StringName = &"normal"

@export var display_name: String = "Normal"

@export_multiline var description: String = ""

@export_group("Board")
@export_range(2, 8, 1) var group_size: int = 2
@export_range(4, 96, 1) var total_cards: int = 16

@export_group("Bot")
@export_range(0.0, 1.0, 0.05) var bot_memory: float = 0.5
@export_range(0.0, 2.0, 0.1) var bot_think_time: float = 0.6

@export_group("Pacing")
@export_range(0.2, 3.0, 0.1) var reveal_time: float = 1.0


## Builds a match from this preset for the given seats. The seats decide who
## plays; the preset decides the board and how sharp the bots are.
func to_config(seats: Array[PlayerSlot]) -> GameConfig:
	var config := GameConfig.new()
	config.group_size = group_size
	config.total_cards = total_cards
	config.reveal_time = reveal_time

	# The preset owns how sharp the bots are: that is what Easy/Normal/Hard
	# means here. Every bot seat is retuned, keeping whatever name it carries.
	var tuned: Array[PlayerSlot] = []
	for seat in seats:
		tuned.append(make_bot_slot(seat.display_name) if seat.is_bot() else seat)
	config.players = tuned
	return config


## A bot tuned to this difficulty, ready to drop into a seat.
func make_bot_slot(bot_name: String = "Bot") -> PlayerSlot:
	return PlayerSlot.bot(bot_name, bot_memory, bot_think_time)


## The seats a match uses when nobody has chosen anything: you against one bot.
func default_seats() -> Array[PlayerSlot]:
	var seats: Array[PlayerSlot] = [PlayerSlot.human("You"), make_bot_slot()]
	return seats
