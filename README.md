# Memorandum

A memory match game built with **Godot 4.7** (GDScript).

Flip cards, find the matching groups, and play against a bot with tunable
memory or against someone on the same keyboard.

![A match in progress](docs/gameplay.gif)

## What it does

- **Groups of 2 to 5 cards**, not just pairs — a group only counts when every
  card in it is face up.
- **Four difficulties** (Easy, Normal, Hard, Nightmare) defined as `.tres`
  resources, editable straight from the inspector.
- **A bot with a probabilistic memory**: it forgets what it has seen according
  to a `bot_memory` value between 0 and 1, so "hard" means a better opponent
  rather than a bigger board.
- **Local two-player mode**, taking turns on the same device.
- Sound effects, an animated shader background, a staggered UI intro and a
  shared theme.

|  |  |  |
|---|---|---|
| ![Choosing a game](docs/difficulty-menu.png) | ![Custom game settings](docs/custom-setup.png) | ![Two players sharing a keyboard](docs/board-mid-game.png) |
| Pick an opponent and a difficulty | Or set the board up yourself | Two players, same keyboard |

## Running it

Open the project folder with Godot 4.7 or newer and press <kbd>F5</kbd>.
There is nothing to install and no plugins to enable. The main scene is
`scenes/main_menu/main_menu.tscn`.

## Architecture

Four layers, with dependencies pointing only downwards:

```
  4. SCREENS    scenes/     what you see and click
  3. ACTORS     players/    who makes the decisions
  2. CORE       core/       pure logic, zero nodes, testable
  1. SERVICES   autoloads/  things that survive a scene change
```

The rules that hold it together:

- The **core** never mentions a node type, which is what makes it testable.
- **One coordinator** (`scenes/game/game.gd`) knows every other piece; nobody
  else knows more than its immediate neighbours.
- **Call downwards, emit upwards** — a child never reaches for its parent.
- **Single source of truth** — no state duplicated between model and view.
- **Base contract plus implementations** (`Player` → `HumanPlayer` /
  `BotPlayer`), so there is not a single `if is_bot:` in the project.
- **Configuration as data**, not code: the difficulties are `.tres` files, so
  balancing the game stopped being programming.

## Status

Everything playable is implemented. Nothing is persisted between runs yet —
records and preferences are lost when the game closes.

## License

MIT. See [LICENSE](LICENSE).
