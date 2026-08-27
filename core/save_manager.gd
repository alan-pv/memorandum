class_name SaveManager
extends RefCounted

## Reads and writes the settings on disk.


const SAVE_PATH := "user://memorandum_settings.json"


static func save_data(data: Dictionary) -> bool:
	return false


static func load_data() -> Dictionary:
	return {}


static func clear_data() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
