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

## Global UI Theme

`assets/theme.tres` — project-wide Godot `Theme` resource assigned in **Project Settings → GUI → Theme → Custom**. Currently overrides `Button/styles/focus` with `StyleBoxEmpty` to remove the default focus outline on all buttons.

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
- **Tile levels**: 1–7; score = `group_size × 10 × tile.level × cascade_multiplier`
- **Match resolution** (any 3+ match creates one survivor upgraded 1 tier):
  - **Plain 3-match** (`SPECIAL_NONE`) — one survivor upgrades 1 tier, no special stamped
  - **4-5 straight line** (`SPECIAL_BOMB`) — survivor upgrades + stamped BOMB (orange 3×3 blast)
  - **T / L / + intersection** (`SPECIAL_CROSS`) — survivor upgrades + stamped CROSS (row+col blast)
  - **5+ straight line** (`SPECIAL_COLOR_BOMB`) — survivor upgrades + stamped COLOR_BOMB (sp_heart gem; destroys all gems of target level when swapped with any gem)
  - **Stars (level 7)** — max tier, cannot upgrade; each star in the match is stamped BOMB and detonates as a 3×3 explosion instead
- **Special already in a group**: fires immediately (existing special takes priority over creating a new one)
- **COLOR_BOMB is immune to normal matches** — skipped during match resolution; only removed silently by BOMB/CROSS chain explosions
- **COLOR_BOMB cannot be chained** by BOMB/CROSS explosions — silently removed instead
- **Chain detonation**: BFS queue; BOMB/CROSS specials caught in a blast zone are added to the queue and also fire
- **Explosion zone flash**: `_flash_rect_in_board(rect, color)` fires a semi-transparent `Polygon2D` overlay on `board_container` (z_index=10) that fades in 0.07s → holds 0.10s → fades out 0.28s; orange for BOMB (3×3), blue for CROSS (row+col), dark purple per-tile for COLOR_BOMB
- **Dead-state prevention**: `_check_for_shuffle()` randomizes the board when no valid moves exist (also recognises COLOR_BOMB + any adjacent gem as a valid move)
- **Tink SFX**: soft crystal-clink (`no_match.mp3` at −14 dB via `SfxTink`) plays when gems settle after collapse or fill
- **Crash guard**: `_game_active` checked after every `await _animate_collapse()` / `await _animate_fill()` to safely abort coroutines when back-navigation fires mid-cascade

### Tile Entity (`Tile.gd`)

- Extends `Area2D`; `class_name Tile`
- **Levels 1–7**: `1_pearl`, `2_yellow`, `3_green`, `4_pink`, `5_blue`, `6_red`, `7_star`
- `special_type: int` — `SPECIAL_NONE / BOMB / CROSS / COLOR_BOMB` (0–3)
- `set_special(type)` — stamps type; BOMB/CROSS draw a coloured 68×68 square via `_draw()`; COLOR_BOMB switches `AnimatedSprite2D` to `"sp_heart"` animation (no rectangle)
- `set_level()` always resets `special_type` to NONE — caller sets it afterwards if needed
- Drag detection threshold: 30px; direction passed to `game._attempt_swap()`
- Animations via `AnimatedSprite2D` + `SpriteFrames` (PNG spritesheets per gem level)

### Data Flow (gem_match)

```
User drag input (Tile._input_event)
  → Game._input() calculates direction
  → Game._attempt_swap()
       → COLOR_BOMB intercept? → _fire_color_bomb() → collapse → fill → _find_matches() loop
       → normal: _find_matches() → _resolve_matches_animated()
            → per group: fire existing special OR remove/upgrade
            → chain detonation BFS (_collect_special_zone)
            → _animate_collapse() → _animate_fill() → repeat until stable
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

Color-sort puzzle themed as an alchemist's workshop. Vials contain up to 5 layers of colored liquid. Pour one vial into another when the target is empty or has a matching top color. Win when every vial holds only one pure color (or is empty).

### Key Constants (`Game.gd`)

| Constant | Value | Notes |
|----------|-------|-------|
| `Vial.MAX_LAYERS` | **5** | Layers per vial |

Difficulty-controlled layout (set by `Game.set_difficulty()` before `prepare_board()`):

| Difficulty | Colors | Empty vials | Vials/row | Undos |
|------------|--------|-------------|-----------|-------|
| Easy       | 6      | 2           | 4         | ∞     |
| Medium     | 8      | 2           | 4         | ∞     |
| Hard       | 12     | 2           | 5         | ∞     |
| Zen        | random (Easy–Hard) | same | same | ∞ |

Total vials = `color_count + empty_vials`. Centred on 540-wide screen.

### Vial Entity (`Vial.gd`)

- `class_name Vial`, extends `Control`; instantiated purely in code — no `.tscn`
- `_layers: Array[int]` — index 0 = bottom, index MAX_LAYERS-1 = top; 0 = empty
- Key queries: `top_color()`, `top_run_count()`, `free_slots()`, `is_empty()`, `is_full()`, `is_pure()`
- **Visuals**: pixel-art sprite sheet `liquid_colors_all.png` (7 cols × 2 rows = 14 colors); each cell is an `AtlasTexture` indexed by `color_id - 1`; vial size (72×176) derived from `bottle.png` at runtime
- **Draw order** (back → front): `bottle_inside.png` at 70% opacity → liquid layer `TextureRect`s → `bottle.png` overlay → golden selection outline (`StyleBoxFlat` Panel)
- **Bottle margins**: `BOTTLE_PAD_TOP = 14` px top, 2 px bottom, 4 px left/right (derived from bottle art); liquid layers offset to `(pad_x, BOTTLE_PAD_TOP)` within the 72×176 Control
- **Pixel-perfect rendering**: layer rects use `TEXTURE_FILTER_NEAREST` to prevent linear-filter edge bleeding (dark fringe at atlas region boundaries that appears as a gap between layers)
- **Shimmer overlay**: `colors_anim.png` — 5-frame horizontal strip (64×32/frame); an `AnimatedSprite2D` child of each layer rect plays it at ADD blend, 5% opacity; all layers within one vial share the same random start frame (synced shimmer), vials desync naturally since each builds independently
- **Fog (Mystery) mode**: hidden layers rendered with `modulate = Color(0,0,0,1)` — fully opaque black; revealed layers render normally
- Selection outline: golden `StyleBoxFlat` border, toggled via `show_selected(bool)`

### Pour Rules

- `_can_pour(src, dst)`: dst must not be full; dst either empty OR `dst.top_color() == src.top_color()`
- `_do_pour(src, dst)`: moves `min(src.top_run_count(), dst.free_slots())` layers at once (pours the entire same-color run, limited by available space); saves an undo snapshot before pouring
- **Board generation**: randomly distributes all `color_count × MAX_LAYERS` tokens across the color vials (creating mixed vials); empty vials appended last. **Note:** a scramble-from-solved approach does NOT work here — valid game pours can only move same-color runs, so the board would stay "pure" and the win condition would fire immediately. Random distribution + 2 empty vials produces solvable boards in the vast majority of cases; the dead-board detector handles the rare stuck positions by reshuffling in-place.
- **Undo stack**: `_undo_stack` (Array of snapshots); depth capped by `_max_undo_depth` per difficulty (−1 = unlimited for Zen); button shows `UNDO ×N` while charges remain
- **Dead-board undo**: undo is allowed even while the reshuffle prompt is visible; pressing it dismisses the prompt and restores the previous state, re-enabling play
- **Tap queuing**: taps during a pour animation are silently queued in `_queued_vial` and processed after the animation finishes

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
    music/menuet.mp3           ambient track (auto-loaded by Main.gd)
    liquid_colors_all.png      sprite sheet — 7 cols × 2 rows, 14 hand-painted liquid colors
    bottle.png                 bottle overlay (72×176); rendered on top of liquid layers
    bottle_inside.png          inner glass texture (72×176); rendered at 70% opacity behind liquid
    colors_anim.png            shimmer overlay — 5-frame horizontal strip (64×32/frame); ADD blend on each layer
    liquid_hue.gdshader        unused — kept for reference (hue-rotation approach was abandoned)
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
