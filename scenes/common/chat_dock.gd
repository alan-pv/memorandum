class_name ChatDock
extends Control

## The chat as a window in the bottom left corner: a bar you click to fold it
## away, and a red dot on that bar when somebody spoke while it was folded.
##
## It is a ChatPanel with somewhere to live, and it knows about networks exactly
## as much as the panel does — nothing:
##
##     var dock := ChatDock.new()
##     add_child(dock)
##     dock.panel.push_line("Somebody", "hello")
##
## Inside a room, `RoomChat.spawn(self)` builds one of these and wires it to the
## relay in a single line. It floats over whatever the screen already is, so no
## layout has to make room for it.


signal toggled(is_open: bool)

const BADGE_SIZE := 12.0

## Air between the bar and the panel. It belongs to the window rather than to
## the column, or folding would leave the gap behind under the bar.
const GAP := 6.0

@export var title: String = "Chat"

## How wide the window is. The bar is the same width, folded or not.
@export var width: int = 340

@export var log_height: int = 190

## Distance from the corner of the screen.
@export var margin: int = 16

@export var start_open: bool = true

@export var badge_color: Color = Color(0.85, 0.24, 0.26)

@export var fold_time: float = 0.18

## Made on first use rather than in `_ready()`, so a caller holding a fresh dock
## can reach the panel without waiting for the tree.
var panel: ChatPanel:
	get:
		if _panel == null:
			_panel = ChatPanel.new()
		return _panel

var _panel: ChatPanel

## Clips the panel, which is what turns folding into a slide instead of a
## disappearance between two frames.
var _window: Control

## Holds the bar and the window. Its width is the chat's while it is open, and
## nothing while it is folded, which lets the bar shrink back to a button.
var _column: VBoxContainer

var _bar: Button
var _badge: Panel
var _is_open: bool = true
var _unread: int = 0
var _fold_tween: Tween
var _pulse_tween: Tween


func _ready() -> void:
	# Usable over a paused game, and never swept into a scene's intro anim.
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("no_intro")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The dock is the whole screen so the corner can be found; everything in it
	# that is not the chat lets clicks through to the game underneath.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	_apply(start_open, false)


# ---------------------------------------------------------------------------
# Asking and telling
# ---------------------------------------------------------------------------

func toggle() -> void:
	_apply(not _is_open, true)


func open() -> void:
	if not _is_open:
		_apply(true, true)


func close() -> void:
	if _is_open:
		_apply(false, true)


func is_open() -> bool:
	return _is_open


func unread() -> int:
	return _unread


## Marks everything as read without opening: a screen replaying a backlog
## nobody has missed calls this once it is done.
func clear_unread() -> void:
	_unread = 0
	_show_badge(false)


# ---------------------------------------------------------------------------
# Building
# ---------------------------------------------------------------------------

func _build() -> void:
	var margins := MarginContainer.new()
	margins.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margins.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "top", "right", "bottom"]:
		margins.add_theme_constant_override("margin_" + side, margin)
	add_child(margins)

	# Pinned to the bottom by the rows, to the left by the columns, and no wider
	# than the chat itself, so the rest of the corner stays clickable.
	var rows := VBoxContainer.new()
	rows.alignment = BoxContainer.ALIGNMENT_END
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margins.add_child(rows)

	var columns := HBoxContainer.new()
	columns.alignment = BoxContainer.ALIGNMENT_BEGIN
	columns.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_child(columns)

	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation", 0)
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	columns.add_child(_column)

	# A plain Button, so it takes the project's own hover, its click sound and
	# whatever else the theme does to buttons, in every project it is copied to.
	_bar = Button.new()
	_bar.tooltip_text = "Show or hide the chat"
	_bar.pressed.connect(toggle)
	_column.add_child(_bar)

	_badge = _build_badge()
	_bar.add_child(_badge)

	_window = Control.new()
	_window.clip_contents = true
	_window.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.add_child(_window)

	panel.title = ""
	panel.log_height = log_height
	panel.line_added.connect(_on_line_added)
	# Held against the bottom edge of the window at its full height, so growing
	# the window slides the panel up into view rather than stretching it.
	panel.anchor_left = 0.0
	panel.anchor_right = 1.0
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	_window.add_child(panel)


## A dot in the top right corner of the bar. It is a Panel rather than a
## texture so it needs no asset: a square with the corners rounded to half its
## side is a circle, and the dark ring keeps it readable on any button colour.
func _build_badge() -> Panel:
	var dot := Panel.new()

	var box := StyleBoxFlat.new()
	box.bg_color = badge_color
	box.set_corner_radius_all(int(BADGE_SIZE / 2.0))
	box.set_border_width_all(2)
	box.border_color = Color(0.0, 0.0, 0.0, 0.5)
	dot.add_theme_stylebox_override("panel", box)

	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot.anchor_left = 1.0
	dot.anchor_right = 1.0
	dot.offset_left = -BADGE_SIZE - 4.0
	dot.offset_right = -4.0
	dot.offset_top = 4.0
	dot.offset_bottom = 4.0 + BADGE_SIZE
	# Scaling reads as a pulse only while it grows from the middle.
	dot.pivot_offset = Vector2(BADGE_SIZE, BADGE_SIZE) / 2.0
	dot.visible = false
	return dot


# ---------------------------------------------------------------------------
# Folding
# ---------------------------------------------------------------------------

func _apply(value: bool, animate: bool) -> void:
	_is_open = value
	var height := _panel_height()
	panel.offset_left = 0.0
	panel.offset_right = 0.0
	panel.offset_top = -height
	panel.offset_bottom = 0.0
	_bar.text = "%s  %s" % [title, "-" if _is_open else "+"]

	if _is_open:
		clear_unread()
		panel.visible = true

	if _fold_tween != null:
		_fold_tween.kill()

	# Open, the window is as tall as the panel and the column as wide as the
	# chat. Folded, both go to nothing and the bar is left at its own size.
	var tall := height + GAP if _is_open else 0.0
	var wide := float(width) if _is_open else 0.0
	if not animate:
		_window.custom_minimum_size.y = tall
		_column.custom_minimum_size.x = wide
		panel.visible = _is_open
		toggled.emit(_is_open)
		return

	_fold_tween = create_tween().set_parallel(true)
	_fold_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_fold_tween.tween_property(_window, "custom_minimum_size:y", tall, fold_time)
	_fold_tween.tween_property(_column, "custom_minimum_size:x", wide, fold_time)
	# Hidden only once it is out of sight, so a fold is never a blink.
	_fold_tween.finished.connect(func() -> void: panel.visible = _is_open)

	if _is_open:
		panel.focus_input()
	toggled.emit(_is_open)


## What the panel asks for: the log, the box to type in and everything the
## theme puts around them. Read every time, so a theme change is respected.
func _panel_height() -> float:
	return maxf(panel.get_combined_minimum_size().y, float(log_height))


# ---------------------------------------------------------------------------
# The dot
# ---------------------------------------------------------------------------

func _on_line_added() -> void:
	if _is_open:
		return
	_unread += 1
	_show_badge(true)


func _show_badge(on: bool) -> void:
	if _pulse_tween != null:
		_pulse_tween.kill()
		_pulse_tween = null
	_badge.scale = Vector2.ONE
	_badge.visible = on
	if not on:
		return
	_pulse_tween = create_tween().set_loops()
	_pulse_tween.tween_property(_badge, "scale", Vector2(1.3, 1.3), 0.5).set_trans(Tween.TRANS_SINE)
	_pulse_tween.tween_property(_badge, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_SINE)


## Escape belongs to whoever is mid-sentence: it lets go of the box instead of
## reaching the screen behind, which is usually a pause menu.
func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel") or not panel.is_typing():
		return
	get_viewport().set_input_as_handled()
	panel.stop_typing()
