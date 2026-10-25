extends SceneTree

const State := preload("res://scripts/PuzzleState.gd")
const Checkpoint := preload("res://scripts/PotionCheckpoint.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

static func gated_write(request: Dictionary, path: String, gate: Semaphore) -> Dictionary:
	gate.wait()
	return Checkpoint.write(request, path)

func hold_writer(game: Node, session: Node, source: RefCounted) -> Semaphore:
	var gate := Semaphore.new()
	var thread := Thread.new()
	var result := thread.start(gated_write.bind(source.capture(game), session._path(), gate))
	check(result == OK, "Held filesystem writer starts")
	session._writer = thread
	session._inflight_stamp = State.stamp(game, "potion_3")
	return gate

func finish_writer(session: Node) -> void:
	var deadline := Time.get_ticks_msec() + 10000
	while session._writer != null and Time.get_ticks_msec() < deadline:
		session._finish_background_write()
		await process_frame
	check(session._writer == null, "Background writer completes and joins")

func read_state(path: String) -> Dictionary:
	var cfg := ConfigFile.new()
	check(cfg.load(path) == OK, "Checkpoint file is readable")
	var data: Dictionary = cfg.get_value("round", "state", {})
	check(State.valid(data, "potion_3"), "Checkpoint retains the validated save schema")
	return data

func _run() -> void:
	var safe := ProjectSettings.globalize_path("res://.godot/puzzle_test_user/").replace("\\", "/")
	if not OS.get_user_data_dir().replace("\\", "/").begins_with(safe):
		quit(2)
		return
	Engine.time_scale = 12.0
	root.get_node("AudioManager")._audio_unlocked = true
	var main = load("res://games/potion_3/scenes/Main.tscn").instantiate()
	root.add_child(main)
	while main._transitioning: await process_frame
	var game = main.get_node("Game")
	var session = game.get_node("RoundSession")
	session.set_process(false)
	main.get_node("Menu").hide()
	game.show()
	game.set_difficulty(2)
	seed(8100)
	game.prepare_board()
	await game.start_game()
	game._game_generation += 1  # Freeze scheduled belt ticks, preserving their layout.
	check(not game._scrolling_rows.is_empty() and game._hazard_disp_scroll, "Fixture contains both conveyor types")
	for i in range(3): game._save_undo_snapshot()
	game._move_count = 3
	var source := Checkpoint.new()
	var request := source.capture(game)
	var original := Checkpoint.materialize(request).duplicate(true)
	check(original == State.capture(game, "potion_3"), "Cached history matches the normal capture")
	# Source dictionaries and live cells cannot mutate an already queued request.
	var entry: Array = game._undo_stack[0][0]
	var old_flag: bool = entry[1].slot_mystery[0]
	entry[1].slot_mystery[0] = not old_flag
	check(Checkpoint.materialize(request) == original, "Queued undo data owns its snapshots")
	entry[1].slot_mystery[0] = old_flag
	var row: Array = game._cells[game._scrolling_rows[0]]
	row.append(row.pop_front())
	game._disp_scroll_cells.push_front(game._disp_scroll_cells.pop_back())
	check(Checkpoint.materialize(source.capture(game)) == State.capture(game, "potion_3"), "Both conveyor rotations preserve undo identities")
	game._undo_stack.pop_back()
	game._save_undo_snapshot()
	check(Checkpoint.materialize(source.capture(game)) == State.capture(game, "potion_3"), "Undo followed by a new branch replaces the cached suffix")
	session.save_now()
	var gate := hold_writer(game, session, source)
	game._move_count += 1
	session.save_in_background()
	var first_queued: Dictionary = Checkpoint.materialize(session._queued_save)
	game._move_count += 1
	session.save_in_background()
	var latest := State.capture(game, "potion_3")
	check(session._writer != null and not session._queued_save.is_empty(), "A blocked writer leaves input free to queue another checkpoint")
	check(first_queued.moves == latest.moves - 1 and Checkpoint.materialize(session._queued_save) == latest, "Newer pending checkpoints coalesce to the latest state")
	gate.post()
	session.save_now()
	check(session._writer == null and session._queued_save.is_empty(), "Lifecycle flush drains the writer and newer checkpoint")
	check(read_state(session._path()) == latest, "Older background completion cannot overwrite the latest checkpoint")
	# A real move starts a save, removes its source visual, then yields in flight.
	# Stopping at that point must persist the complete pre-move board.
	var moving_from: PotionCell
	var moving_to: PotionCell
	var from_slot := -1
	var to_slot := -1
	for cell in game._all_cells():
		if cell.is_locked(): continue
		for slot in range(3):
			if cell.get_item(slot) != 0 and moving_from == null:
				moving_from = cell
				from_slot = slot
			elif cell.get_item(slot) == 0 and not cell.is_dispenser():
				moving_to = cell
				to_slot = slot
	row.append(row.pop_front())
	var before_move := State.capture(game, "potion_3")
	game._try_move(moving_from, from_slot, moving_to, to_slot)
	check(game._animating and session._writer != null, "Real item flight starts without waiting for its checkpoint")
	game.stop_game()
	check(read_state(session._path()) == before_move, "Interrupted item flight flushes the complete pre-move state")
	session._restoring = true
	check(State.restore(game, before_move), "Interrupted move checkpoint remains restorable")
	session._restoring = false
	await game.start_game()
	game._game_generation += 1
	# Failed async writes keep the valid primary and retry with an unchanged board.
	var previous_file := FileAccess.get_file_as_string(session._path())
	var temp_path: String = session._path() + ".tmp"
	check(DirAccess.make_dir_absolute(temp_path) == OK, "Async write-failure fixture installed")
	game._move_count += 1
	session.save_in_background()
	await finish_writer(session)
	check(session._pending_write and FileAccess.get_file_as_string(session._path()) == previous_file, "Async failure preserves the primary and pending checkpoint")
	check(DirAccess.remove_absolute(temp_path) == OK, "Async write-failure fixture removed")
	session.save_in_background()
	await finish_writer(session)
	check(not session._pending_write and read_state(session._path()) == State.capture(game, "potion_3"), "Unchanged checkpoint retries successfully in the background")
	gate = hold_writer(game, session, source)
	game._move_count += 1
	session.save_in_background()
	gate.post()
	session.discard()
	await process_frame
	check(session._writer == null and session._queued_save.is_empty() and not FileAccess.file_exists(session._path()) and not FileAccess.file_exists(session._path() + ".bak"), "Discard joins the writer and cannot resurrect the retired round")
	# Closing before the first save completes must still persist a newer queued state.
	session.begin_new()
	gate = hold_writer(game, session, source)
	game._move_count += 1
	session.save_in_background()
	latest = State.capture(game, "potion_3")
	var path: String = session._path()
	check(session._saved.is_empty(), "Exit fixture has no previously completed checkpoint")
	gate.post()
	main.queue_free()
	await process_frame
	await process_frame
	check(read_state(path) == latest, "Scene exit flushes even the first in-flight checkpoint and newer queued state")
	print("POTION CHECKPOINT: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
