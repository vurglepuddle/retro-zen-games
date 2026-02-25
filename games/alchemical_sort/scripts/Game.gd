#Game.gd (alchemical_sort)
extends Control

signal back_to_menu

# ---- difficulty configuration -----------------------------------------------
# 0=Easy  1=Medium  2=Hard  3=Zen (random each game)
const DIFFICULTY_KEYS := ["easy", "medium", "hard", "zen"]
const SAVE_PATH := "user://alch_sort_save.cfg"

const VIAL_SPACING := 14  # pixels between vials

# Alchemical color palette — placeholder, replace with art-matched colours.
const PALETTE: Array[Color] = [
	Color(0.90, 0.25, 0.25),   # 1 — crimson
	Color(0.25, 0.70, 0.30),   # 2 — verdant
	Color(0.25, 0.45, 0.90),   # 3 — azure
	Color(0.90, 0.75, 0.15),   # 4 — gold
	Color(0.70, 0.25, 0.85),   # 5 — violet
	Color(0.20, 0.80, 0.80),   # 6 — teal
	Color(0.95, 0.50, 0.15),   # 7 — ember
	Color(0.90, 0.90, 0.90),   # 8 — silver
	Color(0.40, 0.25, 0.10),   # 9 — umber
	Color(0.10, 0.40, 0.10),   # 10 — moss
]

# ---- difficulty state --------------------------------------------------------
var _difficulty: int    = 1   # set by set_difficulty() before prepare_board()
var _color_count: int   = 8
var _empty_vials: int   = 2
var _vials_per_row: int = 5

# ---- game state -------------------------------------------------------------
var _vials: Array = []           # Array[Vial]
var _palette: Array[Color] = []  # active slice of PALETTE
var _selected: Vial = null
var _move_count: int = 0
var _best_moves: int = 0
var _board_active: bool = false  # blocks ALL input (startup, reshuffle)
var _pouring: bool = false       # blocks pour-initiation only; selection still works
var _undo_snapshot: Array = []
var _undo_available: bool = false

@onready var _move_label:    Label   = $MoveLabel
@onready var _best_label:    Label   = $BestLabel
@onready var _undo_button:   Button  = $UndoButton
@onready var _win_panel:     Control = $WinPanel
@onready var _win_moves_lbl: Label   = $WinPanel/WinMovesLabel
@onready var _reshuffle_lbl: Label   = $ReshuffleLabel


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_on_back_pressed()


# Call before prepare_board(); sets difficulty parameters and loads save.
func set_difficulty(d: int) -> void:
	_difficulty = d
	# Zen picks a random difficulty each game.
	var actual := d if d != 3 else randi() % 3
	match actual:
		0:  # Easy
			_color_count   = 6
			_empty_vials   = 2
			_vials_per_row = 4
		1:  # Medium
			_color_count   = 8
			_empty_vials   = 2
			_vials_per_row = 5
		2:  # Hard
			_color_count   = 10
			_empty_vials   = 1
			_vials_per_row = 4
	_load_save()


# Called by Main.gd before the fade-in.
func prepare_board() -> void:
	_board_active = false
	_undo_available = false
	_undo_snapshot.clear()
	_win_panel.visible = false
	_clear_vials()
	_build_vials()
	_move_count = 0
	_selected = null
	_update_ui()


# Called by Main.gd after the fade-in completes.
func start_game() -> void:
	_board_active = false
	_undo_available = false
	_update_ui()

	for i in range(_vials.size()):
		var v: Vial = _vials[i]
		var final_y := v.position.y
		v.position.y = final_y - 180.0
		v.modulate.a = 0.0

		var delay := i * 0.065
		var tw := create_tween()
		tw.tween_interval(delay)
		tw.tween_callback(func():
			if not is_instance_valid(v):
				return
			var tw2 := create_tween()
			tw2.set_parallel(true)
			tw2.tween_property(v, "position:y", final_y, 0.42) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw2.tween_property(v, "modulate:a", 1.0, 0.28) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		)

	var total_wait := (_vials.size() - 1) * 0.065 + 0.50
	await get_tree().create_timer(total_wait).timeout
	_board_active = true


# ---- board construction -----------------------------------------------------

func _clear_vials() -> void:
	for v in _vials:
		if is_instance_valid(v):
			v.queue_free()
	_vials.clear()


func _build_vials() -> void:
	_palette = PALETTE.slice(0, _color_count)
	var assignments := _generate_shuffled_layers()
	var total := _color_count + _empty_vials

	var vial_w := Vial.VIAL_W
	var vial_h := Vial.VIAL_H
	var row_w  := _vials_per_row * vial_w + (_vials_per_row - 1) * VIAL_SPACING
	var origin_x := int((540.0 - row_w) / 2.0)
	var origin_y := 130

	for i in range(total):
		var col := i % _vials_per_row
		var row := floori(i / float(_vials_per_row))
		var vial := Vial.new()
		var layers: Array[int] = assignments[i] if i < assignments.size() else []
		vial.setup(layers, _palette)
		vial.position = Vector2(
			origin_x + col * (vial_w + VIAL_SPACING),
			origin_y + row * (vial_h + VIAL_SPACING + 16)
		)
		vial.tapped.connect(_on_vial_tapped)
		add_child(vial)
		_vials.append(vial)

	# Start hidden — start_game() will slide them in.
	for v: Vial in _vials:
		v.modulate.a = 0.0


func _generate_shuffled_layers() -> Array:
	var pool: Array[int] = []
	for color_id in range(1, _color_count + 1):
		for _j in range(Vial.MAX_LAYERS):
			pool.append(color_id)
	pool.shuffle()

	var result: Array = []
	var idx := 0
	for _i in range(_color_count):
		var layers: Array[int] = []
		for _j in range(Vial.MAX_LAYERS):
			layers.append(pool[idx])
			idx += 1
		result.append(layers)

	for _i in range(_empty_vials):
		result.append([0, 0, 0, 0] as Array[int])

	return result


# ---- tap logic --------------------------------------------------------------

func _on_vial_tapped(vial: Vial) -> void:
	if not _board_active:
		return

	if _selected == null:
		if vial.is_empty():
			return
		_selected = vial
		vial.show_selected(true)
		return

	if _selected == vial:
		vial.show_selected(false)
		_selected = null
		return

	# Don't start a new pour while one is already animating, but do move the
	# selection so the player can pre-aim the next pour.
	if not _pouring and _can_pour(_selected, vial):
		_do_pour(_selected, vial)
		return

	_selected.show_selected(false)
	if not vial.is_empty():
		_selected = vial
		vial.show_selected(true)
	else:
		_selected = null


func _can_pour(src: Vial, dst: Vial) -> bool:
	if src.is_empty():
		return false
	if dst.is_full():
		return false
	if dst.is_empty():
		return true
	return dst.top_color() == src.top_color()


func _do_pour(src: Vial, dst: Vial) -> void:
	_pouring = true
	src.show_selected(false)
	_selected = null

	var color_id := src.top_color()
	var amount   := mini(src.top_run_count(), dst.free_slots())
	var color    := _palette[color_id - 1] if color_id >= 1 and color_id <= _palette.size() \
		else Color.WHITE

	_save_undo_snapshot()

	await src.animate_pour_out(amount)

	var src_top := src.position + Vector2(Vial.VIAL_W * 0.5, 0.0)
	var dst_top := dst.position + Vector2(Vial.VIAL_W * 0.5, 0.0)
	await _animate_droplet(src_top, dst_top, color)

	await dst.animate_pour_in(color_id, amount)

	_move_count += 1
	_update_ui()

	if dst.is_pure() and dst.is_full():
		dst.celebrate()
		await get_tree().create_timer(0.28).timeout

	_pouring = false

	if _check_win():
		await get_tree().create_timer(0.35).timeout
		_on_win()
		return

	# Check for dead board after every pour.
	_check_dead_board()


# ---- dead-state detection ---------------------------------------------------

func _has_valid_move() -> bool:
	for i in range(_vials.size()):
		for j in range(_vials.size()):
			if i != j and _can_pour(_vials[i] as Vial, _vials[j] as Vial):
				return true
	return false


func _check_dead_board() -> void:
	if _has_valid_move():
		return

	_board_active = false
	if _selected:
		_selected.show_selected(false)
		_selected = null

	# Brief notice then reshuffle until a valid move exists.
	_reshuffle_lbl.modulate.a = 1.0
	_reshuffle_lbl.visible = true

	await get_tree().create_timer(0.9).timeout

	var attempts := 0
	while not _has_valid_move() and attempts < 30:
		_apply_reshuffle()
		attempts += 1

	var tw := create_tween()
	tw.tween_property(_reshuffle_lbl, "modulate:a", 0.0, 0.4)
	tw.tween_callback(func(): _reshuffle_lbl.visible = false)

	_board_active = true


func _apply_reshuffle() -> void:
	# Collect all non-zero layers across all vials.
	var pool: Array[int] = []
	for v: Vial in _vials:
		for layer in v.get_layers():
			if layer != 0:
				pool.append(layer)
	pool.shuffle()

	# Redistribute: fill non-empty vials from the pool, bottom to top.
	var idx := 0
	for v: Vial in _vials:
		if v.is_empty():
			continue
		var new_layers: Array[int] = [0, 0, 0, 0]
		for i in range(Vial.MAX_LAYERS):
			if idx < pool.size():
				new_layers[i] = pool[idx]
				idx += 1
		v.restore(new_layers)


# ---- droplet arc animation --------------------------------------------------

func _animate_droplet(from_pos: Vector2, to_pos: Vector2, color: Color) -> void:
	var dot := ColorRect.new()
	dot.size = Vector2(8.0, 8.0)
	dot.color = color
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot.z_index = 20
	add_child(dot)

	var ctrl := Vector2(
		(from_pos.x + to_pos.x) * 0.5,
		min(from_pos.y, to_pos.y) - 72.0
	)

	var tw := create_tween()
	tw.tween_method(func(t: float):
		if not is_instance_valid(dot):
			return
		var q := from_pos.lerp(ctrl, t)
		var r := ctrl.lerp(to_pos, t)
		dot.position = q.lerp(r, t) - Vector2(4.0, 4.0)
	, 0.0, 1.0, 0.28)
	await tw.finished

	if is_instance_valid(dot):
		dot.queue_free()


# ---- win condition ----------------------------------------------------------

func _check_win() -> bool:
	for vial: Vial in _vials:
		if vial.is_empty():
			continue
		if not (vial.is_full() and vial.is_pure()):
			return false
	return true


func _on_win() -> void:
	_board_active = false
	if _selected:
		_selected.show_selected(false)
		_selected = null
	_save_progress()
	_load_save()   # refresh best_moves display
	_win_moves_lbl.text = "in %d moves" % _move_count
	_win_panel.visible = true


func _on_new_game_pressed() -> void:
	_win_panel.visible = false
	prepare_board()
	start_game()


# ---- undo -------------------------------------------------------------------

func _save_undo_snapshot() -> void:
	_undo_snapshot.clear()
	for v: Vial in _vials:
		_undo_snapshot.append(v.snapshot())
	_undo_available = true
	_update_ui()


func _on_undo_pressed() -> void:
	if not _undo_available or not _board_active:
		return
	_undo_available = false
	if _selected:
		_selected.show_selected(false)
		_selected = null
	for i in range(_vials.size()):
		(_vials[i] as Vial).restore(_undo_snapshot[i])
	_move_count = maxi(0, _move_count - 1)
	_update_ui()


# ---- save / load ------------------------------------------------------------

func _save_key() -> String:
	return "best_moves_%s" % DIFFICULTY_KEYS[_difficulty]


func _load_save() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		_best_moves = cfg.get_value("progress", _save_key(), 0)
	else:
		_best_moves = 0


func _save_progress() -> void:
	if _move_count == 0:
		return
	if _best_moves == 0 or _move_count < _best_moves:
		_best_moves = _move_count
		var cfg := ConfigFile.new()
		cfg.load(SAVE_PATH)   # preserve other difficulty keys
		cfg.set_value("progress", _save_key(), _best_moves)
		cfg.save(SAVE_PATH)


# ---- UI ---------------------------------------------------------------------

func _update_ui() -> void:
	if _move_label:
		_move_label.text = "Moves: %d" % _move_count
	if _best_label:
		_best_label.text = "Best: %s" % ("–" if _best_moves == 0 else str(_best_moves))
	if _undo_button:
		_undo_button.modulate.a = 1.0 if _undo_available else 0.35


# ---- navigation -------------------------------------------------------------

func _on_back_pressed() -> void:
	if _selected:
		_selected.show_selected(false)
		_selected = null
	back_to_menu.emit()
