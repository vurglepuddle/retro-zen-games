extends SceneTree

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func _run() -> void:
	var safe := ProjectSettings.globalize_path("res://.godot/farm_test_user").replace("\\", "/")
	if not OS.get_user_data_dir().replace("\\", "/").begins_with(safe + "/"):
		push_error("Menu smoke requires isolated APPDATA")
		quit(2)
		return
	var sentinel := "menu preview must preserve this save"
	var file := FileAccess.open(SaveManager.SAVE_PATH, FileAccess.WRITE)
	file.store_string(sentinel)
	file.close()
	var menu = load("res://games/zen_farm/scenes/Menu.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	var garden = menu.get_node("Garden")
	for seed_value in range(12):
		garden.regenerate(seed_value)
		await process_frame
		check(garden.get_node("FarmScroll").size == menu.size, "Tiles must cover full menu")
		check(garden._frogs.size() == 2, "Every garden must have frogs")
		check(garden._butterflies.size() == 7, "Every garden must have flying wildlife")
		check(garden._harvest_icons.is_empty(), "No harvest HUD in preview")
		for child in garden.get_children():
			if child is CanvasItem and child != garden.get_node("FarmScroll"):
				check(not child.visible, "No gameplay HUD: " + child.name)
		for cell: FarmCell in garden._cells:
			check(not cell.visible, "No gameplay labels")
			for slot in range(FarmCell.SLOT_COUNT):
				if cell.slot_states[slot] == FarmCell.SlotState.CROP:
					check(not cell.is_water_plot and cell.state != FarmCell.TileState.GRASS, "Flowers require tilled soil")
				if cell.slot_states[slot] == FarmCell.SlotState.WEED and cell.is_water_plot:
					check(cell.slot_weed_atlas_coords[slot] in garden.WATER_WEED_ATLAS_COORDS, "Only water decor in water")
				if cell.slot_states[slot] == FarmCell.SlotState.DECOR:
					var water_prop := DecorData.footprint(cell.slot_decor_ids[slot]) == DecorData.Footprint.WATER_PLOT
					check(water_prop == cell.is_water_plot, "Props obey surface rule")
		for coord in garden._decor_map.get_used_cells():
			var cell = garden._cell_at_grid(floori(coord.x / 2.0), floori(coord.y / 2.0))
			if cell and not cell.is_water_plot:
				check(garden._decor_map.get_cell_atlas_coords(coord) not in garden.WATER_ONLY_DECOR_ATLAS_COORDS, "No water decor on land")
		garden.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
		garden.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
		check(FileAccess.get_file_as_string(SaveManager.SAVE_PATH) == sentinel, "Preview notifications must not overwrite save")
	menu.hide()
	check(garden.process_mode == Node.PROCESS_MODE_DISABLED, "Hidden preview pauses")
	menu.show()
	check(garden.process_mode == Node.PROCESS_MODE_INHERIT, "Returning to menu resumes")
	await menu._on_another_garden()
	check(not menu._changing_view and is_equal_approx(menu.get_node("Shade").color.a, 0.48), "Randomizer completes fade")
	check(FileAccess.get_file_as_string(SaveManager.SAVE_PATH) == sentinel, "Reroll preserves save")
	for dims in [Vector2i(540, 1200), Vector2i(540, 960), Vector2i(540, 1440)]:
		root.size = dims
		await process_frame
		await process_frame
		check(garden.get_node("FarmScroll").size == menu.size, "Resized preview fills viewport")
		var actions: Control = menu.get_node("Center/Cards/ActionsCard")
		check(menu.get_global_rect().encloses(actions.get_global_rect()), "Menu actions fit viewport")
	root.size = Vector2i(540, 1200)
	await process_frame
	garden.regenerate(7)
	if "--render-review" in OS.get_cmdline_user_args():
		await create_timer(3.0).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/zen_farm_menu.png")
		SaveManager.delete_save()
		menu.refresh_state()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/zen_farm_menu_new.png")
	menu.queue_free()
	await process_frame
	file = FileAccess.open(SaveManager.SAVE_PATH, FileAccess.WRITE)
	file.store_string(sentinel)
	file.close()
	var main = load("res://games/zen_farm/scenes/Main.tscn").instantiate()
	root.add_child(main)
	await create_timer(0.5).timeout
	var live_game = main.get_node("Game")
	live_game.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	check(FileAccess.get_file_as_string(SaveManager.SAVE_PATH) == sentinel, "Cold main menu must preserve existing save on pause")
	main.get_node("Menu").get_node("%NewFarmButton").pressed.emit()
	check(main.get_node("Menu")._confirmation.visible, "Replacing existing farm requires confirmation")
	main.get_node("Menu")._confirmation.confirmed.emit()
	await create_timer(0.9).timeout
	check(live_game.visible and live_game._game_active, "New Farm opens gameplay")
	check(live_game._cells.size() == 20, "Gameplay retains original board dimensions")
	check(main.get_node("Menu/Garden").process_mode == Node.PROCESS_MODE_DISABLED, "Preview sleeps during gameplay")
	live_game._on_back_pressed()
	await create_timer(0.9).timeout
	check(main.get_node("Menu").visible and not live_game.visible, "Back returns to garden menu")
	check(main.get_node("Menu").get_node("%ContinueButton").visible, "Saved farm exposes Continue")
	var saved := FileAccess.get_file_as_string(SaveManager.SAVE_PATH)
	await main.get_node("Menu")._on_another_garden()
	check(FileAccess.get_file_as_string(SaveManager.SAVE_PATH) == saved, "Reroll leaves real farm unchanged")
	main.get_node("Menu").get_node("%ContinueButton").pressed.emit()
	await create_timer(0.9).timeout
	check(live_game.visible and live_game._game_active and live_game._cells.size() == 20, "Continue reloads actual farm")
	main.queue_free()
	await process_frame
	print("ZEN FARM MENU: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
