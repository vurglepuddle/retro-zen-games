extends Node

const State := preload("res://scripts/PuzzleState.gd")
const SafeFile := preload("res://scripts/SafeConfig.gd")
const KINDS := ["gem_match", "tile_chain", "alchemical_sort", "potion_3"]
var game: Node
var kind := ""
var _saved := {}
var _encoded := ""
var _stamp := []
var _pending_write := false
var _elapsed := 0.0
var _armed := false
var _restoring := false
var _continue: Button

func _ready() -> void:
	game = get_parent()
	kind = game.scene_file_path.split("/")[3]
	_load_round()
	_add_continue_button()

func _path() -> String:
	return "user://%s_round.cfg" % kind

func _load_round() -> void:
	for path in [_path(), _path() + ".bak"]:
		var cfg := ConfigFile.new()
		if cfg.load(path) == OK and _valid_config(cfg):
			var data = cfg.get_value("round", "state", {})
			_saved = data
			_encoded = var_to_str(data)
			return

func _valid_config(cfg: ConfigFile) -> bool:
	return cfg.get_value("round", "version", 0) == 1 \
		and State.valid(cfg.get_value("round", "state", {}), kind)

func _add_continue_button() -> void:
	var menu := game.get_parent().get_node("Menu") as Control
	var reference := menu.get_node_or_null("BackButton") as Button
	if reference == null: reference = menu.get_node_or_null("QuitButton") as Button
	_continue = reference.duplicate(0) as Button if reference else Button.new()
	_continue.name = "ContinueRound"
	_continue.text = "CONTINUE"
	_continue.size = Vector2(240, 64)
	_continue.position = {
		"gem_match": Vector2(150, 1008), "tile_chain": Vector2(150, 828),
		"alchemical_sort": Vector2(234, 942), "potion_3": Vector2(282, 1147),
	}[kind]
	if kind in ["alchemical_sort", "potion_3"]:
		_continue.size.y = reference.size.y
	_continue.visible = not _saved.is_empty()
	_continue.pressed.connect(_resume)
	menu.add_child(_continue)

func begin_new() -> void:
	if _restoring: return
	discard()
	if is_instance_valid(_continue):
		_continue.disabled = false
		_continue.text = "CONTINUE"
		_continue.tooltip_text = ""
	_armed = true

func discard() -> void:
	_saved = {}
	_encoded = ""
	_stamp = []
	_pending_write = false
	_armed = false
	for path in [_path(), _path() + ".bak"]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	if is_instance_valid(_continue): _continue.hide()

func _completed() -> bool:
	match kind:
		"potion_3", "alchemical_sort": return game._win_panel.visible
		"tile_chain": return game._clear_panel.visible
		"gem_match": return game._game_over_panel != null and game._game_over_panel.visible
	return false

func _stable() -> bool:
	if not game.is_visible_in_tree(): return false
	match kind:
		"potion_3": return (game._board_active or game._reshuffle_btn.visible) and not game._animating and not game._drag_active
		"alchemical_sort": return (game._board_active or game._reshuffle_btn.visible) and not game._pouring
		"tile_chain": return game._board_active and not game._reshuffling
		"gem_match": return game._game_active and not game._busy
	return false

func save_now() -> void:
	if _restoring or not _armed: return
	if _completed():
		discard()
		return
	if _stable():
		var current := State.stamp(game, kind)
		if current != _stamp:
			var data := State.capture(game, kind)
			if State.valid(data, kind):
				_saved = data
				_stamp = current
				_pending_write = true
	# Unchanged rounds need only the small board stamp, never the full undo
	# history serialized again. Keep failed writes pending so they retry.
	if _saved.is_empty() or not _pending_write: return
	var serialized := var_to_str(_saved)
	if serialized == _encoded:
		_pending_write = false
		return
	var cfg := ConfigFile.new()
	cfg.set_value("round", "version", 1)
	cfg.set_value("round", "state", _saved)
	if SafeFile.save_config(cfg, _path(), "round", ["version", "state"], _valid_config) == OK:
		_encoded = serialized
		_pending_write = false
		if is_instance_valid(_continue): _continue.show()

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= 1.0:
		_elapsed = 0.0
		save_now()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		if is_instance_valid(game): save_now()

func _exit_tree() -> void:
	# stop_game takes the final live snapshot before scene teardown.
	if _armed and not _saved.is_empty() and is_instance_valid(game): save_now()

func _resume() -> void:
	var main := game.get_parent()
	var fade: ColorRect = main.get("_fade_rect")
	if not main._begin_transition(fade): return
	await main._fade_to_black()
	_restoring = true
	var restored := State.restore(game, _saved.duplicate(true))
	_restoring = false
	if restored:
		_armed = true
		main.get_node("Menu").hide()
		game.show()
		if kind == "gem_match": main._last_mode = _saved.mode
	else:
		# Missing artwork can be restored later; keep the saved round intact.
		_continue.text = "UNAVAILABLE"
		_continue.disabled = true
		_continue.tooltip_text = UIFeedback.tooltip("This saved round could not be opened. You can start a new game.")
	await main._fade_from_black()
	if restored:
		await game.start_game()
		if _saved.get("dead", false):
			if kind == "potion_3": game._show_reshuffle_prompt()
			elif kind == "alchemical_sort": game._check_dead_board()
