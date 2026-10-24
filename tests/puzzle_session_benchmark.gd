extends SceneTree

const State := preload("res://scripts/PuzzleState.gd")
# Synthetic, schema-valid undo histories exercise the idle checkpoint path.
# Run with isolated .godot/puzzle_test_user APPDATA; timings are desktop data.
var report := []

func _initialize() -> void:
	_run.call_deferred()

func measure(action: Callable, count: int) -> float:
	var begin := Time.get_ticks_usec()
	for i in count: action.call()
	return float(Time.get_ticks_usec()-begin)/count/1000.0

func _run() -> void:
	var isolated := ProjectSettings.globalize_path("res://.godot/puzzle_test_user/").replace("\\", "/")
	if not OS.get_user_data_dir().replace("\\", "/").begins_with(isolated):
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute("res://.godot/performance_review")
	Engine.time_scale = 20.0
	root.get_node("AudioManager")._audio_unlocked = true
	for kind in ["potion_3","alchemical_sort","tile_chain","gem_match"]:
		seed(28901)
		var main = load("res://games/%s/scenes/Main.tscn" % kind).instantiate()
		root.add_child(main)
		while main._transitioning: await process_frame
		var game = main.get_node("Game")
		main.get_node("Menu").hide()
		game.show()
		if kind in ["potion_3","alchemical_sort"]: game.set_difficulty(2)
		game.prepare_board()
		await game.start_game()
		var session = game.get_node("RoundSession")
		session.save_now()
		for history in ([0,100,500] if kind in ["potion_3","alchemical_sort"] else [0]):
			var data := State.capture(game,kind)
			if history>0:
				var step: Array = data.cells if kind=="potion_3" else []
				if kind=="alchemical_sort":
					for vial in data.vials: step.append(vial.layers)
				for i in history: data.undo.append(step.duplicate(true))
			check_valid(data,kind)
			session._saved = data
			session._encoded = var_to_str(data)
			session._stamp = State.stamp(game,kind)
			var result := {"kind":kind,"synthetic_history":history,"bytes":session._encoded.length(),
				"idle_save_ms":measure(session.save_now,30),
				"serialize_ms":measure(func():var_to_str(data),30),
				"stamp_ms":measure(func():State.stamp(game,kind),30)}
			report.append(result)
			print(JSON.stringify(result))
		# Synthetic history is measurement data, never a real persisted round.
		session._armed = false
		main.queue_free()
		await process_frame
		await process_frame
	var label := "before" if "--before" in OS.get_cmdline_user_args() else "after"
	var file := FileAccess.open("res://.godot/performance_review/save_%s.json" % label,FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	quit()

func check_valid(data: Dictionary, kind: String) -> void:
	assert(State.valid(data,kind),"Benchmark data must pass the normal round validator")
