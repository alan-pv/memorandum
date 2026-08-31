class_name NetPlayer
extends Player

## A seat in an online match.
##
## Every seat is one of these on every client: the one you own, the ones other
## people own, and the bots. What changes from client to client is only who is
## allowed to *ask* for a pick — the flip itself always arrives as a confirm
## from the referee. That is why the turn loop in game.gd never learns that the
## match is online: it asks the seat to pick and awaits picked(), exactly as it
## does against a bot sitting on the same machine.


var slot: PlayerSlot
var net_match: OnlineMatch

## True only on the device this seat belongs to.
var is_mine: bool = false

## A real BotPlayer, and only on the referee. Everywhere else this seat's bot
## is just a stream of confirms like any other player.
var _brain: BotPlayer = null

## The state we were asked to pick from, or null when it is not our turn.
var _asked_from: GameState = null


func setup(p_index: int, p_slot: PlayerSlot) -> void:
	super.setup(p_index, p_slot)
	slot = p_slot
	is_human = false


func attach(p_match: OnlineMatch, p_is_mine: bool, with_brain: bool) -> void:
	net_match = p_match
	is_mine = p_is_mine
	# The board is only worth interacting with on your own turn, and game.gd
	# already asks every player this question to decide that.
	is_human = p_is_mine
	if with_brain:
		_grow_brain()


func request_pick(state: GameState) -> void:
	_asked_from = state

	# The referee may have confirmed this pick before we got round to asking
	# for it — a bot with no think time on a fast machine does that constantly.
	var ready_index := net_match.claim(self)
	if ready_index >= 0:
		# Deferred, so the loop is not resumed from inside its own call.
		deliver.call_deferred(ready_index)
		return

	if _brain != null:
		_brain.request_pick(state)


## The referee said yes. This is the only place a seat ever emits picked().
func deliver(index: int) -> void:
	_asked_from = null
	picked.emit(index)


## A click on the board. It only ever *asks*: nothing on this screen moves until
## the answer comes back, which is what keeps four clients showing the same
## board. The local check is courtesy, not security — the referee checks again.
func on_card_clicked(index: int) -> void:
	if not is_mine or _asked_from == null:
		return
	if not _asked_from.can_select(index):
		return
	net_match.request(index)


## The bot decided. Same path as a click: it asks, it does not flip.
func _on_brain_picked(index: int) -> void:
	if _asked_from == null:
		return
	net_match.request(index)


## The person who owned this seat left, and the referee is taking it over.
## If we were in the middle of asking them to pick, the new brain picks up
## where they left off instead of waiting for a turn that never comes.
func take_over() -> void:
	_grow_brain()
	if _asked_from != null:
		_brain.request_pick(_asked_from)


func observe(index: int, card: CardData) -> void:
	if _brain != null:
		_brain.observe(index, card)


func forget(indices: Array[int]) -> void:
	if _brain != null:
		_brain.forget(indices)


func cancel_pick() -> void:
	_asked_from = null


func _grow_brain() -> void:
	if _brain != null:
		return
	_brain = BotPlayer.new()
	_brain.name = "Brain"
	# add_child before setup: a BotPlayer needs the tree for its think timer.
	add_child(_brain)
	_brain.setup(player_index, slot)
	_brain.picked.connect(_on_brain_picked)
