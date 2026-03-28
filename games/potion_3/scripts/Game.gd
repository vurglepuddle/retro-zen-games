# Game.gd (potion_3) — Triple-match goods-sort board.
# Grid of PotionCell shelves; each shelf holds 3 item slots + z-depth layers.
# Match 3 identical items in one cell to eliminate them. Clear the board to win.

extends Control

signal back_to_menu

# ---- constants ---------------------------------------------------------------
const SAVE_PATH := "user://potion_3_save.cfg"
const DIFFICULTY_KEYS := ["easy", "medium", "hard", "zen"]
const ITEMS_BASE_PATH := "res://games/potion_3/assets/items/"

const COL_SPACING     := 0    # padding is built into CELL_W (9px each side)
const ROW_SPACING     := 9    # gap between rows: 3×270 + 2×9 = 828px board
const DRAG_THRESHOLD  := 10.0
const SCROLL_INTERVAL := 2.5  # seconds between conveyor ticks on scrolling rows
const SCROLL_ROW_MAX   := 1   # max scrolling rows per game; bump to 2 to re-enable dizzy mode
const SCROLL_EXTRA_CELLS := 1 # buffer cells off-screen right per scrolling row (seamless wrap)

const DISP_SCROLL_CELLS    := 6     # visible cells in the hazard belt; 6×108=648 > 540 → rightmost is off-screen → invisible wrap
const DISP_SCROLL_INTERVAL := 2.0   # belt scrolls slightly faster than main conveyor

const STREAK_RESET_DELAY := 4.0   # seconds without a match before combo resets to note_1
const COMBO_VOL_MIN_DB   := -10.0 # volume for note_1 (quiet start)
const COMBO_VOL_MAX_DB   := -3.0  # volume for note_7 (not too loud)

# ---- difficulty state --------------------------------------------------------
var _difficulty:        int = 0
var _actual_difficulty: int = 0
var _rows:              int = 3
var _cols_per_row:      int = 3
var _max_depth:         int = 3
var _item_type_count:   int = 12
var _empty_cell_count:  int = 2

# ---- game state --------------------------------------------------------------
var _game_generation: int  = 0     # incremented on every prepare_board(); stale scroll lambdas bail out
var _cells: Array          = []    # 2D: [row][col] → PotionCell
var _selected_cell: PotionCell = null
var _selected_slot: int    = -1
var _board_active: bool    = false
var _animating: bool       = false
var _move_count: int       = 0
var _best_moves: int       = 0
var _item_textures: Dictionary = {}   # item_id → Texture2D
var _undo_stack: Array     = []

# ---- match sfx --------------------------------------------------------------
var _match_streak:    int   = 0           # consecutive matches; drives combo note index
var _streak_timer_id: int   = 0           # incremented on each new match to cancel old timer
var _item_set_map:  Dictionary = {}       # item_id → set_num (for per-set sfx)
var _set_sfx:       Dictionary = {}       # set_num → AudioStreamPlayer (null = no sfx yet)
var _combo_players: Array      = []       # [0..6] → AudioStreamPlayer for note_1..note_7

# ---- special cells -----------------------------------------------------------
var _scrolling_rows:   Array[int]        = []    # row indices that scroll like conveyors
var _buffer_cells:     Array[PotionCell] = []   # off-screen buffer cells for scroll rows
var _dispenser_cells:  Array[PotionCell] = []   # 1-tall cells below the main board
var _dispenser_count:  int  = 0                 # how many dispensers to create this game
var _special_scroll:   bool = false             # cascading special roll: scrolling row?
var _special_lock:     bool = false             # cascading special roll: locked cells?
var _board_origin_x:   int  = 0                 # left x of the board grid (for scroll math)
var _hazard_disp_scroll: bool      = false
var _disp_scroll_cells: Array[PotionCell] = []
var _disp_scroll_buffer: PotionCell = null
var _scroll_tweens: Array[Tween]   = []   # killed in _clear_cells() to stop tween_method lambdas

# ---- drag state --------------------------------------------------------------
var _drag_active: bool     = false
var _drag_sprite: TextureRect = null
var _press_pos: Vector2    = Vector2.ZERO
var _pressing: bool        = false

# ---- UI nodes ----------------------------------------------------------------
@onready var _move_label:    Label   = $MoveLabel
@onready var _best_label:    Label   = $BestLabel
@onready var _undo_button:   Button  = $UndoButton
@onready var _back_button:   Button  = $BackButton
@onready var _win_panel:     Control = $WinPanel
@onready var _win_moves_lbl: Label   = $WinPanel/WinMovesLabel
@onready var _reshuffle_lbl: Label   = $ReshuffleLabel
@onready var _reshuffle_btn: Button  = $ReshuffleButton
@onready var _sfx_put_down: AudioStreamPlayer = $SfxPutDown


func _ready() -> void:
	_setup_combo_players()


func _setup_combo_players() -> void:
	var base := "res://games/gem_match/assets/sfx/combo/"
	for i in range(1, 8):
		var p := AudioStreamPlayer.new()
		var path := base + "note_%d.mp3" % i
		if ResourceLoader.exists(path):
			p.stream = load(path) as AudioStream
		add_child(p)
		_combo_players.append(p)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_on_back_pressed()


# ===========================================================================
#  Difficulty / Setup
# ===========================================================================

func set_difficulty(d: int) -> void:
	_difficulty = d
	_load_save()


func _apply_difficulty_layout() -> void:
	_actual_difficulty = _difficulty if _difficulty != 3 else randi() % 3
	match _actual_difficulty:
		0:  # Easy   — 3 cols × 3 rows =  9 cells; no special cells
			_cols_per_row = 3; _rows = 3; _max_depth = 3; _item_type_count = 12; _empty_cell_count = 2
		1:  # Medium — 4 cols × 3 rows = 12 cells
			_cols_per_row = 4; _rows = 3; _max_depth = 4; _item_type_count = 22; _empty_cell_count = 2
		2:  # Hard   — 5 cols × 3 rows = 15 cells; board 540×828 px
			_cols_per_row = 5; _rows = 3; _max_depth = 5; _item_type_count = 32; _empty_cell_count = 2

	# Cascading special-cell roll.
	# Each type that wins reduces the probability of the next one appearing,
	# so "nothing" and "one tweak" are common; "all three at once" is rare.
	_dispenser_count    = 0
	_special_scroll     = false
	_special_lock       = false
	_hazard_disp_scroll = false

	if _actual_difficulty == 0:
		return   # Easy never has specials.

	var is_hard := _actual_difficulty == 2
	# Shuffle the order so no type always gets first pick.
	var types: Array = ["dispenser", "scroll", "lock"]
	if is_hard:
		types.append("hazard_disp_scroll")
	types.shuffle()
	var prob := 0.55 if is_hard else 0.38   # base probability for the first special
	for sp in types:
		if randf() < prob:
			match sp:
				"dispenser":
					_dispenser_count = 1
					var add_prob := 0.60 if is_hard else 0.45
					while _dispenser_count < 4:
						if _dispenser_count >= 2:
							add_prob *= 0.45
						if randf() < add_prob:
							_dispenser_count += 1
						else:
							break
				"scroll":
					# Pre-decide rows now so _generate_board_data() can allocate
					# buffer cell items before the grid exists.
					var row_order: Array = []
					for r in range(_rows): row_order.append(r)
					row_order.shuffle()
					for r in row_order:
						if _scrolling_rows.size() >= SCROLL_ROW_MAX:
							break
						_scrolling_rows.append(r)
					_special_scroll = not _scrolling_rows.is_empty()
				"lock": _special_lock = true
				"hazard_disp_scroll": _hazard_disp_scroll = true
			prob *= 0.42   # each extra special is ~58% less likely than the last


func prepare_board() -> void:
	_board_active = false
	_animating = false
	_match_streak = 0
	_streak_timer_id += 1   # invalidate any pending streak-reset timer from last game
	_game_generation += 1   # invalidate any pending scroll lambdas from last game
	_undo_stack.clear()
	_win_panel.visible = false
	_reshuffle_lbl.visible = false
	_reshuffle_btn.visible = false
	_selected_cell = null
	_selected_slot = -1
	_move_count = 0
	_cancel_drag()
	_clear_cells()          # clears _scrolling_rows first
	_apply_difficulty_layout()  # then populates _scrolling_rows so _build_cells can use them
	_load_textures()
	_build_cells()
	# Pre-position cells for the drop-in animation so the fade-in doesn't
	# reveal the board already in its final state before start_game() runs.
	for row in _cells:
		for cell in row:
			var c: PotionCell = cell
			if c in _buffer_cells:
				continue   # buffer cells stay invisible at their off-screen position
			c.position.y -= 160.0
			c.modulate.a = 0.0
	for dc in _dispenser_cells:
		var c := dc as PotionCell
		c.position.y -= 160.0
		c.modulate.a = 0.0
	for dc in _disp_scroll_cells:
		if dc == _disp_scroll_buffer:
			continue   # buffer stays at off-screen position
		var c := dc as PotionCell
		c.position.y -= 160.0
		c.modulate.a = 0.0
	_update_ui()


func start_game() -> void:
	# Snapshot the generation so this coroutine can detect if prepare_board()
	# was called again while it was suspended (e.g. rapid New Game presses).
	# Any await that resumes after a new prepare_board() exits immediately,
	# preventing two concurrent start_game() runs from both arming scroll timers.
	var gen := _game_generation
	_board_active = false
	_undo_stack.clear()
	_update_ui()

	# Staggered drop-in animation.
	# Cells are already offset -160 and invisible from prepare_board().
	# Buffer cells are excluded — they stay invisible at their off-screen position
	# until _advance_scroll fades them in on the first scroll tick.
	var idx := 0
	for row in _cells:
		for cell in row:
			var c: PotionCell = cell
			if c in _buffer_cells:
				continue
			var final_y := c.position.y + 160.0  # restore to actual target
			var delay := idx * 0.05
			var tw := create_tween()
			tw.tween_interval(delay)
			tw.tween_callback(func():
				if not is_instance_valid(c) or not is_instance_valid(self):
					return
				var tw2 := create_tween()
				tw2.set_parallel(true)
				tw2.tween_property(c, "position:y", final_y, 0.38) \
					.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
				tw2.tween_property(c, "modulate:a", 1.0, 0.25) \
					.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			)
			idx += 1

	# Dispenser cells animate in after the main grid.
	for dc in _dispenser_cells:
		var c := dc as PotionCell
		var final_y := c.position.y + 160.0
		var delay := idx * 0.05
		var tw := create_tween()
		tw.tween_interval(delay)
		tw.tween_callback(func():
			if not is_instance_valid(c) or not is_instance_valid(self):
				return
			var tw2 := create_tween()
			tw2.set_parallel(true)
			tw2.tween_property(c, "position:y", final_y, 0.38) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw2.tween_property(c, "modulate:a", 1.0, 0.25) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		)
		idx += 1

	# Hazard belt cells animate in last (buffer stays off-screen).
	for dc in _disp_scroll_cells:
		if dc == _disp_scroll_buffer:
			continue
		var c := dc as PotionCell
		var final_y := c.position.y + 160.0
		var delay := idx * 0.05
		var tw := create_tween()
		tw.tween_interval(delay)
		tw.tween_callback(func():
			if not is_instance_valid(c) or not is_instance_valid(self):
				return
			var tw2 := create_tween()
			tw2.set_parallel(true)
			tw2.tween_property(c, "position:y", final_y, 0.38) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw2.tween_property(c, "modulate:a", 1.0, 0.25) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		)
		idx += 1

	var total_wait := (idx - 1) * 0.05 + 0.45
	await get_tree().create_timer(total_wait).timeout
	if not is_instance_valid(self) or _game_generation != gen:
		return

	# Auto-clear any 3-matches that the generator placed in a single cell.
	_animating = true
	for row in _cells:
		for cell in row:
			var c := cell as PotionCell
			if c.check_match():
				await _process_match(c)
				if not is_instance_valid(self) or _game_generation != gen:
					return
	_animating = false
	_board_active = true

	# Kick off the first scroll tick for each scrolling row.
	# Guard both self-freed (back navigation) and stale generation (rapid New Game).
	for r in _scrolling_rows:
		get_tree().create_timer(SCROLL_INTERVAL).timeout.connect(
			func():
				if is_instance_valid(self) and _game_generation == gen:
					_advance_scroll(r),
			CONNECT_ONE_SHOT)

	# Kick off the hazard dispenser belt scroll (rightward, opposite direction).
	if _hazard_disp_scroll:
		get_tree().create_timer(DISP_SCROLL_INTERVAL).timeout.connect(
			func():
				if is_instance_valid(self) and _game_generation == gen:
					_advance_disp_scroll(),
			CONNECT_ONE_SHOT)


# ===========================================================================
#  Board Generation
# ===========================================================================

func _load_textures() -> void:
	if not _item_textures.is_empty():
		return  # already cached
	# DirAccess can't list inside APKs on Android, so probe by number instead.
	# Items are named item1.png…itemN.png; gaps are allowed (50 consecutive
	# misses ends the search for that set).
	var uid := 1
	for set_num in range(1, 20):  # generous upper bound; stops at first missing set
		var set_path := ITEMS_BASE_PATH + "set%d/" % set_num
		var found_in_set := false
		var misses := 0
		for i in range(1, 1000):
			var path := set_path + "item%d.png" % i
			if ResourceLoader.exists(path):
				_item_textures[uid] = load(path) as Texture2D
				_item_set_map[uid] = set_num
				uid += 1
				found_in_set = true
				misses = 0
			else:
				misses += 1
				if misses >= 50:
					break
		if not found_in_set:
			break  # set folder doesn't exist → no more sets
		# Per-set match sfx: load set{N}/match.mp3 if present.
		# Assign all_same placeholder for now; user replaces with material-specific sounds.
		var sfx_path := set_path + "match.mp3"
		if ResourceLoader.exists(sfx_path):
			var p := AudioStreamPlayer.new()
			p.stream = load(sfx_path) as AudioStream
			add_child(p)
			_set_sfx[set_num] = p


func _clear_cells() -> void:
	# Kill all active scroll tweens first — their tween_method lambdas capture cell
	# nodes, and those nodes are about to be queue_free()d. Without this, Godot fires
	# "lambda capture at index 0 was freed" errors for every remaining tween frame.
	for tw in _scroll_tweens:
		if is_instance_valid(tw):
			tw.kill()
	_scroll_tweens.clear()
	for row in _cells:
		for cell in row:
			(cell as PotionCell).queue_free()
	_cells.clear()
	_scrolling_rows.clear()
	_buffer_cells.clear()   # queue_free already handled above (they're in _cells)
	for dc in _dispenser_cells:
		(dc as PotionCell).queue_free()
	_dispenser_cells.clear()
	for dc in _disp_scroll_cells:
		(dc as PotionCell).queue_free()
	_disp_scroll_cells.clear()
	_disp_scroll_buffer = null


func _build_cells() -> void:
	var board_data := _generate_board_data()
	var items: Array = board_data.items

	var board_w: int = _cols_per_row * PotionCell.CELL_W   # COL_SPACING=0; padding inside CELL_W
	var board_h: int = _rows * PotionCell.CELL_H + (_rows - 1) * ROW_SPACING
	var origin_x := int((540.0 - board_w) / 2.0)
	var vp_h := get_viewport_rect().size.y
	var origin_y := int(90.0 + (vp_h - 180.0 - board_h) / 2.0)
	_board_origin_x = origin_x

	var cell_idx := 0
	for row in range(_rows):
		var row_arr: Array = []
		for col in range(_cols_per_row):
			var cell_layers: Array = items[cell_idx]
			var top_layer: Array[int] = [0, 0, 0]
			var z_stack: Array = []
			if cell_layers.size() > 0:
				top_layer = [cell_layers[0][0], cell_layers[0][1], cell_layers[0][2]]
				for li in range(1, cell_layers.size()):
					z_stack.append(cell_layers[li])

			var cell := PotionCell.new()
			cell.setup(top_layer, z_stack, _item_textures)
			cell.position = Vector2(
				origin_x + col * PotionCell.CELL_W,
				origin_y + row * (PotionCell.CELL_H + ROW_SPACING)
			)
			add_child(cell)
			row_arr.append(cell)
			cell_idx += 1
		_cells.append(row_arr)

	# Add off-screen buffer cells for scrolling rows (enable seamless wrap).
	var extra_idx := _cols_per_row * _rows
	for row_idx in _scrolling_rows:
		for _bi in range(SCROLL_EXTRA_CELLS):
			var cell_layers: Array = items[extra_idx]
			var top_layer: Array[int] = [0, 0, 0]
			var z_stack: Array = []
			if cell_layers.size() > 0:
				top_layer = [cell_layers[0][0] as int, cell_layers[0][1] as int, cell_layers[0][2] as int]
				for li in range(1, cell_layers.size()):
					z_stack.append(cell_layers[li])
			var buf_cell := PotionCell.new()
			buf_cell.setup(top_layer, z_stack, _item_textures)
			buf_cell.position = Vector2(
				float(_board_origin_x + _cols_per_row * PotionCell.CELL_W),
				origin_y + row_idx * (PotionCell.CELL_H + ROW_SPACING)
			)
			buf_cell.modulate.a = 0.0   # invisible until its first scroll-in
			add_child(buf_cell)
			_cells[row_idx].append(buf_cell)
			_buffer_cells.append(buf_cell)   # tracked separately to skip drop-in
			extra_idx += 1

	_generate_special_cells()
	_create_dispenser_cells(board_data.dispenser_groups)
	if _hazard_disp_scroll:
		_create_disp_scroll_belt(board_data.disp_scroll_groups)


func _generate_board_data() -> Dictionary:
	var grid_cells  := _cols_per_row * _rows
	var total_cells := grid_cells + _scrolling_rows.size() * SCROLL_EXTRA_CELLS

	# 1. Choose item types.
	var available: Array = _item_textures.keys()
	available.shuffle()
	var chosen := available.slice(0, _item_type_count)

	# 2. Build the full pool (each type ×3) and shuffle it.
	var pool: Array[int] = []
	for t in chosen:
		var tid := t as int
		pool.append(tid); pool.append(tid); pool.append(tid)
	pool.shuffle()

	# 2b. Pull items for dispensers from the front of the shuffled pool (mixed types).
	# Each dispenser gets 3 random items whose siblings remain in the grid,
	# so the player must pull and hunt for the matching pair on the board.
	var dispenser_groups: Array = []
	for _di in range(_dispenser_count):
		var grp: Array[int] = []
		for _si in range(3):
			grp.append(pool.pop_front() as int)
		dispenser_groups.append(grp)

	# 2c. Pull items for the hazard dispenser scroll belt (Hard only).
	var disp_scroll_groups: Array = []
	if _hazard_disp_scroll:
		for _dsi in range(DISP_SCROLL_CELLS + 1):   # +1 for off-screen buffer cell
			var grp2: Array[int] = []
			for _si in range(3):
				grp2.append(pool.pop_front() as int)
			disp_scroll_groups.append(grp2)

	# 3. Assign cell depths.
	# Target 40% more layers than item_type_count so the flat slot list has more
	# slots than items — the surplus becomes randomly scattered empty slots,
	# giving natural 1-3 item layers WITHOUT losing any items from the pool.
	var depths: Array[int] = []
	for i in range(total_cells):
		depths.append(0)

	var layers_to_place := int(_item_type_count * 1.4)
	var cell_indices: Array[int] = []
	for i in range(total_cells):
		cell_indices.append(i)
	cell_indices.shuffle()

	var filled_target := total_cells - _empty_cell_count
	var filled_count := 0
	for ci in cell_indices:
		if filled_count >= filled_target or layers_to_place <= 0:
			break
		depths[ci] = 1
		layers_to_place -= 1
		filled_count += 1

	var attempts := 0
	while layers_to_place > 0 and attempts < 2000:
		var ci := cell_indices[randi() % cell_indices.size()]
		if depths[ci] > 0 and depths[ci] < _max_depth:
			depths[ci] += 1
			layers_to_place -= 1
		attempts += 1

	if layers_to_place > 0:
		for ci in range(total_cells):
			while layers_to_place > 0 and depths[ci] < _max_depth:
				if depths[ci] == 0:
					depths[ci] = 1
				else:
					depths[ci] += 1
				layers_to_place -= 1

	# 4. Build a flat list of every slot across all layers, shuffle it, then
	# assign items one-by-one. Surplus slots stay 0. This guarantees every
	# item type is placed exactly 3 times while layers look naturally sparse.
	var all_slots: Array = []   # each entry: [cell_i, layer_j, slot_k]
	for ci in range(total_cells):
		for li in range(depths[ci]):
			for si in range(PotionCell.SLOTS):
				all_slots.append([ci, li, si])
	all_slots.shuffle()

	# Build empty cell_items structure.
	var cell_items: Array = []
	for ci in range(total_cells):
		var layers: Array = []
		for _li in range(depths[ci]):
			layers.append([0, 0, 0])
		cell_items.append(layers)

	# Place every pool item into a random slot — no item is ever lost.
	for i in range(pool.size()):
		var s: Array = all_slots[i]
		cell_items[s[0]][s[1]][s[2]] = pool[i]

	return { depths = depths, items = cell_items, dispenser_groups = dispenser_groups, disp_scroll_groups = disp_scroll_groups }


# ===========================================================================
#  Input — Tap to Select / Move
# ===========================================================================

func _on_slot_tapped(cell: PotionCell, slot_idx: int) -> void:
	if not _board_active or _animating:
		return

	# Locked cells are completely inert — no interaction.
	if cell.is_locked():
		return

	var item_id := cell.get_item(slot_idx)

	# Case 1: nothing selected — select this item.
	if _selected_cell == null:
		if item_id == 0:
			return
		_selected_cell = cell
		_selected_slot = slot_idx
		cell.show_slot_highlight(slot_idx, true)
		return

	# Case 2: same slot — deselect.
	if _selected_cell == cell and _selected_slot == slot_idx:
		cell.show_slot_highlight(slot_idx, false)
		_selected_cell = null
		_selected_slot = -1
		return

	# Case 3: tapped empty slot — move item there.
	if item_id == 0:
		# Dispenser cells: you can take items OUT but not put them IN.
		if cell.is_dispenser():
			_selected_cell.show_slot_highlight(_selected_slot, false)
			_selected_cell = null
			_selected_slot = -1
			return
		await _try_move(_selected_cell, _selected_slot, cell, slot_idx)
		return

	# Case 4: tapped a different non-empty slot — switch selection.
	_selected_cell.show_slot_highlight(_selected_slot, false)
	_selected_cell = cell
	_selected_slot = slot_idx
	cell.show_slot_highlight(slot_idx, true)


# ===========================================================================
#  Drag Input
# ===========================================================================

func _input(event: InputEvent) -> void:
	if not visible or _animating or _win_panel.visible:
		return

	# In Godot 4, _input() positions are already in canvas/viewport coordinates
	# (the engine applies the stretch transform before dispatching). Do NOT apply
	# get_canvas_transform() here — that would double-transform and break Android.
	var pos := Vector2.ZERO
	var is_press := false
	var is_release := false
	var is_motion := false

	var is_mobile := OS.has_feature("mobile")

	if event is InputEventScreenTouch:
		pos = event.position
		if event.pressed:
			is_press = true
		else:
			is_release = true
	elif event is InputEventScreenDrag and _pressing:
		pos = event.position
		is_motion = true
	elif not is_mobile and event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT:
		pos = event.position
		if event.pressed:
			is_press = true
		else:
			is_release = true
	elif not is_mobile and event is InputEventMouseMotion and _pressing:
		pos = event.position
		is_motion = true
	else:
		return

	if is_press:
		_pressing = true
		_press_pos = pos
		if _board_active:
			# On mobile use forgiving nearest-item pickup radius; exact hit as fallback.
			var hit: Variant
			if is_mobile:
				hit = _find_pickup_slot_near(pos, 44.0)
			if hit == null:
				hit = _find_cell_slot_at(pos)
			if hit != null:
				_on_slot_tapped(hit[0] as PotionCell, hit[1] as int)

	var drag_threshold := DRAG_THRESHOLD * (2.0 if OS.has_feature("mobile") else 1.0)
	if is_motion and _pressing and _selected_cell != null and _selected_slot >= 0:
		if not _drag_active:
			if pos.distance_to(_press_pos) > drag_threshold:
				_start_drag(pos)
		else:
			_update_drag(pos)

	if is_release:
		if _drag_active:
			_end_drag(pos)
		_pressing = false


func _start_drag(pos: Vector2) -> void:
	if not _board_active:
		return
	var item_id := _selected_cell.get_item(_selected_slot)
	if item_id == 0:
		return
	_drag_active = true

	var half := Vector2(PotionCell.ITEM_SIZE * 0.5, PotionCell.ITEM_SIZE * 0.5)
	_drag_sprite = TextureRect.new()
	_drag_sprite.texture = _item_textures.get(item_id)
	_drag_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_drag_sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_drag_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_drag_sprite.size = Vector2(PotionCell.ITEM_SIZE, PotionCell.ITEM_SIZE)
	_drag_sprite.pivot_offset = half
	if _selected_cell.is_slot_mystery(_selected_slot):
		_drag_sprite.material = PotionCell._get_mystery_mat()
	#_drag_sprite.rotation = -PI / 4.0  # uncomment for 45° CCW tilt
	_drag_sprite.z_index = 50
	_drag_sprite.position = pos - half
	add_child(_drag_sprite)

	# Hide the original slot visual (item data stays until drop).
	_selected_cell.set_slot_visible(_selected_slot, false)


func _update_drag(pos: Vector2) -> void:
	if _drag_sprite:
		var half := Vector2(PotionCell.ITEM_SIZE * 0.5, PotionCell.ITEM_SIZE * 0.5)
		_drag_sprite.position = pos - half


func _end_drag(pos: Vector2) -> void:
	_drag_active = false
	if _drag_sprite:
		_drag_sprite.queue_free()
		_drag_sprite = null

	if _selected_cell == null or _selected_slot < 0:
		return

	# Only snap to another slot if the item was dragged meaningfully away from
	# its origin. If the drop lands closer to home than this threshold, treat
	# it as "peek and return" and put the item back.
	var origin_center := _selected_cell.get_global_rect().position + _selected_cell.get_slot_center(_selected_slot)
	var drag_dist := pos.distance_to(origin_center)
	var snap_threshold := PotionCell.ITEM_SIZE * 0.5

	var to_cell: PotionCell = null
	var to_slot: int = -1

	var exact: Variant = _find_cell_slot_at(pos)

	# Same-cell rearrangement: always honour regardless of drag distance.
	# The user is intentionally organising items within one shelf.
	if exact != null:
		var hit_cell := exact[0] as PotionCell
		var hit_slot := exact[1] as int
		if hit_cell == _selected_cell and hit_slot != _selected_slot \
				and hit_cell.get_item(hit_slot) == 0 \
				and not hit_cell.is_locked():
			to_cell = hit_cell
			to_slot = hit_slot

	# Cross-cell move: only snap if dragged far enough from origin.
	if to_cell == null and drag_dist >= snap_threshold:
		# 1. Try the exact hit first (fast path).
		if exact != null:
			var ec := exact[0] as PotionCell
			if not ec.is_locked() and not ec.is_dispenser() \
					and ec.get_item(exact[1] as int) == 0:
				to_cell = ec
				to_slot = exact[1] as int
		# 2. Always fall back to nearest-empty radius search when the exact hit
		#    was invalid (locked/dispenser/occupied) or missed entirely.
		#    This is the key fix for Android where the finger may land slightly off.
		if to_cell == null:
			var best_dist := PotionCell.CELL_W * 1.5
			for row in _cells:
				for cell in row:
					var c := cell as PotionCell
					if c.is_locked() or c.is_dispenser():
						continue
					for s in range(PotionCell.SLOTS):
						if c.get_item(s) == 0:
							var slot_center := c.get_global_rect().position + c.get_slot_center(s)
							var d := pos.distance_to(slot_center)
							if d < best_dist:
								best_dist = d
								to_cell = c
								to_slot = s

	if to_cell != null and to_slot >= 0:
		if to_cell != _selected_cell or to_slot != _selected_slot:
			_selected_cell.set_slot_visible(_selected_slot, true)
			await _try_move(_selected_cell, _selected_slot, to_cell, to_slot, false)
			return

	# No valid target — restore visual and deselect.
	_selected_cell.set_slot_visible(_selected_slot, true)
	_selected_cell.show_slot_highlight(_selected_slot, false)
	_selected_cell = null
	_selected_slot = -1


func _cancel_drag() -> void:
	if _drag_sprite:
		_drag_sprite.queue_free()
		_drag_sprite = null
	_drag_active = false
	_pressing = false


func _find_cell_slot_at(pos: Vector2) -> Variant:
	for row in _cells:
		for cell in row:
			var c := cell as PotionCell
			var rect := c.get_global_rect()
			if rect.has_point(pos):
				var local_y := pos.y - rect.position.y
				var slot_idx := clampi(int(local_y / float(PotionCell.ITEM_SIZE)), 0, PotionCell.SLOTS - 1)
				return [c, slot_idx]
	# Also check dispenser cells (they always map to slot 0).
	for dc in _dispenser_cells:
		var c := dc as PotionCell
		if c.get_global_rect().has_point(pos):
			return [c, 0]
	for dc in _disp_scroll_cells:
		var c := dc as PotionCell
		if c.get_global_rect().has_point(pos):
			return [c, 0]
	return null


func _find_pickup_slot_near(pos: Vector2, radius: float) -> Variant:
	## Returns the nearest non-empty slot within radius, or null.
	var best_cell: PotionCell = null
	var best_slot := -1
	var best_dist := radius
	for row in _cells:
		for cell in row:
			var c := cell as PotionCell
			if c.is_locked():
				continue   # locked cells can't be interacted with
			for s in range(PotionCell.SLOTS):
				if c.get_item(s) == 0:
					continue
				var center := c.get_global_rect().position + c.get_slot_center(s)
				var d := pos.distance_to(center)
				if d < best_dist:
					best_dist = d
					best_cell = c
					best_slot = s
	# Also check dispenser cells (slot 0 only).
	for dc in _dispenser_cells:
		var c := dc as PotionCell
		if c.get_item(0) == 0:
			continue
		var center := c.get_global_rect().position + c.get_slot_center(0)
		var d := pos.distance_to(center)
		if d < best_dist:
			best_dist = d
			best_cell = c
			best_slot = 0
	for dc in _disp_scroll_cells:
		var c := dc as PotionCell
		if c.get_item(0) == 0:
			continue
		var center := c.get_global_rect().position + c.get_slot_center(0)
		var d := pos.distance_to(center)
		if d < best_dist:
			best_dist = d
			best_cell = c
			best_slot = 0
	if best_cell != null:
		return [best_cell, best_slot]
	return null


# ===========================================================================
#  Move + Match Logic
# ===========================================================================

func _try_move(from_cell: PotionCell, from_slot: int, to_cell: PotionCell, to_slot: int, animate_fly := true) -> void:
	_save_undo_snapshot()
	_animating = true
	_board_active = false

	var item_id    := from_cell.get_item(from_slot)
	var is_mystery := from_cell.is_slot_mystery(from_slot)
	from_cell.show_slot_highlight(from_slot, false)
	_selected_cell = null
	_selected_slot = -1

	if animate_fly:
		await _animate_item_move(from_cell, from_slot, to_cell, to_slot, item_id)

	from_cell.set_slot_mystery(from_slot, false)
	from_cell.remove_item(from_slot)
	to_cell.set_item(to_slot, item_id)
	if is_mystery:
		to_cell.set_slot_mystery(to_slot, true)
	_sfx_put_down.play()

	_move_count += 1
	_update_ui()

	# Check for match in destination cell.
	if to_cell.check_match():
		await _process_match(to_cell)

	# If source cell is now empty, keep revealing until we surface a layer
	# that has items (skips any residual all-zero layers defensively).
	while not from_cell.has_items() and from_cell.layers_remaining() > 0:
		from_cell.reveal_next_layer()
		await get_tree().create_timer(0.2).timeout
		if from_cell.check_match():
			await _process_match(from_cell)

	_animating = false
	_board_active = true

	if _check_win():
		_on_win()
		return

	if not _has_valid_move():
		_show_reshuffle_prompt()


func _play_match_sfx(cell: PotionCell) -> void:
	# 1. Escalating combo note (note_1 on first match, up to note_7).
	#    Volume ramps from COMBO_VOL_MIN_DB to COMBO_VOL_MAX_DB across the 7 notes.
	var idx := clampi(_match_streak, 1, 7) - 1
	if idx < _combo_players.size():
		var p := _combo_players[idx] as AudioStreamPlayer
		if p.stream != null:
			p.volume_db = lerp(COMBO_VOL_MIN_DB, COMBO_VOL_MAX_DB, float(idx) / 6.0)
			p.play()

	# 2. Restart the 5-second streak reset timer.
	#    Incrementing the ID cancels any previously pending reset without disconnecting.
	_streak_timer_id += 1
	var current_id := _streak_timer_id
	get_tree().create_timer(STREAK_RESET_DELAY).timeout.connect(
		func():
			if is_instance_valid(self) and _streak_timer_id == current_id:
				_match_streak = 0
	, CONNECT_ONE_SHOT)

	# 3. Per-set sfx — plays alongside the combo note for material texture.
	#    Determined by the first non-zero item in the matched cell.
	for s in range(PotionCell.SLOTS):
		var item_id := cell.get_item(s)
		if item_id != 0 and _item_set_map.has(item_id):
			var set_num: int = _item_set_map[item_id] as int
			if _set_sfx.has(set_num):
				(_set_sfx[set_num] as AudioStreamPlayer).play()
			break


func _process_match(cell: PotionCell) -> void:
	_match_streak = clampi(_match_streak + 1, 1, 7)
	_play_match_sfx(cell)
	await cell.clear_match()
	_notify_locked_cells()
	await get_tree().create_timer(0.1).timeout
	# Chain: if revealed layer also matches.
	while cell.check_match():
		_match_streak = clampi(_match_streak + 1, 1, 7)
		_play_match_sfx(cell)
		await cell.clear_match()
		_notify_locked_cells()
		await get_tree().create_timer(0.1).timeout


func _animate_item_move(from_cell: PotionCell, from_slot: int,
		to_cell: PotionCell, to_slot: int, item_id: int) -> void:
	var start_pos := from_cell.global_position + from_cell.get_slot_center(from_slot)
	var end_pos   := to_cell.global_position   + to_cell.get_slot_center(to_slot)

	var sprite := TextureRect.new()
	sprite.texture = _item_textures.get(item_id)
	sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.size = Vector2(PotionCell.ITEM_SIZE, PotionCell.ITEM_SIZE)
	sprite.pivot_offset = Vector2(PotionCell.ITEM_SIZE * 0.5, PotionCell.ITEM_SIZE * 0.5)
	#sprite.rotation = -PI / 4.0  # uncomment for 45° CCW tilt
	sprite.position = start_pos - Vector2(PotionCell.ITEM_SIZE * 0.5, PotionCell.ITEM_SIZE * 0.5)
	sprite.z_index = 50
	add_child(sprite)

	# Hide the original slot visual during flight.
	from_cell.remove_item(from_slot)

	var tw := create_tween()
	var target_pos := end_pos - Vector2(PotionCell.ITEM_SIZE * 0.5, PotionCell.ITEM_SIZE * 0.5)
	tw.tween_property(sprite, "position", target_pos, 0.15) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await tw.finished
	sprite.queue_free()


# ===========================================================================
#  Win / Dead Board
# ===========================================================================

func _check_win() -> bool:
	for row in _cells:
		for cell in row:
			if not (cell as PotionCell).is_fully_empty():
				return false
	for dc in _dispenser_cells:
		if not (dc as PotionCell).is_fully_empty():
			return false
	for dc in _disp_scroll_cells:
		if not (dc as PotionCell).is_fully_empty():
			return false
	return true


func _on_win() -> void:
	_board_active = false
	_save_progress()
	# Disable cell mouse input so WinPanel buttons can be clicked.
	for row in _cells:
		for cell in row:
			(cell as PotionCell).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for dc in _dispenser_cells:
		(dc as PotionCell).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for dc in _disp_scroll_cells:
		(dc as PotionCell).mouse_filter = Control.MOUSE_FILTER_IGNORE
	_win_moves_lbl.text = "in %d moves" % _move_count
	_win_panel.visible = true


func _has_valid_move() -> bool:
	## Dead-state detection:
	## 1. No empty slots at all → stuck.
	## 2. Any item type with 3+ accessible copies that can be consolidated
	##    into one cell (given available empty-slot budget) → valid.
	## 3. With ≥2 empty slots: if any cell can be fully emptied to reveal
	##    its next z-layer, that's still a valid state (might produce a match).

	# Count accessible empty slots (non-locked, non-dispenser cells only).
	var empty_slots := 0
	for row in _cells:
		for cell in row:
			var c := cell as PotionCell
			if c.is_locked() or c.is_dispenser():
				continue
			for s in range(PotionCell.SLOTS):
				if c.get_item(s) == 0:
					empty_slots += 1
	if empty_slots == 0:
		return false

	# Collect all currently visible accessible items.
	var item_counts: Dictionary = {}
	for row in _cells:
		for cell in row:
			var c := cell as PotionCell
			if c.is_locked():
				continue
			for s in range(PotionCell.SLOTS):
				var id := c.get_item(s)
				if id != 0:
					item_counts[id] = item_counts.get(id, 0) + 1
	for dc in _dispenser_cells:
		var id := (dc as PotionCell).get_item(0)
		if id != 0:
			item_counts[id] = item_counts.get(id, 0) + 1
	for dc in _disp_scroll_cells:
		if dc == _disp_scroll_buffer:
			continue
		var id := (dc as PotionCell).get_item(0)
		if id != 0:
			item_counts[id] = item_counts.get(id, 0) + 1

	# With ≥2 empty slots: if any non-locked, non-dispenser cell has a z-layer
	# below AND all its current items fit within the empty-slot budget, clearing
	# it to reveal fresh items is a legal play — don't call this dead.
	if empty_slots >= 2:
		for row in _cells:
			for cell in row:
				var c := cell as PotionCell
				if c.is_locked() or c.is_dispenser():
					continue
				if c.layers_remaining() == 0:
					continue
				var items_in_cell := 0
				for s in range(PotionCell.SLOTS):
					if c.get_item(s) != 0:
						items_in_cell += 1
				if items_in_cell <= empty_slots:
					return true   # can empty this cell to reveal next layer

	# Check whether any item type has 3+ copies that could be consolidated
	# into one cell using the available empty-slot budget.
	for id in item_counts:
		if item_counts[id] < 3:
			continue
		for row in _cells:
			for cell in row:
				var c := cell as PotionCell
				if c.is_locked() or c.is_dispenser():
					continue
				var in_cell := 0
				var empty_in_cell := 0
				for s in range(PotionCell.SLOTS):
					if c.get_item(s) == id:
						in_cell += 1
					elif c.get_item(s) == 0:
						empty_in_cell += 1
				# Slots needed from outside = 3 - in_cell.
				# Available = cell's own empties + board empties.
				if (3 - in_cell) <= (empty_in_cell + empty_slots):
					return true

	return false


func _show_reshuffle_prompt() -> void:
	_board_active = false
	_reshuffle_lbl.visible = true
	_reshuffle_btn.visible = true


func _on_reshuffle_pressed() -> void:
	_reshuffle_lbl.visible = false
	_reshuffle_btn.visible = false
	prepare_board()
	start_game()


func _reshuffle_board() -> void:
	# Collect items from visible slots of normal (non-locked, non-dispenser) cells.
	var pool: Array[int] = []
	for row in _cells:
		for cell in row:
			var c := cell as PotionCell
			if c.is_locked() or c.is_dispenser():
				continue
			for s in range(PotionCell.SLOTS):
				var item := c.get_item(s)
				if item != 0:
					pool.append(item)
					c.remove_item(s)
	pool.shuffle()

	# Redistribute into normal slots, leaving at least some empty slots.
	var slot_list: Array = []  # Array of [cell, slot_idx]
	for row in _cells:
		for cell in row:
			var c := cell as PotionCell
			if c.is_locked() or c.is_dispenser():
				continue
			for s in range(PotionCell.SLOTS):
				if c.get_item(s) == 0:
					slot_list.append([c, s])
	slot_list.shuffle()

	for i in range(pool.size()):
		if i < slot_list.size():
			var target: Array = slot_list[i]
			(target[0] as PotionCell).set_item(target[1] as int, pool[i])


# ===========================================================================
#  Undo
# ===========================================================================

func _save_undo_snapshot() -> void:
	var grid_snap: Array = []
	for row in _cells:
		var row_snap: Array = []
		for cell in row:
			var c := cell as PotionCell
			row_snap.append({
				slots          = c.get_slots_array(),
				z_stack        = c.get_z_stack_copy(),
				is_locked      = c.is_locked(),
				unlock_counter = c.get_unlock_counter(),
			})
		grid_snap.append(row_snap)
	var disp_snap: Array = []
	for dc in _dispenser_cells:
		var c := dc as PotionCell
		disp_snap.append({
			slots   = c.get_slots_array(),
			z_stack = c.get_z_stack_copy(),
		})
	_undo_stack.push_back({ grid = grid_snap, dispensers = disp_snap })


func _on_undo_pressed() -> void:
	var in_dead_board := _reshuffle_btn.visible
	if _undo_stack.is_empty() or (not _board_active and not in_dead_board):
		return
	if in_dead_board:
		_reshuffle_lbl.visible = false
		_reshuffle_btn.visible = false
	if _selected_cell:
		_selected_cell.hide_all_highlights()
		_selected_cell = null
		_selected_slot = -1
	var snap: Dictionary = _undo_stack.pop_back()
	for r in range(_rows):
		for c in range(_cells[r].size()):   # includes scroll buffer cells
			(_cells[r][c] as PotionCell).restore(snap.grid[r][c])
	for i in range(_dispenser_cells.size()):
		if i < snap.dispensers.size():
			(_dispenser_cells[i] as PotionCell).restore(snap.dispensers[i])
	_move_count = maxi(0, _move_count - 1)
	_update_ui()
	_board_active = true


# ===========================================================================
#  Save / Load
# ===========================================================================

func _save_key() -> String:
	return "best_moves_%s" % DIFFICULTY_KEYS[_actual_difficulty]


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
		cfg.load(SAVE_PATH)  # preserve other keys
		cfg.set_value("progress", _save_key(), _best_moves)
		cfg.save(SAVE_PATH)


# ===========================================================================
#  UI
# ===========================================================================

func _update_ui() -> void:
	_move_label.text = "MOVES: %d" % _move_count
	if _best_moves > 0:
		_best_label.visible = false
		#_best_label.text = "BEST: %d" % _best_moves
		#_best_label.visible = true
	else:
		_best_label.visible = false
	_undo_button.text = "UNDO" if not _undo_stack.is_empty() else ""
	_undo_button.disabled = _undo_stack.is_empty()


func _on_back_pressed() -> void:
	back_to_menu.emit()


func _on_new_game_pressed() -> void:
	_win_panel.visible = false
	_cancel_drag()
	_pressing = false
	prepare_board()
	start_game()  # fire-and-forget; _board_active = true after animation timer


# ===========================================================================
#  Special Cell Generation
# ===========================================================================

func _generate_special_cells() -> void:
	if _actual_difficulty == 0:
		return   # Easy: no special cells

	var is_hard := _actual_difficulty == 2

	# --- Apply scrolling row tint (rows were decided in _apply_difficulty_layout) ---
	for r in _scrolling_rows:
		for cell in _cells[r]:   # includes buffer cells
			(cell as PotionCell).set_scroll_row_visual()

	# --- Candidate cells (non-empty, not in a scrolling row) ---
	var candidates: Array = []
	for r in range(_rows):
		if r in _scrolling_rows:
			continue
		for c in range(_cols_per_row):
			var cell := _cells[r][c] as PotionCell
			if not cell.is_fully_empty():
				candidates.append(cell)
	candidates.shuffle()

	var ci := 0

	# --- Locked cells (only if this game rolled the lock special) ---
	if _special_lock:
		var lock_max   := 2 if is_hard else 1
		var lock_req   := 3 if is_hard else 2
		var lock_count := 0
		while ci < candidates.size() and lock_count < lock_max:
			(candidates[ci] as PotionCell).set_as_locked(lock_req)
			lock_count += 1
			ci += 1

	# --- Mystery items (Medium+, ~60% chance, 3–5 items) ---
	# Sprite darkened with "?" overlay; scattered across visible layer AND z-stack layers.
	if randf() < 0.70:
		var mystery_count := randi_range(3, 5)
		var mystery_candidates: Array = []
		for r in range(_rows):
			for c in range(_cols_per_row):
				var cell := _cells[r][c] as PotionCell
				if cell.is_locked() or cell.is_dispenser():
					continue
				# Current visible layer — entry format: [cell, -1, slot_idx]
				for s in range(PotionCell.SLOTS):
					if cell.get_item(s) != 0:
						mystery_candidates.append([cell, -1, s])
				# Z-stack layers below — entry format: [cell, layer_idx, slot_idx]
				var z_copy := cell.get_z_stack_copy()
				for li in range(z_copy.size()):
					for s in range(PotionCell.SLOTS):
						if (z_copy[li][s] as int) != 0:
							mystery_candidates.append([cell, li, s])
		mystery_candidates.shuffle()
		for i in range(mini(mystery_count, mystery_candidates.size())):
			var entry: Array = mystery_candidates[i]
			var target_cell := entry[0] as PotionCell
			var layer_idx   := entry[1] as int
			var slot_idx    := entry[2] as int
			if layer_idx == -1:
				target_cell.set_slot_mystery(slot_idx, true)
			else:
				target_cell.set_z_slot_mystery(layer_idx, slot_idx, true)


func _create_dispenser_cells(groups: Array) -> void:
	## Creates 1-tall dispenser cells below the main board, centred horizontally.
	## Each group is an Array[int] of 3 item IDs (all the same type) for one dispenser.
	if groups.is_empty():
		return

	var board_h: int = _rows * PotionCell.CELL_H + (_rows - 1) * ROW_SPACING
	var vp_h    := get_viewport_rect().size.y
	var origin_y := int(90.0 + (vp_h - 180.0 - board_h) / 2.0)
	var disp_y   := origin_y + board_h + 18   # 18 px gap below the board

	var n := groups.size()
	var disp_origin_x := int((540.0 - n * PotionCell.CELL_W) / 2.0)

	for i in range(n):
		var grp: Array = groups[i]
		# Build slots + z_stack: first item visible, rest queued one-per-layer.
		var top_slot: Array[int] = [grp[0] as int, 0, 0]
		var z_stack: Array = []
		for j in range(1, grp.size()):
			z_stack.append([grp[j] as int, 0, 0])

		var dcell := PotionCell.new()
		dcell.setup(top_slot, z_stack, _item_textures)
		dcell.position = Vector2(disp_origin_x + i * PotionCell.CELL_W, disp_y)
		dcell.set_as_dispenser()
		add_child(dcell)
		_dispenser_cells.append(dcell)


# ===========================================================================
#  Scrolling Row Conveyor
# ===========================================================================

func _advance_scroll(row_idx: int) -> void:
	## Slides all cells in a scrolling row one position to the left at constant speed.
	## Fades the departing cell out and the entering buffer cell in.
	## Uses tween.finished.connect (no await) so freeing the scene mid-scroll
	## never causes a "lambda capture freed" coroutine crash.
	if not is_instance_valid(self) or not visible or _cells.is_empty():
		return
	if row_idx >= _cells.size() or _cells[row_idx].is_empty():
		return

	var row_cells: Array = _cells[row_idx]
	var n := row_cells.size()
	# Off-screen holding position: exactly one CELL_W past the board's right edge.
	var off_x := float(_board_origin_x + _cols_per_row * PotionCell.CELL_W)

	var tween := create_tween()
	_scroll_tweens.append(tween)
	tween.set_parallel(true)
	for i in range(n):
		var c := row_cells[i] as PotionCell
		var start_x := c.position.x
		var end_x   := float(_board_origin_x + (i - 1) * PotionCell.CELL_W)
		# tween_method with roundf() keeps position.x on whole pixels every frame,
		# preventing the sub-pixel wobble that makes the cell bg gap appear to shift.
		tween.tween_method(
			func(x: float): if is_instance_valid(c): c.position.x = roundf(x),
			start_x, end_x, SCROLL_INTERVAL
		).set_trans(Tween.TRANS_LINEAR)
	# Fade the departing cell out during the last 20% of the slide.
	tween.tween_property(row_cells[0] as PotionCell, "modulate:a", 0.0,
		SCROLL_INTERVAL * 0.20).set_delay(SCROLL_INTERVAL * 0.80)
	# Fade the entering buffer cell in during the first 20% of the slide.
	tween.tween_property(row_cells[n - 1] as PotionCell, "modulate:a", 1.0,
		SCROLL_INTERVAL * 0.20)

	# Connect finished as a one-shot lambda instead of await.
	# A plain lambda handles the "self freed mid-scroll" case cleanly:
	# Godot logs the capture-freed error, passes null, and the validity
	# check returns before touching any cell data.
	# The generation check prevents a stale lambda (from a game that called
	# queue_free on cells but hasn't processed it yet) from overwriting the
	# fresh _cells array that prepare_board() just built.
	var gen := _game_generation
	tween.finished.connect(func():
		if not is_instance_valid(self) or not visible:
			return
		if _game_generation != gen:
			return
		var departing := row_cells[0] as PotionCell
		if not is_instance_valid(departing):
			return
		departing.position.x = off_x
		departing.modulate.a  = 0.0
		row_cells.remove_at(0)
		row_cells.append(departing)
		_cells[row_idx] = row_cells
		_advance_scroll(row_idx)
	, CONNECT_ONE_SHOT)


func _create_disp_scroll_belt(groups: Array) -> void:
	## Creates a rightward-scrolling row of dispenser cells below the board (Hard hazard).
	## Array layout after creation: [buffer(off-left), vis0, vis1, ..., vis4]
	## so _advance_disp_scroll can use end_x = board_origin_x + i * CELL_W per index.
	var board_h: int = _rows * PotionCell.CELL_H + (_rows - 1) * ROW_SPACING
	var vp_h := get_viewport_rect().size.y
	var origin_y := int(90.0 + (vp_h - 180.0 - board_h) / 2.0)
	var belt_y := origin_y - PotionCell.ITEM_SIZE - 18

	var off_x_left := float(_board_origin_x - PotionCell.CELL_W)

	for i in range(DISP_SCROLL_CELLS):
		var grp: Array = groups[i]
		var top_slot: Array[int] = [grp[0] as int, 0, 0]
		var z_stack: Array = []
		for j in range(1, grp.size()):
			z_stack.append([grp[j] as int, 0, 0])
		var cell := PotionCell.new()
		cell.setup(top_slot, z_stack, _item_textures)
		cell.position = Vector2(_board_origin_x + i * PotionCell.CELL_W, belt_y)
		cell.set_as_dispenser()
		cell.set_scroll_row_visual()
		add_child(cell)
		_disp_scroll_cells.append(cell)

	# Buffer cell — off-screen left, invisible until first scroll tick.
	var buf_grp: Array = groups[DISP_SCROLL_CELLS]
	var buf_top: Array[int] = [buf_grp[0] as int, 0, 0]
	var buf_z: Array = []
	for j in range(1, buf_grp.size()):
		buf_z.append([buf_grp[j] as int, 0, 0])
	_disp_scroll_buffer = PotionCell.new()
	_disp_scroll_buffer.setup(buf_top, buf_z, _item_textures)
	_disp_scroll_buffer.position = Vector2(off_x_left, belt_y)
	_disp_scroll_buffer.set_as_dispenser()
	_disp_scroll_buffer.set_scroll_row_visual()
	_disp_scroll_buffer.modulate.a = 0.0
	add_child(_disp_scroll_buffer)
	_disp_scroll_cells.push_front(_disp_scroll_buffer)   # [buffer, vis0..vis4]


func _advance_disp_scroll() -> void:
	## Slides the hazard belt one step to the RIGHT (opposite the main conveyor).
	## Cell at index i targets x = board_origin_x + i * CELL_W.
	## The rightmost cell wraps to the off-screen left buffer position.
	if not is_instance_valid(self) or not visible or _disp_scroll_cells.is_empty():
		return

	var cells := _disp_scroll_cells
	var n := cells.size()
	var off_x_left := float(_board_origin_x - PotionCell.CELL_W)

	var tween := create_tween()
	_scroll_tweens.append(tween)
	tween.set_parallel(true)
	for i in range(n):
		var c := cells[i] as PotionCell
		var end_x := float(_board_origin_x + i * PotionCell.CELL_W)
		tween.tween_method(
			func(x: float): if is_instance_valid(c): c.position.x = roundf(x),
			c.position.x, end_x, DISP_SCROLL_INTERVAL
		).set_trans(Tween.TRANS_LINEAR)
	# Departing (rightmost) fades out in the last 20%.
	tween.tween_property(cells[n - 1] as PotionCell, "modulate:a", 0.0,
		DISP_SCROLL_INTERVAL * 0.20).set_delay(DISP_SCROLL_INTERVAL * 0.80)
	# Entering buffer (index 0) fades in during the first 20%.
	tween.tween_property(cells[0] as PotionCell, "modulate:a", 1.0,
		DISP_SCROLL_INTERVAL * 0.20)

	var gen := _game_generation
	tween.finished.connect(func():
		if not is_instance_valid(self) or not visible:
			return
		if _game_generation != gen:
			return
		var departing := cells[n - 1] as PotionCell
		if not is_instance_valid(departing):
			return
		departing.position.x = off_x_left
		departing.modulate.a = 0.0
		cells.remove_at(n - 1)
		cells.push_front(departing)
		_disp_scroll_cells = cells
		_advance_disp_scroll()
	, CONNECT_ONE_SHOT)


# ===========================================================================
#  Locked-Cell Match Notification
# ===========================================================================

func _notify_locked_cells() -> void:
	## Decrement every locked cell's counter after a match.
	## Each cell animates its own unlock when the counter reaches zero.
	for row_arr in _cells:
		for cell in row_arr:
			(cell as PotionCell).notify_match()
