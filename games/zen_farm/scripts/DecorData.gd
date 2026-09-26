#DecorData.gd (zen_farm)
# Static data for placeable garden props. Art lives in games/zen_farm/assets/prop_*.png
# (sources in art_src/zen_farm/*.aseprite), exported at 4x like the rest of the farm art.
#
# Size rules: a building tile (slot) is 16x16 native = 64 px; a plot is 2x2 slots.
# Props may rise one building tile (64 px) above their footprint.
class_name DecorData

const LANTERN = 0
const BEEHIVE = 1
const BRIDGE  = 2
const WELL    = 3
const TEA_HUT = 4

enum Footprint { SLOT, PLOT, WATER_PLOT }

const _DIR := "res://games/zen_farm/assets/"

# Shop display order.
static func all_ids() -> Array[int]:
	return [LANTERN, BEEHIVE, BRIDGE, WELL, TEA_HUT]

static func prop_name(id: int) -> String:
	match id:
		LANTERN: return "Stone Lantern"
		BEEHIVE: return "Beehive"
		BRIDGE:  return "Bridge"
		WELL:    return "Well"
		TEA_HUT: return "Tea Hut"
	return "?"

static func cost(id: int) -> int:
	match id:
		LANTERN: return 20
		BEEHIVE: return 30
		BRIDGE:  return 25
		WELL:    return 50
		TEA_HUT: return 120
	return 0

static func footprint(id: int) -> Footprint:
	match id:
		LANTERN, BEEHIVE: return Footprint.SLOT
		BRIDGE: return Footprint.WATER_PLOT
	return Footprint.PLOT

# Sprite sheet (frames laid out horizontally). The bridge uses two sheets, see bridge_texture_path().
static func texture_path(id: int) -> String:
	match id:
		LANTERN: return _DIR + "prop_stone_lantern.png"
		BEEHIVE: return _DIR + "prop_beehive.png"
		WELL:    return _DIR + "prop_well.png"
		TEA_HUT: return _DIR + "prop_tea_hut.png"
	return ""

static func bridge_texture_path(vertical: bool) -> String:
	return _DIR + ("prop_bridge_v.png" if vertical else "prop_bridge_h.png")

# One frame, in screen px (4x art).
static func frame_size(id: int) -> Vector2i:
	match id:
		LANTERN, BEEHIVE: return Vector2i(64, 128)
		WELL, TEA_HUT:    return Vector2i(128, 192)
	return Vector2i(64, 64)

# Frame holding the night-lit variant; -1 when the prop has no light.
static func lit_frame(id: int) -> int:
	match id:
		LANTERN, TEA_HUT: return 1
	return -1
