**Zen Games — project review, 7 October 2026**

The five games have their core loops. The most valuable remaining work is reliability, phone layouts, consistent presentation, audio completion, and a reproducible release process. Several entries in the old TODO are already implemented and should be retired.

The initial review covered the `potion3-shop-ui` working tree, including the existing uncommitted shop art and Android splash work. Gameplay files were left unchanged during that review. The implementation pass below fixes the requested reliability items. Review scripts, isolated test saves, logs, and desktop previews are under `.godot/`. The player's normal saves were not used.

**Implementation progress, 7 October 2026**

- [x] Items 1-4: Android Back hierarchy, Alchemy undo protection and lifecycle cancellation, Gem Match lifecycle cancellation.
- [x] Items 6-10: correct Potion difficulty records, farm exit saves, checked writes and recovery, recoverable New Farm, transition locks.
- [ ] Item 5: deferred at your request; friends use 20:9 phones.
- [x] Back behavior accepted: user confirmed it works during live testing on 7 October. Automated checks cover play -> game menu -> main menu -> app closes across all five games.
- [ ] Items 11-57: remain open for later passes, including art and presentation work.

Validation: 128 release regression checks, 6,265 farm menu checks, 855 farm decor checks, and 332 alchemical lamp checks passed with zero failures (7,580 checks total). The separate hub navigation/quit check passed too. Farm confirmation and restore controls were also inspected in a rendered 540 x 1200 preview. Test app data is isolated inside `.godot/`; normal player saves were preserved.

**Priority key**

- P1: fix before a release or substantial additional polish.
- P2: finish or improve during the next development pass.
- P3: optional additions or decisions about future scope.

“Reproduced” means a targeted desktop Godot check demonstrated the behavior. “Observed” means it is present in the current code, assets, or rendered previews. “Validation” means it still needs the named runtime/device check.

**Fix first**

1. **Implemented: Android Back follows the requested hierarchy.** One scene controller handles native Back for each game; automatic Android quit is disabled. Gameplay returns to its game menu, the game menu returns to the hub, and Back at the hub closes the app. Hidden scenes do not handle the same event; repeated Back during fades is ignored. Farm confirmations dismiss first. Desktop notification tests pass across all five games; the user also confirmed Back works during live testing on 7 October. Sources: `scripts/GameNavigation.gd`, `scripts/MasterMenu.gd`, each game's `Main.gd`.

2. **Fixed: Alchemical Sort cannot undo an unfinished pour.** Undo is rejected while pouring and remains available once the pour completes. Regression checks confirm a two-layer pour keeps two layers, and ordinary undo restores them without duplication. Source: `games/alchemical_sort/scripts/Game.gd`.

3. **Fixed: Abandoned Alchemical Sort operations cannot touch a later board.** Leaving or rebuilding invalidates the board generation, cancels board tweens, and clears pouring, queued taps, selection, and transient effects. Pour, undo, catalyst, mystery reveal, and entrance continuations check their generation. Regression checks cover re-entry at several pour phases and rebuilding during undo, catalyst transfer, and mystery reveal. Source: `games/alchemical_sort/scripts/Game.gd`.

4. **Fixed: Gem Match cannot reactivate after leaving.** Startup, swapping, matching, special effects, collapse/fill, shuffle, level-up, and delayed sound continuations are tied to the current board. Leaving stops board tweens and input; an old operation cannot activate or modify a replacement board. Normal swap/cascade scoring and early-exit/re-entry checks pass. Source: `games/gem_match/scripts/Game.gd`.

5. **Deferred at your request: Make layouts fit shorter portrait screens and respond to resizing.** Observed in rendered 540×960 previews: the hub's farm tile and mute button extend below the viewport; Gem Match's level-mode button and gameplay Back button are outside it; Tile Chain's Back button is outside; Alchemical Sort's Back button is partly outside; Potion Sort's difficulty buttons are clipped and its Back button is outside; the farm's bottom toolbar is outside. Some boards also retain their previous positions after resize. Fit board and controls together, then account for phone cutouts/system insets. Sources: `scenes/MasterMenu.tscn` and each game's `Menu.tscn`/`Game.tscn`; `.godot/review_previews.stdout.log`.

6. **Fixed: Potion Sort loads the record for the resolved difficulty.** The record is loaded after the board resolves Easy/Medium/Hard, including every Zen reroll. Tests check separate records, a Medium improvement, and preservation of the other difficulty keys. Source: `games/potion_3/scripts/Game.gd`.

7. **Fixed: Farm exits save consistently.** The Back button and Android Back use the same checked save-and-exit operation. Pause/close save an open farm; cold or hidden farm instances cannot overwrite the saved state. Hidden gameplay processing is paused. A failed exit save leaves the farm open for retry. Tests cover hardware Back, pause after exit, Continue, and failed-save retry. Sources: `games/zen_farm/scripts/Game.gd`, `Main.gd`.

8. **Fixed: Saves keep a previous good copy and check failures.** Farm, best-score, and audio writes use a shared helper: write and flush a temporary file, verify its contents, keep a checked backup, then replace the primary. Farm loading falls back to the backup and uses the same file for dimensions and state. Failed writes/backup copies are reported and preserve the primary; unreadable/partial farm metadata cannot replace a good backup. Tests cover recovery and write/backup failures. Sources: `scripts/SafeConfig.gd`, `games/zen_farm/scripts/SaveManager.gd`, score/audio save callers.

9. **Fixed: New Farm is confirmed and recoverable.** An existing farm requires confirmation. It is retained in `user://zen_farm_previous.cfg`; later autosaves do not overwrite that retained farm. RESTORE PREVIOUS FARM appears in the farm menu when the retained save is usable. New Farm is cancelled if retaining or saving fails. Tests cover cancellation, confirmation, later saves, restore, and backup failure. Sources: `games/zen_farm/scripts/Menu.gd`, `Main.gd`, `SaveManager.gd`.

10. **Fixed: Navigation transitions cannot overlap.** The hub and all game controllers lock navigation during fades; the fade overlay blocks taps. Locks release when the destination is visible, while board entrances remain cancellable through Back. Repeated-start, repeated-Back, and repeated-hub-selection checks pass. Sources: `scripts/GameNavigation.gd`, `scripts/MasterMenu.gd`, game `Main.gd` files.

**Shared presentation and usability**

11. **P2 — Finish the hub's game cards.** The hub background and Gem Match logo are present, but the other four choices remain plain button rectangles with labels. Give each game a recognizable illustration/logo and consistent pressed feedback. Source: `scenes/MasterMenu.tscn`.

12. **P2 — Finish the first-launch splash.** `_show_splash()` still constructs a plain ColorRect and TAP TO START text. Decide on the final introduction, use the existing artwork where appropriate, and connect the native Android splash, audio-unlock screen, and hub transition into a coherent sequence. Source: `scripts/MasterMenu.gd:30`; `assets/bg_master_intro.png`; `android/splash/`.

13. **P2 — Give mute states distinct, understandable artwork.** All three states currently reuse the same Back-arrow textures. Players cannot tell all-on, music-off, and all-off apart. Add proper icons/state labels and a suitable touch target. Source: `scenes/MasterMenu.tscn:186`; `scripts/MuteButton.gd`.

14. **P2 — Make audio settings reachable while playing.** The reusable mute script is only used on the hub. Add a consistent settings entry without requiring players to leave a puzzle to change sound. Decide whether ambience and haptics have separate controls; haptics currently follow full audio mute. Sources: scene references to `MuteButton.gd`; `scripts/Haptics.gd`.

15. **P2 — Add short, replayable instructions for the puzzle games.** The farm has an introductory card; the other games lack an equivalent explanation. Cover Gem Match's upgrades/specials, Tile Chain's shared-layer chain, bottle pour rules, and Potion Sort's hidden layers, locks, dispensers, and conveyors. A one-screen explanation plus a help entry is enough initially.

16. **P2 — Standardize touch handling.** Potion Sort restricts play to finger zero and avoids mobile mouse duplication; Gem Match and the farm do not have equivalent pointer ownership. Test two fingers, emulated mouse events, cancel/release, dragging across UI, and leaving while a finger is held. Farm drag distance also only accumulates horizontal movement. Sources: Gem Match `Tile.gd:324`/`Game.gd:525`; farm `Game.gd:2032`; Potion Sort `Game.gd:675`.

17. **P2 — Define background/pause behavior for timed modes and audio.** Verify Android Home, screen lock, app switching, and browser tab switching. Choose whether an optional timed round pauses or resumes, and prevent surprise countdown loss or audio continuing unexpectedly. Gem Match currently has no explicit application-pause handling.

18. **P2 — Improve readability on touch screens.** Review tiny HUD labels, difficulty plaques, low-contrast text, and actual phone touch sizes. Alchemical Sort needs a way to distinguish close colors without relying only on hue. Hover-only tooltips need touch alternatives.

19. **P3 — Add a small comfort/settings pass.** Optional reduced motion, gentler flashes/shake, independent music/SFX levels, and haptics control would suit the relaxed design. Preserve the existing atmosphere and defaults.

**Gem Match**

20. **P2 — Finish the timed/level end panels.** The code works, but panels are still assembled from a dark overlay, labels, and flat text buttons. Match them to the established gem/stone artwork and show results clearly. Source: `games/gem_match/scripts/Game.gd:217`.

21. **P2 — Explain and present modes consistently.** The normal Start button has dedicated art while TIMED MODE and LEVEL MODE are plain text. Add brief mode descriptions and optionally surface saved records before starting. Keep timed play clearly optional.

22. **P3 — Review special-gem presentation against the final art direction.** Bombs, crosses, and color bombs already have animated/procedural effects; the old task to replace plain colored squares is obsolete. Check whether the current ember/lightning/orbit markers are sufficiently distinct and readable during cascades. Source: `games/gem_match/scripts/Tile.gd:117`.

**Tile Chain**

23. **P2 — Finish the menu identity and controls.** The title, Start, and Quit are plain text. Add the final logo/buttons and rename QUIT to BACK because it returns to the hub. Source: `games/tile_chain/scenes/Menu.tscn`.

24. **P2 — Rework the board frame and HUD for the current viewport.** The current rendered game has broad gray areas above/below the illustrated board, with very small combo/best labels. Align the frame, board, labels, and controls across supported heights instead of stretching an older fixed composition. Source: `games/tile_chain/scenes/Game.tscn`; `Game.gd:198`.

25. **P2 — Finish Tile Chain sound.** Removal reuses Gem Match's `no_match.mp3`; the break and milestone players have no streams. Choose subtle removal, chain-break, and milestone sounds and balance their levels. Source: `games/tile_chain/scenes/Game.tscn:136`, `:230`.

26. **P3 — Add tileset choice or more themes if desired.** Three sets already exist and random selection/validation are implemented. A preferred-set selector or additional themes would be new content, rather than unfinished core functionality. Source: `games/tile_chain/assets/Set_1..3`; `Game.gd:111`.

**Alchemical Sort**

27. **P2 — Add pour and completion audio.** The game has its music and visual effects, but no pour/glug or completed-vial SFX wiring. These are a substantial missing part of the feel. Sources: `games/alchemical_sort/scripts/Game.gd`; `scenes/Game.tscn`.

28. **P2 — Finish the solved/dead-state presentation.** Style the result, best-move feedback, and no-moves/reshuffle controls to match the cabinet UI. The recent cabinet, bottle art, lamps, sparkles, fog, and completion gleam are already present.

29. **P2 — Strengthen puzzle generation and recovery.** Random layer distribution preserves counts but does not establish solvability. `_has_valid_move()` only finds an immediate legal pour, including reversible moves into empty vials. Validate generated boards or generate from a solved state using legal reverse operations, and offer a clear user-requested restart/hint path even when legal cycles remain. Source: `Game.gd:365`, `:499`, `:521`.

30. **P2 — Specify undo behavior for catalyst effects.** The undo snapshot stores only liquid layers, while catalyst consumption/rune state and mystery reveal state live separately. Decide which of those changes undo should restore, and cover the chosen policy with a focused check. Source: `Game.gd:566`, `:806`; `Vial.gd:226`.

31. **P2 — Explain the rune and Zen helper vessel.** These already work as special mechanics but have little player-facing explanation. Make the benefit and capacity visible without requiring experimentation or reading code. Source: `Game.gd:328`, `:346`.

**Potion Sort**

32. **P2 — Finish Potion Sort's audio identity.** Its own music remains commented out, so the hub track continues. Item placement and combo notes work; pickup, win, and per-material match sounds remain absent. No `set*/match.mp3` files currently exist despite support for them. Sources: `Main.gd:12`; `Game.gd:356`, `:974`.

33. **P2 — Decide how records/results should be shown.** Move and best labels are hidden in the scene, the best label is deliberately hidden in code, and the win-move label is also hidden. Preserve the clean board, but show move count and a correct best/new-best result on the solved panel if records remain a feature. Sources: `Game.gd:1068`, `:1293`; `scenes/Game.tscn:334`.

34. **P2 — Validate the new box artwork through all interactions.** The new frames, lock cover, and depth indicators are already implemented. Check overlap, nearest-slot pickup, hidden-layer previews, mystery silhouettes, lock/undo transitions, dispenser depletion, and both conveyor directions on phones. Keep item conservation as an explicit regression invariant. Sources: `scripts/Cell.gd`; `scripts/Game.gd`.

35. **P3 — Make item-theme selection a deliberate option.** The game currently mixes a large library across its item sets. Optional themed rounds or a set preference could improve visual coherence and recognition without adding a new mechanic. Source: `Game.gd:356`, `:522`.

**Zen Farm**

36. **P2 — Choose the release economy and progression pace.** New farms currently start with 10,000 coins, although the initial field value is 10. Confirm whether this is intended free-play or a development allowance, then tune flower seed/harvest/sell values, land pricing, upgrades, and decor costs around that decision. Source: `Game.gd:574`; `CropData.gd`; `DecorData.gd`.

37. **P2 — Gate the weather/day/night development shortcuts.** R, D, and N remain enabled in regular gameplay input. Put them behind a debug/developer option if they are not intended public controls. Source: `Game.gd:2038`.

38. **P2 — Make seed selection clearer on phones.** Most buttons show only a cost, unlock number, or W. Names are supplied as tooltips, and W does not explain the water upgrade prerequisite. Add touch-visible seed information and meaningful locked-state feedback. Source: `Game.gd:4320`.

39. **P3 — Add crop progress when inspecting a flower.** A compact stage/time/water explanation on selection or hold would help players understand growth without filling the garden with permanent bars. The existing harvest icons and status feedback should remain useful.

40. **P2 — Make unlocks and offline returns understandable.** Show clear feedback when a new flower or surface upgrade becomes available, and explain what grew or wilted while away. Coin/tool pulses, harvest icons, rain, and Full Bloom effects already exist; build on those instead of repeating their implementation.

41. **P2 — Version and validate the farm save schema.** There is partial legacy migration, but no explicit schema version or broad validation of saved columns, stages, crop IDs, water/can levels, and slot state. Invalid stages can reach indexed duration lookups. Add bounded validation, migrations, and recovery for malformed/older saves. Sources: `SaveManager.gd:61`, `:157`; `Game.gd:2118`, `:2660`.

42. **P2 — Resolve the failing well-art assertion.** The current native animation changes three pixels at x=13..15, y=30. The test only allows y=31..33, so it fails despite a very small animation. Inspect the intended waterline and update either the asset or the test; do not record the art suite as passing. Source: `tests/check_zen_farm_art.py:47`; `assets/prop_well.png`.

43. **P3 — Choose a long-term garden goal.** The garden expands by adding columns and already has Full Bloom. Optional garden statistics, saved screenshots, arrangements, or cosmetic milestones could give continued play a purpose. The old proposal for completion at 16 plots is obsolete. Orders, irrigation networks, storage limits, seasons, and prestige from the old spec are scope decisions, not missing commitments.

**Engineering, release, and maintenance**

44. **P2 — Share the existing tests and their run instructions.** `tests/` is ignored by Git and no test files are tracked. A fresh checkout loses the checks that currently protect the garden and lamp. Track the small useful harnesses, document isolated APPDATA and expected summary/exit code, and list the Python art check's Pillow requirement. Source: `.gitignore:56`; `tests/`.

45. **P2 — Add coverage for the uncovered high-risk behavior.** Existing checks focus on farm visuals/decor and lamp behavior. Add targeted regressions for the reproduced issues above, five-game navigation, gem special combinations, bottle count conservation, potion item conservation through undo/conveyors/locks, and farm save/offline migrations. A useful test must fail on a script error even when Godot exits zero.

46. **P2 — Check repeated scene changes for accumulating resources.** The farm checks and review harnesses report ObjectDB/resource warnings at exit. Determine which belong to test cleanup and verify that repeated hub/game/menu changes do not steadily increase live nodes, timers, or memory. The warnings alone do not establish a production leak.

47. **P2 — Measure phone performance and hidden-scene work.** Profile large expanded farms, rain plus wildlife/Full Bloom, dense bottle effects, and Potion Sort's animated conveyors. The real farm continues processing while hidden; several games retain timer/animation work behind menus. Establish frame time, memory, loading time, and battery-sensitive idle behavior before deciding what to optimize. Source: farm `Game.gd:1629`; game animation/timer loops.

48. **P2 — Make a small maintenance pass where fixes require it.** The farm controller is 5,226 lines; the gem controller is 1,922. Extract save validation, transition cancellation, or clearly reusable UI/audio pieces incrementally as those areas are repaired. Preserve current scene and save contracts. Retire unused backup code only after confirming references and keeping source art backed up.

49. **P2 — Replace the stale backlog and handoff docs.** README percentages and claims about missing art/audio do not match the current games. TODO still lists many completed features; CLAUDE/mythos notes include outdated paths, tests, palette counts, and already-fixed refresh/debug details. Keep one current backlog, archive the old farm spec, update screenshots, and describe timers as optional modes. Sources: `README.md`, `TODO.md`, `CLAUDE.md`, `mythos_notes.md`, `FARM_GAME_SPEC.md`.

50. **P1 for Web release — Configure and verify a supported Web renderer.** The project selects Mobile rendering and has no Web-specific renderer override. Godot 4.3 Web supports Compatibility, not Mobile. Choose a Web-specific configuration or explicitly validated renderer strategy, then check every shader/effect in the exported browser build. Source: `project.godot:40`; [Godot 4.3 Web export documentation](https://docs.godotengine.org/en/4.3/tutorials/export/exporting_for_web.html#webgl-version).

51. **P2 — Run an exported Android acceptance pass.** Verify system Back, shorter/taller screens and insets, two-finger input, drag/release, pause/resume, haptics, all mute states, save survival across app upgrades, native splash, and cold launch. The custom splash requires the local template/setup steps and Gradle build; desktop previews cannot confirm the Android result. Source: `android/splash/README.md` and `setup.py`.

52. **P2 — Run an exported browser acceptance pass.** Verify first-gesture audio, music/SFX behavior, resizing, touch and mouse, save persistence, tab sleep, loading time, PWA offline/update behavior, and the desired mobile browsers. The Web preset currently enables desktop texture compression and disables its mobile counterpart; validate the intended targets. Source: `export_presets.cfg`; [Godot 4.3 Web export documentation](https://docs.godotengine.org/en/4.3/tutorials/export/exporting_for_web.html).

53. **P2 — Make the current working tree reproducible from Git.** The Alchemical Sort cabinet UI, Potion Sort's new box textures, and Android splash files are currently untracked. Several are directly referenced/preloaded by modified scenes/scripts. Include the intended assets with their code when committing, and verify a fresh checkout can import and run. Keep the existing user changes intact until that handoff is prepared.

54. **P2 — Keep export configuration reproducible and packages focused.** Export presets are ignored, version name is empty locally, and both presets export all resources without exclusions. Provide a sanitized configuration/setup guide and explicit release versioning. Exclude test scripts and review-only resources from shipped packages; inspect the resulting package before removing candidate unused assets. Source: `.gitignore`; `export_presets.cfg`; `tests/` has no `.gdignore`.

55. **P2 — Record asset sources and retain editable artwork.** The repository has the project GPL license but no separate asset/font/music credits manifest. Document sources/permissions/required attribution, and ensure ignored Aseprite source art has a deliberate backup/sharing arrangement. This makes future redistribution and art updates reviewable. Sources: `LICENSE`; `.gitignore:55`; `art_src/`.

56. **P3 — Plan an engine upgrade after a reliable baseline.** Godot 4.3 is the current verified engine and its official documentation now marks it unsupported. A future upgrade should be a separate change with renderer, shader, Android export, Web audio, and save compatibility checks. Source: [Godot 4.3 documentation](https://docs.godotengine.org/en/4.3/tutorials/export/exporting_for_web.html).

57. **P3 — Decide whether interrupted puzzle rounds should resume.** The four puzzle games currently save records rather than the active board. Optional Continue/Resume would suit short mobile sessions, particularly long Potion Sort rounds. Keep it separate from the farm's existing persistent progress and make snapshot/migration rules explicit.

**Already implemented — retire these old TODO entries**

- Farm pixel art, nine flowers including Lotus, toolbar skin/icons, garden props, natural decor, connected walkways, day/night, rain, insects/frogs, ambient audio, Full Bloom, and the full-screen randomized menu garden.
- Alchemical Sort bottle/liquid artwork, the fourteen-entry palette, cabinet/menu skin, mystery visuals, droplets, completed-vial sparkle/gleam, catalyst/Zen helper, and the living lamp/fireflies. The old Hard-mode palette-shortage claim is obsolete.
- Potion Sort's shop/menu/backdrop/candle, new box/lock/depth art, touch pickup, one-start-per-board protection, and identity-based undo snapshots that include dispensers/hazard belt.
- Tile Chain's three tilesets, random choice, missing-layer warnings, removal sparkles, selection effects, and record saving.
- Gem Match's animated gems/special indicators, cascades, hints, shuffle effects, timed/level modes, and saved timed/level records.
- Farm Main already uses `refresh_state()` rather than manually calling `_ready()`; Alchemical Sort's layout print is already debug-gated.

**Validation after the requested fixes**

| Check | Current result |
|---|---|
| Engine | Godot 4.3 stable, `77dcf97d8` |
| Release reliability regression | 128 checks, 0 failures, exit 0 |
| Hub navigation and Back-to-quit | Repeated taps, return to hub, and clean exit passed, exit 0 |
| Farm menu smoke | 6,265 checks, 0 failures, exit 0 |
| Farm decor smoke | 855 checks, 0 failures, exit 0 |
| Alchemical lamp smoke | 332 checks, 0 failures, exit 0 |
| Farm confirmation/restore rendering | Inspected at 540 x 1200 using Compatibility rendering |
| Source whitespace check | `git diff --check` passed |
| Farm art check from initial review | Failed on well-frame pixel bounds; item 42 remains open |
| User acceptance | User confirmed Back works during live testing on 7 October |
| Browser acceptance | Not part of these fixes; still open if a Web release is planned |

The failed-write regression fixtures deliberately produce file-open errors and save warnings; the checks confirm the old data survives and the game remains usable. Runs also emitted the existing sandbox certificate-store and shutdown cleanup messages. No runtime script errors appeared in the passing regression runs.

Current evidence: `.godot/release_reliability.stdout.log`, `release_reliability.stderr.log`, `release_hub_back.stdout.log`, `release_zen_farm_menu_smoke.stdout.log`, `release_zen_farm_decor_smoke.stdout.log`, `release_alchemical_lamp_smoke.stdout.log`, and the `release_*farm*.png` previews. Regression scripts: `tests/release_reliability_smoke.gd` and `tests/release_hub_back_smoke.gd`. All save testing used isolated app-data directories under `.godot/`.

Original review evidence is retained in `.godot/review_checks.stdout.log`, `review_lifecycle.stdout.log`, `review_lifecycle.stderr.log`, `review_previews.stdout.log`, and the `review_montage_*.png` previews.

**Suggested order of work**

Back behavior has been accepted during live testing. The requested reliability fixes are implemented; item 5 stays deferred. Then work through items 11-57 one by one. Check the Web configuration if a Web release is planned.
