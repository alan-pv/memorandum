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


func to_config(opponent: GameConfig.Opponent = GameConfig.Opponent.BOT) -> GameConfig:
	var config := GameConfig.new()
	config.group_size = group_size
	config.total_cards = total_cards
	config.bot_memory = bot_memory
	config.bot_think_time = bot_think_time
	config.reveal_time = reveal_time
	config.opponent = opponent
	if opponent == GameConfig.Opponent.HUMAN:
		config.player_names = PackedStringArray(["Player 1", "Player 2"])
	else:
		config.player_names = PackedStringArray(["You", "Bot"])
	return config
