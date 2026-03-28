#CropData.gd (zen_farm)
# Static data class for crop definitions.
class_name CropData

const CARROT = 0
const LETTUCE = 1
const POTATO = 2

const STAGE_SEED    = 0
const STAGE_SPROUT  = 1
const STAGE_GROWING = 2
const STAGE_MATURE  = 3

static func crop_name(crop_id: int) -> String:
	match crop_id:
		CARROT:  return "Carrot"
		LETTUCE: return "Lettuce"
		POTATO:  return "Potato"
	return "?"

# Duration in seconds for each non-mature stage: [seed, sprout, growing]
static func get_stage_durations(crop_id: int) -> Array:
	match crop_id:
		CARROT:  return [15.0, 15.0, 15.0]   # 45 s total
		LETTUCE: return [20.0, 20.0, 20.0]   # 60 s total
		POTATO:  return [30.0, 30.0, 30.0]   # 90 s total
	return [15.0, 15.0, 15.0]

static func get_sell_value(crop_id: int) -> int:
	match crop_id:
		CARROT:  return 2
		LETTUCE: return 3
		POTATO:  return 5
	return 1

# Color of the crop tile at full saturation (mature / well-watered).
static func get_color(crop_id: int) -> Color:
	match crop_id:
		CARROT:  return Color(0.88, 0.48, 0.10)
		LETTUCE: return Color(0.28, 0.72, 0.28)
		POTATO:  return Color(0.62, 0.50, 0.28)
	return Color.WHITE

static func get_stage_label(stage: int) -> String:
	match stage:
		STAGE_SEED:    return "seed"
		STAGE_SPROUT:  return "sprout"
		STAGE_GROWING: return "growing"
		STAGE_MATURE:  return "READY"
	return "?"

# Seed cost in coins (per seed).
static func get_seed_cost(crop_id: int) -> int:
	match crop_id:
		CARROT:  return 1
		LETTUCE: return 1
		POTATO:  return 1
	return 1
