extends SceneTree

var checks := 0
var failures: Array[String] = []
var game: Control

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func counts() -> Dictionary:
	var result := {}
	for vial: Vial in game._vials:
		for color in vial.get_layers():
			if color != 0: result[color] = result.get(color, 0) + 1
	return result

func _run() -> void:
	var isolated := ProjectSettings.globalize_path("res://.godot/puzzle_test_user/").replace("\\", "/")
	if not OS.get_user_data_dir().replace("\\", "/").begins_with(isolated):
		push_error("Use isolated puzzle_test_user APPDATA")
		quit(2)
		return
	Engine.time_scale = 30.0
	game = load("res://games/alchemical_sort/scenes/Game.tscn").instantiate()
	root.add_child(game)
	var layouts := {}
	for seed_id in range(32):
		seed(seed_id)
		game.set_difficulty(3)
		game.prepare_board()
		layouts[str([game._actual_difficulty, game._fog_mode])] = true
		var helper: Vial = game._vials.back()
		var layers: Array[int] = [1, 0, 0, 0, 0]
		helper.restore(layers)
		check(helper.is_full() and helper.free_slots() == 0, "Helper is full after one logical liquid")
		check(is_equal_approx(helper.surface_y(), float(Vial.BOTTLE_PAD_TOP)), "Helper's full surface reaches its neck")
		check(is_equal_approx(helper._layer_rects[0].size.y * helper._layer_rects[0].scale.y, 160.0), "Helper liquid fills the full glass window")
		var normal_count: int = game._vials.size() - 1
		var first: int = (normal_count - 1) / game._vials_per_row * game._vials_per_row
		var left := INF
		var right := -INF
		for vial: Vial in game._vials.slice(first):
			var edge: float = vial.position.x + vial.pivot_offset.x * (1.0 - vial.scale.x)
			left = minf(left, edge)
			right = maxf(right, edge + vial.VIAL_W * vial.scale.x)
		check(absf((left + right) * 0.5 - 270.0) <= 1.0, "Helper and last shelf are centred together")
		check(left >= 16.0 and right <= 524.0, "Helper stays clear of board edges")
		await process_frame
	check(layouts.size() >= 4, "Zen sample exercises ordinary layouts and mystery layouts")
	# Replay independently solved witnesses through the real animated pour code.
	var boards = JSON.parse_string(FileAccess.get_file_as_string("res://.godot/alchemy_boards.json"))
	var solutions = JSON.parse_string(FileAccess.get_file_as_string("res://.godot/alchemy_solver_results.json"))
	for index in range(4):
		var fixture: Dictionary = boards[index]
		seed(int(fixture.seed))
		game.set_difficulty(int(fixture.mode))
		game.prepare_board()
		game._rune_vial = null  # audit the base pour rules independently of the optional gift
		game._rune_fired = true
		for i in range(fixture.layers.size()):
			var layers: Array[int] = []
			for value in fixture.layers[i]: layers.append(int(value))
			game._vials[i].restore(layers)
		game._board_active = true
		var inventory := counts()
		for pair in solutions[index].path:
			var source: Vial = game._vials[int(pair[0])]
			var destination: Vial = game._vials[int(pair[1])]
			check(game._can_pour(source, destination), "Independent solution move is legal in the real game")
			await game._do_pour(source, destination)
			check(counts() == inventory, "Animated pours preserve every color, including partial transfers")
		check(game._check_win(), "Independent witness solves the actual game")
	game.queue_free()
	await process_frame
	print("ALCHEMY RULES: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
