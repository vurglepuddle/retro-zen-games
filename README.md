# Zen Games

**Zen Games** is a collection of small puzzle and garden games built with
Godot 4.3, primarily for Android. Web support is incoming.

There are no timers. No energy systems. Just tap-tap, clink-clink and some music. Gem Match also offers
**optional timed and level modes**; Zen Farm uses growth and weather cycles. All vibes.

## Android download

[Zen Games 1.0.2](https://github.com/vurglepuddle/retro-zen-games/releases/download/v1.0.2/Zen-Games-1.0.2.apk)

This is a release APK signed with the project's release key, for ARM32 and
ARM64 phones running Android 7.0 or newer. Download it on your phone, open it,
and allow your browser to install apps when Android asks. Google Play is not
required. Installing updates signed with the same key preserves your saves.

See the [release notes and SHA-256 checksums](https://github.com/vurglepuddle/retro-zen-games/releases/tag/v1.0.2)
for this build.

## Screenshots

Captured 20 October 2026 from the current scenes. Potion Sort and Zen Farm show
their menus. The gallery excludes Potion Sort's third-party item images.

<table>
  <tr>
    <td align="center"><img height="360" alt="Zen Games hub with five game choices and separate music and sound switches" src="assets/screenshots/master_menu.png" /><br />Hub</td>
    <td align="center"><img height="360" alt="Gem Match untimed board" src="assets/screenshots/match-3.png" /><br />Gem Match</td>
    <td align="center"><img height="360" alt="Tile Chain layered-symbol board" src="assets/screenshots/tile_chain.png" /><br />Tile Chain</td>
  </tr>
  <tr>
    <td align="center"><img height="360" alt="Alchemical Sort cabinet and bottles" src="assets/screenshots/alchemical_sort.png" /><br />Alchemical Sort</td>
    <td align="center"><img height="360" alt="Potion Sort shop menu" src="assets/screenshots/goods_match_3.png" /><br />Potion Sort menu</td>
    <td align="center"><img height="360" alt="Zen Farm randomized garden menu" src="assets/screenshots/zen_garden.png" /><br />Zen Farm menu</td>
  </tr>
</table>

## Current games

All five core loops are playable. The collection is still in development:
presentation, sound, instructions, puzzle generation, progression, phone
validation and release setup all have work remaining.

| Game | Implemented |
| --- | --- |
| **Gem Match** | Match-3 cascades, upgrading gems (topped by star, heart and sun), special gems with pixel-art fire, lightning and moon effects, locked gems, hints, automatic shuffling, an untimed mode, optional timed/level modes and their saved records. |
| **Tile Chain** | Layered-symbol pairing, combo chains, three randomly selected tilesets, selection/removal effects, reshuffling and a saved best combo. |
| **Alchemical Sort** | Bottle color sorting, Easy/Medium/Hard/Zen layouts, mystery rounds, undo, move records, catalyst/helper mechanics, cabinet art and interactive lamps. |
| **Potion Sort** | Triple-match shelf sorting, hidden layers, undo, conveyors, dispensers, locks, mystery items, move records and an interactive shop with candle, window, owl and cat. Item artwork requires a separate license; see below. |
| **Zen Farm** | A persistent, expanding flower garden with nine flowers, land/water plots, tools, upgrades, decor, inventory, offline growth, rain, day/night, wildlife, Full Bloom effects and a randomized garden menu. Pixel art, music and ambience are present. |



Puzzle games offer **Continue** for unfinished rounds. Music and sound effects
can be toggled during play, with controls styled to each game's artwork.

## Run and develop

Open [project.godot](project.godot) in Godot **4.3** and press **F5**. The entry
scene is [MasterMenu.tscn](scenes/MasterMenu.tscn). The project uses GDScript and a
540 × 1212 portrait viewport with `canvas_items` / `keep_width` stretching.

Android export uses the Godot build template and Gradle. Native splash setup
is documented in [android/splash/README.md](android/splash/README.md).
Export presets and signing settings are local and ignored by Git; a clean
checkout needs its own configuration.

## Asset credits and reuse

The project's original artwork, music, sound effects, and VETKA pixel font use
**CC BY-NC-SA 4.0, with credit to the project author optional**. You may copy,
share, and modify these assets for noncommercial purposes. Shared adaptations
must use the same license or an officially compatible license. Keep the license
and waiver information, indicate changes, and retain required third-party
notices.

Commercial use requires separate permission from
[vurglepuddle](https://github.com/vurglepuddle), including in open-source
projects. See [CREDITS.md](CREDITS.md) for the full asset terms, contact details,
and exclusions. The source code remains under [GPL-3.0](LICENSE).

Zen Farm / Zen Garden uses flowers, grass, and the stone-road texture from
[kathychow's 16x16 tiny garden free pack](https://kathychow.itch.io/16x16-tiny-garden-free-pack),
with modified and expanded flowers. The garden's original tileset work, water,
most decor, and other original additions are by `vurglepuddle`. Retained pack
artwork keeps its own terms; see [the garden credits](CREDITS.md#zen-farm--zen-garden-artwork).

## Potion Sort item artwork

The numbered item sets in `games/potion_3/assets/items/set*/` are third-party
licensed artwork. They are excluded from this repository and are not covered by
its GPL-3.0 license. To run Potion Sort with these images or other images, obtain
your own license and place the files at
`games/potion_3/assets/items/setN/itemN.png`.
Git ignores these local set folders. The other games' assets and Potion Sort's
own UI assets remain in the repository.
See [CREDITS.md](CREDITS.md) for the third-party exclusions.
