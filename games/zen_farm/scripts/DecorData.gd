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
const PAVILION = 5

enum Footprint { SLOT, PLOT, WATER_PLOT }

const _DIR := "res://games/zen_farm/assets/"
# Walkway parts sheet (walkway.aseprite at 4x): row 0 = 16 landings indexed by joined sides
# (1 left, 2 right, 4 up, 8 down); row 1 = half-arms, plain and bank-end (with posts).
const WALKWAY_TEXTURE := _DIR + "prop_walkway.png"

# Shop display order.
static func all_ids() -> Array[int]:
	return [LANTERN, BEEHIVE, BRIDGE, WELL, TEA_HUT, PAVILION]

static func prop_name(id: int) -> String:
	match id:
		LANTERN: return "Stone Lantern"
		BEEHIVE: return "Beehive"
		BRIDGE:  return "Bridge"
		WELL:    return "Well"
		TEA_HUT: return "Tea Hut"
		PAVILION: return "Water Pavilion"
	return "?"

static func cost(id: int) -> int:
	match id:
		LANTERN: return 20
		BEEHIVE: return 30
		BRIDGE:  return 25
		WELL:    return 50
		TEA_HUT: return 120
		PAVILION: return 150
	return 0

static func footprint(id: int) -> Footprint:
	match id:
		LANTERN, BEEHIVE: return Footprint.SLOT
		BRIDGE, PAVILION: return Footprint.WATER_PLOT
	return Footprint.PLOT

# Bridges and pavilions link up into one walkway network over the water.
static func is_walkway(id: int) -> bool:
	return id == BRIDGE or id == PAVILION

# Sprite sheet (frames laid out horizontally). Bridges are built from WALKWAY_TEXTURE instead.
static func texture_path(id: int) -> String:
	match id:
		LANTERN: return _DIR + "prop_stone_lantern.png"
		BEEHIVE: return _DIR + "prop_beehive.png"
		WELL:    return _DIR + "prop_well.png"
		TEA_HUT: return _DIR + "prop_tea_hut.png"
		PAVILION: return _DIR + "prop_water_pavilion.png"
	return ""

# One frame, in screen px (4x art).
static func frame_size(id: int) -> Vector2i:
	match id:
		LANTERN, BEEHIVE: return Vector2i(64, 128)
		WELL, TEA_HUT, PAVILION: return Vector2i(128, 192)
	return Vector2i(64, 64)

# Frame holding the night-lit variant; -1 when the prop has no light.
static func lit_frame(id: int) -> int:
	match id:
		LANTERN, TEA_HUT, PAVILION: return 1
	return -1

# Where the warm light sits, from the prop's base point (bottom-centre of its footprint).
static func light_offset(id: int) -> Vector2:
	match id:
		PAVILION: return Vector2(0, -114)   # between the two eave lanterns
	return Vector2(0, -70)                  # lantern window / tea hut door
