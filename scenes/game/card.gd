class_name Card
extends Control

## The visual of a card: paints itself, animates and reports clicks.


signal clicked(index: int)

const FLIP_TIME := 0.14

@onready var _pivot: Control = %Pivot
@onready var _back: Panel = %Back
@onready var _front: Panel = %Front
@onready var _value_label: Label = %ValueLabel

var index: int = -1

var data: CardData

var face_up: bool = false

var interactive: bool = true

var collected: bool = false


func _ready() -> void:
	resized.connect(_update_pivot)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	_update_pivot()
	_apply_face(face_up)


func _update_pivot() -> void:
	if _pivot != null:
		_pivot.pivot_offset = _pivot.size * 0.5


func setup(p_data: CardData, p_index: int) -> void:
	data = p_data
	index = p_index
	face_up = false
	collected = false
	_paint_front()
	_apply_face(false)


func _paint_front() -> void:
	if data == null:
		return
	_value_label.text = data.get_label()
	# duplicate(): the theme StyleBox is shared by every card.
	var style := _front.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	style.bg_color = data.color
	_front.add_theme_stylebox_override("panel", style)
	_value_label.add_theme_color_override("font_color", CardPalette.text_color_for(data.color))


func _apply_face(show_front: bool) -> void:
	_front.visible = show_front
	_back.visible = not show_front


func flip_to(new_face_up: bool, animate: bool = true) -> void:
	if face_up == new_face_up:
		return
	face_up = new_face_up

	if not animate: 
		_apply_face(face_up)
		return

	var tween := create_tween()
	tween.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(_pivot, "scale:x", 0.0, FLIP_TIME)
	tween.tween_callback(_apply_face.bind(face_up))
	tween.tween_property(_pivot, "scale:x", 1.0, FLIP_TIME).set_ease(Tween.EASE_OUT)

	await tween.finished


func play_match() -> void:
	collected = true
	interactive = false

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_pivot, "scale", Vector2(1.15, 1.15), 0.12) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_pivot, "modulate:a", 1.0, 0.12)
	tween.chain()
	tween.set_parallel(true)
	tween.tween_property(_pivot, "scale", Vector2(0.6, 0.6), 0.22) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(_pivot, "modulate:a", 0.0, 0.22)

	await tween.finished
	# Transparent but still VISIBLE to the container: with visible = false the
	# GridContainer would re-flow every other card.
	_pivot.modulate.a = 0.0


func play_fail() -> void:
	var tween := create_tween()
	for offset in [8.0, -6.0, 4.0, -2.0, 0.0]:
		tween.tween_property(_pivot, "position:x", offset, 0.04)
	await tween.finished


func reset_visuals() -> void:
	collected = false
	interactive = true
	visible = true
	_pivot.scale = Vector2.ONE
	_pivot.position = Vector2.ZERO
	_pivot.modulate.a = 1.0
	face_up = false
	_apply_face(false)


func _gui_input(event: InputEvent) -> void:
	if not interactive or collected:
		return
	if event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT \
			and event.pressed:
		accept_event()
		clicked.emit(index)


func _on_mouse_entered() -> void:
	if not interactive or collected or face_up:
		return
	AudioManager.play_sfx(AudioManager.SFX_HOVER)
	
	var tween := create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	
	# "Levantada": escala un poco y sube en Y
	tween.tween_property(_pivot, "scale", Vector2(1.08, 1.08), 0.12)
	tween.tween_property(_pivot, "position:y", -6.0, 0.12)
	
	# Wobble: left -> right -> centre.
	var _sign = 1.0 if randf() > 0.5 else -1.0
	tween.chain().tween_property(_pivot, "rotation_degrees", 4.0 * _sign, 0.1) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.chain().tween_property(_pivot, "rotation_degrees", -2.0 * _sign, 0.08) \
		.set_trans(Tween.TRANS_SINE)
	tween.chain().tween_property(_pivot, "rotation_degrees", 0.0, 0.08) \
		.set_trans(Tween.TRANS_SINE)

func _on_mouse_exited() -> void:
	if collected:
		return
	var tween := create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(_pivot, "scale", Vector2.ONE, 0.1)
	tween.tween_property(_pivot, "position:y", 0.0, 0.1)
	tween.tween_property(_pivot, "rotation_degrees", 0.0, 0.1)
