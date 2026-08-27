class_name PlayerScoreEntry
extends PanelContainer

@onready var _name_label: Label = %NameLabel
@onready var _score_label: Label = %ScoreLabel
var is_active: bool = false

func setup(player_name: String, score: int = 0) -> void:
	_name_label.text = player_name
	set_score(score)

func set_score(score: int) -> void:
	_score_label.text = str(score)

func set_active(value: bool, animate: bool = true) -> void:
	if is_active == value and animate:
		return
	is_active = value

	if not animate:
		modulate.a = 1.0 if value else 0.45
		scale = Vector2.ONE * (1.06 if value else 1.0)
		return

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 1.0 if value else 0.45, 0.15)
	tween.tween_property(self, "scale", Vector2.ONE * (1.06 if value else 1.0), 0.15)

func _ready() -> void:
	pivot_offset = size * 0.5
	resized.connect(func() -> void: pivot_offset = size * 0.5)
