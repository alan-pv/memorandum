extends Node
## Autoload. Conecta sonido + animación a TODOS los botones del juego,
## sin importar en qué escena estén ni cuándo se creen.

func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)
	_scan_existing(get_tree().root)

func _scan_existing(node: Node) -> void:
	if node is Button or node is TextureButton:
		connect_signals(node)
	for child in node.get_children():
		_scan_existing(child)
	
func _on_node_added(node: Node) -> void:
	if node is Button or node is TextureButton:
		connect_signals(node)

func connect_signals(node: Control) -> void:
	# Evita conexiones dobles si el nodo reingresa al árbol
	if node.pressed.is_connected(_on_click):
		return

	node.mouse_entered.connect(_on_hover)
	node.pressed.connect(_on_click)
	node.mouse_entered.connect(animate_hover.bind(node))
	node.pressed.connect(animate_hover.bind(node))
	node.mouse_filter = Control.MOUSE_FILTER_STOP

func _on_hover() -> void:
	AudioManager.play_sfx(AudioManager.SFX_HOVER)

func _on_click() -> void:
	AudioManager.play_sfx(AudioManager.SFX_CLICK)

func animate_hover(node: Control) -> void:
	if node.get_parent().name == "Anim":
		node = node.get_parent()

	var tween = node.create_tween()
	tween.set_trans(Tween.TRANS_ELASTIC)
	tween.set_ease(Tween.EASE_OUT)

	node.pivot_offset = node.size / 2

	var _sign = randf_range(1, -1)

	tween.tween_property(node, "rotation_degrees", 2.5 * _sign, 0.1)
	tween.tween_property(node, "rotation_degrees", 0.0, 0.7)

	var scale_tween = node.create_tween()
	scale_tween.tween_property(node, "scale", Vector2(0.80, 1.1), 0.1)
	scale_tween.tween_property(node, "scale", Vector2(1.0, 1.0), 0.1)
