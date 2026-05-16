#SaveManager.gd (zen_farm)
class_name SaveManager

const SAVE_PATH := "user://zen_farm_save.cfg"

static func save_game(game: Node) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "timestamp", Time.get_unix_time_from_system())
	cfg.set_value("meta", "coins",     game._coins)
	cfg.set_value("meta", "can_water", game._can_water)
	cfg.set_value("meta", "can_level", game._can_level)
	cfg.set_value("meta", "cols",      game._cols)
	cfg.set_value("meta", "grass_toggle_unlocked", game._grass_toggle_unlocked)
	cfg.set_value("meta", "water_toggle_unlocked", game._water_toggle_unlocked)

	# inventory: crop_id → count
	for cid in game._inventory:
		cfg.set_value("inventory", str(cid), game._inventory[cid])

	# cells — keyed by grid position so column-expansion order doesn't matter
	var decor_coverage := []
	for coord in game._static_decor_coverage.keys():
		if coord is Vector2i:
			decor_coverage.append(coord)
	cfg.set_value("decor", "coverage", decor_coverage)
	var decor_tiles := []
	for coord in game._static_decor_tiles.keys():
		if not (coord is Vector2i):
			continue
		var snapshot: Array = game._static_decor_tiles[coord]
		if snapshot.size() >= 4:
			decor_tiles.append([coord, snapshot[0], snapshot[1], snapshot[2], snapshot[3]])
	cfg.set_value("decor", "tiles", decor_tiles)

	for cell: FarmCell in game._cells:
		var sec := "cell_r%d_c%d" % [cell.grid_row, cell.grid_col]
		var key := Vector2i(cell.grid_col, cell.grid_row)
		cfg.set_value(sec, "state",        int(cell.state))
		cfg.set_value(sec, "is_water_plot", cell.is_water_plot)
		cfg.set_value(sec, "crop_id",      cell.crop_id)
		cfg.set_value(sec, "growth_stage", cell.growth_stage)
		cfg.set_value(sec, "time_in_stage",cell.time_in_stage)
		cfg.set_value(sec, "watered",      cell.watered)
		cfg.set_value(sec, "wilt_timer",   cell.wilt_timer)
		cfg.set_value(sec, "slot_states",        cell.slot_states)
		cfg.set_value(sec, "slot_crop_ids",      cell.slot_crop_ids)
		cfg.set_value(sec, "slot_growth_stages", cell.slot_growth_stages)
		cfg.set_value(sec, "slot_time_in_stage", cell.slot_time_in_stage)
		cfg.set_value(sec, "slot_watered",       cell.slot_watered)
		cfg.set_value(sec, "slot_wilt_timers",   cell.slot_wilt_timers)
		cfg.set_value(sec, "slot_weed_atlas_coords", cell.slot_weed_atlas_coords)
		for slot in range(FarmCell.SLOT_COUNT):
			cfg.set_value(sec, "harvest_icon_shown_once_%d" % slot, game._harvest_icon_shown_once.get(Vector3i(cell.grid_col, cell.grid_row, slot), false))

	cfg.save(SAVE_PATH)


# Returns true if a save file was found and loaded.
static func load_game(game: Node) -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return false

	game._coins           = cfg.get_value("meta", "coins",     10)
	game._last_save_time  = cfg.get_value("meta", "timestamp", 0.0)
	game._can_water       = cfg.get_value("meta", "can_water", 0)
	game._can_level       = cfg.get_value("meta", "can_level", 0)
	game._cols            = cfg.get_value("meta", "cols",      4)
	game._grass_toggle_unlocked = cfg.get_value("meta", "grass_toggle_unlocked", false)
	game._water_toggle_unlocked = cfg.get_value("meta", "water_toggle_unlocked", false)

	if cfg.has_section("decor"):
		game._static_decor_coverage.clear()
		game._static_decor_tiles.clear()
		var decor_coverage: Array = cfg.get_value("decor", "coverage", [])
		for coord in decor_coverage:
			if coord is Vector2i:
				game._static_decor_coverage[coord] = true
		var decor_tiles: Array = cfg.get_value("decor", "tiles", [])
		for entry in decor_tiles:
			if not (entry is Array):
				continue
			if entry.size() < 5 or not (entry[0] is Vector2i):
				continue
			game._static_decor_tiles[entry[0]] = [String(entry[1]), int(entry[2]), entry[3], int(entry[4])]

	for cid in [CropData.ROSE, CropData.LAVENDER, CropData.DAISY, CropData.SUNFLOWER, CropData.HYDRANGEA, CropData.TULIP, CropData.LOTUS]:
		var count: int = cfg.get_value("inventory", str(cid), 0)
		if count > 0:
			game._inventory[cid] = count

	for cell: FarmCell in game._cells:
		var sec := "cell_r%d_c%d" % [cell.grid_row, cell.grid_col]
		if not cfg.has_section(sec):
			continue

		cell.state         = cfg.get_value(sec, "state",         0) as FarmCell.TileState
		cell.is_water_plot = cfg.get_value(sec, "is_water_plot", cell.state == FarmCell.TileState.WATER)
		cell.crop_id       = cfg.get_value(sec, "crop_id",       -1)
		cell.growth_stage  = cfg.get_value(sec, "growth_stage",  0)
		cell.time_in_stage = cfg.get_value(sec, "time_in_stage", 0.0)
		cell.watered       = cfg.get_value(sec, "watered",       false)
		cell.wilt_timer    = cfg.get_value(sec, "wilt_timer",    0.0)
		cell.reset_slots()
		if cfg.has_section_key(sec, "slot_states"):
			var states: Array = cfg.get_value(sec, "slot_states", [])
			var crop_ids: Array = cfg.get_value(sec, "slot_crop_ids", [])
			var stages: Array = cfg.get_value(sec, "slot_growth_stages", [])
			var times: Array = cfg.get_value(sec, "slot_time_in_stage", [])
			var watered: Array = cfg.get_value(sec, "slot_watered", [])
			var wilts: Array = cfg.get_value(sec, "slot_wilt_timers", [])
			var weed_coords: Array = cfg.get_value(sec, "slot_weed_atlas_coords", [])
			for slot in range(FarmCell.SLOT_COUNT):
				cell.slot_states[slot] = int(states[slot]) if slot < states.size() else FarmCell.SlotState.EMPTY
				cell.slot_crop_ids[slot] = int(crop_ids[slot]) if slot < crop_ids.size() else -1
				cell.slot_growth_stages[slot] = int(stages[slot]) if slot < stages.size() else 0
				cell.slot_time_in_stage[slot] = float(times[slot]) if slot < times.size() else 0.0
				cell.slot_watered[slot] = bool(watered[slot]) if slot < watered.size() else false
				cell.slot_wilt_timers[slot] = float(wilts[slot]) if slot < wilts.size() else 0.0
				cell.slot_weed_atlas_coords[slot] = weed_coords[slot] if slot < weed_coords.size() and weed_coords[slot] is Vector2i else Vector2i(-1, -1)
		elif cell.state == FarmCell.TileState.CROP or cell.state == FarmCell.TileState.WILTED or cell.state == FarmCell.TileState.WEED:
			var migrated_state := FarmCell.SlotState.EMPTY
			if cell.state == FarmCell.TileState.CROP:
				migrated_state = FarmCell.SlotState.CROP
			elif cell.state == FarmCell.TileState.WILTED:
				migrated_state = FarmCell.SlotState.WILTED
			elif cell.state == FarmCell.TileState.WEED:
				migrated_state = FarmCell.SlotState.WEED
			cell.slot_states[0] = migrated_state
			cell.slot_crop_ids[0] = cell.crop_id
			cell.slot_growth_stages[0] = cell.growth_stage
			cell.slot_time_in_stage[0] = cell.time_in_stage
			cell.slot_watered[0] = cell.watered
			cell.slot_wilt_timers[0] = cell.wilt_timer
			cell.slot_weed_atlas_coords[0] = Vector2i(-1, -1)

		for slot in range(FarmCell.SLOT_COUNT):
			var key := Vector3i(cell.grid_col, cell.grid_row, slot)
			game._harvest_icon_shown_once[key] = cfg.get_value(sec, "harvest_icon_shown_once_%d" % slot, false)

		cell.refresh_visual()

	return true


static func load_cols() -> int:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return 4
	return cfg.get_value("meta", "cols", 4)


static func save_exists() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


static func delete_save() -> void:
	DirAccess.remove_absolute(SAVE_PATH)
