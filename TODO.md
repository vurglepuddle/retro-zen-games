## Machine (Claude) Tasks
**Feel & Polish**

* ~~Animate the score counter (tween the number upward when points are gained)~~ ✓

* ~~Add a combo multiplier — chained cascade matches multiply the score (×2, ×3…) with a brief on-screen label pop~~ ✓

* ~~Special gem system — classic 3 special types created by match shape/size:~~ ✓
  * ~~BOMB (orange): 4-5 in a line → 3×3 explosion when matched, chains BOMB/CROSS~~
  * ~~CROSS (blue): T/L/+ intersection → full row+col explosion when matched, chains BOMB/CROSS~~
  * ~~COLOR_BOMB (black): 5+ in a line → swap with any gem to destroy all of that tier; immune to normal match resolution~~

* ~~Hint system — after ~5 seconds of no input, pulse the tiles involved in one valid swap~~ ✓

* ~~Shuffle notification — briefly show a "Shuffling…" label when the board auto-shuffles~~ ✓

* ~~Score milestone screen flash — subtle warm-gold flash at 1 000, 10 000, 100 000, … points~~ ✓

* ~~Menu → game fade transition (black fade between screens, both directions)~~ ✓

* ~~Screen shake on explosion — full shake for BOMB, faint shake for CROSS~~ ✓
* ~~Tink SFX on gem land — soft crystal-clink after collapse/fill~~ ✓
* ~~Explosion zone flash — semi-transparent overlay: orange 3×3 for BOMB/stars, blue row+col for CROSS, dark purple per-tile for COLOR_BOMB~~ ✓

* ~~Particle burst on tile clear — small gem sparkles fly out from matched tiles~~ Do not need.

* ~~Add the mute sound button~~ → User will handle

**Quality of Life**

* ~~Back-to-menu button in-game (top-left "‹") + Android Back gesture support~~ ✓

* ~~Wire Main.gd to handle `back_to_menu` signal~~ ✓

* ~~Sound placeholder nodes for all SFX~~ ✓

**Zen Toybox Architecture**

* ~~Master menu (MasterMenu.tscn) as app entry point — placeholder tile for gem_match~~ ✓

* ~~Folder reorganisation — gem_match isolated under games/gem_match/~~ ✓

* ~~Back button in gem_match sub-menu → returns to MasterMenu~~ ✓

**Android / Export**

* ~~Android back gesture → return to menu (no dialog needed for a zen game)~~ ✓

* * *
## Human Tasks
**Art**

* ~~Source background image~~ ✓

* ~~Source game logo (GEM MATCH, PNG)~~ ✓

* ~~Source start button graphic~~ ✓

* ~~App icon~~ ✓ (star icon)

* ~~Pick a font~~ ✓ (vetka.ttf)

* ~~Draw the second state for the start button (hover / pressed)~~ ✓ Done!

* Style the in-game back button "‹" — currently plain text

* Style the mute sound button (2 versions: on/off) and wire it up

* Style the MasterMenu — background, polish the game-tile card

**Sound**

* ~~Source all SFX~~ ✓ — assigned in Game.tscn

* ~~Looping ambient track~~ ✓ (999.mp3 at 50% volume)

* ~~MasterMenu ambient music~~ ✓ (`assets/music/999_turbo.mp3`)
* ~~MasterMenu button SFX node~~ ✓ (SfxClick AudioStreamPlayer — assign sound in Inspector)

**Design Decisions**

* ~~Level-6 behaviour~~ → 3×3 area clear ✓

* ~~Score milestones~~ → warm-gold screen flash ✓

* ~~Game name~~ → **GEM MATCH** ✓

* ~~Restart button?~~ → Not needed (zen game) ✓

* ~~Save high score?~~ → Not needed (zen game) ✓

* ~~Name for the toybox app (currently "ZEN GAMES" in project.godot and MasterMenu title)~~ ZEN GAMES ✓

* * *
* * *
# TILE CHAIN

## Machine (Claude) Tasks

**Tileset System**
* ~~Multi-tileset support — on each game start, scan `assets/` for all `Set_N/` folders and randomly pick one; Game.gd path constants become dynamic~~ ✓
* Validate tileset on load — warn in Output if a folder is missing z/a/b/c tiles

**Core Mechanics**
* ~~Board-cleared celebration — when all cells are empty, show a subtle message and pause briefly before allowing restart~~ ✓ (ClearPanel overlay)
* ~~Dead-board detection — if no two cells share any element, trigger an automatic reshuffle (with a "Shuffling…" notice, like gem_match)~~ ✓
* ~~New Game button (in-game, or on the "board cleared" screen) — rebuild board without returning to menu~~ ✓

**Feel & Polish**
* ~~Combo counter pop animation — brief scale-up tween on the label when the combo increments~~ ✓ (MilestoneLabel pops at ×10, ×20, ×30…)
* ~~Board entrance animation — cells fade/scale in from zero on game start~~ ✓ (bloom in random order, ~2 s)
* ~~Selection pulse — gentle glow/oscillating scale on the currently selected cell~~ ✓
* ~~Border sparkles — star animations appear randomly in the rune zones around the board~~ ✓
* Rune glow animation — runes on bg.png randomly brighten/dim using overlay sprites (waiting on art asset — user is making animated glow, will slot under cut-transparency bg.png)
* Board blue glow — same as above, part of the handmade animation pass
* Match burst — tiny particle or flash on the cell where elements disappear
* ~~Android back gesture support (return to Menu from Game)~~ ✓
* ~~A small sfx played every time you clear a tile~~ ✓ (no_match.mp3 placeholder — swap when ready)
* ~~Slower spinning animation (too quick currently)~~ ✓
* ~~Idle tile animations — each layer spins lazily at its own speed~~ ✓

**Quality of Life**
* ~~Persist longest combo as session high score~~ ✓ (ConfigFile save between sessions)
* ~~Sound effects — combo milestone (×10, ×20…)~~ ✓ (SfxMilestone node — assign audio)
* ~~Ambient music~~ ✓ (999_2.mp3 at 50% volume)
* ~~Tileset validation — warn in Output if a Set_N folder is missing z/a/b/c tiles~~ ✓

---

## Human Tasks

**Art**
* Export all additional tilesets; place each as `games/tile_chain/assets/Set_N/` with the same z/a/b/c naming convention
* Logo / title graphic for the Tile Chain menu screen (replaces plain text "TILE CHAIN")
* Background art for the menu and/or game board
* Styled selection outline or highlight (replaces the plain white border)
* TILE CHAIN tile card art for the MasterMenu (like the gem_match logo)
* `rune_glow.png` — soft cyan/white radial gradient blob (~80×80 px, transparent background); drop in `games/tile_chain/assets/`; one texture reused for all rune overlay sprites

**Sound**
* ~~Match SFX (element removed)~~ ✓ placeholder wired — swap `no_match.mp3` for a proper removal sound when ready
* Combo milestone chime (×5, ×10…)
* Combo break SFX
* ~~Ambient / background track~~ ✓ (999_2.mp3)

**Design Decisions**
* ~~Final game name — "TILE CHAIN" or something else?~~ ✓ TILE CHAIN
* ~~Should the longest combo persist between sessions (save file)?~~ ✓ Yes, ConfigFile
* ~~Board size — currently 5×8 (COLS×ROWS at 90 px); tune after seeing it in-game~~ ✓ staying at 5×8
* ~~Should unmatched-tap break the combo, or should the old selection just move to the new tile?~~ ✓ moves selection, breaks combo

* * *
* * *
# ALCHEMICAL SORT

## Machine (Claude) Tasks

**Core Mechanics**
* ~~Scaffold folder structure, scripts, scenes, MasterMenu tile~~ ✓
* ~~Pour animation — liquid visually flows from source vial to target (fade out → droplet arc → fade in)~~ ✓
* ~~Win screen / "Solved!" overlay showing move count + New Game button~~ ✓ (WinPanel)
* ~~Undo button — per-difficulty undo stack (Easy=3, Medium=2, Hard=1, Zen=∞); button shows `UNDO ×N`~~ ✓
* ~~Android back gesture support (`_notification(NOTIFICATION_WM_GO_BACK_REQUEST)`)~~ ✓
* ~~Save best (fewest) move count per difficulty to `user://alch_sort_save.cfg`~~ ✓
* ~~Dead-state detection — shows "No valid moves left." label + RESHUFFLE button; user decides when to reshuffle~~ ✓
* ~~Mystery fog-of-war mode — 25% random event on Medium/Hard/Zen; only top color-run visible; layers revealed as poured off; "Mystery…" tween on game start~~ ✓
* ~~Board generation — random distribution creates mixed vials; 2 empty vials + dead-board detection makes boards reliably playable~~ ✓

**Difficulty / Tuning**
* ~~Difficulty selector in Menu (Easy 6-color / Medium 8-color / Hard 10-color / Zen random)~~ ✓

**Feel & Polish**
* ~~Vial entrance animation on game start (bottles slide/drop in one by one)~~ ✓
* Bubbling/shimmer idle animation on liquid layers
* Satisfying "glug" sound when pouring (SFX node + audio file)
* Completion glow on a fully solved vial (celebrate() scale-bounce placeholder — needs visual glow effect)

---

## Human Tasks

**Art**
* Pixel-art bottle sprite — empty bottle silhouette (transparent, all colors show through liquid)
* Liquid fill sprites or shader per color layer (8–10 colors in the palette)
* Background art for the game screen (lab/workshop aesthetic)
* "ALCHEMICAL SORT" logo for the Menu scene and MasterMenu tile card

**Sound**
* Pouring / glugging SFX
* Vial-complete chime
* ~~Ambient track~~ ✓ (`games/alchemical_sort/music/menuet.mp3`)

**Design Decisions**
* Final color count and palette — currently 8 colors, placeholder `PALETTE` array in `Game.gd`
* ~~Should pouring animate one layer at a time or all at once?~~ ✓ All at once (entire top run pours together)
* ~~Move counter vs. timer — which metric to display and save?~~ ✓ Move counter
* ~~Bottle capacity — currently 4 layers; tune after playtesting~~ ✓ 5 layers
* ~~Difficulty — currently fixed at 8 colors / 2 empty vials; selector pending~~ ✓ (Easy/Medium/Hard/Zen)
