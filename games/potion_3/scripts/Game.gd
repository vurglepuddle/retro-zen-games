# Game.gd (potion_3) — Triple-match goods-sort board.
# Grid of PotionCell shelves; each shelf holds 3 item slots + z-depth layers.
# Match 3 identical items in one cell to eliminate them. Clear the board to win.

extends Control

signal back_to_menu

# ---- constants ---------------------------------------------------------------
const COLS := 3
const SAVE_PATH := "user://potion_3_save.cfg"
const DIFFICULTY_KEYS := ["easy", "medium", "hard", "zen"]
const ITEMS_BASE_PATH := "res://games/potion_3/assets/items/"

const COL_SPACING := 12
const ROW_SPACING := 8
const DRAG_THRESHOLD := 10.0

# ---- difficulty state --------------------------------------------------------
var _difficulty:        int = 0
var _actual_difficulty: int = 0
var _rows:              int = 3
var _max_depth:         int = 3
var _item_type_count:   int = 12
var _empty_cell_count:  int = 2

# ---- game state --------------------------------------------------------------
var _cells: Array          = []    # 2D: [row][col] → PotionCell
var _selected_cell: PotionCell = null
var _selected_slot: int    = -1
var _board_active: bool    = false
var _animating: bool       = false
var _move_count: int       = 0
var _best_moves: int       = 0
var _item_textures: Dictionary = {}   # item_id → Texture2D
var _undo_stack: Array     = []

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
		0:  # Easy — 3×3, 7 filled, 12 layers (avg depth ~1.7)
			_rows = 3;  _max_depth = 3;  _item_type_count = 12;  _empty_cell_count = 2
		1:  # Medium — 3×4, 10 filled, 22 layers (avg depth ~2.2)
			_rows = 4;  _max_depth = 4;  _item_type_count = 22;  _empty_cell_count = 2
		2:  # Hard — 3×5, 13 filled, 32 layers (avg depth ~2.5)
			_rows = 5;  _max_depth = 5;  _item_type_count = 32;  _empty_cell_count = 2


func prepare_board() -> void:
	_apply_difficulty_layout()
	_board_active = false
	_animating = false
	_undo_stack.clear()
	_win_panel.visible = false
	_reshuffle_lbl.visible = false
	_reshuffle_btn.visible = false
	_selected_cell = null
	_selected_slot = -1
	_move_count = 0
	_cancel_drag()
	_clear_cells()
	_load_textures()
	_build_cells()
	# Pre-position cells for the drop-in animation so the fade-in doesn't
	# reveal the board already in its final state before start_game() runs.
	for row in _cells:
		for cell in row:
			var c: PotionCell = cell
			c.position.y -= 160.0
			c.modulate.a = 0.0
	_update_ui()


func start_game() -> void:
	_board_active = false
	_undo_stack.clear()
	_update_ui()

	# Staggered drop-in animation.
	# Cells are already offset -160 and invisible from prepare_board().
	var idx := 0
	for row in _cells:
		for cell in row:
			var c: PotionCell = cell
			var final_y := c.position.y + 160.0  # restore to actual target
			var delay := idx * 0.05
			var tw := create_tween()
			tw.tween_interval(delay)
			tw.tween_callback(func():
				if not is_instance_valid(c):
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
	_board_active = true


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
				uid += 1
				found_in_set = true
				misses = 0
			else:
				misses += 1
				if misses >= 50:
					break
		if not found_in_set:
			break  # set folder doesn't exist → no more sets


func _clear_cells() -> void:
	for row in _cells:
		for cell in row:
			(cell as PotionCell).queue_free()
	_cells.clear()


func _build_cells() -> void:
	var board_data := _generate_board_data()
	var depths: Array = board_data.depths
	var items: Array  = board_data.items

	var board_w: int = COLS * PotionCell.CELL_W + (COLS - 1) * COL_SPACING
	var board_h: int = _rows * PotionCell.CELL_H + (_rows - 1) * ROW_SPACING
	var origin_x := int((540.0 - board_w) / 2.0)
	var vp_h := get_viewport_rect().size.y
	var origin_y := int(90.0 + (vp_h - 180.0 - board_h) / 2.0)

	var cell_idx := 0
	for row in range(_rows):
		var row_arr: Array = []
		for col in range(COLS):
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
				origin_x + col * (PotionCell.CELL_W + COL_SPACING),
				origin_y + row * (PotionCell.CELL_H + ROW_SPACING)
			)
			add_child(cell)
			row_arr.append(cell)
			cell_idx += 1
		_cells.append(row_arr)


func _generate_board_data() -> Dictionary:
	var total_cells := COLS * _rows

	# 1. Choose item types from all loaded textures.
	var available: Array = _item_textures.keys()
	available.shuffle()
	var chosen := available.slice(0, _item_type_count)

	# 2. Create item pool (each type ×3).
	# Layers can hold 1–3 items; leftovers within a layer become empty slots.
	var pool: Array[int] = []
	for t in chosen:
		pool.append(t)
		pool.append(t)
		pool.append(t)
	pool.shuffle()

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

	return { depths = depths, items = cell_items }


# ===========================================================================
#  Input — Tap to Select / Move
# ===========================================================================

func _on_slot_tapped(cell: PotionCell, slot_idx: int) -> void:
	if not _board_active or _animating:
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
	var snap_threshold := PotionCell.CELL_W * 0.25  # ~60% of a cell width

	var to_cell: PotionCell = null
	var to_slot: int = -1

	var exact: Variant = _find_cell_slot_at(pos)

	# Same-cell rearrangement: always honour regardless of drag distance.
	# The user is intentionally organising items within one shelf.
	if exact != null:
		var hit_cell := exact[0] as PotionCell
		var hit_slot := exact[1] as int
		if hit_cell == _selected_cell and hit_slot != _selected_slot \
				and hit_cell.get_item(hit_slot) == 0:
			to_cell = hit_cell
			to_slot = hit_slot

	# Cross-cell move: only snap if dragged far enough from origin.
	if to_cell == null and drag_dist >= snap_threshold:
		if exact != null and (exact[0] as PotionCell).get_item(exact[1] as int) == 0:
			to_cell = exact[0]
			to_slot = exact[1]
		else:
			# Nearest empty slot within a reasonable radius.
			var best_dist := PotionCell.CELL_W * 1.5
			for row in _cells:
				for cell in row:
					var c := cell as PotionCell
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
	# On mobile, fingers are imprecise — expand the hit rect upward by half an
	# item so touching just above an item still registers on the right cell.
	const TOUCH_EXPAND_Y := PotionCell.ITEM_SIZE * 0.5
	for row in _cells:
		for cell in row:
			var c := cell as PotionCell
			var rect := c.get_global_rect()
			var expanded := Rect2(rect.position - Vector2(0, TOUCH_EXPAND_Y),
					rect.size + Vector2(0, TOUCH_EXPAND_Y))
			if expanded.has_point(pos):
				var local_x := pos.x - rect.position.x
				var slot_w := rect.size.x / float(PotionCell.SLOTS)
				var slot_idx := clampi(int(local_x / slot_w), 0, PotionCell.SLOTS - 1)
				return [c, slot_idx]
	return null


func _find_pickup_slot_near(pos: Vector2, radius: float) -> Variant:
	## Returns the nearest non-empty slot within radius, or null.
	var best_cell: PotionCell = null
	var best_slot := -1
	var best_dist := radius
	for row in _cells:
		for cell in row:
			var c := cell as PotionCell
			for s in range(PotionCell.SLOTS):
				if c.get_item(s) == 0:
					continue
				var center := c.get_global_rect().position + c.get_slot_center(s)
				var d := pos.distance_to(center)
				if d < best_dist:
					best_dist = d
					best_cell = c
					best_slot = s
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

	var item_id := from_cell.get_item(from_slot)
	from_cell.show_slot_highlight(from_slot, false)
	_selected_cell = null
	_selected_slot = -1

	if animate_fly:
		await _animate_item_move(from_cell, from_slot, to_cell, to_slot, item_id)

	from_cell.remove_item(from_slot)
	to_cell.set_item(to_slot, item_id)
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


func _process_match(cell: PotionCell) -> void:
	await cell.clear_match()
	await get_tree().create_timer(0.1).timeout
	# Chain: if revealed layer also matches.
	while cell.check_match():
		await cell.clear_match()
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
	return true


func _on_win() -> void:
	_board_active = false
	_save_progress()
	# Disable cell mouse input so WinPanel buttons can be clicked.
	for row in _cells:
		for cell in row:
			(cell as PotionCell).mouse_filter = Control.MOUSE_FILTER_IGNORE
	_win_moves_lbl.text = "in %d moves" % _move_count
	_win_panel.visible = true


func _has_valid_move() -> bool:
	## A move is possible if there's at least one non-empty slot AND one empty slot.
	var has_item := false
	var has_empty := false
	for row in _cells:
		for cell in row:
			var c := cell as PotionCell
			for s in range(PotionCell.SLOTS):
				if c.get_item(s) != 0:
					has_item = true
				else:
					has_empty = true
			if has_item and has_empty:
				return true
	return has_item and has_empty


func _show_reshuffle_prompt() -> void:
	_board_active = false
	_reshuffle_lbl.visible = true
	_reshuffle_btn.visible = true


func _on_reshuffle_pressed() -> void:
	_reshuffle_lbl.visible = false
	_reshuffle_btn.visible = false
	_reshuffle_board()
	_board_active = true


func _reshuffle_board() -> void:
	# Collect all items from all visible slots (not z-stacks — those stay in place).
	var pool: Array[int] = []
	for row in _cells:
		for cell in row:
			var c := cell as PotionCell
			for s in range(PotionCell.SLOTS):
				var item := c.get_item(s)
				if item != 0:
					pool.append(item)
					c.remove_item(s)
	pool.shuffle()

	# Redistribute into slots, leaving at least some empty slots.
	var slot_list: Array = []  # Array of [cell, slot_idx]
	for row in _cells:
		for cell in row:
			var c := cell as PotionCell
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
	var snap: Array = []
	for row in _cells:
		var row_snap: Array = []
		for cell in row:
			var c := cell as PotionCell
			row_snap.append({
				slots = c.get_slots_array(),
				z_stack = c.get_z_stack_copy()
			})
		snap.append(row_snap)
	_undo_stack.push_back(snap)


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
	var snap: Array = _undo_stack.pop_back()
	for r in range(_rows):
		for c in range(COLS):
			(_cells[r][c] as PotionCell).restore(snap[r][c])
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
