extends RefCounted

const State := preload("res://scripts/PuzzleState.gd")
const SafeFile := preload("res://scripts/SafeConfig.gd")

# Only capture() and reset() run on the game thread. Each undo step is immutable
# after creation; copy it once, then share those plain values with save jobs.
var _generation := -1
var _sources := []
var _steps := []

func reset() -> void:
	_generation = -1
	_sources.clear()
	_steps.clear()

func capture(game: Node) -> Dictionary:
	if _generation != game._game_generation:
		reset()
		_generation = game._game_generation
	var history: Array = game._undo_stack
	var common := 0
	while common < mini(history.size(), _sources.size()) and is_same(history[common], _sources[common]):
		common += 1
	_sources.resize(common)
	_steps.resize(common)
	for i in range(common, history.size()):
		var step := {}
		for entry in history[i]:
			step[entry[0].get_instance_id()] = entry[1].duplicate(true)
		_sources.append(history[i])
		_steps.append(step)
	var data := State.capture(game, "potion_3", false)
	var ids := []
	for cell in game._all_cells(): ids.append(cell.get_instance_id())
	data["_cell_ids"] = ids
	# The worker owns the outer array; cached step dictionaries are read-only.
	data["_undo_steps"] = _steps.duplicate()
	return data

static func materialize(request: Dictionary) -> Dictionary:
	var data := request.duplicate()
	if data.has("_undo_steps"):
		var undo := []
		for step in data._undo_steps:
			var ordered := []
			for id in data._cell_ids: ordered.append(step.get(id, {}))
			undo.append(ordered)
		data.undo = undo
		data.erase("_undo_steps")
		data.erase("_cell_ids")
	return data

static func write(request: Dictionary, path: String) -> Dictionary:
	# No scene nodes, textures, shared mutable containers, or UI calls here.
	var data := materialize(request)
	if not State.valid(data, "potion_3"):
		return {"valid": false}
	var encoded := var_to_str(data)
	var cfg := ConfigFile.new()
	cfg.set_value("round", "version", 1)
	cfg.set_value("round", "state", data)
	var result := SafeFile.save_config(cfg, path, "round", ["version", "state"], _valid_config)
	return {"valid": true, "state": data, "encoded": encoded, "error": result}

static func _valid_config(cfg: ConfigFile) -> bool:
	return cfg.get_value("round", "version", 0) == 1 \
		and State.valid(cfg.get_value("round", "state", {}), "potion_3")
