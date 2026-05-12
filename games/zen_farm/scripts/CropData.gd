#CropData.gd (zen_farm)
# Static data class for crop definitions.
class_name CropData

const ROSE  = 0
const LAVENDER = 5
const DAISY  = 2
const SUNFLOWER  = 3
const HYDRANGEA = 4
const TULIP = 7
const LOTUS = 8

const STAGE_SEED    = 0
const STAGE_SPROUT  = 1
const STAGE_GROWING = 2
const STAGE_MATURE  = 3

static func crop_name(crop_id: int) -> String:
	match crop_id:
		ROSE:  return "Rose"
		LAVENDER: return "Lavender"
		DAISY:  return "Daisy"
		SUNFLOWER:  return "Sunflower"
		HYDRANGEA: return "Hydrangea"
		TULIP: return "Tulip"
		LOTUS: return "Lotus"
	return "?"

# Duration in seconds for each non-mature stage: [seed, sprout, growing]
static func get_stage_durations(crop_id: int) -> Array:
	match crop_id:
		ROSE:  return [15.0, 15.0, 15.0]   #  45 s total
		LAVENDER: return [20.0, 20.0, 20.0]   #  60 s total
		DAISY:  return [30.0, 30.0, 30.0]   #  90 s total
		SUNFLOWER:  return [40.0, 40.0, 40.0]   # 120 s total
		HYDRANGEA: return [60.0, 60.0, 60.0]   # 180 s total
		TULIP: return [60.0, 60.0, 60.0]   # 180 s total
		LOTUS: return [60.0, 60.0, 60.0]   # 180 s total
	return [15.0, 15.0, 15.0]

static func get_sell_value(crop_id: int) -> int:
	match crop_id:
		ROSE:  return 2
		LAVENDER: return 1
		DAISY:  return 3
		SUNFLOWER:  return 4
		HYDRANGEA: return 7
		TULIP: return 8
		LOTUS: return 8
	return 1

static func get_color(crop_id: int) -> Color:
	match crop_id:
		ROSE:  return Color(0.88, 0.48, 0.10)
		LAVENDER: return Color(0.28, 0.72, 0.28)
		DAISY:  return Color(0.62, 0.50, 0.28)
		SUNFLOWER:  return Color(0.90, 0.22, 0.12)
		HYDRANGEA: return Color(0.92, 0.50, 0.08)
		TULIP: return Color(0.92, 0.50, 0.08)
		LOTUS: return Color(0.70, 0.42, 0.90)
	return Color.WHITE

# Seed cost in coins (per seed).
static func get_seed_cost(crop_id: int) -> int:
	match crop_id:
		ROSE:  return 1
		LAVENDER: return 1
		DAISY:  return 1
		SUNFLOWER:  return 1
		HYDRANGEA: return 2
		TULIP: return 2
		LOTUS: return 2
	return 1

# Minimum tiles owned before this crop becomes available in the seed panel.
static func get_unlock_tile_count(crop_id: int) -> int:
	match crop_id:
		LAVENDER: return 0
		ROSE:  return 4
		DAISY:  return 8
		SUNFLOWER:  return 12
		HYDRANGEA: return 16
		TULIP: return 16
		LOTUS: return 0
	return 0


static func is_water_crop(crop_id: int) -> bool:
	return crop_id == LOTUS

static func get_stage_label(stage: int) -> String:
	match stage:
		STAGE_SEED:    return "seed"
		STAGE_SPROUT:  return "sprout"
		STAGE_GROWING: return "growing"
		STAGE_MATURE:  return "READY"
	return "?"
