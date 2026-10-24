extends SceneTree

func _initialize() -> void:
	var game = load("res://games/alchemical_sort/scenes/Game.tscn").instantiate()
	var cases := []
	for i in range(48):
		seed(27000 + i)
		game._difficulty = i % 4
		game._apply_difficulty_layout()
		cases.append({"seed": 27000 + i, "mode": i % 4, "layers": game._generate_shuffled_layers()})
	var file := FileAccess.open("res://.godot/alchemy_boards.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(cases))
	game.free()
	print("EXPORTED ALCHEMY BOARDS: ", cases.size())
	quit()
