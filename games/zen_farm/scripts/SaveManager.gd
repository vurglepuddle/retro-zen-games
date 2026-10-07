#SaveManager.gd (zen_farm)
class_name SaveManager

const SAVE_PATH := "user://zen_farm_save.cfg"
const PREVIOUS_PATH := "user://zen_farm_previous.cfg"
const _SaveFile = preload("res://scripts/SafeConfig.gd")

static func save_game(game: Node) -> bool:
	if game.menu_preview or game._cells.is_empty():
		return false
	var result := _SaveFile.save_config(_make_config(game), SAVE_PATH, "meta", ["coins", "cols"])
	if result != OK:
		game._show_status("Couldn't save your farm. Please try again.")
	return result == OK


static func _make_config(game: Node) -> ConfigFile:
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
		cfg.set_value(sec, "slot_decor_ids", cell.slot_decor_ids)
		cfg.set_value(sec, "bridge_turn", cell.bridge_turn)
		for slot in range(FarmCell.SLOT_COUNT):
			cfg.set_value(sec, "harvest_icon_shown_once_%d" % slot, game._harvest_icon_shown_once.get(Vector3i(cell.grid_col, cell.grid_row, slot), false))

	return cfg


# Returns true if a save file was found and loaded.
static func load_game(game: Node) -> bool:
	var cfg := ConfigFile.new()
	if not _load_config(cfg):
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

	game._inventory.clear()
	for cid in CropData.all_ids():
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
			var decor_ids: Array = cfg.get_value(sec, "slot_decor_ids", [])
			# saves from before walkways turned stored a vertical flag (shape 1 = up/down)
			cell.bridge_turn = int(cfg.get_value(sec, "bridge_turn", 1 if cfg.get_value(sec, "bridge_vertical", false) else 0))
			for slot in range(FarmCell.SLOT_COUNT):
				cell.slot_states[slot] = int(states[slot]) if slot < states.size() else FarmCell.SlotState.EMPTY
				cell.slot_crop_ids[slot] = int(crop_ids[slot]) if slot < crop_ids.size() else -1
				cell.slot_growth_stages[slot] = int(stages[slot]) if slot < stages.size() else 0
				cell.slot_time_in_stage[slot] = float(times[slot]) if slot < times.size() else 0.0
				cell.slot_watered[slot] = bool(watered[slot]) if slot < watered.size() else false
				cell.slot_wilt_timers[slot] = float(wilts[slot]) if slot < wilts.size() else 0.0
				cell.slot_weed_atlas_coords[slot] = weed_coords[slot] if slot < weed_coords.size() and weed_coords[slot] is Vector2i else Vector2i(-1, -1)
				cell.slot_decor_ids[slot] = int(decor_ids[slot]) if slot < decor_ids.size() else -1
				# A DECOR slot without a known prop id can't be drawn or removed — free it.
				if cell.slot_states[slot] == FarmCell.SlotState.DECOR \
						and not DecorData.all_ids().has(cell.slot_decor_ids[slot]):
					cell.slot_states[slot] = FarmCell.SlotState.EMPTY
					cell.slot_decor_ids[slot] = -1
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
	if not _load_config(cfg):
		return 4
	return cfg.get_value("meta", "cols", 4)


static func save_exists() -> bool:
	return FileAccess.file_exists(SAVE_PATH) or FileAccess.file_exists(SAVE_PATH + ".bak")


static func _load_config(cfg: ConfigFile) -> bool:
	for path in [SAVE_PATH, SAVE_PATH + ".bak"]:
		cfg.clear()
		if cfg.load(path) == OK and cfg.has_section_key("meta", "coins") and cfg.has_section_key("meta", "cols"):
			return true
	cfg.clear()
	return false


static func replace_with_new_farm(game: Node) -> bool:
	if save_exists():
		var current := ConfigFile.new()
		var source := SAVE_PATH
		if current.load(source) != OK or not current.has_section_key("meta", "coins") or not current.has_section_key("meta", "cols"):
			if FileAccess.file_exists(SAVE_PATH + ".bak"):
				source = SAVE_PATH + ".bak"
		if _SaveFile.copy_file(source, PREVIOUS_PATH) != OK:
			push_warning("Could not keep the previous farm; New Farm was cancelled.")
			return false
	return save_game(game)


static func previous_exists() -> bool:
	var cfg := ConfigFile.new()
	return cfg.load(PREVIOUS_PATH) == OK and cfg.has_section_key("meta", "coins") and cfg.has_section_key("meta", "cols")


static func restore_previous_farm() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(PREVIOUS_PATH) != OK or not cfg.has_section_key("meta", "coins") or not cfg.has_section_key("meta", "cols"):
		return false
	return _SaveFile.save_config(cfg, SAVE_PATH, "meta", ["coins", "cols"]) == OK


static func delete_save() -> void:
	# Explicit reset used by the isolated smoke checks; New Farm keeps a copy.
	for path in [SAVE_PATH, SAVE_PATH + ".bak", SAVE_PATH + ".tmp"]:
		if FileAccess.file_exists(path):
			var result := DirAccess.remove_absolute(path)
			if result != OK:
				push_warning("Could not remove farm save %s (error %d)." % [path, result])
