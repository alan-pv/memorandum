class_name ChatPanel
extends PanelContainer

## A chat log and a box to type in. Knows nothing about networks: it emits what
## was typed and shows whatever it is told to show, so the same widget serves a
## lobby, a match or a single-player tutorial.
##
## Pair it with something that carries the lines around — RoomChat does it over
## the relay — or drive it by hand from anywhere.


## Somebody pressed Enter or Send. Already trimmed and cut to `max_length`.
signal submitted(text: String)

## A line landed in the log, whoever wrote it. Whatever frames the panel uses
## it to notice what the reader missed while looking elsewhere.
signal line_added

## Kept small on purpose: a log nobody scrolls does not need to be a transcript.
@export var max_lines: int = 80

@export var max_length: int = 200

@export var title: String = "Chat"

## How tall the log is before it starts scrolling.
@export var log_height: int = 180

@export var placeholder: String = "Say something..."

## Lines nobody wrote: arrivals, departures, warnings.
@export var system_color: Color = Color(0.70, 0.70, 0.70, 0.75)

var _log: RichTextLabel
var _field: LineEdit
var _send_button: Button


func _ready() -> void:
	_build()


func _build() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)

	if not title.is_empty():
		var caption := Label.new()
		caption.text = title
		caption.add_theme_font_size_override("font_size", 20)
		box.add_child(caption)

	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	# The log follows the newest line only while the reader is already at the
	# bottom, so scrolling up to re-read something is not yanked away.
	_log.scroll_following = true
	_log.selection_enabled = true
	_log.focus_mode = Control.FOCUS_NONE
	_log.custom_minimum_size = Vector2(0, log_height)
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_log)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)

	_field = LineEdit.new()
	_field.placeholder_text = placeholder
	_field.max_length = max_length
	_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_field.text_submitted.connect(_on_submitted)
	row.add_child(_field)

	_send_button = Button.new()
	_send_button.text = "Send"
	_send_button.pressed.connect(func() -> void: _on_submitted(_field.text))
	row.add_child(_send_button)


# ---------------------------------------------------------------------------
# Showing lines
# ---------------------------------------------------------------------------

## One line somebody said. The text is added as text, never parsed, so a player
## typing bbcode gets brackets on screen instead of colouring everyone's chat.
func push_line(author: String, text: String, color: Color = Color.WHITE) -> void:
	if _log == null:
		return
	_log.push_color(color)
	_log.add_text("%s: " % author)
	_log.pop()
	_log.add_text(text)
	_log.newline()
	_trim()
	line_added.emit()


func push_system(text: String) -> void:
	if _log == null:
		return
	_log.push_color(system_color)
	_log.add_text(text)
	_log.pop()
	_log.newline()
	_trim()
	line_added.emit()


func clear() -> void:
	if _log != null:
		_log.clear()


func focus_input() -> void:
	if _field != null:
		_field.grab_focus()


## True while the caret is in the box. A screen that answers to keystrokes asks
## before acting on one, and leaves them to whoever is mid-sentence.
func is_typing() -> bool:
	return _field != null and _field.has_focus()


func stop_typing() -> void:
	if _field != null:
		_field.release_focus()


## Locks the box without hiding the log: there is still something to read when
## the room is gone or the connection dropped.
func set_input_enabled(value: bool) -> void:
	if _field == null:
		return
	_field.editable = value
	_send_button.disabled = not value


func _on_submitted(text: String) -> void:
	var clean := text.strip_edges().substr(0, max_length)
	_field.clear()
	_field.grab_focus()
	if clean.is_empty():
		return
	submitted.emit(clean)


func _trim() -> void:
	while _log.get_paragraph_count() > max_lines:
		_log.remove_paragraph(0)
