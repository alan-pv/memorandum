class_name GameConfig
extends Resource

## The settings of a match and their validation.


const MIN_PLAYERS := 2
const MAX_PLAYERS := 4

@export_range(2, 5, 1) var group_size: int = 2

@export_range(4, 96, 1) var total_cards: int = 16

## Who sits at the table, in turn order. Seat 0 is always the local player.
@export var players: Array[PlayerSlot] = []

@export_range(0.2, 3.0, 0.1) var reveal_time: float = 1.0

@export var early_abort: bool = true

## True once the match is driven by the network. Read by game.gd to decide
## where picks come from; nothing else in core/ cares.
@export var online: bool = false

## Names in turn order. Derived from the seats, so it can never drift out of
## sync with them. The HUD and the results screen read it as a plain property.
var player_names: PackedStringArray:
	get:
		var names := PackedStringArray()
		for slot in players:
			names.append(slot.display_name)
		return names


func _init() -> void:
	if players.is_empty():
		# Typed on its own line: assigning a bare [...] literal to an
		# Array[PlayerSlot] fails at runtime, it stays a plain Array.
		var default_seats: Array[PlayerSlot] = [
			PlayerSlot.human("You"),
			PlayerSlot.bot("Bot"),
		]
		players = default_seats


func player_count() -> int:
	return players.size()


func group_count() -> int:
	if group_size <= 0:
		return 0
	return total_cards / group_size


func is_valid() -> bool:
	return validation_error().is_empty()


func validation_error() -> String:
	if not (group_size >= 2):
		return "A group must contain at least 2 cards."
	if not (total_cards >= group_size):
		return "There must be at least as many cards as one group needs."
	if not (total_cards % group_size == 0):
		return "The card count must be an exact multiple of the group size."
	if not (group_count() >= 2):
		return "One single group is not a game: there must be at least two."
	if player_count() < MIN_PLAYERS:
		return "A match needs at least %d players." % MIN_PLAYERS
	if player_count() > MAX_PLAYERS:
		return "A match cannot have more than %d players." % MAX_PLAYERS
	if group_count() < player_count():
		return "There are fewer groups than players: everyone must be able to score."
	return ""


func clone() -> GameConfig:
	return duplicate(true) as GameConfig


func to_dict() -> Dictionary:
	var slots: Array = []
	for slot in players:
		slots.append(slot.to_dict())
	return {
		"group_size": group_size,
		"total_cards": total_cards,
		"reveal_time": reveal_time,
		"early_abort": early_abort,
		"players": slots,
	}


## Rebuilds a config from the wire. Values arrive from another client, so every
## field is clamped into a range this build can actually run.
static func from_dict(data: Dictionary) -> GameConfig:
	var config := GameConfig.new()
	config.group_size = clampi(int(data.get("group_size", 2)), 2, 5)
	config.total_cards = clampi(int(data.get("total_cards", 16)), 4, 96)
	config.reveal_time = clampf(float(data.get("reveal_time", 1.0)), 0.2, 3.0)
	config.early_abort = bool(data.get("early_abort", true))
	config.online = true

	var slots: Array[PlayerSlot] = []
	var raw: Array = data.get("players", [])
	for entry in raw.slice(0, MAX_PLAYERS):
		if entry is Dictionary:
			slots.append(PlayerSlot.from_dict(entry))
	config.players = slots
	return config


func _to_string() -> String:
	return "GameConfig(%d cards, groups of %d, %d players)" % [
		total_cards, group_size, player_count()
	]
