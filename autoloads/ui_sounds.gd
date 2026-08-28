extends Node
## Autoload. Hover and click sound plus feedback for every button.

func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)
	_scan(get_tree().root)


func _scan(node: Node) -> void:
	if node is BaseButton:
		_setup(node)
	for child in node.get_children():
		_scan(child)


func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		_setup(node)


func _setup(btn: BaseButton) -> void:
	if btn.has_meta("btnfx"):
		return
	btn.set_meta("btnfx", true)
	btn.mouse_entered.connect(_on_hover.bind(btn))
	btn.pressed.connect(_on_click.bind(btn))


func _fx_target(btn: Control) -> Control:
	var p := btn.get_parent()
	if p is Control and p.name == "Anim":
		return p
	return btn


func _on_hover(btn: BaseButton) -> void:
	if btn.disabled:
		return
	AudioManager.play_sfx(AudioManager.SFX_HOVER)
	_bump(btn)


func _on_click(btn: BaseButton) -> void:
	AudioManager.play_sfx(AudioManager.SFX_CLICK)
	_bump(btn)


func _bump(btn: BaseButton) -> void:
	var c := _fx_target(btn)
	# Stay out of the way while the scene is still playing its intro.
	if c.is_in_group("ui_intro_playing"):
		return

	c.pivot_offset = c.size * 0.5

	for key in ["bump_scale", "bump_rot"]:
		if not c.has_meta(key):
			continue
		var old: Variant = c.get_meta(key)
		if old is Tween and old.is_valid():
			old.kill()

	var dir: float = [-1.0, 1.0].pick_random()
	var rot := c.create_tween()
	rot.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	rot.tween_property(c, "rotation_degrees", 2.5 * dir, 0.1)
	rot.tween_property(c, "rotation_degrees", 0.0, 0.7)
	c.set_meta("bump_rot", rot)

	var sc := c.create_tween()
	sc.tween_property(c, "scale", Vector2(0.80, 1.1), 0.1)
	sc.tween_property(c, "scale", Vector2.ONE, 0.1)
	c.set_meta("bump_scale", sc)
