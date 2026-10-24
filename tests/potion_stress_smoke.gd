extends SceneTree

var checks := 0
var failures: Array[String] = []
var game: Control
var textures := {}
var moves_run := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func counts() -> Dictionary:
	var result := {}
	for cell in game._all_cells():
		var layers: Array = [cell.get_slots_array()] + cell.get_z_stack_copy()
		for layer in layers:
			for id in layer:
				if id != 0:
					result[id] = result.get(id, 0) + 1
	return result

func state() -> Array:
	var result := []
	for cell in game._all_cells():
		result.append([cell, cell.get_snapshot()])
	return result

func _run() -> void:
	var isolated := ProjectSettings.globalize_path("res://.godot/puzzle_test_user/").replace("\\", "/")
	if not OS.get_user_data_dir().replace("\\", "/").begins_with(isolated):
		push_error("Use isolated puzzle_test_user APPDATA")
		quit(2)
		return
	Engine.time_scale = 30.0
	var image := Image.create(30, 30, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var texture := ImageTexture.create_from_image(image)
	for id in range(1, 65):
		textures[id] = texture
	game = load("res://games/potion_3/scenes/Game.tscn").instantiate()
	root.add_child(game)
	game._item_textures = textures
	# Check generation independently of rendering/animations over reproducible seeds.
	for seed_id in range(400):
		seed(seed_id)
		game._scrolling_rows.clear()
		game.set_difficulty(seed_id % 4)
		game._apply_difficulty_layout()
		var data: Dictionary = game._generate_board_data()
		var generated := {}
		for cell in data.items:
			for layer in cell:
				for id in layer:
					if id != 0: generated[id] = generated.get(id, 0) + 1
		for group in data.dispenser_groups + data.disp_scroll_groups:
			for id in group:
				if id != 0: generated[id] = generated.get(id, 0) + 1
		check(generated.size() == game._item_type_count, "Seed %d: all types placed" % seed_id)
		for id in generated:
			check(generated[id] == 3, "Seed %d: type %d has exactly three copies" % [seed_id, id])
	# Real move/match/reveal/undo code, including every kind of inventory cell.
	for seed_id in range(24):
		seed(8000 + seed_id)
		game.set_difficulty(seed_id % 4)
		game.prepare_board()
		game._board_active = true
		for cell in game._all_cells():
			cell.position.y += 160.0
			cell.modulate.a = 1.0
		for move_id in range(45):
			var sources := []
			var destinations := []
			for cell in game._all_cells():
				if cell.is_locked(): continue
				for slot in range(3):
					if cell.get_item(slot) != 0: sources.append([cell, slot])
					elif not cell.is_dispenser(): destinations.append([cell, slot])
			if sources.is_empty() or destinations.is_empty(): break
			var source: Array = sources.pick_random()
			var destination: Array = destinations.pick_random()
			var before := counts()
			var snapshot := state()
			var was_mystery: bool = source[0].is_slot_mystery(source[1])
			var item: int = source[0].get_item(source[1])
			await game._try_move(source[0], source[1], destination[0], destination[1], false)
			moves_run += 1
			var after := counts()
			for id in before:
				var removed: int = before[id] - after.get(id, 0)
				check(removed == 0 or removed == 3, "Seed %d move %d: only complete triples removed (%d)" % [seed_id, move_id, id])
			if destination[0].get_item(destination[1]) == item:
				check(destination[0].is_slot_mystery(destination[1]) == was_mystery, "Mystery identity follows move")
			if move_id % 3 == 0 and not game._win_panel.visible:
				# Rotate array order as conveyors do; undo must follow cell identity.
				for row in game._cells:
					row.append(row.pop_front())
				if not game._disp_scroll_cells.is_empty():
					game._disp_scroll_cells.push_front(game._disp_scroll_cells.pop_back())
				game._on_undo_pressed()
				check(counts() == before, "Undo conserves every item after conveyor reorder")
				for entry in snapshot:
					check(entry[0].get_snapshot() == entry[1], "Undo restores layers, mystery flags and locks by identity")
			if game._win_panel.visible: break
			game._board_active = true
		await process_frame
	# Input boundaries must follow the overlapping artwork, not 90px rows.
	game.set_difficulty(0)
	game.prepare_board()
	game._board_active = true
	for cell in game._all_cells():
		cell.position.y += 160.0
		cell.modulate.a = 1.0
	var cell: PotionCell = game._cells[0][0]
	var point := cell.global_position + Vector2(45, PotionCell.SLOT_Y_OFFSET + 2 * (90 - PotionCell.SLOT_OVERLAP) + 2)
	var hit = game._find_cell_slot_at(point)
	check(hit != null and hit[0] == cell and hit[1] == 2, "Overlapping slot artwork owns its top hit area")
	# A stale/double event must not overwrite a destination or move an empty slot.
	var original := state()
	cell.set_item(0, 1)
	cell.set_item(1, 2)
	var before_invalid := counts()
	await game._try_move(cell, 0, cell, 1, false)
	check(counts() == before_invalid, "Occupied destination rejects stale input without losing items")
	for entry in original: entry[0].restore(entry[1])
	# Exercise the actual opposite-direction conveyor tweens and wrap callbacks.
	game.stop_game()
	game._clear_cells()
	game.set_difficulty(2)
	game._apply_difficulty_layout()
	game._scrolling_rows.assign([0])
	game._dispenser_count = 2
	game._hazard_disp_scroll = true
	game._build_cells()
	game._board_active = true
	var belt_inventory := counts()
	game._advance_scroll(0)
	game._advance_disp_scroll()
	for tick in range(6):
		var active: Tween = game._scroll_tweens.back()
		await active.finished
		check(counts() == belt_inventory, "Real conveyor wrap preserves visible and hidden inventories")
		check(game._scroll_tweens.size() <= 2, "Only active conveyor tweens are retained")
	game.stop_game()
	game._clear_cells()
	game._scrolling_rows.assign([0])
	game._dispenser_count = 0
	game._hazard_disp_scroll = false
	game._special_lock = false
	game._build_cells()
	for shelf in game._all_cells():
		var slots := [1, 1, 1] if not shelf in game._buffer_cells else [0, 0, 0]
		shelf.restore({"slots": slots, "z_stack": [], "slot_mystery": [false, false, false],
			"z_stack_mystery": [], "is_locked": false, "unlock_counter": 0})
	var source: PotionCell = game._cells[0][0]
	source.set_item(0, 2)
	game._board_active = true
	game._selected_cell = source
	game._selected_slot = 0
	game._press_pos = source.global_position + source.get_slot_center(0)
	game._start_drag(game._press_pos)
	await game._end_drag(Vector2(535, source.global_position.y + source.get_slot_center(0).y))
	check(source.get_item(0) == 2, "Drop snapping cannot hide an item in an off-screen conveyor buffer")
	check(source._slot_rects[0].visible, "Rejected edge drop restores the dragged sprite")
	game.stop_game()
	game.queue_free()
	await process_frame
	print("POTION MOVES EXERCISED: %d" % moves_run)
	print("POTION STRESS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
