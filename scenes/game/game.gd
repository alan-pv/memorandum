extends Control

## Match coordinator: sets it up and drives the turn loop.


@onready var board: Board = %Board
@onready var hud: HUD = %HUD
@onready var pause_menu: PauseMenu = %PauseMenu

var config: GameConfig
var state: GameState
var players: Array[Player] = []

## Only exists in an online match. When it is null the whole file behaves
## exactly as it did before the network existed.
var online: OnlineMatch = null

var turns_taken: int = 0
var elapsed_seconds: float = 0.0

var _running: bool = false


func _ready() -> void:
	config = GameSettings.config
	if config == null:
		push_warning("No GameConfig in GameSettings: falling back to a default one.")
		config = GameConfig.new()
		GameSettings.config = config

	if config.online:
		_create_online()

	_create_players()
	_create_state()
	_connect_signals()

	if online != null:
		online.bind_state(state, players)

	hud.setup(config)
	board.build(state.cards)
	hud.set_remaining(state.remaining_groups())

	if state.cards.is_empty():
		hud.show_message("The deck is empty.\nImplement DeckBuilder.build()", 0.0)
		return

	_run_game()


## Sets up the network side before anything else exists, so the seats can ask
## it who they belong to. The room it reads was left there by the lobby.
func _create_online() -> void:
	online = OnlineMatch.new()
	online.name = "OnlineMatch"
	add_child(online)
	online.prepare(config)
	online.message.connect(_on_online_message)
	online.aborted.connect(_on_online_aborted)
	pause_menu.set_online(true)


func _create_players() -> void:
	players.clear()

	for i in config.players.size():
		var slot := config.players[i]
		var player := _player_for_slot(slot)
		player.name = "Seat%d" % i
		player.setup(i, slot)
		add_child(player)
		if player is NetPlayer:
			(player as NetPlayer).attach(online, online.owns_seat(i), online.referees_seat(i))
		players.append(player)


## Online, every seat is a NetPlayer — yours, theirs and the bots alike. They
## all wait for the same confirms, so every client runs the identical loop.
func _player_for_slot(slot: PlayerSlot) -> Player:
	if config.online:
		return NetPlayer.new()

	match slot.kind:
		PlayerSlot.Kind.BOT:
			return BotPlayer.new()
		PlayerSlot.Kind.REMOTE:
			push_error("A remote seat needs an online match: this one is local.")
			return HumanPlayer.new()
		_:
			return HumanPlayer.new()


func _create_state() -> void:
	# Online the deck was shuffled once, by the referee, and travelled with the
	# config. Shuffling a second one here would be playing a different game.
	var deck: Array[CardData] = []
	if config.online:
		deck = OnlineMatch.deck_from_wire(GameSettings.online_deck, config)
	else:
		deck = DeckBuilder.build(config)
	state = GameState.new()
	state.setup(config, deck, players.size())


func _connect_signals() -> void:
	board.card_clicked.connect(_on_board_card_clicked)
	state.score_changed.connect(hud.set_score)
	state.turn_changed.connect(hud.set_turn)
	hud.pause_pressed.connect(_open_pause)
	pause_menu.resume_requested.connect(_close_pause)
	pause_menu.restart_requested.connect(_restart)
	pause_menu.quit_requested.connect(_quit_to_menu)


func _on_board_card_clicked(index: int) -> void:
	for player in players:
		player.on_card_clicked(index)


func _run_game() -> void:
	_running = true
	hud.set_turn(state.current_player)

	if online != null:
		hud.show_message("Waiting for everyone...", 0.0)
		await online.wait_for_everyone()
		if not _running:
			return
		hud.show_message("", 0.0)

	while _running and not state.is_finished():
		await _play_turn()

	if not _running:
		return
	_finish_game()


func _play_turn() -> void:
	var player := players[state.current_player]
	state.clear_selection()
	board.set_interactive(player.is_human)
	hud.set_turn(state.current_player)

	for pick_number in config.group_size:
		# call_deferred: a bot with think_time 0 would emit picked before the await listens.
		player.request_pick.call_deferred(state)
		var index: int = await player.picked
		if not _running:
			return

		state.select(index)
		await board.reveal(index)
		if not _running:
			return

		for observer in players:
			observer.observe(index, state.cards[index])

		if config.early_abort and not GameRules.is_selection_viable(_selected_cards()):
			break

	var matched := state.resolve_selection()
	turns_taken += 1
	var picked_indices := state.selection.duplicate()

	if matched:
		await board.collect(picked_indices)
		for observer in players:
			observer.forget(picked_indices)
		hud.set_remaining(state.remaining_groups())
		hud.show_message("Group complete!", 0.8)
	else:
		
		await get_tree().create_timer(config.reveal_time).timeout
		AudioManager.play_sfx(AudioManager.SFX_FAIL)
		if not _running:
			return
		await board.hide_cards(picked_indices)

	if not _running:
		return

	if online != null:
		online.end_turn()
	state.end_turn(matched)


func _selected_cards() -> Array[CardData]:
	var chosen: Array[CardData] = []
	for i in state.selection:
		chosen.append(state.cards[i])
	return chosen


func _finish_game() -> void:
	_running = false
	board.set_interactive(false)
	if online != null:
		online.finish()
	

	GameSettings.last_result = {
		"scores": state.scores.duplicate(),
		"names": config.player_names,
		"winner": GameRules.winner_index(state.scores),
		"turns": turns_taken,
		"seconds": elapsed_seconds,
	}
	await get_tree().create_timer(0.6).timeout
	SceneSwitcher.go_to(SceneSwitcher.RESULTS, false)
	AudioManager.play_sfx(AudioManager.SFX_WIN)


func _process(delta: float) -> void:
	if not _running:
		return
	elapsed_seconds += delta
	hud.set_time(elapsed_seconds)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if pause_menu.visible:
			_close_pause()
		else:
			_open_pause()


func _open_pause() -> void:
	pause_menu.open()


func _close_pause() -> void:
	pause_menu.close()


func _restart() -> void:
	_stop()
	pause_menu.close()
	SceneSwitcher.go_to(SceneSwitcher.GAME, false)


func _quit_to_menu() -> void:
	_stop()
	pause_menu.close()
	if online != null:
		Rooms.leave()
	SceneSwitcher.go_to(SceneSwitcher.MAIN_MENU, false)


func _on_online_message(text: String) -> void:
	hud.show_message(text, 2.0)


## The referee left, or the connection died. There is no rules engine any more,
## so the match stops here instead of drifting out of sync in silence.
func _on_online_aborted(reason: String) -> void:
	if not _running:
		return
	_stop()
	board.set_interactive(false)
	hud.show_message(reason, 0.0)
	await get_tree().create_timer(2.5).timeout
	SceneSwitcher.go_to(SceneSwitcher.MAIN_MENU, false)


func _stop() -> void:
	_running = false
	for player in players:
		player.cancel_pick()
