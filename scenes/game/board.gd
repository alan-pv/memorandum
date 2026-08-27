class_name Board
extends Control

## The table: lays out the cards and turns indices into animations.


signal card_clicked(index: int)

@export var card_scene: PackedScene

const MIN_CARD_SIZE := Vector2(52.0, 70.0)
const MAX_CARD_SIZE := Vector2(120.0, 160.0)

@onready var _grid: GridContainer = %Grid

var _cards: Array[Card] = []


func build(deck: Array[CardData]) -> void:
	clear()
	if card_scene == null:
		push_error("Board: card_scene is not assigned in the inspector.")
		return

	_grid.columns = maxi(1, compute_columns(deck.size()))

	for i in deck.size():
		var card := card_scene.instantiate() as Card

		card.clicked.connect(_on_card_clicked)
		# add_child before setup: @onready vars do not exist until the node is in the tree.
		_grid.add_child(card)
		_cards.append(card)
		card.setup(deck[i], i)

	_resize_cards()


func compute_columns(count: int) -> int:
	if count <= 0:
		return 1

	var board_size := size
	if board_size.x <= 0.0 or board_size.y <= 0.0:
		board_size = get_viewport_rect().size

	var container_aspect := board_size.x / maxf(board_size.y, 1.0)
	var card_aspect := 3.0 / 4.0 
	var columns := int(round(sqrt(float(count) * container_aspect / card_aspect)))
	return clampi(columns, 1, count)


func _resize_cards() -> void:
	if _cards.is_empty():
		return
	var columns := maxi(1, _grid.columns)
	var rows := int(ceil(float(_cards.size()) / float(columns)))
	var separation := Vector2(
		_grid.get_theme_constant("h_separation"),
		_grid.get_theme_constant("v_separation")
	)
	var available := size - Vector2(separation.x * (columns - 1), separation.y * (rows - 1))
	var per_card := Vector2(available.x / columns, available.y / rows)

	var scale_factor := minf(per_card.x / 3.0, per_card.y / 4.0)
	var card_size := Vector2(3.0, 4.0) * scale_factor
	card_size = card_size.clamp(MIN_CARD_SIZE, MAX_CARD_SIZE)

	for card in _cards:
		card.custom_minimum_size = card_size


func _ready() -> void:
	resized.connect(_resize_cards)


func reveal(index: int) -> void:
	var card := get_card(index)
	if card == null:
		return
	AudioManager.play_sfx(AudioManager.SFX_FLIP)
	await card.flip_to(true)


func hide_cards(indices: Array[int]) -> void:
	if indices.is_empty():
		return
	for i in indices:
		var card := get_card(i)
		if card != null:
			card.play_fail()
	
	for i in indices:
		var card := get_card(i)
		if card == null:
			continue
		if i == indices[indices.size() - 1]:
			await card.flip_to(false)
		else:
			card.flip_to(false)
	


func collect(indices: Array[int]) -> void:
	if indices.is_empty():
		return
	for i in indices:
		var card := get_card(i)
		if card == null:
			continue
		if i == indices[indices.size() - 1]:
			await card.play_match()
		else:
			card.play_match()
	AudioManager.play_sfx(AudioManager.SFX_MATCH)


func set_interactive(value: bool) -> void:
	for card in _cards:
		card.interactive = value and not card.collected


func get_card(index: int) -> Card:
	if index < 0 or index >= _cards.size():
		push_warning("Board: card index out of range: %d" % index)
		return null
	return _cards[index]


func preview_all(seconds: float) -> void:
	if seconds <= 0.0:
		return
	for card in _cards:
		card.flip_to(true, false)
	await get_tree().create_timer(seconds).timeout
	for card in _cards:
		card.flip_to(false, false)


func clear() -> void:
	for card in _cards:
		card.queue_free()
	_cards.clear()


func _on_card_clicked(index: int) -> void:
	card_clicked.emit(index)
