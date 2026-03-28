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

	# inventory: crop_id → count
	for cid in game._inventory:
		cfg.set_value("inventory", str(cid), game._inventory[cid])

	# cells
	for i in range(game._cells.size()):
		var cell: FarmCell = game._cells[i]
		var sec := "cell_%d" % i
		cfg.set_value(sec, "state",        int(cell.state))
		cfg.set_value(sec, "crop_id",      cell.crop_id)
		cfg.set_value(sec, "growth_stage", cell.growth_stage)
		cfg.set_value(sec, "time_in_stage",cell.time_in_stage)
		cfg.set_value(sec, "watered",      cell.watered)
		cfg.set_value(sec, "wilt_timer",   cell.wilt_timer)

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

	for cid in [0, 1, 2, 3, 4]:  # CARROT, LETTUCE, POTATO, TOMATO, PUMPKIN
		var count: int = cfg.get_value("inventory", str(cid), 0)
		if count > 0:
			game._inventory[cid] = count

	for i in range(game._cells.size()):
		var sec := "cell_%d" % i
		if not cfg.has_section(sec):
			continue
		var cell: FarmCell = game._cells[i]
		cell.state        = cfg.get_value(sec, "state",        0) as FarmCell.TileState
		cell.crop_id      = cfg.get_value(sec, "crop_id",      -1)
		cell.growth_stage = cfg.get_value(sec, "growth_stage", 0)
		cell.time_in_stage= cfg.get_value(sec, "time_in_stage",0.0)
		cell.watered      = cfg.get_value(sec, "watered",      false)
		cell.wilt_timer   = cfg.get_value(sec, "wilt_timer",   0.0)
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
