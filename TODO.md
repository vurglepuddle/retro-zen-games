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
* ~~Explosion flash clipping — flash now drawn per valid board cell (SHAPE mask); no longer bleeds outside the gem area into decorative background~~ ✓
* ~~`_game_active` crash guards — abort coroutines cleanly on back-navigation mid-cascade~~ ✓

* ~~Particle burst on tile clear — small gem sparkles fly out from matched tiles~~ Do not need.

**Pending**
* ~~Timed mode — score-race variant (countdown timer + game-over screen when time runs out)~~ ✓ (90 s countdown, escalating red at 10 s, TIME'S UP panel with PLAY AGAIN / MENU)
* ~~Persist timed mode high score (reuse tile_chain ConfigFile save pattern)~~ ✓ (`gem_match_save.cfg`)
* ~~Level mode — fill a score bar to "level up"; each level raises the target 30%; leveling up adds 5 s; "LEVEL N!" banner pops on level-up; TIME'S UP panel shows level reached + best level saved~~ ✓ (LEVEL MODE button in menu; `set_level_mode()` in Game.gd)
* ~~Polish win / game-over screen code — NEW BEST! highlight, fade-in, PLAY AGAIN / < MENU buttons~~ ✓
* Polish win / game-over screen art (art TBD — human task)

* ~~Global mute toggle (3-state: all on → music off → all off) — `AudioManager` autoload singleton owns music player + state; `MuteButton.gd` reusable script for per-screen TextureButtons~~ ✓
* ~~Web audio fix — removed dynamic `AudioServer.add_bus()` (corrupts WebAudio driver); music-only mute via `volume_db = -80` instead~~ ✓
* ~~Music crossfade — 0.30 s fade-out → switch stream → 0.40 s fade-in when switching tracks between scenes~~ ✓
* ~~Splash screen — "TAP TO START" overlay on first load; 3-layer cover system guarantees no menu flash; naturally unlocks web audio on tap~~ ✓

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

* Style the mute button — make 6 textures (normal/pressed × all-on / music-off / all-off) and assign them to the `MuteButton` TextureButton node in each scene's Inspector

* Style the MasterMenu — background, polish the game-tile card

* BOMB special gem graphic — replace the plain orange `_draw()` square with real art
* CROSS special gem graphic — replace the plain blue `_draw()` square with real art

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
* ~~Polish win screen code — combo info, best combo, NEW BEST! highlight, fade-in, < MENU button~~ ✓
* Polish win screen art (art TBD — human task)
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
* Replace menu text buttons with TextureButtons
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
* ~~Polish win screen code — best moves, NEW BEST! highlight, fade-in, < MENU button~~ ✓
* Polish win screen art (art TBD — human task)

---

## Human Tasks

**Art**
* Pixel-art bottle sprite — empty bottle silhouette (transparent, all colors show through liquid)
* Liquid fill sprites or shader per color layer (8–10 colors in the palette)
* Background art for the game screen (lab/workshop aesthetic) — placeholder, user will redraw
* "ALCHEMICAL SORT" logo for the Menu scene and MasterMenu tile card
* Replace menu text buttons with TextureButtons

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

* * *
* * *
# POTION_3

## Machine (Claude) Tasks

**Core (Done)**
* ~~Scaffold folder structure, scripts, scenes, MasterMenu tile~~ ✓
* ~~Triple match mechanic — 3 identical items in one cell auto-eliminate, reveal next z-layer~~ ✓
* ~~Undo system — unlimited for all difficulties; button shows `UNDO ×N`~~ ✓
* ~~Dead-board detection + RESHUFFLE prompt~~ ✓
* ~~Win screen with move count + New Game button~~ ✓
* ~~Save/load best moves per difficulty~~ ✓
* ~~Board entrance drop-in animation~~ ✓
* ~~Drag-to-move with snap + same-cell rearrangement~~ ✓
* ~~Android touch input via `InputEventScreenTouch` / `InputEventScreenDrag`~~ ✓
* ~~Multi-set item loading — probes up to set12 numerically (DirAccess fails on APK); 12 sets / ~700 items currently loaded~~ ✓
* ~~Hit-test via `get_global_rect()` — fixes coordinate mismatch on Android with stretch mode~~ ✓

**Feel & Polish**
* ~~Taller cells — CELL_H increased to 130; items stay at TOP_PAD (not re-centered); full cell height is interactive~~ ✓
* ~~Preview (z-layer below) — darkened from 0.35 to 0.30 brightness~~ ✓
* ~~Generation improvement — flat-slot assignment guarantees every item type placed exactly ×3; 40% extra layers give natural 1–3-item sparsity without losing items~~ ✓
* ~~Layer reveal bug — `Cell.setup()` strips all-zero z-layers and advances past empty top layer; `_try_move` loops reveal until items surface~~ ✓
* ~~New Game button fix — background ColorRect set to `MOUSE_FILTER_IGNORE`; was blocking all clicks on Win panel (tree order beats z_index in Godot GUI routing)~~ ✓
* ~~Android touch pickup — `_find_pickup_slot_near(pos, 44px)` selects nearest non-empty slot on press; drag threshold doubled on mobile; `get_global_rect()` used consistently for all hit-testing~~ ✓

**New Mechanics**
* ~~Scrolling cells — one scrolling row max (`SCROLL_ROW_MAX = 1`, bump to 2 for testing); continuous linear scroll (`SCROLL_INTERVAL = 2.5 s` tween, no pause); 1 off-screen buffer cell per scrolling row for seamless wrap; fade-out on exit, fade-in on entry; `tween_method` + `roundf()` prevents sub-pixel wobble~~ ✓
* ~~Dispenser cell — 1-tall cell below the main board; items pulled from the main pool (mixed types, 2 siblings remain in the grid); can take items out but not place back in; auto-advances z-stack; ⬇ indicator label~~ ✓
* ~~Locked cells — dark overlay covers full cell; unlocked by N matches anywhere (2 on Medium, 3 on Hard); counter shown in overlay; fade-out animation on unlock~~ ✓
* ~~Cascading special probability — in `_apply_difficulty_layout()`, types shuffled then rolled with decaying probability (base 0.55/0.38, ×0.42 per win); ensures "nothing" and "one tweak" are common, "all three" is rare~~ ✓
* ~~Auto-clear initial matches — `start_game()` scans all cells after drop-in and processes any pre-generated 3-matches~~ ✓
* ~~Item perspective overlap — `SLOT_OVERLAP = 12`, `SLOT_Y_OFFSET = 16`; bottom item renders on top (tree order); dispenser slot 0 reset to y=0~~ ✓
* ~~Drag snap fix — fallback nearest-empty radius search now always runs as a second pass (was blocked when exact hit landed on locked/dispenser cell)~~ ✓
* ~~More dispensers — up to 4 per board; sub-probability decays ×0.45 after count ≥ 2~~ ✓
* ~~Hazard dispenser belt — Hard only; `DISP_SCROLL_CELLS = 6` rightward-scrolling dispenser cells above the board (opposite main conveyor); 6th cell off-screen → invisible wrap; items allocated from main pool~~ ✓
* ~~Mystery items — Medium+, 60% chance, 3–5 items; near-black dusty-blue silhouette with vetka "?" overlay; scattered across visible AND z-stack layers; mystery state travels with item on move; never revealed on tap (blind matching); drag sprite also darkened~~ ✓
* ~~Dispenser depth indicator — row of small blue dots at bottom of dispenser cell; count = items remaining; auto-updates via `_refresh_dispenser_indicator()` on every `_refresh_all()`~~ ✓
* ~~Locked cell counter font — uses vetka.ttf~~ ✓

**Quality of Life**
* Ambient music track (placeholder commented out in Main.gd — assign when ready)
* ~~Item put-down SFX — `item_put_down.mp3` plays on every successful item placement~~ ✓
* ~~Consecutive-match combo SFX — escalating `note_1`…`note_7` (borrowed from gem_match); volume ramps from `COMBO_VOL_MIN_DB = -10` to `COMBO_VOL_MAX_DB = -3`; streak resets after 5 s of no match (`STREAK_RESET_DELAY`) so repositioning moves don't break the combo~~ ✓
* ~~Per-set SFX infrastructure — `_item_set_map` tracks item_id → set_num; `_load_textures()` auto-loads `set{N}/match.mp3` if present; plays alongside combo note for material texture; placeholder = none (user drops files in to activate)~~ ✓
* SFX — item pick-up, win fanfare
* Style pass — menu TextureButtons, logo, background art

**Crash & Bug Fixes (done)**
* ~~Back-navigation crash — `start_game()` lambdas and scroll timer lambda now guard `is_instance_valid(self)`; validity check added after every `await`~~ ✓
* ~~Scroll buffer-cell gap — buffer cells excluded from `prepare_board()` y-offset and `start_game()` drop-in tween via `_buffer_cells` tracking array; were erroneously tweened to `modulate:a = 1.0`, appearing visible at off-screen position~~ ✓
* ~~Scroll coroutine crash — `_advance_scroll` converted from `await`-based coroutine to plain `tween.finished.connect` lambda; avoids "lambda capture freed" crash pattern when scene is freed mid-scroll~~ ✓
* ~~Scroll stale-lambda gap (difficulty reload) — `_game_generation` counter incremented in `prepare_board()`; scroll lambda bails out on mismatch, preventing a deferred-queue_free race from overwriting the fresh `_cells` array~~ ✓

---

## Human Tasks

**Art**
* Background art for the game screen
* "POTION_3" logo (or final game name) for Menu + MasterMenu tile
* Menu TextureButtons (Start, Back, difficulty selector)
* Win screen art / decoration
* Dispenser cell visual — currently uses the standard cell bg with a ⬇ label; can be replaced with custom art
* Locked cell overlay — currently a dark panel with a counter; can be replaced with a lock-icon graphic

**Sound**
* ~~Match combo SFX~~ ✓ (escalating notes from gem_match — replace with final sounds when ready)
* ~~Item place SFX~~ ✓ (`item_put_down.mp3`)
* Per-set match SFX — drop `set{N}/match.mp3` files in item set folders for material-specific sounds (metal clink, wood thud, food squish…); infrastructure already wired
* Item pick-up SFX
* Win fanfare
* Ambient track

**Design Decisions**
* ~~Final game name (POTION_3 is placeholder)~~ → decide when doing art pass
* ~~Should scrolling row speed increase with difficulty, or be fixed?~~ → Fixed (`SCROLL_INTERVAL = 2.5 s`); bump to tune
* ~~Dispenser cell count per board?~~ → Cascade-rolled: Medium 0–1, Hard 0–2; items pulled from main pool
* ~~Locked cell unlock count?~~ → 2 matches on Medium, 3 on Hard
* ~~Should Zen difficulty mix all special cell types?~~ → Yes (Zen picks random Easy/Medium/Hard layout including its specials)

* * *
* * *
# ZEN FARM

## Machine (Claude) Tasks

**Core (Done)**
* ~~Scaffold folder structure, scripts, scenes, MasterMenu tile~~ ✓
* ~~4×4 grid of FarmCell nodes; LOCKED/SOIL/CROP/WILTED/WEED states~~ ✓
* ~~Crop growth loop — 4 stages (seed/sprout/growing/mature); watered flag; wilt on neglect~~ ✓
* ~~Weed spawning — every 45 s, 40% chance on idle soil; capped at 30% of soil tiles~~ ✓
* ~~Tool system — HAND, WATERING CAN (resource), SHEARS (harvest/cut)~~ ✓
* ~~Watering can — capacity 5; depletes on use; refills at Well~~ ✓
* ~~Coin economy — harvest earns coins; sell button sells inventory at 70%; buy land costs coins~~ ✓
* ~~Dynamic land pricing — 2c/4c/12c/25c per 4-tile bracket; all locked tiles show current price~~ ✓
* ~~Onboarding — all tiles locked at start; tip panel on first play~~ ✓
* ~~5 crops with milestone unlocks — Lettuce always, Carrot@4, Potato@8, Tomato@12, Pumpkin@16~~ ✓
* ~~Seed costs — Lettuce 1c → Pumpkin 6c; paid on planting, not purchase~~ ✓
* ~~Watering can upgrade shop — Lv0→Lv1 (15c, 10 charges) → Lv2 (35c, 20 charges, MAX)~~ ✓
* ~~Save / load + offline catch-up (growth/wilt simulated from timestamp delta)~~ ✓
* ~~Coin float animation on harvest; tile pop animation on unlock~~ ✓
* ~~Economy safety nets — weed cut earns 1c; seed uproot refunds half cost; purchase guard vs 0-coin softlock~~ ✓
* ~~SFX system — 10 AudioStreamPlayer nodes; graceful no-op when files missing~~ ✓
* ~~Music — melodic loop + ambient loop in Main.gd; starts on load, stops on back-to-master~~ ✓

**Feel & Polish**
* Crop milestone notification animation — flash or banner when new seed type unlocks (currently just StatusLabel)
* Harvest animation — beyond coin float; maybe a brief cell flash or bounce
* Well fill animation — visual ripple or fill indicator on the well panel
* Weed spawn animation — subtle "pop-in" when a weed appears
* Can upgrade celebration — something more satisfying than just the status label
* Win / completion state — what happens when all 16 tiles are unlocked and all crops are mature? Some kind of zen moment

**Quality of Life**
* Weed tip on first weed spawn — currently shows in StatusLabel; consider a TipPanel card like the intro
* Crop milestone TipPanel cards — show what the newly unlocked crop costs/earns
* Better "no action" feedback — distinguish "wrong tool" (redirect) vs "genuinely nothing here"
* Time-to-mature indicator on crop tiles (e.g., a small progress bar or stage dots)

---

## Human Tasks

**Art**
* Background art for the game screen (farm/garden aesthetic)
* "ZEN FARM" logo for Menu + MasterMenu tile card
* Replace menu text buttons with TextureButtons
* Well panel art — currently a plain gray rectangle
* ToolBar icons — HAND, CAN, SHEARS are text buttons; need icon textures or illustrated buttons
* FarmCell visual polish — crops are color blocks with text labels; could use simple sprite art
* Coin float label polish — currently plain vetka text; could use a coin icon
* Win / completion screen art

**Sound**
* `sfx/plant.mp3` — satisfying seed-plop or soil-pat
* `sfx/water.mp3` — water pour / sprinkle
* `sfx/well_fill.mp3` — bucket fill / splash
* `sfx/harvest.mp3` — shear snip / crop pull
* `sfx/weed_cut.mp3` — grass slash / snip
* `sfx/buy_land.mp3` — earth thud / stone chunk
* `sfx/sell.mp3` — coin clink / register
* `sfx/upgrade.mp3` — level-up chime
* `sfx/crop_tap.mp3` — soft inspection ping
* `sfx/no_action.mp3` — very soft thud / nope
* `music/music.mp3` — melodic loop (set loop=true in Godot import)
* `music/ambient.mp3` — nature/wind ambient loop (set loop=true in Godot import)

**Design Decisions**
* ~~Should all tiles start locked?~~ ✓ Yes — all 16 locked; dynamic pricing by bracket
* ~~Should seeds cost coins?~~ ✓ Yes — 1c–6c depending on crop
* ~~Watering can upgrade model?~~ ✓ 5→10→20 charges for 15c/35c
* ~~Weed cut reward?~~ ✓ +1c to provide a recovery path
* Should weeds have a "danger" escalation? (e.g., spread to adjacent tiles over time)
* Is 45 s weed interval right for mobile play sessions? Consider tuning
* Should there be a "prestige" or reset loop once the farm is fully unlocked?
* Final game name ("ZEN FARM" is placeholder)

* * *
* * *
# ALL GAMES / GLOBAL

## Machine (Claude) Tasks
* ~~Fix game board layout to use dynamic viewport height — tile_chain hardcodes `810.0`; gem_match centering may also be affected; audit all games~~ ✓ (tile_chain + alchemical_sort fixed; others already dynamic)

## Cross-cutting Tasks (Human + Machine)
* ~~Audit Android hardware back button handling in all four games — ensure `NOTIFICATION_WM_GO_BACK_REQUEST` is handled consistently everywhere~~ ✓ (added to gem_match Game.gd + all four Menu.gd files)
