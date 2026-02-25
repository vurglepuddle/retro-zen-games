# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A **zen toybox** app built with **Godot Engine 4.3** using **GDScript**. The app launches a master menu from which the player picks a mini-game. Three games exist:
- **gem_match** — a relaxing match-3 puzzle game
- **tile_chain** — a tile-pairing combo chain game
- **alchemical_sort** — a color-sort puzzle game (alchemical bottles theme)

No npm, Makefile, or external build tools — everything runs through the Godot editor.

## Running the Game

- **Run**: Open `project.godot` in Godot Editor → press F5 (or click the Play button)
- **Godot executable**: `c:\GOG Games\Godot_v4.3-stable_win64.exe`
- **Main scene**: `res://scenes/MasterMenu.tscn` (app entry point)
- **Export**: Godot Editor → File > Export Project (for standalone builds)
- **Lint/Warnings**: Godot's Output panel shows GDScript warnings and errors

There is no test framework; use manual testing or create dedicated test scenes.

## Architecture

### Navigation Flow

```
MasterMenu  (res://scenes/MasterMenu.tscn)
  ├─ tap "GEM MATCH" tile
  │    └─ games/gem_match/scenes/Main.tscn  (orchestrator)
  │         ├─ Menu.tscn  (sub-menu: logo, music, start button)
  │         │    ├─ Start  → Game.tscn
  │         │    └─ ‹ Back → MasterMenu
  │         └─ Game.tscn
  │              └─ ‹ Back → Menu.tscn
  ├─ tap "TILE CHAIN" tile
  │    └─ games/tile_chain/scenes/Main.tscn  (orchestrator)
  │         ├─ Menu.tscn  (placeholder: title, start, quit)
  │         │    ├─ Start  → Game.tscn
  │         │    └─ Quit   → MasterMenu
  │         └─ Game.tscn
  │              └─ ‹ Back → Menu.tscn
  └─ tap "ALCHEMICAL SORT" tile
       └─ games/alchemical_sort/scenes/Main.tscn  (orchestrator)
            ├─ Menu.tscn  (title, start, back)
            │    ├─ Start  → Game.tscn
            │    └─ ‹ Back → MasterMenu
            └─ Game.tscn
                 └─ ‹ Back → Menu.tscn
```

### Folder Structure

```
match3_game/
  project.godot               main_scene = res://scenes/MasterMenu.tscn
  assets/
    font/vetka.ttf            shared font
    game_icon.png             app icon
  games/
    gem_match/
      assets/
        gems/                 animated gem PNGs (levels 1–6) + legacy SVGs
        sfx/                  match, no_match, shuffle + combo/note_1–7
        music/999.mp3         looping ambient track
        BG.png, BG_top.png    background layers
        Logo_gem.png          GEM MATCH logo
        START_normal/pressed  start button textures
      scenes/
        Main.tscn             gem_match orchestrator (Menu ↔ Game)
        Menu.tscn             sub-menu (logo, start button, back button)
        Game.tscn             match-3 gameplay
        Tile.tscn             individual tile entity
      scripts/
        Main.gd               orchestrates Menu ↔ Game, music, fades
        Menu.gd               emits start_game / back_to_master
        Game.gd               all match-3 logic
        Tile.gd               tile input & animation
    tile_chain/
      assets/
        Set_1/                first tileset (z-1..3, A-1..9, B-1..12, C-1..12)
        Set_N/                future tilesets follow the same naming convention
      scenes/
        Main.tscn             tile_chain orchestrator (Menu ↔ Game)
        Menu.tscn             placeholder sub-menu (start, quit)
        Game.tscn             board + UI (combo labels, back button)
      scripts/
        Main.gd               orchestrates Menu ↔ Game, fades
        Menu.gd               emits start_game / back_to_master
        Game.gd               board construction, tap logic, combo tracking
        BoardCell.gd          class_name BoardCell; one cell with z/a/b/c layers
  scenes/
    MasterMenu.tscn           master app menu (one tile per game)
  scripts/
    MasterMenu.gd             fade-in on load, launches chosen game
```

### Scene & Script Reference

| Scene | Script | Role |
|-------|--------|------|
| `scenes/MasterMenu.tscn` | `scripts/MasterMenu.gd` | App hub; game-tile grid |
| `games/gem_match/scenes/Main.tscn` | `…/scripts/Main.gd` | gem_match orchestrator; music |
| `games/gem_match/scenes/Menu.tscn` | `…/scripts/Menu.gd` | Sub-menu; start + back signals |
| `games/gem_match/scenes/Game.tscn` | `…/scripts/Game.gd` | Match-3 logic |
| `games/gem_match/scenes/Tile.tscn` | `…/scripts/Tile.gd` | Tile entity & input |
| `games/tile_chain/scenes/Main.tscn` | `…/scripts/Main.gd` | tile_chain orchestrator; fades |
| `games/tile_chain/scenes/Menu.tscn` | `…/scripts/Menu.gd` | Placeholder sub-menu |
| `games/tile_chain/scenes/Game.tscn` | `…/scripts/Game.gd` | Board + combo logic |
| *(no .tscn — class only)* | `…/scripts/BoardCell.gd` | Single board cell; 4 texture layers |

### Communication Pattern

Scenes communicate via **Godot signals** (loose coupling):
- `Menu` emits `start_game` → `Main` transitions to Game
- `Menu` emits `back_to_master` → `Main` changes scene to MasterMenu
- `Game` emits `back_to_menu` → `Main` transitions back to Menu
- `MasterMenu` tile pressed → `get_tree().change_scene_to_file()`

---

## gem_match

### Board & Game Logic (`Game.gd`)

- **Board**: 10×7 grid stored as `board: Array[Array]`; valid cells defined by the `SHAPE` constant (diamond/irregular mask)
- **Tile levels**: 1–6; matched tiles are removed and one is upgraded; score = `group_size × 10 × upgraded_tile.level × cascade_multiplier`
- **Resolution loop**: after every swap, the game repeatedly runs match detection → tile removal/upgrade → gravity collapse → refill until no matches remain
- **Dead-state prevention**: `_check_for_shuffle()` randomizes the board when no valid moves exist

### Tile Entity (`Tile.gd`)

- Extends `Area2D` for collision/input
- Drag detection threshold: 30px; direction passed to `game._attempt_swap()`
- Animations via `AnimatedSprite2D` + `SpriteFrames` (PNG spritesheets per gem level)

### Data Flow (gem_match)

```
User drag input (Tile._input_event)
  → Game._input() calculates direction
  → Game._attempt_swap()
  → _find_matches() → _resolve_matches_animated() → _animate_collapse() → _animate_fill()
  → repeat until stable
  → _check_for_shuffle() if no moves remain
```

---

## tile_chain

### Board & Game Logic (`Game.gd`)

- **Board**: COLS×ROWS grid (currently 5×8) of `BoardCell` nodes built at runtime in `prepare_board()`
- **Cell size**: 90 px (set in both `BoardCell.CELL_SIZE` and `Game.CELL_SIZE` — keep in sync)
- **Tileset**: assets loaded from `assets/Set_1/` (TODO: random selection from all `Set_N/` folders)
- **Z layer**: background tile; assigned by `(row + col) % z_count` to produce `///` diagonal stripes
- **A / B / C layers**: one randomly chosen variant per cell, stacked as transparent TextureRects; A is the largest shape, C the smallest
- **Matching**: two cells match if they share at least one element with the same id; all shared elements are removed simultaneously from both cells
- **Combo**: consecutive successful pair-removals without a failed match; breaks to 0 on a tap with no shared elements; preserved (not broken) when the anchor cell ends up empty after a match

### BoardCell (`BoardCell.gd`)

- `class_name BoardCell`, extends `Control`; instantiated purely in code — no `.tscn`
- Layers: `_z_rect`, `_a_rect`, `_b_rect`, `_c_rect` (all `TextureRect`, MOUSE_FILTER_IGNORE)
- Selection outline: `Panel` with a `StyleBoxFlat` border (transparent fill), toggled via `show_outline(bool)`
- Removal animation (`_spin_out`): rotate 180° + shrink + fade-out over 0.25 s via Tween
- IDs (`a_id`, `b_id`, `c_id`) are set to 0 immediately on `remove_element()` — visual is async

### Data Flow (tile_chain)

```
User tap (BoardCell._gui_input)
  → BoardCell.tapped signal → Game._on_cell_tapped(cell)
  → if no selection: select cell, show outline
  → if same cell: deselect
  → else: _find_shared(selected, cell)
       → empty result: break combo, new selection = tapped cell
       → shared layers found: remove from both, combo++, new anchor = tapped cell
            → if new anchor is empty: clear selection (combo preserved)
```

---

## alchemical_sort

### Concept

Color-sort puzzle themed as an alchemist's workshop. Vials contain up to 4 layers of colored liquid. Pour one vial into another when the target is empty or has a matching top color. Win when every vial holds only one pure color (or is empty).

### Key Constants (`Game.gd`)

| Constant | Value | Notes |
|----------|-------|-------|
| `COLOR_COUNT` | 8 | Distinct potion colors; increase for harder puzzles |
| `EMPTY_VIALS` | 2 | Spare vials; must be ≥ 1 |
| `Vial.MAX_LAYERS` | 4 | Layers per vial |

Total vials = `COLOR_COUNT + EMPTY_VIALS`. Layout: up to 5 per row, centred on 540-wide screen.

### Vial Entity (`Vial.gd`)

- `class_name Vial`, extends `Control`; instantiated purely in code — no `.tscn`
- `_layers: Array[int]` — index 0 = bottom, index MAX_LAYERS-1 = top; 0 = empty
- Key queries: `top_color()`, `top_run_count()`, `free_slots()`, `is_empty()`, `is_full()`, `is_pure()`
- Visual placeholder: `ColorRect` per layer — **replace with sprite-based pixel art bottle**
- Selection outline: golden `StyleBoxFlat` border, toggled via `show_selected(bool)`

### Pour Rules

- `_can_pour(src, dst)`: dst must not be full; dst either empty OR `dst.top_color() == src.top_color()`
- `_do_pour(src, dst)`: moves `min(src.top_run_count(), dst.free_slots())` layers at once (pours the entire same-color run, limited by available space)

### Win Condition

All vials are `is_pure()` — i.e., each vial contains only one color id (or is empty).

### Data Flow

```
User tap (Vial._gui_input)
  → Vial.tapped signal → Game._on_vial_tapped(vial)
  → if no selection: select vial (if non-empty)
  → if same vial: deselect
  → else: _can_pour?
       → no:  move selection to tapped vial
       → yes: _do_pour(selected, tapped) → _check_win()
```

### Folder Structure

```
games/alchemical_sort/
  assets/
    music/theme.mp3       optional ambient track (auto-loaded if present)
    bottles/              TODO: pixel-art bottle sprites per color
  scenes/
    Main.tscn             orchestrator (Menu ↔ Game, fades)
    Menu.tscn             title, START GAME, ‹ BACK
    Game.tscn             board + move counter + back button
  scripts/
    Main.gd               fades, music, signal wiring
    Menu.gd               emits start_game / back_to_master
    Game.gd               board logic, pour mechanic, win check
    Vial.gd               class_name Vial; single bottle node
```

---

## Adding a New Game

1. Create `games/<game_name>/` with `assets/`, `scenes/`, `scripts/` subdirectories
2. Add a tile button to `scenes/MasterMenu.tscn` and connect `_on_<game_name>_pressed` in `scripts/MasterMenu.gd`
3. The new game's root scene should be `games/<game_name>/scenes/Main.tscn`
