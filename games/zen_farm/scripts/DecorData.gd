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
const STONE_PATH = 6
const MOSSY_PATH = 7

enum Footprint { SLOT, PLOT, WATER_PLOT }

const _DIR := "res://games/zen_farm/assets/"
# Walkway parts sheet (walkway.aseprite at 4x): row 0 = 16 landings indexed by joined sides
# (1 left, 2 right, 4 up, 8 down); row 1 = half-arms, plain and bank-end (with posts).
const WALKWAY_TEXTURE := _DIR + "prop_walkway.png"

# Shop display order.
static func all_ids() -> Array[int]:
	return [LANTERN, BEEHIVE, BRIDGE, WELL, TEA_HUT, PAVILION, STONE_PATH, MOSSY_PATH]

static func prop_name(id: int) -> String:
	match id:
		LANTERN: return "Stone Lantern"
		BEEHIVE: return "Beehive"
		BRIDGE:  return "Bridge"
		WELL:    return "Well"
		TEA_HUT: return "Tea Hut"
		PAVILION: return "Water Pavilion"
		STONE_PATH: return "Stone Path"
		MOSSY_PATH: return "Mossy Path"
	return "?"

static func cost(id: int) -> int:
	match id:
		LANTERN: return 20
		BEEHIVE: return 30
		BRIDGE:  return 25
		WELL:    return 50
		TEA_HUT: return 120
		PAVILION: return 150
		STONE_PATH, MOSSY_PATH: return 5
	return 0

static func footprint(id: int) -> Footprint:
	match id:
		LANTERN, BEEHIVE, STONE_PATH, MOSSY_PATH: return Footprint.SLOT
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
		STONE_PATH, MOSSY_PATH: return _DIR + "tileset.png"
	return ""

static func is_path(id: int) -> bool:
	return id == STONE_PATH or id == MOSSY_PATH


# Existing stone artwork, at its original atlas coordinates.
static func frame_region(id: int, frame: int = 0) -> Rect2:
	match id:
		STONE_PATH: return Rect2(15 * 64, 64, 64, 64)
		MOSSY_PATH: return Rect2(16 * 64, 64, 64, 64)
	var fs := frame_size(id)
	return Rect2(frame * fs.x, 0, fs.x, fs.y)


# The well has one extra water frame; its masonry stays perfectly still.
static func animation_frames(id: int) -> int:
	return 2 if id == WELL else 1

static func animation_frame_seconds(id: int) -> float:
	return 0.85 if id == WELL else 0.0

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

# Visible light sources, from the prop's bottom-centre. Four screen px = one art pixel.
static func light_offsets(id: int) -> Array[Vector2]:
	match id:
		LANTERN: return [Vector2(0, -70)]
		PAVILION: return [Vector2(-28, -118), Vector2(24, -118)]
		TEA_HUT: return [Vector2(-30, -82), Vector2(0, -70), Vector2(30, -82)]
	return []

static func light_scale(id: int) -> float:
	return 1.3 if id == LANTERN else 1.25
