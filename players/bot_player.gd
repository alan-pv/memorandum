class_name BotPlayer
extends Player

## Bot player: thinks for a moment, then decides which card to flip.


var memory: BotMemory
var think_time: float = 0.15


func setup(p_index: int, slot: PlayerSlot) -> void:
	super.setup(p_index, slot)
	is_human = false
	think_time = slot.bot_think_time
	memory = BotMemory.new(slot.bot_memory)


func observe(index: int, card: CardData) -> void:
	memory.observe(index, card.value)


func forget(indices: Array[int]) -> void:
	memory.forget(indices)


func request_pick(state: GameState) -> void:
	if think_time > 0.0:
		await get_tree().create_timer(think_time).timeout
	if not is_inside_tree():
		return
	var index := choose_index(state)
	if index < 0:
		push_error("The bot found no valid card to pick.")
		return
	picked.emit(index)


func choose_index(state: GameState) -> int:
	var available := state.available_indices()
	if available.is_empty(): 
		return -1

	if not state.selection.is_empty():
		var target: int = state.cards[state.selection[0]].value
		var known := memory.indices_with_value(target, state.selection)
		if not known.is_empty(): 
			return known[0]

	if state.selection.is_empty():
		var index = memory.find_complete_group(state.config.group_size)
		if not index.is_empty():
			return index[0]

	var unknown = memory.unknown_from(available)
	if not unknown.is_empty(): 
		return unknown.pick_random()

	return available.pick_random()
