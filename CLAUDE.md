# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A **zen toybox** app built with **Godot Engine 4.3** using **GDScript**. The app launches a master menu from which the player picks a mini-game. Four games exist:
- **gem_match** — a relaxing match-3 puzzle game
- **tile_chain** — a tile-pairing combo chain game
- **alchemical_sort** — a color-sort puzzle game (alchemical bottles theme)
- **potion_3** — a goods-sort / triple-match shelf game (pixel-art potion items)

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
  ├─ tap "ALCHEMICAL SORT" tile
  │    └─ games/alchemical_sort/scenes/Main.tscn  (orchestrator)
  │         ├─ Menu.tscn  (title, start, back)
  │         │    ├─ Start  → Game.tscn
  │         │    └─ ‹ Back → MasterMenu
  │         └─ Game.tscn
  │              └─ ‹ Back → Menu.tscn
  └─ tap "POTION_3" tile
       └─ games/potion_3/scenes/Main.tscn  (orchestrator)
            ├─ Menu.tscn  (title, difficulty selector, start, back)
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
    potion_3/
      assets/
        items/
          set1/ … set12/      pixel-art potion PNGs; named item1.png … itemN.png
                               ~700 items across 12 thematic sets; mixed at runtime
        sfx/
          item_put_down.mp3   plays on every successful item placement
      scenes/
        Main.tscn             potion_3 orchestrator (Menu ↔ Game, fades)
        Menu.tscn             title, difficulty selector, START, ‹ BACK
        Game.tscn             board + move/best labels + undo + back + win panel
      scripts/
        Main.gd               fades, signal wiring (same pattern as alchemical_sort)
        Menu.gd               emits start_game(difficulty) / back_to_master
        Game.gd               board generation, move/match/win logic, undo, save
        Cell.gd               class_name PotionCell; single shelf cell node
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
| `games/potion_3/scenes/Main.tscn` | `…/scripts/Main.gd` | potion_3 orchestrator; fades |
| `games/potion_3/scenes/Menu.tscn` | `…/scripts/Menu.gd` | Difficulty select; start + back signals |
| `games/potion_3/scenes/Game.tscn` | `…/scripts/Game.gd` | Board + match + undo + win logic |
| *(no .tscn — class only)* | `…/scripts/Cell.gd` | Single shelf cell; 3 slots + z-stack |

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

## potion_3

### Concept

Goods-sort / triple-match game. The board is a grid of **vertical shelf cells** (3 slots stacked top-to-bottom). Each cell has a hidden z-stack of layers beneath. Move items between cells; when 3 identical items occupy the same cell they auto-eliminate and the next hidden layer is revealed. Win when all cells (including dispensers) are empty.

### Key Constants (`Cell.gd` / `Game.gd`)

| Constant | Value | Notes |
|----------|-------|-------|
| `PotionCell.SLOTS` | **3** | Item slots per layer (stacked vertically) |
| `PotionCell.CELL_W` | **108** | 5 cols × 108 = 540 px |
| `PotionCell.CELL_H` | **270** | 3 × ITEM_SIZE |
| `PotionCell.ITEM_SIZE` | **90** | Item TextureRect size |
| `PotionCell.SIDE_PAD` | **9** | (CELL_W − ITEM_SIZE) / 2 |
| `PotionCell.VISUAL_INSET` | **4** | bg panel shrunk on all sides; items stay put |
| `PotionCell.SLOT_OVERLAP` | **12** | Each slot overlaps the one above by this many px (perspective) |
| `PotionCell.SLOT_Y_OFFSET` | **16** | Shifts the whole item stack down inside the cell |
| `PotionCell.DISP_BG_PAD_H/V` | **4** | Dispenser cell bg padding (tunable independently) |
| `Game.SCROLL_ROW_MAX` | **1** | Max scrolling rows; bump to 2 to re-enable |
| `Game.SCROLL_EXTRA_CELLS` | **1** | Off-screen buffer cells per scrolling row |
| `Game.SCROLL_INTERVAL` | **2.5 s** | Duration of one scroll tick (continuous, no pause) |
| `Game.COL_SPACING` | **0** | Padding built into CELL_W |
| `Game.ROW_SPACING` | **9** | Gap between rows: 3×270 + 2×9 = 828 px board |
| `Game.DISP_SCROLL_CELLS` | **6** | Visible cells in hazard belt; 6×108=648 > 540 → rightmost off-screen → invisible wrap |
| `Game.DISP_SCROLL_INTERVAL` | **2.0 s** | Hazard belt scroll speed |

Difficulty layout (set by `Game.set_difficulty()` before `prepare_board()`):

| Difficulty | Cols | Rows | Max depth | Item types | Empty cells |
|------------|------|------|-----------|------------|-------------|
| Easy       | 3    | 3    | 3         | 12         | 2           |
| Medium     | 4    | 3    | 4         | 22         | 2           |
| Hard       | 5    | 3    | 5         | 32         | 2           |
| Zen        | random (Easy–Hard) | same | same | same | same |

### PotionCell Entity (`Cell.gd`)

- `class_name PotionCell`, extends `Control`; instantiated purely in code — no `.tscn`
- `_slots: Array[int]` — 3 item IDs (0 = empty) for the current (top) layer
- `_z_stack: Array` — array of `[id0, id1, id2]` layers hidden below; index 0 = next to reveal
- `_slot_mystery: Array[bool]` — per-slot mystery flag for the current visible layer
- `_z_stack_mystery: Array` — parallel to `_z_stack`; each entry is `[bool, bool, bool]` per layer; auto-applied to `_slot_mystery` when `reveal_next_layer()` pops a layer
- **Vertical layout**: slot `i` rect at `y = SLOT_Y_OFFSET + i * (ITEM_SIZE − SLOT_OVERLAP)`; bottom slot (index 2) added last → rendered on top (perspective depth)
- **Preview rects**: slightly offset behind/above main rects at 20-25% brightness
- **Selection**: golden `StyleBoxFlat` highlight per slot, toggled via `show_slot_highlight(slot_idx, lit)`
- **Hit-testing**: always via `get_global_rect()` in Game — slot index = `clampi(int(local_y / ITEM_SIZE), 0, SLOTS−1)`
- **Mystery items**: slot rendered as near-black dusty-blue silhouette (`modulate = Color(0.02,0.03,0.08,1)`); "?" label (vetka.ttf) overlaid on transparent panel; mystery state travels with item on move (`_try_move` carries and re-applies flag); never revealed on tap — blind matching only; `set_slot_visible()` hides the "?" panel too during drag

### Special Cell Types

**Dispenser** (`set_as_dispenser()`):
- 1-tall cell (height = `ITEM_SIZE`), positioned below the main board; centered horizontally
- Holds one item visible; remaining items in `_z_stack` one-per-layer
- Items pulled from the main pool (mixed types); each item's 2 siblings are somewhere in the grid
- Cannot receive items (`has_empty_slot()` always returns −1)
- Slot 0 y-position reset to 0 (no `SLOT_Y_OFFSET`) after `set_as_dispenser()`
- Background size controlled by `DISP_BG_PAD_H` / `DISP_BG_PAD_V` (independent of `VISUAL_INSET`)
- ⬇ label indicator in the cell
- **Depth indicator**: row of small blue dots (7×5 px, 3 px gap) at the bottom of the cell; `_disp_total` dots created at setup; `_refresh_dispenser_indicator()` hides dots beyond the current remaining count; called from `_refresh_all()` automatically

**Locked** (`set_as_locked(unlock_count)`):
- Full-size dark overlay (`CELL_W × CELL_H`, no inset) — completely covers items and preview rects
- Counter shown in centre of overlay using vetka.ttf; decrements on every match anywhere on the board (`notify_match()`)
- Overlay fades out on unlock; `_refresh_preview()` called after to restore preview rects
- `has_empty_slot()` returns −1 while locked; `is_fully_empty()` always false while locked

**Hazard Dispenser Belt** (`_create_disp_scroll_belt()` / `_advance_disp_scroll()`):
- Hard mode only; scrolls **rightward** (opposite the main conveyor belt)
- `DISP_SCROLL_CELLS = 6` visible dispenser cells positioned above the board (`belt_y = origin_y − ITEM_SIZE − 18`) in the 200 px empty space at the top
- 6 cells × 108 px = 648 px > 540 px viewport → rightmost cell is always off-screen → wrap is invisible
- Array layout: `[buffer(off-left), vis0..vis5]`; each cell `i` targets `_board_origin_x + i × CELL_W`; rightmost wraps to off-left buffer position
- Items allocated from pool in `_generate_board_data()` (`DISP_SCROLL_CELLS + 1` groups)
- `_hazard_disp_scroll: bool` flag; `_disp_scroll_cells` and `_disp_scroll_buffer` track belt state
- `_advance_disp_scroll()` uses `tween.finished.connect` (no `await`) to avoid freed-lambda crash; guarded by `_game_generation`

**Scrolling row** (`set_scroll_row_visual()`):
- Amber-tinted background; rows decided in `_apply_difficulty_layout()` before board generation
- Each scrolling row gets `SCROLL_EXTRA_CELLS = 1` real buffer cells positioned at `off_x = _board_origin_x + _cols_per_row * CELL_W` (just off the board's right edge)
- Buffer cells start at `modulate.a = 0`; fade in during first 20% of each scroll tick
- Departing cell fades out during last 20% of each tick, then teleports back to `off_x`
- `tween_method` + `roundf()` snaps x to integer each frame — prevents sub-pixel wobble
- Scroll is continuous: `_advance_scroll()` loops itself immediately after each wrap (no timer between ticks); first tick delayed by `SCROLL_INTERVAL` from `start_game()`

### Cascading Special-Cell Probability

Decided in `_apply_difficulty_layout()` before any cells exist (so board gen can allocate items for dispensers). Types shuffled then rolled with decaying probability:
- Base: `0.55` (Hard) / `0.38` (Medium); each win multiplies by `0.42`
- Result: "nothing" and "one special" are common; "all three" is rare (~10%)
- Dispenser count: 1–4; sub-probability to add another decays by ×0.45 after count ≥ 2
- Hard mode adds `"hazard_disp_scroll"` to the types list before shuffle
- Dispenser count, scrolling row indices, and hazard belt flag stored in member vars for `_generate_board_data()` and `_build_cells()`
- Mystery items: rolled separately in `_generate_special_cells()` — Medium+, 60% chance, 3–5 items scattered across visible layer AND z-stack layers of non-locked non-dispenser cells

### Board Generation

1. Pick `_item_type_count` random IDs from the loaded texture pool
2. Build full pool (each type × 3), shuffle it
3. Pull dispenser items from the front of the shuffled pool (3 per dispenser, mixed types)
4. Include `_scrolling_rows.size() × SCROLL_EXTRA_CELLS` extra cells in total cell count
5. Assign depths (`layers_to_place = item_type_count × 1.4` → 40% slot surplus)
6. Build flat slot list, shuffle, assign pool items — no item ever lost
7. After `_build_cells()` main loop, create buffer cells for scrolling rows (off-screen right)
8. `start_game()` scans all cells after drop-in and auto-clears any pre-generated 3-matches

**Critical**: never reduce `layers_to_place` below `_item_type_count` or items will be stranded.

### Item Texture Loading

Items are named `item1.png … itemN.png` inside `assets/items/set1/ … set12/`. Uses numeric probing (not `DirAccess`) because `DirAccess.open("res://...")` returns `null` inside Android APKs:

```gdscript
for set_num in range(1, 20):   # generous upper bound
    for i in range(1, 1000):
        var path := "…/set%d/item%d.png" % [set_num, i]
        if ResourceLoader.exists(path):  # works on APK
            _item_textures[uid] = load(path)
            uid += 1
            misses = 0
        else:
            misses += 1
            if misses >= 50: break   # stop after 50 consecutive misses
```

### Android Input Notes

- All board input handled in `Game._input` (no `_gui_input` on cells)
- `OS.has_feature("mobile")` gates mouse branches — prevents double-firing from Godot's touch→mouse emulation
- Hit-testing always uses `cell.get_global_rect()` — `global_position` alone is unreliable under `canvas_items` stretch mode on Android
- Pickup uses `_find_pickup_slot_near(pos, 44px)` radius first, then exact hit — finger precision forgiveness
- Drag snap: exact hit tried first; if invalid (locked/dispenser/occupied), always falls back to nearest-empty radius search (`CELL_W × 1.5`) — key fix for Android imprecision
- **Decorative controls** (background ColorRect, overlays) must have `mouse_filter = MOUSE_FILTER_IGNORE`; in Godot GUI routing, tree order among siblings beats z_index for input priority

### Data Flow (potion_3)

```
prepare_board()
  → _clear_cells()                  # clears _scrolling_rows
  → _apply_difficulty_layout()      # sets _cols_per_row, _dispenser_count, _scrolling_rows
  → _build_cells()
       → _generate_board_data()     # allocates items for grid + dispensers + scroll buffers
       → main grid cells created
       → buffer cells created off-screen for scrolling rows
       → _generate_special_cells()  # applies scroll tint; sets locked cells; applies mystery items
       → _create_dispenser_cells()  # creates 1-tall cells below board
       → _create_disp_scroll_belt() # Hard only: rightward-scrolling hazard belt above board

start_game()
  → staggered drop-in animation
  → auto-clear any pre-generated 3-matches
  → _advance_scroll(r) for each scrolling row  ← continuous loop, no timer
  → _advance_disp_scroll() for hazard belt (Hard only) ← continuous loop, no timer

User press (Game._input — InputEventScreenTouch / MouseButton)
  → _find_pickup_slot_near(pos) or _find_cell_slot_at(pos)
  → _on_slot_tapped(cell, slot)
       → nothing selected: select slot (highlight)
       → same slot: deselect
       → selected + empty non-locked/non-dispenser target: _try_move(from, to)
            → _animate_item_move() fly sprite
            → to_cell.set_item() → check_match() → _process_match()
            → _notify_locked_cells()  ← decrements all locked cell counters
            → from_cell reveal next z-layer if now empty
            → _check_win() or _show_reshuffle_prompt()

User drag (Game._input — motion while pressing)
  → threshold exceeded: _start_drag() — floating sprite under finger
  → _update_drag() — sprite follows finger
  → release: _end_drag()
       → same-cell rearrangement: always allowed
       → cross-cell: 1. exact hit (if valid empty slot); 2. nearest-empty radius fallback
```

### Folder Structure

```
games/potion_3/
  assets/
    items/
      set1/ … set12/      item1.png … itemN.png (pixel-art, ~700 total)
    sfx/
      item_put_down.mp3   plays on item placement
  scenes/
    Main.tscn             orchestrator (Menu ↔ Game, fades)
    Menu.tscn             difficulty selector + START + ‹ BACK
    Game.tscn             board UI (MoveLabel, BestLabel, UndoButton, BackButton,
                          ReshuffleLabel/Button hidden, WinPanel)
  scripts/
    Main.gd               fades (0.22 s out / 0.38 s in), signal wiring
    Menu.gd               emits start_game(difficulty: int) / back_to_master
    Game.gd               all board logic
    Cell.gd               class_name PotionCell; shelf cell node
    Cell_triangular.gd    backup of triangular tessellation attempt (no class_name; not used)
```

---

## Adding a New Game

1. Create `games/<game_name>/` with `assets/`, `scenes/`, `scripts/` subdirectories
2. Add a tile button to `scenes/MasterMenu.tscn` and connect `_on_<game_name>_pressed` in `scripts/MasterMenu.gd`
3. The new game's root scene should be `games/<game_name>/scenes/Main.tscn`
