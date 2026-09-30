extends "res://games/zen_farm/scripts/Game.gd"
## A disposable, non-interactive garden. Rendering and wildlife come from Game;
## only composition and the camera belong to the menu. Never prepare/load a farm.

var garden_seed: int
var _garden_rows := 0
var _drift_time := 0.0
var _garden_ready := false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	menu_preview = true
	super._ready()
	for child in get_children():
		if child is CanvasItem and child != $FarmScroll:
			child.hide()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	$FarmScroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$FarmScroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	set_process_input(false)
	resized.connect(_on_garden_resized)
	regenerate()


func regenerate(seed_value: int = -1) -> void:
	_garden_ready = false
	_game_active = false
	_clear_cells()
	# Bees own their flight tweens; remove any still flying from the old scene.
	for child in _insect_container.get_children():
		child.queue_free()
	_rng.randomize()
	garden_seed = _rng.randi() if seed_value < 0 else seed_value
	_rng.seed = garden_seed
	_cols = ceili(size.x / TILE_SIZE) + 4
	_garden_rows = ceili(size.y / TILE_SIZE) + 4
	_drift_time = _rng.randf_range(0.0, TAU)
	# A winding pond, clustered flower beds, and quieter grassy banks.
	var pond_x := _rng.randf_range(2.0, float(_cols - 3))
	var bend := _rng.randf_range(0.0, TAU)
	var flowers: Array[int] = []
	for id in CropData.all_ids():
		if not CropData.is_water_crop(id):
			flowers.append(id)
	var beds := FastNoiseLite.new()
	beds.seed = garden_seed
	beds.frequency = 0.32
	for row in range(_garden_rows):
		var river := clampf(pond_x + sin(row * 0.7 + bend) * 1.4, 1.0, _cols - 2.0)
		for col in range(_cols):
			var cell := FarmCell.new()
			cell.grid_col = col
			cell.grid_row = row
			cell.position = Vector2(col, row) * TILE_SIZE
			_grid_container.add_child(cell)
			cell.hide() # No prices, READY labels, or other gameplay UI.
			_cells.append(cell)
			cell.visual_changed.connect(_refresh_cell_tilemap.bind(cell))
			if absf(col - river) < 0.85:
				cell.state = FarmCell.TileState.WATER
				cell.is_water_plot = true
				if _rng.randf() < 0.13:
					_place_menu_prop(cell, 0, DecorData.PAVILION if _rng.randf() < 0.3 else DecorData.BRIDGE)
				else:
					for slot in range(FarmCell.SLOT_COUNT):
						if _rng.randf() < 0.55:
							cell.slot_states[slot] = FarmCell.SlotState.WEED
							cell.slot_weed_atlas_coords[slot] = WATER_WEED_ATLAS_COORDS[_rng.randi_range(0, WATER_WEED_ATLAS_COORDS.size() - 1)]
			elif beds.get_noise_2d(col, row) > -0.12:
				cell.state = FarmCell.TileState.SOIL
				var flower := flowers[_rng.randi_range(0, flowers.size() - 1)]
				for slot in range(FarmCell.SLOT_COUNT):
					if _rng.randf() < 0.84:
						cell.slot_states[slot] = FarmCell.SlotState.CROP
						cell.slot_crop_ids[slot] = flower
						cell.slot_growth_stages[slot] = CropData.STAGE_MATURE if _rng.randf() < 0.86 else CropData.STAGE_GROWING
			else:
				cell.state = FarmCell.TileState.GRASS
				if _rng.randf() < 0.28:
					var props := [DecorData.LANTERN, DecorData.BEEHIVE, DecorData.WELL, DecorData.TEA_HUT]
					_place_menu_prop(cell, _rng.randi_range(0, 3), props[_rng.randi_range(0, props.size() - 1)])
	# Guarantee visible frog seats and a hive on each seed, away from the cards.
	var frog_seats: Array[FarmCell] = []
	for row in [3, _garden_rows - 4]:
		var wet := _cell_at_grid(clampi(roundi(pond_x + sin(row * 0.7 + bend) * 1.4), 3, _cols - 4), row)
		wet.reset_slots()
		wet.state = FarmCell.TileState.WATER
		wet.is_water_plot = true
		wet.slot_states[0] = FarmCell.SlotState.WEED
		wet.slot_weed_atlas_coords[0] = FROGGO_ELIGIBLE_ATLAS_COORDS[0]
		frog_seats.append(wet)
	var hive := _cell_at_grid(2, _garden_rows - 3)
	if hive.is_water_plot:
		hive = _cell_at_grid(_cols - 3, _garden_rows - 3)
	hive.reset_slots()
	hive.state = FarmCell.TileState.GRASS
	hive.is_water_plot = false
	_place_menu_prop(hive, 0, DecorData.BEEHIVE)
	for cell: FarmCell in _cells:
		_refresh_cell_tilemap(cell)
	_sync_all_props()
	_position_garden()
	_game_active = true
	_garden_ready = true
	_setup_butterflies(7)
	for bfly in _butterflies:
		bfly["node"].position = _butterfly_wander_pos()
	for cell in frog_seats:
		_spawn_frog(cell, 0, cell.slot_weed_atlas_coords[0])
	_release_hive_bee(_cell_origin(hive) + Vector2(32, 64))
	_hive_bee_timer = 4.0


func _place_menu_prop(cell: FarmCell, slot: int, id: int) -> void:
	if not _decor_place_problem(cell, slot, id).is_empty():
		return
	var slots: Array = [slot] if DecorData.footprint(id) == DecorData.Footprint.SLOT else range(FarmCell.SLOT_COUNT)
	for s in slots:
		cell.slot_states[s] = FarmCell.SlotState.DECOR
		cell.slot_decor_ids[s] = id


func _process(delta: float) -> void:
	if not _garden_ready or not is_visible_in_tree():
		return
	_drift_time += delta * 0.035
	_position_garden()
	_tick_frogs(delta)
	_tick_props(delta)


func _position_garden() -> void:
	var field := Vector2(_cols, _garden_rows) * TILE_SIZE
	var pos := ((size - field) * 0.5 + Vector2(sin(_drift_time) * 72.0, cos(_drift_time * 0.7) * 48.0)).round()
	for layer in [_grid_container, _terrain_map, _decor_map, _plant_map,
			_rock_decor_map, _locked_sign_front_map, _locked_sign_front_rock_map,
			_moisture_map, _wilt_map, _icon_container, _insect_container,
			_water_shade_layer, _water_highlight_layer]:
		if layer:
			layer.position = pos
	_update_water_overlay_origin(pos)
	_position_prop_layers(pos)


func _visible_content_rect() -> Rect2:
	return Rect2(-_insect_container.position, size)


func _butterfly_wander_pos() -> Vector2:
	var rect := _visible_content_rect().grow(-24.0)
	for attempt in range(12):
		var point := Vector2(randf_range(rect.position.x, rect.end.x), randf_range(rect.position.y, rect.end.y))
		if _butterfly_can_rest_at(point):
			return point
	return rect.get_center()


func _cell_at_content_pos(pos: Vector2) -> FarmCell:
	return _cell_at_grid(floori(pos.x / TILE_SIZE), floori(pos.y / TILE_SIZE))


func _on_garden_resized() -> void:
	if _garden_ready:
		regenerate(garden_seed)


func _input(_event: InputEvent) -> void:
	pass


func _show_slot_harvest_icon(_cell: FarmCell, _slot: int) -> void:
	pass


func _play(_sfx: AudioStreamPlayer) -> void:
	pass # Menu ambience is already provided by Main.
