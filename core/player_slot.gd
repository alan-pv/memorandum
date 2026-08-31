class_name PlayerSlot
extends Resource

## One seat at the table: who sits there and how they play.


enum Kind {
	HUMAN,  ## A person on this device.
	BOT,    ## The machine, tuned by memory and think time.
	REMOTE, ## A person on another device. Only used from the online mode on.
}

const MEMORY_LABELS := {
	0.25: "Forgetful",
	0.50: "Average",
	0.75: "Sharp",
	1.00: "Perfect",
}

@export var kind: Kind = Kind.HUMAN

@export var display_name: String = "Player"

@export_range(0.0, 1.0, 0.05) var bot_memory: float = 0.5

@export_range(0.0, 2.0, 0.1) var bot_think_time: float = 0.6

## Peer id of the device that owns this seat. 0 while offline.
@export var peer_id: int = 0


static func human(p_name: String) -> PlayerSlot:
	var slot := PlayerSlot.new()
	slot.kind = Kind.HUMAN
	slot.display_name = p_name
	return slot


static func bot(p_name: String, memory: float = 0.5, think_time: float = 0.6) -> PlayerSlot:
	var slot := PlayerSlot.new()
	slot.kind = Kind.BOT
	slot.display_name = p_name
	slot.bot_memory = memory
	slot.bot_think_time = think_time
	return slot


func is_bot() -> bool:
	return kind == Kind.BOT


## Closest label for this bot's memory, for the setup screens.
func memory_label() -> String:
	var best_key: float = 0.5
	var best_distance := INF
	for key: float in MEMORY_LABELS:
		var distance: float = absf(bot_memory - key)
		if distance < best_distance:
			best_distance = distance
			best_key = key
	return MEMORY_LABELS[best_key]


func to_dict() -> Dictionary:
	return {
		"kind": int(kind),
		"name": display_name,
		"memory": bot_memory,
		"think": bot_think_time,
		"peer": peer_id,
	}


## Rebuilds a slot from the wire. Every field is checked: the sender may be a
## modified client, so a missing or wrong-typed key must fall back, never crash.
static func from_dict(data: Dictionary) -> PlayerSlot:
	var slot := PlayerSlot.new()
	slot.kind = clampi(int(data.get("kind", Kind.HUMAN)), 0, Kind.size() - 1) as Kind
	slot.display_name = str(data.get("name", "Player")).substr(0, 24)
	slot.bot_memory = clampf(float(data.get("memory", 0.5)), 0.0, 1.0)
	slot.bot_think_time = clampf(float(data.get("think", 0.6)), 0.0, 2.0)
	slot.peer_id = int(data.get("peer", 0))
	return slot


func _to_string() -> String:
	return "PlayerSlot(%s, %s)" % [Kind.keys()[kind], display_name]
