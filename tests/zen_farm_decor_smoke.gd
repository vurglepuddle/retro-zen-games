# Run with APPDATA redirected to res://.godot/farm_test_user on Windows.
# Refuses to touch the player's save. Add -- --render-review for PNG previews.
extends SceneTree

var failures: Array[String] = []
var checks := 0
var game: Control

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func _run() -> void:
	var safe_root := ProjectSettings.globalize_path("res://.godot/farm_test_user").replace("\\", "/")
	if not OS.get_user_data_dir().replace("\\", "/").begins_with(safe_root + "/"):
		push_error("Refusing save tests outside isolated user directory: " + OS.get_user_data_dir())
		quit(2)
		return
	SaveManager.delete_save()
	game = load("res://games/zen_farm/scenes/Game.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game._build_cells()
	game._coins = 1000
	game._tip_panel.hide()

	# Actual purchase -> render -> reject occupied/water/locked -> save/reload -> refund.
	var cell: FarmCell = game._cell_at_grid(0, 0)
	cell.state = FarmCell.TileState.GRASS
	cell.refresh_visual()
	for id in [DecorData.STONE_PATH, DecorData.MOSSY_PATH]:
		var before: int = game._coins
		game._start_decor_placement(id)
		game._try_place_decor(cell, id - DecorData.STONE_PATH)
		check(game._coins == before - 5, "Path purchase must charge exactly once")
		check(cell.decor_at(id - DecorData.STONE_PATH) == id, "Path must occupy its tapped slot")
		var entry: Dictionary = game._prop_entry_for(cell, id - DecorData.STONE_PATH)
		check(entry["parts"].size() == 1, "Flat paths must have one ground sprite")
		var sprite: Sprite2D = entry["parts"][0]
		check(sprite.get_parent() == game._prop_layer_under, "Paths must render under flowers")
		check(sprite.region_rect == DecorData.frame_region(id), "Path must use the existing tileset art")
		check(not game._decor_place_problem(cell, id - DecorData.STONE_PATH, id).is_empty(), "Occupied path spot must reject another purchase")
	check(cell.empty_slot_count() == 2, "Paths must leave the other planting slots free")
	var wet: FarmCell = game._cell_at_grid(1, 0)
	wet.state = FarmCell.TileState.WATER
	wet.is_water_plot = true
	check(not game._decor_place_problem(wet, 0, DecorData.STONE_PATH).is_empty(), "Stone paths must reject water")
	check(not game._decor_place_problem(game._cell_at_grid(2, 0), 0, DecorData.STONE_PATH).is_empty(), "Stone paths must reject unowned land")
	SaveManager.save_game(game)
	cell.reset_slots()
	check(SaveManager.load_game(game), "Save must reload")
	check(cell.decor_at(0) == DecorData.STONE_PATH and cell.decor_at(1) == DecorData.MOSSY_PATH, "Both path variants must survive save/load")
	for slot in range(2):
		game._pack_decor(cell, slot)
	check(game._coins == 1000 and cell.empty_slot_count() == 4, "Packing paths must refund in full and free their slots")

	# New grass is eligible for natural placement; pond-only art never enters grass RNG.
	var atlas: TileSetAtlasSource = game._decor_map.tile_set.get_source(game.DM_SOURCE)
	for x in range(9):
		check(atlas.has_tile(Vector2i(x, 7)) and atlas.get_tile_data(Vector2i(x, 7), 0).terrain == game.DM_DECOR, "New grass item %d must be registered for natural growth" % x)
	check(atlas.has_tile(Vector2i(9, 6)) and atlas.get_tile_size_in_atlas(Vector2i(9, 6)) == Vector2i(1, 2), "Compact tree must retain its tall artwork and one-slot footprint")
	var coords: Array[Vector2i] = []
	for y in range(24):
		for x in range(32):
			coords.append(Vector2i(x, 20 + y))
	seed(891)
	game._decor_map.set_cells_terrain_connect(coords, game.DM_TERRAIN_SET, game.DM_DECOR)
	game._move_rocks_from_decor(coords)
	var seen := {}
	for coord in coords:
		var rolled: Vector2i = game._decor_map.get_cell_atlas_coords(coord)
		seen[rolled] = true
		check(rolled not in game.WATER_ONLY_DECOR_ATLAS_COORDS, "Pond decor must never appear on grass")
	for x in range(9):
		check(seen.has(Vector2i(x, 7)), "New grass item %d must actually occur in seeded natural placement" % x)
	check(seen.has(Vector2i(9, 6)), "Compact tree must occur in natural placement")
	for x in range(10, 15):
		var coord := Vector2i(x, 7)
		check(atlas.has_tile(coord) and coord in game.WATER_WEED_ATLAS_COORDS, "New pond item must be registered")
		wet.slot_states[0] = FarmCell.SlotState.WEED
		wet.slot_weed_atlas_coords[0] = coord
		wet.refresh_visual()
		check(game._decor_map.get_cell_atlas_coords(game._slot_coord(wet, 0)) == coord, "Pond art must render without being rerolled")
	SaveManager.save_game(game)
	wet.reset_slots()
	SaveManager.load_game(game)
	check(wet.slot_weed_atlas_coords[0] == Vector2i(14, 7), "New pond art must survive save/load")

	# Petals stay in field space through panning and layout changes, including idle sighs.
	cell.slot_states[0] = FarmCell.SlotState.CROP
	cell.slot_crop_ids[0] = 0
	cell.slot_growth_stages[0] = CropData.STAGE_MATURE
	cell.refresh_visual()
	game._aim_petals(game._bloom_petals)
	game._aim_petals(game._sigh_petals)
	var points_before: PackedVector2Array = game._bloom_flower_points()[0]
	var pos_before: Vector2 = game._bloom_petals.position
	game._apply_scroll(24)
	check(game._bloom_petals.position != pos_before, "Pan must move existing airborne petals with the field")
	check(game._bloom_flower_points()[0] == points_before, "Pan must not bake camera offsets into emission points")
	for emitter: CPUParticles2D in [game._bloom_petals, game._sigh_petals]:
		check(emitter.local_coords and emitter.position == game._grid_container.position, "Both petal systems must use field-local coordinates")
	game._update_grid_size()
	check(game._bloom_petals.position == game._grid_container.position, "Field resizing must preserve petal alignment")

	# Every visible light has its own halo, tracks weather/night, and is freed with its prop.
	for id in [DecorData.PAVILION, DecorData.TEA_HUT, DecorData.LANTERN]:
		var key := Vector3i(90 + id, 90, game.PLOT_PROP_SLOT)
		game._build_prop_sprites(key, id, Vector2(256, 256), "test")
		var entry: Dictionary = game._prop_nodes[key]
		var expected := 2 if id == DecorData.PAVILION else (3 if id == DecorData.TEA_HUT else 1)
		check(entry["halos"].size() == expected, "Each lantern/window must have its own halo")
		var positions := {}
		for halo: Sprite2D in entry["halos"]:
			positions[halo.position] = true
		check(positions.size() == expected, "Building halos must occupy distinct light positions")
		game._lamp_amount = 1.0
		game._tick_props(0.1)
		for halo: Sprite2D in entry["halos"]:
			check(halo.modulate.a > 0.0, "Every halo must light at night")
		game._free_prop(key)
		for halo: Sprite2D in entry["halos"]:
			check(halo.is_queued_for_deletion(), "Removing a building must remove every halo")

	# The displayed well really advances and loops, with both depth-split sprites in sync.
	var well_key := Vector3i(80, 80, game.PLOT_PROP_SLOT)
	game._build_prop_sprites(well_key, DecorData.WELL, Vector2(128, 128), "well test")
	var well: Dictionary = game._prop_nodes[well_key]
	game._tick_prop_animation(well, 0.86)
	for sprite: Sprite2D in well["parts"]:
		check(sprite.region_rect.position.x == 128, "Both well halves must switch to the extra water frame")
	game._tick_prop_animation(well, 0.85)
	for sprite: Sprite2D in well["parts"]:
		check(sprite.region_rect.position.x == 0, "Well water must loop back to frame one")
	game._free_prop(well_key)
	game._upgrade_panel.show()
	game._set_shop_tab(1)
	await process_frame
	await process_frame
	check(game._garden_scroll.visible and game._garden_btns.size() == 8, "Garden shop must include both stone paths")
	check(game._garden_scroll.get_v_scroll_bar().max_value > game._garden_scroll.size.y, "All eight shop items must be reachable by scrolling")
	game._refresh_shop_garden()
	for btn: Button in game._garden_btns.values():
		var font := btn.get_theme_font("font")
		check(font.get_string_size(btn.text, HORIZONTAL_ALIGNMENT_LEFT, -1, btn.get_theme_font_size("font_size")).x <= btn.size.x - 44.0, "Every shop item must show its full name and price")
	game._set_shop_tab(0)
	check(not game._garden_scroll.visible, "Garden scroller must hide on the Tools tab")
	game._upgrade_panel.hide()

	if "--render-review" in OS.get_cmdline_user_args():
		await _render_review()
	SaveManager.delete_save()
	game.queue_free()
	await process_frame
	print("ZEN FARM DECOR: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _render_review() -> void:
	game._clear_cells()
	game._cols = 4
	game._build_cells()
	for c: FarmCell in game._cells:
		c.state = FarmCell.TileState.GRASS
		c.refresh_visual()
	game._tip_panel.hide()
	game._scroll_x = 0
	game._update_grid_size()
	game._decor_map.clear()
	game._rock_decor_map.clear()
	for x in range(9):
		game._decor_map.set_cell(Vector2i(x % 8, x / 8), game.DM_SOURCE, Vector2i(x, 7))
	game._decor_map.set_cell(Vector2i(2, 1), game.DM_SOURCE, Vector2i(9, 6))
	game._plant_map.set_cell(Vector2i(3, 1), game.PM_SOURCE, Vector2i(7, game.PM_MATURE_ROW))
	for spec in [[0, 2, DecorData.WELL], [1, 2, DecorData.TEA_HUT], [2, 2, DecorData.PAVILION], [3, 2, DecorData.BRIDGE], [3, 3, DecorData.BRIDGE]]:
		var c: FarmCell = game._cell_at_grid(spec[0], spec[1])
		c.reset_slots()
		c.is_water_plot = spec[2] in [DecorData.PAVILION, DecorData.BRIDGE]
		c.state = FarmCell.TileState.WATER if c.is_water_plot else FarmCell.TileState.GRASS
		for slot in range(4):
			c.slot_states[slot] = FarmCell.SlotState.DECOR
			c.slot_decor_ids[slot] = spec[2]
		c.refresh_visual()
	game._sync_all_props()
	for col in range(3):
		var pond: FarmCell = game._cell_at_grid(col, 4)
		pond.state = FarmCell.TileState.WATER
		pond.is_water_plot = true
		for slot in range(4):
			pond.slot_states[slot] = FarmCell.SlotState.WEED
			pond.slot_weed_atlas_coords[slot] = Vector2i(10 + (col * 4 + slot) % 5, 7)
		pond.refresh_visual()
	game._day_seconds = game.DAY_NIGHT_CYCLE * 0.3
	game._status_label.text = ""
	game._update_day_night(0.0)
	game._tick_props(0.0)
	await _capture("farm_decor_day")
	game._day_seconds = game.DAY_NIGHT_CYCLE * 0.76
	game._update_day_night(0.0)
	game._tick_props(0.0)
	await _capture("farm_decor_night")
	game._upgrade_panel.show()
	game._set_shop_tab(1)
	game._refresh_shop_garden()
	game._garden_scroll.scroll_vertical = 47
	await _capture("farm_decor_shop")
	game._upgrade_panel.hide()
	game._day_seconds = game.DAY_NIGHT_CYCLE * 0.3
	game._update_day_night(0.0)
	# Freeze already-emitted petals, then pan: their whole world moves with the field.
	for col in range(4):
		var flower_cell: FarmCell = game._cell_at_grid(col, 0)
		for slot in range(4):
			flower_cell.slot_states[slot] = FarmCell.SlotState.CROP
			flower_cell.slot_crop_ids[slot] = 7
			flower_cell.slot_growth_stages[slot] = CropData.STAGE_MATURE
		flower_cell.refresh_visual()
	game._aim_petals(game._bloom_petals)
	# A diagnostic tint and clear patch make actual rendered particles measurable.
	game._day_night_overlay.hide()
	game._bloom_petals.emission_points = PackedVector2Array([Vector2(200, 140)])
	game._bloom_petals.emission_colors = PackedColorArray([Color.WHITE])
	game._bloom_petals.color = Color(1, 0, 1)
	game._bloom_petals.preprocess = 3.0
	game._bloom_petals.restart()
	game._bloom_petals.emitting = true
	await create_timer(0.7).timeout
	game._bloom_petals.speed_scale = 0.00001
	await _capture("farm_petals_before_pan")
	var before_image := root.get_texture().get_image()
	var before_center := _petal_center(before_image)
	game._apply_scroll(32)
	await _capture("farm_petals_after_pan")
	var after_center := _petal_center(root.get_texture().get_image())
	check(before_center.x >= 0 and after_center.x >= 0, "Airborne petals must actually render during the pan check")
	var pan_pixels := 32.0 * before_image.get_width() / 540.0
	check(absf((before_center.x - after_center.x) - pan_pixels) < 2.0, "Rendered airborne petals must follow the field by exactly the pan distance")

func _petal_center(img: Image) -> Vector2:
	var total := Vector2.ZERO
	var count := 0
	for y in range(img.get_height() / 2):
		for x in range(img.get_width()):
			var c := img.get_pixel(x, y)
			if c.r > 0.8 and c.b > 0.8 and c.g < 0.12:
				total += Vector2(x, y)
				count += 1
	return total / count if count > 0 else Vector2(-1, -1)

func _capture(filename: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	check(img != null and not img.is_empty(), "Review viewport must render")
	if img:
		img.save_png("res://art_src/zen_farm/preview/" + filename + ".png")
