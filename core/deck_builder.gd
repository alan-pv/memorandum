class_name DeckBuilder
extends RefCounted

## Builds and shuffles the deck from a GameConfig.


static func build(config: GameConfig) -> Array[CardData]:
	var deck: Array[CardData] = []

	if not (config.is_valid()):
		push_error("Invalid configuration: " + config.validation_error())
		return deck

	var groups := config.group_count()
	for value in range(1, (groups+1)):
		var color := CardPalette.color_for_value(value, groups)
		for copy in config.group_size:
			deck.append(CardData.new(value, color, copy))
	shuffle_deck(deck)
	return deck


static func shuffle_deck(deck: Array[CardData]) -> void:
	for i in range(deck.size() - 1, 0, -1):
		var j := randi_range(0, i)
		var tmp := deck[i]; deck[i] = deck[j]; deck[j] = tmp


static func count_by_value(deck: Array[CardData]) -> Dictionary:
	var counts: Dictionary = {}
	for card in deck:
		counts[card.value] = counts.get(card.value, 0) + 1
	return counts
