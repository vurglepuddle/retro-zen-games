# ZEN FARM — Game Design Spec (V1)

**Project**: Zen Games (Godot 4.3, GDScript)
**Codename**: `zen_farm` (folder: `games/zen_farm/`)
**Screen**: 540×960 portrait (same as other Zen Games)
**Persistence**: Saved to `user://zen_farm_save.cfg` — this is the only persistent game in the toybox

---

## Core Identity

> You're staring out at a little field. Things grow. You tend them when you feel like it. If you go hard, there's always more to do. If you zone out, the field just... breathes a little slower.

**No lose condition.** Crops can wilt but never die permanently. Weeds creep in but are cosmetic. The farm never resets. Progress is always forward, just sometimes slower.

---

## 1. The Grid

### Layout
- **Starting size**: 4×4 tiles (centered on screen, with UI above/below)
- **Max size**: ~10×12 tiles (scrollable vertically once the farm outgrows one screen)
- **Tile size**: 48×48 px (fits 11 tiles across 540 px with margins; gives room for pixel art)
- **Expansion**: Buy new land tiles with coins; land is added in chunks (rows or irregular patches) from the edges of the current plot

### Tile Types
| Tile | Description |
|------|-------------|
| **Soil** | Empty farmable tile. Can be tilled, then planted. |
| **Crop** | A planted tile. Shows growth stages (seed → sprout → mature → harvestable). |
| **Wilted** | Neglected crop. Greyed out, recoverable by watering (takes extra time). |
| **Weed** | Slowly spawns on empty soil. Cosmetic pressure — tap to clear. Doesn't destroy anything. |
| **Path** | Decorative/structural. Placed by player. No function, just looks nice. |
| **Water** | Irrigation piece (see §3). Speeds up adjacent crop growth. |
| **Storage** | Holds harvested produce. Limited capacity per unit. |
| **Locked** | Unpurchased expansion tile. Shows price, tap to buy. |

---

## 2. Crops & Growth

### Time Model
- **Hybrid real-time**: Crops grow on real-world timers (seconds/minutes, not hours — this is a pick-up-and-play game, not Farmville)
- **Growth continues while the game is open**, even if the player isn't tapping
- **Offline catch-up**: When the player returns, the game fast-forwards elapsed time. Crops that would have matured do so; crops that weren't watered may have wilted
- **No energy gating**: The player can always act. There's no action limit, no stamina bar, no "come back tomorrow"

### Growth Stages (per crop)
1. **Seed** — just planted, small dot on tile (~10 s)
2. **Sprout** — tiny green shoots (~20 s)
3. **Growing** — visible plant, halfway there (~30 s)
4. **Mature** — full-grown, ready to harvest (stays indefinitely)
5. **Wilted** — if left unwatered too long after planting. Water to reset timer and resume growth. Not permanent

*Times above are base values for the simplest crop. Higher-tier crops take longer. Irrigation reduces time.*

### Watering
- Crops need water to progress through growth stages
- **Without irrigation**: player must tap a crop to water it (or tap-drag across multiple). Each watering sustains growth for one stage
- **With irrigation** (see §3): adjacent crops auto-water, reducing/eliminating manual watering
- **Rain events**: occasional random rain waters everything. Brief animation, pleasant sound

### Starter Crops (unlocked from the beginning)
| Crop | Base grow time | Sell value | Notes |
|------|---------------|------------|-------|
| Carrot | 45 s total | 2 coins | Fast, reliable |
| Lettuce | 60 s total | 3 coins | Slightly better value |
| Potato | 90 s total | 5 coins | Slow but worth more |

*More crops unlock via milestones. Keep initial variety small — 3 is enough to learn the systems.*

### Unlockable Crops (examples, expand later)
| Crop | Unlock condition | Base grow time | Sell value |
|------|-----------------|---------------|------------|
| Tomato | Complete 5 orders | 75 s | 4 coins |
| Wheat | Expand to 6×6 | 120 s | 7 coins |
| Pumpkin | Complete 15 orders | 180 s | 12 coins |
| Sunflower | Reach 500 coins total earned | ∞ (decorative) | 0 |

---

## 3. Tetris-Style Building Placement

This is the **spatial puzzle** layer. Buildings and infrastructure are **polyomino shapes** (like Tetris pieces) that the player places on the grid.

### Placeable Structures

| Structure | Shape examples | Effect |
|-----------|---------------|--------|
| **Well** (1×1) | ▪ | Waters adjacent 4 tiles (cardinal). Cheap, small range. |
| **Irrigation Channel** (1×3, 1×4, L-shape, T-shape) | ▪▪▪ or ▪▪/▪ | Waters all tiles adjacent to any piece of the channel. The core spatial puzzle. |
| **Storage Crate** (2×1) | ▪▪ | Stores up to 12 harvested items. Must have storage to harvest. |
| **Silo** (2×2) | ▪▪/▪▪ | Stores up to 40 items. Expensive but space-efficient. |
| **Scarecrow** (1×1) | ▪ | Reduces weed spawn rate in a 3×3 area around it. |
| **Compost Bin** (1×2) | ▪▪ | Crops adjacent to it grow 20% faster (stacks with irrigation). |

### Placement Rules
- Structures occupy soil tiles — those tiles can no longer grow crops
- **The puzzle**: fitting irrigation, storage, and crop space efficiently as the farm grows
- Player opens a build menu → selects structure → ghost preview on grid → tap to place, tap again to rotate
- Structures can be picked up and moved (costs nothing, just takes a moment)
- Cannot overlap crops or other structures

### Why This Is Fun
- Early game (4×4): trivial — just plant and tap-water
- Mid game (6×6 to 8×8): irrigation channels become important. Do you use an L-piece to cover a corner, or two straights?
- Late game (10×12): balancing crop area vs. irrigation coverage vs. storage capacity. Scarecrow placement matters. It's a quiet optimisation puzzle

---

## 4. Economy

### Currency: Coins
- **Earned by**: Fulfilling orders (primary), selling produce directly at the market (lower value)
- **Spent on**: Seeds, structures, land expansion, crop unlocks

### Bartering
Some things cost **produce, not coins**:
- Certain structures require materials (e.g., Silo costs 10 Wheat + 50 coins)
- Crop unlocks may require delivering specific items (e.g., "bring 5 Tomatoes to unlock Pumpkin seeds")
- This gives the player a reason to grow specific things, not just the most profitable crop

### Market (Direct Sell)
- Always available. Tap harvested items in storage → sell for coins
- Lower value than filling orders (roughly 60-70% of order value)
- Safety valve: if no matching orders, you can still make progress

### Prices (approximate, tune in playtesting)
| Item | Cost |
|------|------|
| Carrot seeds (×3) | 1 coin |
| Lettuce seeds (×3) | 2 coins |
| Potato seeds (×3) | 3 coins |
| Well | 10 coins |
| Irrigation L-piece | 20 coins |
| Irrigation straight (1×3) | 15 coins |
| Storage Crate | 15 coins |
| Silo | 50 coins + 10 Wheat |
| Scarecrow | 25 coins |
| Compost Bin | 30 coins + 5 Potatoes |
| Land expansion (per chunk) | 25–100 coins (escalating) |

---

## 5. Orders & Progression

### Rolling Orders (Small)
- **Order board** visible at top of screen: 2–3 active orders at a time
- Each order: "Deliver X of [crop]" → reward in coins (+ sometimes a bonus: seeds, structure, unlock)
- When fulfilled, the order slides out and a new one rolls in after a short delay (~30 s)
- Orders scale gently with farm size: early orders ask for 2–3 carrots; later ones ask for 6 Wheat + 4 Tomatoes
- **Never punishing**: unfilled orders just sit there. No expiry timer. No penalty. Take your time

### Milestone Goals (Big)
- Shown separately (maybe a small notebook icon / panel)
- Examples:
  - "Harvest 20 crops total" → Unlock Tomato seeds
  - "Expand your farm to 6×6" → Unlock Irrigation T-piece
  - "Fill 10 orders" → Unlock Compost Bin
  - "Earn 500 coins total" → Unlock Sunflower (decorative)
  - "Have 5 structures placed at once" → Unlock Silo blueprint
- These are the long-term dopamine drip. Not urgent, just... there, pulling you forward

---

## 6. Setbacks & Weather

### Wilting
- Crops that aren't watered (manually or via irrigation) stop growing after their current stage timer runs out
- After **2× the stage duration** without water, they wilt (visual change: grey/droopy sprite)
- **Recovery**: water a wilted crop → it un-wilts and resumes from where it was (doesn't reset to seed). Takes one extra watering cycle as penalty
- Crops **never die**. Worst case = wilted and waiting

### Weeds
- Empty soil tiles have a small chance per minute of sprouting a weed
- Weeds are purely cosmetic/spatial pressure — they take up a tile you could be using
- Tap to pull them (instant, free)
- Scarecrows reduce spawn rate nearby
- If the player is away for a long time, weeds spread a bit but never onto crops or structures. Cap at ~30% of empty tiles

### Weather (future feature — flag for V2)
- **Rain**: waters all crops. Happy event. Lasts 30–60 s
- **Drought**: growth speed halved for a period. Irrigation still works at full speed (making it more valuable)
- **Wind**: purely visual — swaying crops, particles. No mechanical effect. Just vibes

---

## 7. The "Scales to Your Energy" Principle

This is the key design pillar. The game should feel different depending on the player's mood:

### Zen Mode (Low Engagement)
- Open the game, look at the farm, maybe pull a weed or two
- Crops grow on their own if irrigated. Storage fills up passively
- Check back later, harvest, sell, done
- The farm is a digital terrarium

### Active Mode (High Engagement)
- Plant seeds in every open tile, manually water everything
- Rearrange irrigation for optimal coverage
- Fill orders as fast as possible, buy expansion, repeat
- Plan crop rotations to match incoming orders
- Optimize structure placement like a Tetris endgame
- The game keeps generating small orders and weeds as fast as you can handle them

### How the System Scales
- Order generation rate is **not** time-gated — new orders appear shortly after you complete one
- Weed spawn rate scales with empty space (more empty tiles = more to manage)
- More land = more to tend = more to harvest = more orders to fill
- The player's own ambition drives the pace, not the game's timers

---

## 8. Persistence & Save

### What's Saved (to `user://zen_farm_save.cfg`)
- Grid state: every tile (type, crop id, growth stage, watered status, wilt state)
- Structure positions and types
- Inventory / storage contents
- Coin balance
- Active orders and their progress
- Milestone progress
- Total stats (crops harvested, orders filled, coins earned lifetime)
- Last-seen timestamp (for offline catch-up calculation)
- Unlocked crops and structures

### When to Save
- After every meaningful action (plant, harvest, build, sell, order complete)
- On scene exit (back to MasterMenu)
- On app backgrounding / `NOTIFICATION_WM_GO_BACK_REQUEST`

### Offline Catch-Up
On load, calculate `time_elapsed = now - last_seen_timestamp`:
- Advance all crop timers by `time_elapsed`
- Process watering from irrigation (crops near water sources don't wilt)
- Wilt crops that ran out of water during the gap
- Spawn weeds (capped at 30% of empty soil)
- Do NOT auto-harvest — the player should see their mature crops and tap them. That's a satisfying moment

---

## 9. UI Layout (540×960 Portrait)

```
┌──────────────────────────────┐
│  [☰]  💰 142    [📋 Orders]  │  ← Top bar: menu, coins, order board toggle
├──────────────────────────────┤
│                              │
│                              │
│        FARM GRID             │  ← Main area: scrollable grid
│     (centered, grows         │     48×48 tiles, pixel art
│      as farm expands)        │
│                              │
│                              │
│                              │
├──────────────────────────────┤
│  [🌱 Plant] [🔨 Build] [📦] │  ← Bottom toolbar: plant mode, build mode, storage view
│         [‹ BACK]             │  ← Back to MasterMenu
└──────────────────────────────┘
```

### Interaction Modes
- **Default**: tap crop to water/harvest. Tap weed to pull
- **Plant mode**: tap empty soil to plant selected seed
- **Build mode**: select structure → ghost preview → tap to place, tap to rotate
- **Storage view**: see inventory, sell items, fill orders

---

## 10. Technical Architecture

### Folder Structure
```
games/zen_farm/
  assets/
    tiles/          ← tileset PNG(s) from itch.io — soil, grass, water, paths
    crops/          ← per-crop sprite sheets (seed/sprout/grow/mature/wilt)
    structures/     ← well, irrigation pieces, storage, scarecrow, compost
    sfx/            ← water splash, harvest pop, coin clink, weed pull, rain
    music/          ← ambient loop (pastoral, gentle)
  scenes/
    Main.tscn       ← orchestrator (Menu ↔ Game, fades) — same pattern as other games
    Menu.tscn       ← title, CONTINUE / NEW FARM, ‹ BACK
    Game.tscn       ← the farm view + all UI
  scripts/
    Main.gd         ← fades, signal wiring (same pattern)
    Menu.gd         ← emits start_game / back_to_master
    Game.gd         ← farm grid, crop logic, orders, economy, save/load
    FarmCell.gd     ← class_name FarmCell; single grid cell (soil/crop/structure/weed)
    CropData.gd     ← class_name CropData; Resource subclass — defines crop stats
    Structure.gd    ← class_name Structure; polyomino definition + placement logic
    OrderBoard.gd   ← active orders, generation, fulfillment
    SaveManager.gd  ← serialization/deserialization to ConfigFile
```

### Key Signals (same loose-coupling pattern)
```
Menu.start_game → Main transitions to Game
Menu.back_to_master → Main changes scene to MasterMenu
Game.back_to_menu → Main transitions back to Menu
FarmCell.tapped(cell) → Game handles context (water/harvest/pull weed)
OrderBoard.order_completed(order) → Game grants rewards
```

### Growth Tick
- `_process(delta)` or a 1-second Timer accumulates time on each crop
- Each crop tracks `time_in_stage` and compares against its stage duration
- Irrigation check: scan neighbors for water sources each tick (or cache and invalidate on build/move)

---

## 11. Scope & Phases

### Phase 1 — Core Loop (MVP)
- [ ] Scaffold folder structure + MasterMenu tile
- [ ] 4×4 grid with soil tiles
- [ ] 3 starter crops (carrot, lettuce, potato) with growth stages
- [ ] Tap to plant, tap to water, tap to harvest
- [ ] Basic storage (invisible/unlimited for MVP)
- [ ] Coin counter + direct sell
- [ ] Save/load persistence
- [ ] Offline catch-up
- [ ] Wilting mechanic
- [ ] Basic weed spawning

### Phase 2 — Spatial Puzzle
- [ ] Well (1×1 irrigation)
- [ ] Irrigation channels (L, T, straight polyominoes)
- [ ] Storage Crate + Silo (limited storage)
- [ ] Build mode UI with ghost preview + rotation
- [ ] Structure pick-up and move

### Phase 3 — Economy & Orders
- [ ] Order board (2–3 rolling orders)
- [ ] Milestone system (5–10 milestones)
- [ ] Crop unlocks (tomato, wheat, pumpkin)
- [ ] Structure unlocks (silo, compost bin, scarecrow)
- [ ] Bartering (produce-cost structures)

### Phase 4 — Expansion & Polish
- [ ] Land expansion (buy tiles at edges)
- [ ] Scrollable grid for larger farms
- [ ] Decorative tiles (paths, flowers)
- [ ] Weather events (rain)
- [ ] Ambient music + full SFX pass
- [ ] Visual polish: crop animations, water shimmer, weed sway

### Phase 5 — Future / V2 (Dream List)
- [ ] Seasonal cycles
- [ ] Drought weather event
- [ ] Rare/exotic crops
- [ ] Farm visitors (purely cosmetic — little characters walking around)
- [ ] Farm stats page (total harvested, favorite crop, days played)

---

## 12. Open Questions (Decide During Dev)

1. **Game name**: "Zen Farm"? "Little Plot"? "Pocket Field"? Decide during art pass
2. **Tile art source**: Buy a tileset from itch.io or draw custom? (User to decide)
3. **Grid scroll or zoom?**: For larger farms — scroll only, or pinch-to-zoom too?
4. **Crop placement**: one seed per tile, or can some crops span 2×2? (Start with 1×1, consider later)
5. **Night cycle?**: Purely cosmetic darkening + fireflies? Or does it affect gameplay? (Suggest: cosmetic only, V2)
6. **Sound**: Reuse `999.mp3`-style ambient, or source something pastoral/new?
