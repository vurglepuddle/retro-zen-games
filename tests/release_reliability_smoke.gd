extends SceneTree

const SafeFile = preload("res://scripts/SafeConfig.gd")
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)


func _run() -> void:
	var isolated := ProjectSettings.globalize_path("res://.godot/release_test_user/").replace("\\", "/")
	if not OS.get_user_data_dir().replace("\\", "/").begins_with(isolated):
		push_error("Use the isolated release_test_user APPDATA directory.")
		quit(2)
		return
	_timeout()
	root.get_node("AudioManager")._audio_unlocked = true
	SaveManager.delete_save()
	for suffix in ["", ".tmp"]:
		if FileAccess.file_exists(SaveManager.PREVIOUS_PATH + suffix):
			DirAccess.remove_absolute(SaveManager.PREVIOUS_PATH + suffix)
	await _navigation()
	await _alchemy()
	await _gem()
	await _potion_records()
	await _farm()
	_config_failures()
	print("RELEASE RELIABILITY: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _timeout() -> void:
	await create_timer(90.0).timeout
	push_error("Release regression checks timed out.")
	quit(3)


func _navigation() -> void:
	for name in ["gem_match", "tile_chain", "alchemical_sort", "potion_3", "zen_farm"]:
		var main = load("res://games/%s/scenes/Main.tscn" % name).instantiate()
		root.add_child(main)
		current_scene = main
		await create_timer(0.5).timeout
		check(not quit_on_go_back, name + ": native automatic quit disabled")
		var menu = main.get_node("Menu")
		var game = main.get_node("Game")
		var counts := {"menu": 0, "hub": 0}
		menu.back_to_master.connect(func(): counts.hub += 1)
		game.back_to_menu.connect(func(): counts.menu += 1)
		if name == "tile_chain":
			menu.start_game.emit()
			menu.start_game.emit()
		elif name == "zen_farm":
			menu.start_game.emit(true)
			menu.start_game.emit(true)
		else:
			menu.start_game.emit(0)
			menu.start_game.emit(2)
		check(main._transitioning, name + ": transition locks immediately")
		check(main._fade_rect.mouse_filter == Control.MOUSE_FILTER_STOP, name + ": fade blocks taps")
		root.propagate_notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
		check(counts.menu == 0 and counts.hub == 0, name + ": Back ignored during transition")
		await create_timer(0.7).timeout
		check(game.visible and not menu.visible, name + ": starts one game")
		check(not main._transitioning, name + ": transition unlocks on arrival")
		if name in ["alchemical_sort", "potion_3"]:
			check(game._difficulty == 0, name + ": repeated start did not select another difficulty")
		if name == "zen_farm":
			game._coins = 4321
		root.propagate_notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
		root.propagate_notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
		check(counts.menu == 1 and counts.hub == 0, name + ": one Back returns only to game menu")
		await create_timer(2.5).timeout
		check(menu.visible and not game.visible, name + ": game menu remains visible after old animations finish")
		var active: bool = game._game_active if name in ["gem_match", "zen_farm"] else game._board_active
		check(not active, name + ": hidden board cannot reactivate")
		if name == "zen_farm":
			var cfg := ConfigFile.new()
			cfg.load(SaveManager.SAVE_PATH)
			check(cfg.get_value("meta", "coins", -1) == 4321, "Farm: hardware Back flushed changes")
			var saved := FileAccess.get_file_as_string(SaveManager.SAVE_PATH)
			game.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
			check(FileAccess.get_file_as_string(SaveManager.SAVE_PATH) == saved, "Farm: hidden pause leaves save alone")
		root.propagate_notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
		check(counts.hub == 1, name + ": next Back goes to hub")
		await create_timer(0.7).timeout
		check(current_scene.scene_file_path == "res://scenes/MasterMenu.tscn", name + ": hub loaded")
		current_scene.queue_free()
		current_scene = null
		await process_frame


func _alchemy() -> void:
	var game = load("res://games/alchemical_sort/scenes/Game.tscn").instantiate()
	root.add_child(game)
	game.set_difficulty(0)
	game.prepare_board()
	for vial: Vial in game._vials:
		vial.restore([0, 0, 0, 0, 0])
	var source: Vial = game._vials[0]
	var destination: Vial = game._vials[1]
	source.restore([1, 1, 0, 0, 0])
	game._board_active = true
	game._do_pour(source, destination)
	await create_timer(0.18).timeout
	game._on_undo_pressed()
	check(game._undo_stack.size() == 1 and game._pouring, "Alchemy: undo is rejected during a pour")
	await create_timer(0.8).timeout
	check(source.is_empty() and destination.top_run_count() == 2, "Alchemy: pour conserves both layers")
	await game._on_undo_pressed()
	check(source.top_run_count() == 2 and destination.is_empty(), "Alchemy: normal undo still restores the pour")
	game.queue_free()
	await process_frame
	# Exercise the original crash through the real fade/re-entry path at several phases.
	for delay in [0.02, 0.17, 0.34]:
		var main = load("res://games/alchemical_sort/scenes/Main.tscn").instantiate()
		root.add_child(main)
		await create_timer(0.5).timeout
		main.get_node("Menu").start_game.emit(0)
		await create_timer(1.9).timeout
		game = main.get_node("Game")
		game._do_pour(game._vials[0], game._vials[6])
		await create_timer(delay).timeout
		main.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
		await create_timer(0.7).timeout
		main.get_node("Menu").start_game.emit(0)
		await create_timer(1.9).timeout
		check(game._board_active and not game._pouring and game._queued_vial == null, "Alchemy: re-entry after pour phase %s is playable" % delay)
		check(game._move_count == 0, "Alchemy: old pour cannot count a move on a new board")
		game._on_undo_pressed()
		main.queue_free()
		await process_frame
	# Cancel mystery reveal and an animated undo before rebuilding.
	game = load("res://games/alchemical_sort/scenes/Game.tscn").instantiate()
	root.add_child(game)
	game.set_difficulty(4)
	game.prepare_board()
	game.start_game()
	await create_timer(0.1).timeout
	game.set_difficulty(0)
	game.prepare_board()
	game.start_game()
	await create_timer(1.6).timeout
	check(game._board_active and not game._mystery_label.visible, "Alchemy: old mystery/entrance cannot affect a new board")
	for vial: Vial in game._vials:
		vial.restore([0, 0, 0, 0, 0])
	source = game._vials[0]
	destination = game._vials[1]
	source.restore([1, 1, 0, 0, 0])
	await game._do_pour(source, destination)
	game._on_undo_pressed()
	await create_timer(0.18).timeout
	game.prepare_board()
	game.start_game()
	await create_timer(1.6).timeout
	check(game._board_active and not game._pouring and game._move_count == 0, "Alchemy: leaving during animated undo cannot change the replacement board")
	for vial: Vial in game._vials:
		vial.restore([0, 0, 0, 0, 0])
	source = game._vials[0]
	destination = game._vials[1]
	source.restore([1, 2, 2, 0, 0])
	destination.restore([1, 1, 0, 0, 0])
	game._fire_catalyst(source)
	await create_timer(0.1).timeout
	game.prepare_board()
	game.start_game()
	await create_timer(1.6).timeout
	check(game._board_active and not game._pouring and game._move_count == 0, "Alchemy: leaving during catalyst transfer cannot change the replacement board")
	game.queue_free()
	await process_frame


func _gem() -> void:
	var game = load("res://games/gem_match/scenes/Game.tscn").instantiate()
	root.add_child(game)
	game.prepare_board()
	await game.start_game()
	check(game._game_active, "Gem: normal entrance activates gameplay")
	var pair: Array = game._find_hint_pair()
	check(pair.size() == 2, "Gem: generated board has a move")
	if pair.size() == 2:
		await game._attempt_swap(pair[0], Vector2(pair[1].col - pair[0].col, pair[1].row - pair[0].row))
		check(game._game_active and not game._busy and game.score > 0, "Gem: normal swap/cascade completes and scores")
		pair = game._find_hint_pair()
		game._attempt_swap(pair[0], Vector2(pair[1].col - pair[0].col, pair[1].row - pair[0].row))
		await create_timer(0.22).timeout
		game.stop_game()
		game.prepare_board()
		await game.start_game()
		await create_timer(0.8).timeout
		check(game._game_active and not game._busy and game.score == 0, "Gem: old swap/cascade cannot mutate replacement board")
	game.queue_free()
	await process_frame


func _potion_records() -> void:
	var cfg := ConfigFile.new()
	for record in [["easy", 120], ["medium", 50], ["hard", 20]]:
		cfg.set_value("progress", "best_moves_" + record[0], record[1])
	check(SafeFile.save_config(cfg, "user://potion_3_save.cfg") == OK, "Potion: record fixture saved")
	var game = load("res://games/potion_3/scenes/Game.tscn").instantiate()
	root.add_child(game)
	for difficulty in [0, 1, 2, 0, 1]:
		game.set_difficulty(difficulty)
		game.prepare_board()
		check(game._best_moves == [120, 50, 20][difficulty], "Potion: difficulty %d loads its own record" % difficulty)
	game.set_difficulty(3)
	for i in range(12):
		game.prepare_board()
		check(game._best_moves == [120, 50, 20][game._actual_difficulty], "Potion: Zen reroll loads the resolved record")
	game.set_difficulty(1)
	game.prepare_board()
	game._move_count = 40
	game._save_progress()
	cfg.clear()
	cfg.load("user://potion_3_save.cfg")
	check(cfg.get_value("progress", "best_moves_medium", 0) == 40, "Potion: improvement saves to the chosen difficulty")
	check(cfg.get_value("progress", "best_moves_easy", 0) == 120 and cfg.get_value("progress", "best_moves_hard", 0) == 20, "Potion: saving preserves other difficulty records")
	game.queue_free()
	await process_frame


func _farm() -> void:
	var main = load("res://games/zen_farm/scenes/Main.tscn").instantiate()
	root.add_child(main)
	await create_timer(0.5).timeout
	var menu = main.get_node("Menu")
	var game = main.get_node("Game")
	var before := FileAccess.get_file_as_string(SaveManager.SAVE_PATH)
	menu._on_new_farm_pressed()
	check(menu._confirmation.visible and not main._transitioning, "Farm: New Farm asks before replacing a save")
	check(FileAccess.get_file_as_string(SaveManager.SAVE_PATH) == before, "Farm: opening confirmation leaves old save intact")
	main.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	check(not menu._confirmation.visible and menu.visible, "Farm: Android Back dismisses confirmation")
	menu._on_new_farm_pressed()
	menu._confirmation.confirmed.emit()
	await create_timer(0.8).timeout
	check(game.visible and game._game_active and game._coins == 10000, "Farm: confirmed New Farm creates the usual fresh board")
	check(FileAccess.get_file_as_string(SaveManager.PREVIOUS_PATH) == before, "Farm: previous farm remains recoverable")
	game._coins = 222
	main.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await create_timer(0.8).timeout
	var cfg := ConfigFile.new()
	cfg.load(SaveManager.SAVE_PATH)
	check(cfg.get_value("meta", "coins", -1) == 222, "Farm: Back saves new farm")
	check(FileAccess.get_file_as_string(SaveManager.PREVIOUS_PATH) == before, "Farm: later saves preserve the previous farm")
	menu._on_restore_pressed()
	menu._confirmation.confirmed.emit()
	await create_timer(0.8).timeout
	check(game._coins == 4321 and game._game_active, "Farm: Restore Previous Farm loads the retained farm")
	game._coins = 777
	check(SaveManager.save_game(game), "Farm: first safe write succeeds")
	game._coins = 888
	check(SaveManager.save_game(game), "Farm: second safe write succeeds")
	cfg.clear()
	cfg.set_value("interrupted", "empty", true)
	cfg.save(SaveManager.SAVE_PATH)
	check(SaveManager.load_game(game) and game._coins == 777, "Farm: unreadable primary recovers last-good backup")
	check(SaveManager.load_cols() == game._cols, "Farm: dimensions and farm load use the same recovery")
	check(SaveManager.save_game(game), "Farm: recovery can save again")
	cfg.clear()
	cfg.set_value("meta", "coins", 0)
	cfg.save(SaveManager.SAVE_PATH)
	var old_backup := FileAccess.get_file_as_string(SaveManager.SAVE_PATH + ".bak")
	check(SaveManager.save_game(game), "Farm: saving after partial metadata succeeds")
	check(FileAccess.get_file_as_string(SaveManager.SAVE_PATH + ".bak") == old_backup, "Farm: partial metadata cannot replace the last-good backup")
	var saved := FileAccess.get_file_as_string(SaveManager.SAVE_PATH)
	DirAccess.make_dir_absolute(SaveManager.SAVE_PATH + ".tmp")
	game._coins = 999
	check(not SaveManager.save_game(game), "Farm: write failure is returned")
	check(FileAccess.get_file_as_string(SaveManager.SAVE_PATH) == saved, "Farm: failed write preserves primary")
	game.request_back()
	check(game._game_active and game.visible and not main._transitioning, "Farm: failed exit save keeps the farm open")
	DirAccess.remove_absolute(SaveManager.SAVE_PATH + ".tmp")
	game.request_back()
	await create_timer(0.8).timeout
	check(menu.visible and not game._farm_open, "Farm: retrying exit after write failure succeeds")
	var retained := FileAccess.get_file_as_string(SaveManager.SAVE_PATH)
	DirAccess.make_dir_absolute(SaveManager.PREVIOUS_PATH + ".tmp")
	menu._on_new_farm_pressed()
	menu._confirmation.confirmed.emit()
	await create_timer(0.8).timeout
	check(menu.visible and not game.visible and not main._transitioning, "Farm: failed previous-farm backup cancels New Farm")
	check(FileAccess.get_file_as_string(SaveManager.SAVE_PATH) == retained, "Farm: failed New Farm keeps the current save")
	DirAccess.remove_absolute(SaveManager.PREVIOUS_PATH + ".tmp")
	main.queue_free()
	await process_frame


func _config_failures() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("record", "value", 42)
	var path := "user://safe_config_regression.cfg"
	check(SafeFile.save_config(cfg, path) == OK, "Config: first save succeeds")
	cfg.set_value("record", "value", 75)
	check(SafeFile.save_config(cfg, path) == OK, "Config: replacement succeeds")
	var backup := ConfigFile.new()
	backup.load(path + ".bak")
	check(backup.get_value("record", "value", 0) == 42, "Config: backup holds previous successful save")
	DirAccess.remove_absolute(path)
	check(SafeFile.load_config(cfg, path) == OK and cfg.get_value("record", "value", 0) == 42, "Config: missing primary recovers backup")
	check(SafeFile.save_config(cfg, path) == OK, "Config: backup recovery can save again")
	var empty := FileAccess.open(path, FileAccess.WRITE)
	empty.close()
	check(SafeFile.load_config(cfg, path) == OK and cfg.get_value("record", "value", 0) == 42, "Config: empty primary recovers backup")
	check(SafeFile.save_config(cfg, path) == OK, "Config: empty-file recovery preserves the valid backup")
	DirAccess.make_dir_absolute(path + ".tmp")
	cfg.set_value("record", "value", 99)
	check(SafeFile.save_config(cfg, path) != OK, "Config: failed replacement is reported")
	var original := ConfigFile.new()
	original.load(path)
	check(original.get_value("record", "value", 0) == 42, "Config: failed replacement leaves old data intact")
	DirAccess.remove_absolute(path + ".tmp")
	DirAccess.make_dir_absolute(path + ".bak.tmp")
	check(SafeFile.save_config(cfg, path) != OK, "Config: failed backup write is reported")
	original.clear()
	original.load(path)
	check(original.get_value("record", "value", 0) == 42, "Config: failed backup write leaves primary intact")
	backup.clear()
	backup.load(path + ".bak")
	check(backup.get_value("record", "value", 0) == 42, "Config: failed backup write leaves backup intact")
	DirAccess.remove_absolute(path + ".bak.tmp")
