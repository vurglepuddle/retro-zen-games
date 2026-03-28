#CropData.gd (zen_farm)
# Static data class for crop definitions.
class_name CropData

const CARROT  = 0
const LETTUCE = 1
const POTATO  = 2
const TOMATO  = 3
const PUMPKIN = 4

const STAGE_SEED    = 0
const STAGE_SPROUT  = 1
const STAGE_GROWING = 2
const STAGE_MATURE  = 3

static func crop_name(crop_id: int) -> String:
	match crop_id:
		CARROT:  return "Carrot"
		LETTUCE: return "Lettuce"
		POTATO:  return "Potato"
		TOMATO:  return "Tomato"
		PUMPKIN: return "Pumpkin"
	return "?"

# Duration in seconds for each non-mature stage: [seed, sprout, growing]
static func get_stage_durations(crop_id: int) -> Array:
	match crop_id:
		CARROT:  return [15.0, 15.0, 15.0]   #  45 s total
		LETTUCE: return [20.0, 20.0, 20.0]   #  60 s total
		POTATO:  return [30.0, 30.0, 30.0]   #  90 s total
		TOMATO:  return [40.0, 40.0, 40.0]   # 120 s total
		PUMPKIN: return [60.0, 60.0, 60.0]   # 180 s total
	return [15.0, 15.0, 15.0]

static func get_sell_value(crop_id: int) -> int:
	match crop_id:
		CARROT:  return 4
		LETTUCE: return 2
		POTATO:  return 6
		TOMATO:  return 9
		PUMPKIN: return 15
	return 1

static func get_color(crop_id: int) -> Color:
	match crop_id:
		CARROT:  return Color(0.88, 0.48, 0.10)
		LETTUCE: return Color(0.28, 0.72, 0.28)
		POTATO:  return Color(0.62, 0.50, 0.28)
		TOMATO:  return Color(0.90, 0.22, 0.12)
		PUMPKIN: return Color(0.92, 0.50, 0.08)
	return Color.WHITE

# Seed cost in coins (per seed).
static func get_seed_cost(crop_id: int) -> int:
	match crop_id:
		CARROT:  return 2
		LETTUCE: return 1
		POTATO:  return 3
		TOMATO:  return 4
		PUMPKIN: return 6
	return 1

# Minimum tiles owned before this crop becomes available in the seed panel.
static func get_unlock_tile_count(crop_id: int) -> int:
	match crop_id:
		LETTUCE: return 0
		CARROT:  return 4
		POTATO:  return 8
		TOMATO:  return 12
		PUMPKIN: return 16
	return 0

static func get_stage_label(stage: int) -> String:
	match stage:
		STAGE_SEED:    return "seed"
		STAGE_SPROUT:  return "sprout"
		STAGE_GROWING: return "growing"
		STAGE_MATURE:  return "READY"
	return "?"
