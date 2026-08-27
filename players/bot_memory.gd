class_name BotMemory
extends RefCounted

## What the bot remembers about the board, forgetting according to retention.


var retention: float = 0.5

var _known: Dictionary = {}


func _init(p_retention: float = 0.5) -> void:
	retention = clampf(p_retention, 0.0, 1.0)


func observe(index: int, value: int) -> void:
	if randf() <= retention:
		_known[index] = value


func forget(indices: Array[int]) -> void:
	for i in indices:
		_known.erase(i)


func indices_with_value(value: int, exclude: Array[int]) -> Array[int]:
	var result: Array[int] = []
	for i in _known:
		if (_known[i] == value) and (not exclude.has(i)):
			result.append(i)
	return result


func find_complete_group(group_size: int) -> Array[int]:
	var by_value: Dictionary = {}
	for index in _known:
		var v: int = _known[index]
		if not by_value.has(v):
			var list: Array[int] = []
			by_value[v] = list
		by_value[v].append(index)
	for index in by_value:
		if by_value[index].size() == group_size:
			return by_value[index]
	return []


func unknown_from(available: Array[int]) -> Array[int]:
	var unknown := []
	for i in available:
		if not _known.has(i):
			unknown.append(i)
	return unknown


func size() -> int:
	return _known.size()


func clear() -> void:
	_known.clear()
