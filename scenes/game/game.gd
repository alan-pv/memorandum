extends Control

## Match coordinator: sets it up and drives the turn loop.


@onready var board: Board = %Board
@onready var hud: HUD = %HUD
@onready var pause_menu: PauseMenu = %PauseMenu

var config: GameConfig
var state: GameState
var players: Array[Player] = []

var turns_taken: int = 0
var elapsed_seconds: float = 0.0

var _running: bool = false


func _ready() -> void:
	config = GameSettings.config
	if config == null:
		push_warning("No GameConfig in GameSettings: falling back to a default one.")
		config = GameConfig.new()
		GameSettings.config = config

	_create_players()
	_create_state()
	_connect_signals()

	hud.setup(config)
	board.build(state.cards)
	hud.set_remaining(state.remaining_groups())

	if state.cards.is_empty():
		hud.show_message("The deck is empty.\nImplement DeckBuilder.build()", 0.0)
		return

	_run_game()


func _create_players() -> void:
	players.clear()

	var human := HumanPlayer.new()
	human.name = "Player1"
	human.setup(0, config.player_names[0], config)
	add_child(human)
	players.append(human)

	var second: Player
	if config.opponent == GameConfig.Opponent.BOT:
		second = BotPlayer.new()
		second.name = "Bot"
	else:
		second = HumanPlayer.new()
		second.name = "Player2"
	second.setup(1, config.player_names[1], config)
	add_child(second)
	players.append(second)


func _create_state() -> void:
	var deck := DeckBuilder.build(config)
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
		if player is HumanPlayer:
			(player as HumanPlayer).on_card_clicked(index)


func _run_game() -> void:
	_running = true
	hud.set_turn(state.current_player)

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

	state.end_turn(matched)


func _selected_cards() -> Array[CardData]:
	var chosen: Array[CardData] = []
	for i in state.selection:
		chosen.append(state.cards[i])
	return chosen


func _finish_game() -> void:
	_running = false
	board.set_interactive(false)
	

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
	SceneSwitcher.go_to(SceneSwitcher.MAIN_MENU, false)


func _stop() -> void:
	_running = false
	for player in players:
		player.cancel_pick()
