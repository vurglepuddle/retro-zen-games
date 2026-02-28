#Game.gd (alchemical_sort)
extends Control

signal back_to_menu

# ---- difficulty configuration -----------------------------------------------
# 0=Easy  1=Medium  2=Hard  3=Zen (random each game)  4=Mystery (dev/test only)
# Mystery fog-of-war fires as a 25 % random event on Medium, Hard, and Zen.
const DIFFICULTY_KEYS := ["easy", "medium", "hard", "zen", "mystery"]
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
var _difficulty:        int = 1  # set by set_difficulty(); persists across new games
var _actual_difficulty: int = 1  # resolved each game (Zen re-rolls; Mystery overrides)
var _color_count:       int = 8
var _empty_vials:       int = 2
var _vials_per_row:     int = 5

# ---- game state -------------------------------------------------------------
var _vials: Array = []           # Array[Vial]
var _palette: Array[Color] = []  # active slice of PALETTE
var _selected: Vial = null
var _move_count: int = 0
var _best_moves: int = 0
var _board_active: bool = false  # blocks ALL input (startup, reshuffle)
var _fog_mode: bool = false      # true for Mystery difficulty
var _pouring: bool = false       # true while pour animation plays
var _queued_vial: Vial = null    # last tap during a pour; processed when animation ends
var _undo_stack: Array = []      # stack of board snapshots (each = Array of vial snaps)
var _max_undo_depth: int = 1     # -1 = unlimited (Zen); otherwise Easy=3, Medium=2, Hard=1
var _droplet_mat: ShaderMaterial = null  # lazily built, shared across all pours

@onready var _move_label:    Label   = $MoveLabel
@onready var _best_label:    Label   = $BestLabel
@onready var _undo_button:   Button  = $UndoButton
@onready var _win_panel:     Control = $WinPanel
@onready var _win_moves_lbl: Label   = $WinPanel/WinMovesLabel
@onready var _reshuffle_lbl: Label   = $ReshuffleLabel
@onready var _reshuffle_btn: Button  = $ReshuffleButton
@onready var _mystery_label: Label   = $MysteryLabel


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_on_back_pressed()


# Call before prepare_board(); records the chosen difficulty and loads save.
# Layout parameters (_color_count etc.) are set per-game in _apply_difficulty_layout().
func set_difficulty(d: int) -> void:
	_difficulty = d
	match d:
		0: _max_undo_depth = -1   # Easy
		1: _max_undo_depth = -1   # Medium
		2: _max_undo_depth = -1   # Hard
		3: _max_undo_depth = -1  # Zen = unlimited
		4: _max_undo_depth = -1   # Mystery (dev button)
	_load_save()


# Called at the start of every prepare_board() so Zen re-rolls and Mystery can
# fire as a random event.  This is the only place that writes _color_count,
# _empty_vials, _vials_per_row, and _fog_mode.
func _apply_difficulty_layout() -> void:
	# Zen picks a random base difficulty each game (Easy/Medium/Hard).
	_actual_difficulty = _difficulty if _difficulty != 3 else randi() % 3

	# Mystery fog-of-war fires as a 25 % random event when the player chose
	# Medium, Hard, or Zen.  The explicit Mystery button (d=4) always fires.
	if _difficulty == 4:
		_fog_mode = true
	elif _difficulty == 0:
		_fog_mode = false  # Easy is never Mystery
	else:
		_fog_mode = (randi() % 4 == 0)

	if _fog_mode:
		# Mystery: fewer colors, fog of war
		_color_count   = 5
		_empty_vials   = 2
		_vials_per_row = 4
	else:
		match _actual_difficulty:
			0:  # Easy
				_color_count   = 6
				_empty_vials   = 2
				_vials_per_row = 4
			1:  # Medium
				_color_count   = 8
				_empty_vials   = 2
				_vials_per_row = 4
			2:  # Hard
				_color_count   = 12
				_empty_vials   = 2
				_vials_per_row = 5


# Called by Main.gd before the fade-in.
func prepare_board() -> void:
	_apply_difficulty_layout()  # re-roll Zen / Mystery every new game
	_board_active = false
	_undo_stack.clear()
	_win_panel.visible = false
	_reshuffle_lbl.visible = false
	_reshuffle_btn.visible = false
	_clear_vials()
	_build_vials()
	_move_count = 0
	_selected = null
	_update_ui()


# Called by Main.gd after the fade-in completes.
func start_game() -> void:
	_board_active = false
	_undo_stack.clear()
	_update_ui()

	if _fog_mode:
		_show_mystery_reveal()  # fire-and-forget; runs concurrently with vial drop-in

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


# ---- mystery reveal animation -----------------------------------------------

func _show_mystery_reveal() -> void:
	if not is_instance_valid(_mystery_label):
		return
	_mystery_label.scale    = Vector2(0.8, 0.8)
	_mystery_label.modulate = Color(1, 1, 1, 0)
	_mystery_label.visible  = true

	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_mystery_label, "modulate:a", 1.0, 0.4) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_mystery_label, "scale", Vector2.ONE, 0.4) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tw.finished

	await get_tree().create_timer(0.9).timeout

	var tw2 := create_tween()
	tw2.tween_property(_mystery_label, "modulate:a", 0.0, 0.4) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tw2.finished
	_mystery_label.visible = false


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

	# Derive layout dimensions from the bottle artwork (the true visual size of each vial).
	var _layout_tex := load("res://games/alchemical_sort/assets/bottle.png") as Texture2D
	var vial_w: int = _layout_tex.get_width()
	var vial_h: int = _layout_tex.get_height()
	var row_w  := _vials_per_row * vial_w + (_vials_per_row - 1) * VIAL_SPACING
	var origin_x := int((540.0 - row_w) / 2.0)
	var origin_y := 130

	for i in range(total):
		var col := i % _vials_per_row
		var row := floori(i / float(_vials_per_row))
		var vial := Vial.new()
		var layers: Array[int] = []
		layers.assign(assignments[i] if i < assignments.size() else [])
		vial.setup(layers, _palette)
		if _fog_mode:
			vial.enable_fog()
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
	# Randomly distribute all color layers across the vials.
	# This naturally creates mixed vials (different colors in the same bottle),
	# which is required for the puzzle to exist.  The two empty vials give enough
	# room that the vast majority of random boards are solvable; the dead-board
	# detector handles the rare edge cases by reshuffling in-place.
	var pool: Array[int] = []
	for color_id in range(1, _color_count + 1):
		for _j in range(Vial.MAX_LAYERS):
			pool.append(color_id)
	pool.shuffle()

	var result: Array = []
	var idx := 0
	for _i in range(_color_count):
		var layers: Array = []
		for _j in range(Vial.MAX_LAYERS):
			layers.append(pool[idx])
			idx += 1
		result.append(layers)

	for _i in range(_empty_vials):
		var empty: Array = []
		for _j in range(Vial.MAX_LAYERS):
			empty.append(0)
		result.append(empty)

	return result


# ---- tap logic --------------------------------------------------------------

func _on_vial_tapped(vial: Vial) -> void:
	if not _board_active:
		return
	if _pouring:
		# Don't change visible state mid-animation — just remember the last tap.
		# _do_pour() will process it when the animation finishes.
		_queued_vial = vial
		return
	_process_tap(vial)


func _process_tap(vial: Vial) -> void:
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

	if _can_pour(_selected, vial):
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
	src.reveal_top()  # expose newly uncovered layer in fog mode (no-op otherwise)

	var src_top := src.position + Vector2(src.VIAL_W * 0.5, 0.0)
	var dst_top := dst.position + Vector2(dst.VIAL_W * 0.5, 0.0)
	await _animate_droplet(src_top, dst_top, color)

	await dst.animate_pour_in(color_id, amount)

	_move_count += 1
	_update_ui()

	if dst.is_pure() and dst.is_full():
		dst.celebrate()
		await get_tree().create_timer(0.13).timeout

	_pouring = false

	if _check_win():
		_queued_vial = null
		await get_tree().create_timer(0.35).timeout
		_on_win()
		return

	# Process any tap queued during the animation, then check for dead board.
	var queued := _queued_vial
	_queued_vial = null
	if queued != null and is_instance_valid(queued):
		_process_tap(queued)
		if _pouring:  # queued tap triggered a new pour; it will run _check_dead_board
			return

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

	# Show the reshuffle button and let the user decide when to reshuffle.
	_reshuffle_lbl.visible = true
	_reshuffle_btn.visible = true


func _on_reshuffle_pressed() -> void:
	_reshuffle_lbl.visible = false
	_reshuffle_btn.visible = false

	var attempts := 0
	while not _has_valid_move() and attempts < 30:
		_apply_reshuffle()
		attempts += 1

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
		var new_layers: Array[int] = [0, 0, 0, 0, 0]
		for i in range(Vial.MAX_LAYERS):
			if idx < pool.size():
				new_layers[i] = pool[idx]
				idx += 1
		v.restore(new_layers)
		if _fog_mode:
			v.enable_fog()  # reset fog so only the new top run is visible


# ---- droplet arc animation --------------------------------------------------

func _animate_droplet(from_pos: Vector2, to_pos: Vector2, color: Color) -> void:
	# Build the glow shader once and reuse it for every pour.
	if _droplet_mat == null:
		var shader := Shader.new()
		shader.code = """
shader_type canvas_item;
void fragment() {
	vec2 c = UV - 0.5;
	float d = length(c) * 2.0;
	float core  = 1.0 - step(0.42, d);
	float halo  = (1.0 - smoothstep(0.42, 1.0, d)) * 0.55;
	float shine = 1.0 - step(0.18, length(c + vec2(0.13, 0.13)) * 2.0);
	vec3  col   = COLOR.rgb + vec3(0.45) * shine * core;
	COLOR = vec4(min(col, vec3(1.0)), COLOR.a * max(core, halo));
}
"""
		_droplet_mat = ShaderMaterial.new()
		_droplet_mat.shader = shader

	const HALF := 12.0  # half of the 24×24 dot
	var dot := ColorRect.new()
	dot.size = Vector2(HALF * 2.0, HALF * 2.0)
	dot.color = color
	dot.material = _droplet_mat
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot.z_index = 20
	# Set position before add_child so it never flashes at (0, 0).
	dot.position = from_pos - Vector2(HALF, HALF)
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
		dot.position = q.lerp(r, t) - Vector2(HALF, HALF)
	, 0.0, 1.0, 0.18)
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
	var snap: Array = []
	for v: Vial in _vials:
		snap.append(v.snapshot())
	_undo_stack.push_back(snap)
	# Trim to max depth (oldest entry at index 0 is removed first).
	if _max_undo_depth > 0 and _undo_stack.size() > _max_undo_depth:
		_undo_stack.pop_front()
	_update_ui()


func _on_undo_pressed() -> void:
	var in_dead_board := _reshuffle_btn.visible
	if _undo_stack.is_empty() or (not _board_active and not in_dead_board):
		return
	if in_dead_board:
		_reshuffle_lbl.visible = false
		_reshuffle_btn.visible = false
	if _selected:
		_selected.show_selected(false)
		_selected = null

	var snap: Array = _undo_stack.pop_back()

	# Find which vial received the pour (has more layers now) and which sent it.
	var src_vial: Vial = null
	var dst_vial: Vial = null
	var pour_color_id: int = 0
	var pour_amount: int = 0
	for i in range(_vials.size()):
		var v     := _vials[i] as Vial
		var curr  := v.get_layers()
		var prev  := snap[i] as Array
		var curr_n := 0
		var prev_n := 0
		for l in curr: if l != 0: curr_n += 1
		for l in prev: if l != 0: prev_n += 1
		if curr_n > prev_n and dst_vial == null:
			dst_vial      = v
			pour_amount   = curr_n - prev_n
			pour_color_id = curr[curr_n - 1]   # top layer = what was poured in
		elif curr_n < prev_n and src_vial == null:
			src_vial = v

	_board_active = false
	_pouring      = true

	if src_vial != null and dst_vial != null and pour_amount > 0:
		await dst_vial.animate_pour_out(pour_amount)
		var color   := _palette[pour_color_id - 1] if pour_color_id >= 1 and pour_color_id <= _palette.size() else Color.WHITE
		var dst_top := dst_vial.position + Vector2(dst_vial.VIAL_W * 0.5, 0.0)
		var src_top := src_vial.position + Vector2(src_vial.VIAL_W * 0.5, 0.0)
		await _animate_droplet(dst_top, src_top, color)   # arc runs dst → src (reversed)

	for i in range(_vials.size()):
		(_vials[i] as Vial).restore(snap[i])
	_move_count   = maxi(0, _move_count - 1)
	_update_ui()
	_pouring      = false
	_board_active = true


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
		var has_undo := not _undo_stack.is_empty()
		_undo_button.modulate.a = 1.0 if has_undo else 0.35
		if has_undo and _max_undo_depth != -1:
			_undo_button.text = "UNDO ×%d" % _undo_stack.size()
		else:
			_undo_button.text = "UNDO"


# ---- navigation -------------------------------------------------------------

func _on_back_pressed() -> void:
	if _selected:
		_selected.show_selected(false)
		_selected = null
	back_to_menu.emit()
