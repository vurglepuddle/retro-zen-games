extends SceneTree

const State := preload("res://scripts/PuzzleState.gd")
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
	var isolated := ProjectSettings.globalize_path("res://.godot/puzzle_test_user/").replace("\\", "/")
	if not OS.get_user_data_dir().replace("\\", "/").begins_with(isolated):
		push_error("Use isolated puzzle_test_user APPDATA")
		quit(2)
		return
	Engine.time_scale = 12.0
	for kind in ["potion_3", "alchemical_sort", "tile_chain", "gem_match"]:
		seed(8703)
		var main = load("res://games/%s/scenes/Main.tscn" % kind).instantiate()
		root.add_child(main)
		while main._transitioning:
			await process_frame
		await process_frame
		var game = main.get_node("Game")
		var session = game.get_node("RoundSession")
		session.discard()
		main.get_node("Menu").hide()
		game.show()
		if kind in ["potion_3", "alchemical_sort"]: game.set_difficulty(3)
		if kind == "gem_match": game.set_timed_mode(true)
		game.prepare_board()
		await game.start_game()
		await create_timer(0.2).timeout
		var snapshot := State.capture(game, kind)
		check(State.valid(snapshot, kind), kind + ": captured state validates")
		var broken := snapshot.duplicate(true)
		broken["cells" if kind != "alchemical_sort" else "vials"] = []
		check(not State.valid(broken, kind), kind + ": malformed dimensions rejected")
		var audio: Control = game.get_node("AudioControls")
		check(audio.get_child_count() == 2, kind + ": both audio controls installed")
		var old_music: bool = root.get_node("AudioManager").music_on
		var audio_point: Vector2 = audio.get_child(0).get_global_rect().get_center()
		for pressed in [true, false]:
			var event := InputEventMouseButton.new()
			event.button_index = MOUSE_BUTTON_LEFT
			event.position = audio_point
			event.pressed = pressed
			root.push_input(event, true)
		check(root.get_node("AudioManager").music_on != old_music, kind + ": music button handles a real GUI click once")
		audio.get_child(0).pressed.emit()
		if kind == "alchemical_sort":
			var helper: Vial = game._vials.back()
			check(helper.is_cauldron and helper.capacity == 1, "Alchemy: Zen helper has capacity one")
			await game._do_pour(game._vials[0], helper)
			check(helper.is_full() and is_equal_approx(helper.surface_y(), float(Vial.BOTTLE_PAD_TOP)), "Alchemy: one liquid fills helper to the top")
			check(is_equal_approx(helper._layer_rects[0].scale.y, 5.0), "Alchemy: liquid spans full helper window")
			var last_row: Array = game._vials.slice((game._vials.size() - 2) / game._vials_per_row * game._vials_per_row)
			var left := INF
			var right := -INF
			for vial: Vial in last_row:
				left = minf(left, vial.position.x + vial.pivot_offset.x * (1.0 - vial.scale.x))
				right = maxf(right, vial.position.x + vial.pivot_offset.x * (1.0 - vial.scale.x) + vial.VIAL_W * vial.scale.x)
			check(absf((left + right) * 0.5 - 270.0) <= 1.0, "Alchemy: last shelf including helper is centred")
		if kind == "potion_3":
			var source: PotionCell = null
			var source_slot := -1
			var destination: PotionCell = null
			var destination_slot := -1
			for cell in game._all_cells():
				if cell.is_locked(): continue
				for slot in range(3):
					if cell.get_item(slot) > 0 and source == null:
						source = cell; source_slot = slot
					elif cell.get_item(slot) == 0 and not cell.is_dispenser():
						destination = cell; destination_slot = slot
			await game._try_move(source, source_slot, destination, destination_slot, false)
			check(game._undo_stack.size() == 1, "Potion: round fixture includes undo history")
		session.save_now()
		check(FileAccess.file_exists(session._path()), kind + ": round saved")
		snapshot = session._saved.duplicate(true)
		var invalid := snapshot.duplicate(true)
		if kind == "alchemical_sort":
			invalid.vials.back().layers = [1, 2, 0, 0, 0]
			check(not State.valid(invalid, kind), "Overfull helper save is rejected")
		if kind == "potion_3":
			invalid.cells[0].slots[0] = 999999
			check(not State.valid(invalid, kind), "Broken triple counts/missing artwork are rejected")
		# Interrupt a real animation synchronously, before its item arrives.
		# The file must retain the last complete board, not the in-flight state.
		if kind == "alchemical_sort":
			var target: Vial = game._vials[game._vials.size() - 3]
			game._do_pour(game._vials[0], target)
			game.stop_game()
			check(session._saved == snapshot, "Interrupted pour keeps the last complete checkpoint")
		# An invalid newer primary must recover the verified backup round.
		var cfg := ConfigFile.new()
		cfg.set_value("round", "version", 1)
		cfg.set_value("round", "state", snapshot)
		cfg.save(session._path() + ".bak")
		cfg.set_value("round", "state", {"kind": kind, "mode": 0})
		cfg.save(session._path())
		session._encoded = var_to_str(snapshot)  # leave the intentionally bad primary for load recovery
		main.queue_free()
		await process_frame
		await process_frame
		main = load("res://games/%s/scenes/Main.tscn" % kind).instantiate()
		root.add_child(main)
		while main._transitioning:
			await process_frame
		await process_frame
		game = main.get_node("Game")
		session = game.get_node("RoundSession")
		if kind == "potion_3":
			game._load_textures()
			var reordered := {}
			for id in game._item_textures: reordered[id + 10000] = game._item_textures[id]
			game._item_textures = reordered
			var expected_paths := {}
			for id in snapshot.item_paths: expected_paths[id + 10000] = snapshot.item_paths[id]
			snapshot.item_paths = expected_paths
			var all_states: Array = snapshot.cells.duplicate()
			for step in snapshot.undo: all_states.append_array(step)
			for cell in all_states:
				for layer in [cell.slots] + cell.z_stack:
					for i in range(3):
						if layer[i] != 0: layer[i] += 10000
		check(session._continue.visible, kind + ": Continue offered after fresh scene load")
		await session._resume()
		await create_timer(3.0).timeout
		var backup := ConfigFile.new()
		check(backup.load(session._path() + ".bak") == OK and State.valid(backup.get_value("round", "state", {}), kind), kind + ": saving after recovery preserves a valid backup")
		var restored := State.capture(game, kind)
		if kind == "gem_match":
			restored.time = snapshot.time
		if kind == "alchemical_sort":
			restored.tint_time = snapshot.tint_time
			for i in range(snapshot.tints.size()):
				check(restored.tints[i].is_equal_approx(snapshot.tints[i]), "Alchemy: tint survives save precision")
				check(restored.phases[i].is_equal_approx(snapshot.phases[i]), "Alchemy: drift survives save precision")
			restored.tints = snapshot.tints
			restored.phases = snapshot.phases
		if restored != snapshot:
			for key in snapshot:
				if restored.get(key) != snapshot[key]:
					print(kind, " differs: ", key, " restored=", str(restored.get(key)).left(200), " saved=", str(snapshot[key]).left(200))
		check(restored == snapshot, kind + ": Continue restores exact logical round")
		if kind in ["potion_3", "alchemical_sort"]:
			await game._on_undo_pressed()
			check(game._move_count == snapshot.moves - 1, kind + ": undo remains usable after reload")
		session.discard()
		main.queue_free()
		await process_frame
		await process_frame
	# Farm keeps its existing save system; its audio buttons share the same bus state.
	var farm_main = load("res://games/zen_farm/scenes/Main.tscn").instantiate()
	root.add_child(farm_main)
	while farm_main._transitioning: await process_frame
	await farm_main._on_start_game(true)
	var farm = farm_main.get_node("Game")
	farm.get_node("TipPanel").hide()
	var farm_audio: Control = farm.get_node("AudioControls")
	check(not farm_audio.get_global_rect().intersects(farm.get_node("FarmScroll").get_global_rect()), "Farm audio occupies the HUD, not plant hit areas")
	for button in farm_audio.get_children():
		var old_music: bool = root.get_node("AudioManager").music_on
		var old_sfx: bool = root.get_node("AudioManager").sfx_on
		for pressed in [true, false]:
			var event := InputEventMouseButton.new()
			event.button_index = MOUSE_BUTTON_LEFT
			event.position = button.get_global_rect().get_center()
			event.pressed = pressed
			root.push_input(event, true)
		if button.name == "Music":
			check(root.get_node("AudioManager").music_on != old_music and root.get_node("AudioManager").sfx_on == old_sfx, "Farm music button is independent")
		else:
			check(root.get_node("AudioManager").sfx_on != old_sfx and root.get_node("AudioManager").music_on == old_music, "Farm SFX button is independent")
	farm_main.queue_free()
	await process_frame
	print("PUZZLE SESSION: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
