# Memorandum

A memory match game built with **Godot 4.7** (GDScript).

Flip cards, find the matching groups, and beat either a bot with tunable memory
or a friend on the same device.

## Features

- **Groups of 2 to 5 cards**, not just pairs — a match only counts when every
  card of the group is face up.
- **Four difficulties** (Easy, Normal, Hard, Nightmare) defined as `.tres`
  resources, editable straight from the inspector.
- **Custom setup** screen: board size, group size, reveal time, opponent and
  bot memory.
- **Bot opponent** with a probabilistic memory model — it forgets what it saw
  according to a `bot_memory` value between 0 and 1.
- **Local two-player mode**, taking turns on the same device.
- Sound effects, animated shader background and a shared UI theme.

## Running it

Open the project folder with Godot 4.7 or newer and press <kbd>F5</kbd>.
The main scene is `scenes/main_menu/main_menu.tscn`.

## Architecture

Four layers, with dependencies pointing only downwards:

```
  4. SCREENS    scenes/     what you see and click
  3. ACTORS     players/    who makes the decisions
  2. CORE       core/       pure logic, zero nodes, testable
  1. SERVICES   autoloads/  things that survive a scene change
```

Rules that hold it together:

- The **core** never mentions a node type, which is what makes it testable.
- **One coordinator** (`scenes/game/game.gd`) knows every other piece; nobody
  else knows more than its immediate neighbours.
- **Call downwards, emit upwards** — a child never reaches for its parent.
- **Single source of truth** — no state duplicated between model and view.
- **Base contract plus implementations** (`Player` → `HumanPlayer` /
  `BotPlayer`), so there is not a single `if is_bot:` in the project.
- **Configuration as data**, not code.

## Status

Everything playable is implemented. `core/save_manager.gd` is deliberately left
unimplemented: records and preferences are not persisted yet.
