"""Pixel-level checks for native scale, original palette, water-only motion and opaque joins."""
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "games/zen_farm/assets"
checks = 0


def check(condition, message):
    global checks
    checks += 1
    assert condition, message


def opaque_colors(image):
    return {p for p in image.getdata() if p[3]}


def verify_scale4(image):
    native = image.resize((image.width // 4, image.height // 4), Image.Resampling.NEAREST)
    check(native.resize(image.size, Image.Resampling.NEAREST).tobytes() == image.tobytes(),
          "Runtime export must retain exact 4x pixel blocks")
    return native


tiles = Image.open(ASSETS / "tileset.png").convert("RGBA")
objects = Image.open(ASSETS / "objects.png").convert("RGBA")
palette = opaque_colors(tiles.crop((0, 0, tiles.width, 384))) | opaque_colors(objects)
new_art = tiles.crop((0, 384, 960, 512))
check(opaque_colors(new_art) <= palette, "Natural decor must use only existing tile/flower colors")
native = verify_scale4(new_art)
for item in range(15):
    sprite = native.crop((item * 16, 0, item * 16 + 16, 32))
    box = sprite.getbbox()
    check(box is not None, f"Decor {item} must be visible")
    check(box[2] - box[0] <= 16 and box[3] - box[1] <= (24 if item == 9 else 16),
          f"Decor {item} must stay within its compact size budget")
    if item != 9:
        check(box[1] >= 16, "Small items must lie inside their registered bottom atlas row")

well = verify_scale4(Image.open(ASSETS / "prop_well.png").convert("RGBA"))
check(well.size == (64, 48), "Well sheet must have exactly two 32x48 frames")
changed = [(x, y) for y in range(48) for x in range(32)
           if well.getpixel((x, y)) != well.getpixel((x + 32, y))]
check(0 < len(changed) < 24, "Well water must move subtly, not flash or remain static")
check(all(7 <= x <= 24 and 31 <= y <= 33 for x, y in changed),
      "Only the water may change between well frames")

walk = Image.open(ASSETS / "prop_walkway.png").convert("RGBA")
verify_scale4(walk)
for mask in range(16):
    # Assemble exactly the regions and positions used by _build_bridge.
    plot = Image.new("RGBA", (128, 128))
    plot.alpha_composite(walk.crop((mask * 64, 0, mask * 64 + 64, 64)), (32, 32))
    if mask & 1:
        plot.alpha_composite(walk.crop((0, 64, 32, 128)), (0, 32))
        check(all(plot.getpixel((x, y))[3] == 255 for x in (0, 31, 32) for y in range(48, 80)),
              f"Left join must cover every water pixel (mask {mask})")
    if mask & 2:
        plot.alpha_composite(walk.crop((0, 64, 32, 128)), (96, 32))
        check(all(plot.getpixel((x, y))[3] == 255 for x in (95, 96, 127) for y in range(48, 80)),
              f"Right join must cover every water pixel (mask {mask})")
    if mask & 4:
        plot.alpha_composite(walk.crop((128, 64, 192, 96)), (32, 0))
        check(all(plot.getpixel((x, y))[3] == 255 for y in (0, 31, 32) for x in range(48, 80)),
              f"Upper join must cover every water pixel (mask {mask})")
    if mask & 8:
        plot.alpha_composite(walk.crop((128, 64, 192, 96)), (32, 96))
        check(all(plot.getpixel((x, y))[3] == 255 for y in (95, 96, 127) for x in range(48, 80)),
              f"Lower join must cover every water pixel (mask {mask})")

print(f"ZEN FARM ART: {checks} checks passed; 15 compact decor, original palette, "
      f"{len(changed)} water pixels animated, all 16 walkway masks have opaque joins")
