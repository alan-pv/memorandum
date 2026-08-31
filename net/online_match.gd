class_name OnlineMatch
extends Node

## The Memorandum half of the network: one match, refereed by the host and
## replayed identically by everybody else.
##
## Above it, game.gd only ever sees Players emitting picked(), so the turn loop
## is the same code offline and online. Below it, Rooms only ever sees opaque
## dictionaries, so the relay never learns what a card is.
##
## The whole networked state of a match is the ordered list of confirmed picks.
## Which cards those are, whose turn it is and what the score is, every client
## works out for itself from (config, deck, picks) — and all three of those are
## transmitted explicitly. Nobody rolls dice on their own.


## Something worth putting on the HUD for a moment.
signal message(text: String)

## The match cannot go on: the referee left, or the connection died.
signal aborted(reason: String)


# ---------------------------------------------------------------------------
# The Memorandum-specific messages, all of them.
#
# They ride inside the relay's opaque `payload`, so adding one here changes
# nothing at all on the server.
# ---------------------------------------------------------------------------

## Host -> everyone, from the lobby: the config and the deck of this match.
const T_START := "start"
## Referee -> everyone, while waiting: "are you in the game scene yet?"
const T_PING := "ping"
## Everyone -> referee: "I am, and I am listening."
const T_READY := "ready"
## The owner of a seat -> referee: "I would like to flip card i."
const T_PICK := "pick"
## Referee -> everyone: "card i is flipped." The only message that moves a game.
const T_CONFIRM := "confirm"

# Both `pick` and `confirm` carry the turn they belong to under "k". Without it
# a client that is a moment behind — a browser on a slow machine, animating one
# turn while the referee has already confirmed the first pick of the next —
# would throw that confirm away with the turn that ended, and from then on it
# would be playing a different game from everybody else.

## A guest that never answers a ping is a tab that was closed during the fade.
const READY_TIMEOUT := 20.0
const PING_SECONDS := 0.4

var config: GameConfig
var state: GameState

var is_referee: bool = false
var local_peer_id: int = 0
var referee_peer_id: int = 0

## Picks confirmed for the turn being played and not flipped yet. The referee
## counts them when validating: without that, a player clicking three cards
## quickly would collect three confirms for a group of two.
var confirmed_picks: Array[int] = []

## Which turn this client is playing. It is the same number on every client at
## the same point in the stream, so it is what a confirm is tagged with.
var turn_number: int = 0

## Confirms for a turn this client has not reached yet. A slow client — a
## browser on a phone, say — can still be animating one turn while the referee
## has already confirmed the first pick of the next; those confirms wait here
## instead of being thrown away with the turn that ended.
var _ahead: Array[Dictionary] = []

var _players: Array[NetPlayer] = []
var _waiting: NetPlayer = null
var _arrived: Array[int] = []
var _abandoned: Array[int] = []
var _finished: bool = false


func _ready() -> void:
	Net.payload_received.connect(_on_payload)
	Rooms.updated.connect(_on_room_updated)
	Rooms.left.connect(_on_room_left)


# ---------------------------------------------------------------------------
# Setup, in the two halves game.gd needs
# ---------------------------------------------------------------------------

## Before the players exist: from here on the match knows who it is talking as.
func prepare(p_config: GameConfig) -> void:
	config = p_config
	local_peer_id = Net.my_peer_id
	referee_peer_id = _host_peer_id()
	is_referee = referee_peer_id != 0 and referee_peer_id == local_peer_id
	if referee_peer_id == 0:
		push_warning("Online match with no room behind it: nobody will referee.")


## After the board exists. Every seat is a NetPlayer on every client; what
## changes is only who is allowed to ask for a pick.
func bind_state(p_state: GameState, p_players: Array[Player]) -> void:
	state = p_state
	_players.clear()
	for player in p_players:
		if player is NetPlayer:
			_players.append(player as NetPlayer)
	if _players.size() != config.player_count():
		push_error("An online match needs every seat to be a NetPlayer.")


func owns_seat(index: int) -> bool:
	var slot := config.players[index]
	return not slot.is_bot() and slot.peer_id == local_peer_id


## Bots run on the referee and nowhere else: they ask for their turn down the
## same path a person does, so they add nothing at all to the protocol.
func referees_seat(index: int) -> bool:
	return is_referee and config.players[index].is_bot()


## Nobody flips a card until every client is in the game scene and listening.
## The referee keeps asking instead of waiting for one announcement, because a
## "ready" sent while the referee was still fading out of the lobby is a
## message nobody was there to hear.
func wait_for_everyone() -> void:
	if not is_referee:
		_send({"t": T_READY})
		return

	var expected := _remote_peers()
	if expected.is_empty():
		return

	var waited := 0.0
	while waited < READY_TIMEOUT:
		_send({"t": T_PING})
		await get_tree().create_timer(PING_SECONDS).timeout
		if not is_inside_tree():
			return
		waited += PING_SECONDS
		if _everyone_arrived(expected):
			return

	message.emit("Someone never made it to the table.")


# ---------------------------------------------------------------------------
# The pick stream
# ---------------------------------------------------------------------------

## A seat asks to flip a card. On the referee that is a local call; anywhere
## else it is one message across the relay. Either way nothing is flipped yet.
func request(index: int) -> void:
	if _finished:
		return
	if is_referee:
		_judge(local_peer_id, index, turn_number)
	else:
		_send({"t": T_PICK, "i": index, "k": turn_number})


## The seat whose turn it is announces it is listening. Answers with a pick
## that is already waiting, or -1 to mean "hold on until one arrives".
func claim(player: NetPlayer) -> int:
	if not confirmed_picks.is_empty():
		return confirmed_picks.pop_front()
	_waiting = player
	return -1


## Closes the turn and opens the next one.
##
## Anything still queued belonged to the turn that just ended — a turn cut short
## by `early_abort` can leave a confirm nobody will ever flip — so it goes.
## Anything that arrived tagged for the turn we are about to start was waiting
## for exactly this moment.
func end_turn() -> void:
	_waiting = null
	confirmed_picks.clear()
	turn_number += 1

	var still_ahead: Array[Dictionary] = []
	for entry in _ahead:
		if int(entry.get("k", -1)) == turn_number:
			confirmed_picks.append(int(entry.get("i", -1)))
		elif int(entry.get("k", -1)) > turn_number:
			still_ahead.append(entry)
	_ahead = still_ahead


func finish() -> void:
	_finished = true
	end_turn()


## The referee's verdict on a request. Everything that reaches the wire has
## already been through may_pick().
func _judge(from_peer: int, index: int, turn: int) -> void:
	if not is_referee or state == null:
		return
	# A request tagged with a turn that is over is a click that took the long
	# way round. Honouring it would flip a card its sender was not looking at.
	if turn != turn_number:
		return
	if not may_pick(from_peer, index):
		return
	_send({"t": T_CONFIRM, "i": index, "k": turn_number})
	_accept(index, turn_number)


## A confirmed pick, from the referee or from ourselves. It goes to the seat
## that is waiting for it, or into the queue until that seat asks — and if it is
## for a turn this client has not reached, it waits for that turn instead.
func _accept(index: int, turn: int) -> void:
	if state == null or index < 0 or index >= state.cards.size():
		return
	if turn > turn_number:
		_ahead.append({"k": turn, "i": index})
		return
	if turn < turn_number:
		# A confirm for a turn already closed here. It cannot be replayed
		# without desyncing, and it should never happen: say so out loud.
		push_warning("Dropped a confirm for turn %d while playing turn %d." % [turn, turn_number])
		return

	confirmed_picks.append(index)
	if _waiting == null:
		return
	var player := _waiting
	_waiting = null
	player.deliver(confirmed_picks.pop_front())


# ---------------------------------------------------------------------------
# The referee's rulebook
# ---------------------------------------------------------------------------

## True when this peer is allowed to flip this card right now.
##
## The only guard on the whole match: every other client trusts whatever comes
## out of here, and every request off the network was written by a client that
## may have been modified to ask for anything at all.
##
## The queue is the subtle part. `state` is the REFEREE'S state, and it only
## advances when its own turn loop flips a card, after the reveal animation.
## Three quick clicks all arrive before any of them has been flipped, so the
## state looks identical to all three; what tells them apart is how many picks
## are already confirmed and waiting.
func may_pick(from_peer: int, index: int) -> bool:
	if state == null or state.is_finished():
		return false

	var seat := state.current_player
	if seat < 0 or seat >= config.players.size():
		return false
	if config.players[seat].peer_id != from_peer:
		return false

	if not state.can_select(index):
		return false
	if confirmed_picks.has(index):
		return false
	if state.selection.size() + confirmed_picks.size() >= config.group_size:
		return false

	return true


# ---------------------------------------------------------------------------
# Incoming
# ---------------------------------------------------------------------------

func _on_payload(from_id: int, payload: Dictionary) -> void:
	match str(payload.get("t", "")):
		T_PING:
			if not is_referee and from_id == referee_peer_id:
				_send({"t": T_READY})
		T_READY:
			if is_referee and not _arrived.has(from_id):
				_arrived.append(from_id)
		T_PICK:
			_judge(from_id, int(payload.get("i", -1)), int(payload.get("k", -1)))
		T_CONFIRM:
			# Only the referee gets to move the game on. Anyone else claiming
			# to have confirmed something is a client that has been tampered with.
			if not is_referee and from_id == referee_peer_id:
				_accept(int(payload.get("i", -1)), int(payload.get("k", turn_number)))


## The relay resends the whole room whenever it changes, so a member who is no
## longer in the list is a player who left or dropped.
func _on_room_updated(_room: Dictionary) -> void:
	if state == null or _finished:
		return
	var present := Rooms.member_ids()
	for i in config.players.size():
		var slot := config.players[i]
		if slot.is_bot() or slot.peer_id == 0 or slot.peer_id == local_peer_id:
			continue
		if present.has(slot.peer_id) or _abandoned.has(i):
			continue
		_abandon(i)


## The seat stays, a bot moves into it. Only the referee changes anything: it
## takes ownership of the seat and grows a brain for it, and from then on that
## brain asks for picks down the very same path the person did. Every other
## client keeps replaying confirms and never notices the difference.
##
## The new bot starts with an empty memory, which is only fair: it did not see
## the cards the person who left had seen.
func _abandon(seat: int) -> void:
	_abandoned.append(seat)
	var slot := config.players[seat]
	message.emit("%s left. A bot takes the seat." % slot.display_name)
	if not is_referee:
		return
	slot.peer_id = local_peer_id
	if seat < _players.size():
		_players[seat].take_over()


## The room is gone. Without the referee there is no rules engine, so the match
## stops here rather than limping on out of sync.
func _on_room_left(reason: String) -> void:
	if _finished:
		return
	_finished = true
	aborted.emit(reason)


# ---------------------------------------------------------------------------
# The lobby side: freezing a match and handing it out
# ---------------------------------------------------------------------------

## Host, from the lobby. The deck is shuffled once, here, and travels with the
## config: a client that shuffled its own would be playing a different game.
static func broadcast_start(match_config: GameConfig) -> PackedInt32Array:
	var values := deck_to_wire(DeckBuilder.build(match_config))
	Rooms.send({
		"t": T_START,
		"config": match_config.to_dict(),
		"deck": values,
	})
	GameSettings.start_online_game(match_config, values)
	return values


## Guest, from the lobby. Returns false when the payload is not a usable start,
## so the lobby can stay put instead of loading a broken match.
static func accept_start(payload: Dictionary) -> bool:
	if str(payload.get("t", "")) != T_START:
		return false
	var raw: Variant = payload.get("config", {})
	if not (raw is Dictionary):
		return false
	var match_config := GameConfig.from_dict(raw as Dictionary)
	if not match_config.is_valid():
		push_error("The host sent a config this build cannot play: %s"
			% match_config.validation_error())
		return false
	var values := PackedInt32Array(payload.get("deck", PackedInt32Array()))
	if values.size() != match_config.total_cards:
		push_error("The host sent %d cards for a %d card board."
			% [values.size(), match_config.total_cards])
		return false
	GameSettings.start_online_game(match_config, values)
	return true


## A deck on the wire is just its values in order: everything else about a card
## is derived, so sending it would only be another way to disagree.
static func deck_to_wire(deck: Array[CardData]) -> PackedInt32Array:
	var values := PackedInt32Array()
	for card in deck:
		values.append(card.value)
	return values


## Rebuilds the deck the referee shuffled, in the order it sent.
##
## Only the value travels: the color is derived from the palette and the copy
## index is just which one of that group's cards this is. Order is the whole
## point — index 7 here has to be the same card as index 7 on the referee, or a
## confirm for 7 flips a different card on every screen.
static func deck_from_wire(values: PackedInt32Array, match_config: GameConfig) -> Array[CardData]:
	var deck: Array[CardData] = []
	var groups := match_config.group_count()
	var placed: Dictionary = {}
	for value in values:
		var copy: int = placed.get(value, 0)
		deck.append(CardData.new(value, CardPalette.color_for_value(value, groups), copy))
		placed[value] = copy + 1
	return deck


# ---------------------------------------------------------------------------
# Plumbing
# ---------------------------------------------------------------------------

func _send(payload: Dictionary) -> void:
	Rooms.send(payload)


func _host_peer_id() -> int:
	for member in Rooms.current.get("members", []):
		if member.get("host", false):
			return int(member.get("id", 0))
	return 0


## Everyone we are waiting for: one entry per device other than this one, bots
## included, since a bot sits on somebody's machine.
func _remote_peers() -> Array[int]:
	var peers: Array[int] = []
	for slot in config.players:
		if slot.peer_id == 0 or slot.peer_id == local_peer_id:
			continue
		if not peers.has(slot.peer_id):
			peers.append(slot.peer_id)
	return peers


func _everyone_arrived(expected: Array[int]) -> bool:
	for peer in expected:
		if not _arrived.has(peer):
			return false
	return true
