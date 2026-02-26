#Game.gd
extends Node2D

signal back_to_menu

const TILE_SCENE = preload("res://games/gem_match/scenes/Tile.tscn")

# Octagonal board (10 rows x 7 cols). 0 = empty cell, 1 = valid cell.
const SHAPE := [
	[1,1,1,1,1,1,1],
	[1,1,1,1,1,1,1],
	[1,1,1,1,1,1,1],
	[1,1,1,1,1,1,1],
	[1,1,1,1,1,1,1],
	[1,1,1,1,1,1,1],
	[1,1,1,1,1,1,1],
	[1,1,1,1,1,1,1],
	[1,1,1,1,1,1,1],
	[0,1,1,1,1,1,0]
]

# Cell size in pixels (tile 80px + 5px gap). Board is scaled to fit viewport.
@export_range(16, 256)
var cell_size: int = 85

# Delay (seconds) before the fall SFX fires at game start.
@export_range(0.0, 2.0, 0.01)
var sfx_fall_delay: float = 0.03

var board_rows: int = SHAPE.size()
var board_cols: int = SHAPE[0].size()
var board: Array = []
var score: int = 0
var last_swapped_tiles: Array = []

# True while any animation is running. Input is ignored during this time.
var _busy := false
var _drag_tile = null
var _drag_start := Vector2.ZERO

# Animated score counter.
var _displayed_score: int = 0
var _score_tween: Tween = null

# Combo label tween — stored so a rapid new combo kills the old animation first.
var _combo_tween: Tween = null

# Combo announcer word list — index 0 fires on cascade 2, index 6 on cascade 8+.
const COMBO_WORDS := [
	"GOOD!", "GREAT!", "FANTASTIC!", "EXCELLENT!",
	"SPECTACULAR!", "EXTRAORDINARY!", "UNBELIEVABLE!", "INCONCEIVABLE!",
	"PREPOSTEROUS!", "LUDICROUS!", "REALITY-SHATTERING!", "UNIVERSE-ALTERING!",
	"COSMICALLY TRANSCENDENT!", "GOD-TIER!", "MULTIVERSAL!",
]

# Hint system — after HINT_DELAY seconds of no input, pulse a valid swap pair.
const HINT_DELAY := 5.0
var _hint_timer: float = 0.0
var _hint_tiles: Array = []

var _game_active: bool = false

# Score milestone flash overlay.
var _flash_overlay: ColorRect = null
var _next_milestone: int = 1000

@onready var board_container: Node2D = $Board
@onready var score_label: Label      = $ScoreLabel
@onready var shuffle_label: Label    = $ShuffleLabel
@onready var combo_label: Label      = $ComboLabel
@onready var back_button: Button     = $BackButton

@onready var sfx_swap:      AudioStreamPlayer = $SfxSwap
@onready var sfx_match:     AudioStreamPlayer = $SfxMatch
@onready var sfx_no_match:  AudioStreamPlayer = $SfxNoMatch
@onready var sfx_shuffle:   AudioStreamPlayer = $SfxShuffle
@onready var sfx_fall:      AudioStreamPlayer = $SfxFall
@onready var sfx_explosion: AudioStreamPlayer = $SfxExplosion
@onready var sfx_lightning:  AudioStreamPlayer = $SfxLightning
@onready var sfx_color_bomb: AudioStreamPlayer = $SfxColorBomb
@onready var sfx_tink:       AudioStreamPlayer = $SfxTink

@onready var sfx_notes: Array = [
	$SfxNote1, $SfxNote2, $SfxNote3, $SfxNote4,
	$SfxNote5, $SfxNote6, $SfxNote7
]

@onready var sfx_voices: Array = [
	$SfxVoiceGood, $SfxVoiceExcellent, $SfxVoiceAwesome,
	$SfxVoiceSpectacular, $SfxVoiceExtraordinary, $SfxVoiceUnbelievable, $SfxVoiceInconceivable
]


# ----- Setup ----------------------------------------------------------------

func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	_flash_overlay = ColorRect.new()
	_flash_overlay.color = Color(1.0, 0.92, 0.4, 0.0)
	_flash_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_flash_overlay)

	back_button.pressed.connect(_go_back_to_menu)


func prepare_board() -> void:
	_game_active = false
	_next_milestone = 1000
	_busy = false
	_drag_tile = null
	_stop_hints()
	_hint_timer = 0.0
	for child in board_container.get_children():
		child.queue_free()
	board = []
	score = 0
	_displayed_score = 0
	if score_label:
		score_label.text = "Score: 0"
	_generate_board()
	_position_board()
	_update_all_tile_positions()
	for r in range(board_rows):
		for c in range(board_cols):
			if board[r][c] != null:
				board[r][c].modulate.a = 0.0


func start_game() -> void:
	_play_sfx_delayed(sfx_fall, sfx_fall_delay)
	await _animate_board_entrance()
	_check_for_shuffle()
	_game_active = true


func _generate_board() -> void:
	board.resize(board_rows)
	for r in range(board_rows):
		board[r] = []
		for c in range(board_cols):
			if SHAPE[r][c] == 1:
				var tile := TILE_SCENE.instantiate()
				tile.row  = r
				tile.col  = c
				tile.game = self
				board[r].append(tile)
				board_container.add_child(tile)
				tile.set_level(_pick_start_level(r, c))
			else:
				board[r].append(null)


func _pick_start_level(r: int, c: int) -> int:
	var candidates: Array = [1, 2, 3, 4, 5]
	candidates.shuffle()
	for lv in candidates:
		if not _would_match_at(r, c, lv):
			return lv
	return candidates[0]


func _would_match_at(r: int, c: int, lv: int) -> bool:
	if c >= 2:
		var a = board[r][c - 1]
		var b = board[r][c - 2]
		if a != null and b != null and a.level == lv and b.level == lv:
			return true
	if r >= 2:
		var a = board[r - 1][c]
		var b = board[r - 2][c]
		if a != null and b != null and a.level == lv and b.level == lv:
			return true
	return false


func _position_board() -> void:
	var vp     := get_viewport_rect().size
	var board_w := board_cols * float(cell_size)
	var board_h := board_rows * float(cell_size)
	var ui_top  := 70.0
	var margin  := 10.0
	var scale_x := (vp.x - margin * 2.0) / board_w
	var scale_y := (vp.y - ui_top - margin) / board_h
	var s: float = clamp(min(scale_x, scale_y), 0.1, 1.5)
	board_container.scale    = Vector2(s, s)
	board_container.position = Vector2(
		(vp.x - board_w * s) / 2.0,
		ui_top + (vp.y - ui_top - margin - board_h * s) / 2.0
	)


func _update_all_tile_positions() -> void:
	for r in range(board_rows):
		for c in range(board_cols):
			var tile = board[r][c]
			if tile != null:
				tile.row = r
				tile.col = c
				tile.update_position(Vector2(cell_size, cell_size))


func _animate_board_entrance() -> void:
	var all_tiles: Array = []
	for c in range(board_cols):
		for r in range(board_rows):
			var t = board[r][c]
			if t != null:
				all_tiles.append(t)

	var n := all_tiles.size()
	if n == 0:
		return

	for tile in all_tiles:
		var target := _cell_pos(tile.row, tile.col)
		tile.position = Vector2(
			target.x,
			-(board_rows + randf_range(1.0, 4.0)) * float(cell_size)
		)

	var tw := create_tween()
	tw.set_parallel(true)
	var cumulative_delay := 0.0

	for i in range(n):
		var tile  = all_tiles[i]
		var target := _cell_pos(tile.row, tile.col)
		var progress := float(i) / float(max(n - 1, 1))
		cumulative_delay += lerp(0.035, 0.007, progress) + randf_range(-0.003, 0.003)
		var dur: float = clampf(lerpf(0.60, 0.20, progress) + randf_range(-0.05, 0.07), 0.15, 0.80)
		tw.tween_property(tile, "modulate:a", 1.0, 0.10).set_delay(cumulative_delay)
		tw.tween_property(tile, "position", target, dur) \
			.set_delay(cumulative_delay) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	await tw.finished


# ----- Input ----------------------------------------------------------------

func _go_back_to_menu() -> void:
	_game_active = false
	_stop_hints()
	back_to_menu.emit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _game_active:
		_go_back_to_menu()


func _process(delta: float) -> void:
	if not _game_active:
		return
	if _busy:
		_hint_timer = 0.0
		if not _hint_tiles.is_empty():
			_stop_hints()
		return
	_hint_timer += delta
	if _hint_timer >= HINT_DELAY and _hint_tiles.is_empty():
		_start_hint()


func start_drag(tile, press_pos: Vector2) -> void:
	if _busy:
		return
	_hint_timer = 0.0
	_stop_hints()
	_drag_tile  = tile
	_drag_start = press_pos


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton or event is InputEventScreenTouch:
		_hint_timer = 0.0
		_stop_hints()

	if _busy or _drag_tile == null or not is_instance_valid(_drag_tile):
		_drag_tile = null
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_drag_tile = null
		return
	if event is InputEventScreenTouch and not event.pressed:
		_drag_tile = null
		return

	var current_pos := Vector2(-1.0, -1.0)
	if event is InputEventMouseMotion:
		current_pos = event.position
	elif event is InputEventScreenDrag:
		current_pos = event.position

	if current_pos.x < 0.0:
		return

	var delta := current_pos - _drag_start
	if max(abs(delta.x), abs(delta.y)) < 30.0:
		return

	var tile = _drag_tile
	_drag_tile = null

	var dir := Vector2.ZERO
	if abs(delta.x) >= abs(delta.y):
		dir = Vector2(sign(delta.x), 0)
	else:
		dir = Vector2(0, sign(delta.y))

	_attempt_swap(tile, dir)


# ----- Hint system ----------------------------------------------------------

func _find_hint_pair() -> Array:
	# Prioritise COLOR_BOMB hints — they can always fire with any adjacent gem.
	for r in range(board_rows):
		for c in range(board_cols):
			if SHAPE[r][c] == 0:
				continue
			var t = board[r][c]
			if t == null or t.special_type != Tile.SPECIAL_COLOR_BOMB:
				continue
			for dir in [Vector2(1, 0), Vector2(0, 1)]:
				var nr := r + int(dir.y)
				var nc := c + int(dir.x)
				if nr < 0 or nr >= board_rows or nc < 0 or nc >= board_cols:
					continue
				if SHAPE[nr][nc] == 0:
					continue
				var adj = board[nr][nc]
				if adj != null:
					return [t, adj]

	for r in range(board_rows):
		for c in range(board_cols):
			var tile = board[r][c]
			if tile == null:
				continue
			for dir in [Vector2(1, 0), Vector2(0, 1)]:
				var nr := r + int(dir.y)
				var nc := c + int(dir.x)
				if nr < 0 or nr >= board_rows or nc < 0 or nc >= board_cols:
					continue
				if SHAPE[nr][nc] == 0:
					continue
				var other = board[nr][nc]
				if other == null:
					continue
				board[r][c] = other; board[nr][nc] = tile
				tile.row = nr; tile.col = nc
				other.row = r; other.col = c
				var found := _find_matches().size() > 0
				board[r][c] = tile; board[nr][nc] = other
				tile.row = r; tile.col = c
				other.row = nr; other.col = nc
				if found:
					return [tile, other]
	return []


func _start_hint() -> void:
	var pair := _find_hint_pair()
	if pair.is_empty():
		return
	_hint_tiles = pair
	for t in _hint_tiles:
		if is_instance_valid(t):
			t.start_hint()


func _stop_hints() -> void:
	for t in _hint_tiles:
		if is_instance_valid(t):
			t.stop_hint()
	_hint_tiles = []


# ----- Swap (animated) ------------------------------------------------------

func _attempt_swap(tile, dir: Vector2) -> void:
	if _busy:
		return
	var r: int = tile.row
	var c: int = tile.col
	var nr: int = r + int(dir.y)
	var nc: int = c + int(dir.x)
	if nr < 0 or nr >= board_rows or nc < 0 or nc >= board_cols:
		return
	if SHAPE[nr][nc] == 0:
		return
	var other = board[nr][nc]
	if other == null:
		return

	_busy = true

	var p1: Vector2 = tile.position
	var p2: Vector2 = other.position

	# --- COLOR_BOMB intercept: swap fires the bomb immediately. ---
	var color_bomb = null
	var bomb_target = null
	if tile.special_type == Tile.SPECIAL_COLOR_BOMB:
		color_bomb = tile;  bomb_target = other
	elif other.special_type == Tile.SPECIAL_COLOR_BOMB:
		color_bomb = other; bomb_target = tile

	if color_bomb != null:
		_play_sfx(sfx_swap)
		_swap_logic(tile, other)
		await _tween_two(tile, p2, other, p1, 0.15)
		_swap_logic(tile, other)
		await _tween_two(tile, p1, other, p2, 0.10)
		await _fire_color_bomb(color_bomb, bomb_target.level)
		_busy = false
		return

	# --- Normal match logic. ---
	_swap_logic(tile, other)
	await _tween_two(tile, p2, other, p1, 0.15)

	last_swapped_tiles = [tile, other]
	var matches := _find_matches()

	if matches.size() == 0:
		_play_sfx(sfx_no_match)
		await _tween_two(tile, p1, other, p2, 0.15)
		_swap_logic(tile, other)
		last_swapped_tiles = []
	else:
		_play_sfx(sfx_swap)
		await _resolve_matches_animated(matches)

	_busy = false


func _swap_logic(t1, t2) -> void:
	var r1 = t1.row; var c1 = t1.col
	var r2 = t2.row; var c2 = t2.col
	board[r1][c1] = t2
	board[r2][c2] = t1
	t1.row = r2; t1.col = c2
	t2.row = r1; t2.col = c1


func _tween_two(a, pa: Vector2, b, pb: Vector2, dur: float) -> void:
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(a, "position", pa, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(b, "position", pb, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	await tw.finished


# ----- Match resolution (animated) -----------------------------------------

func _resolve_matches_animated(initial_groups: Array) -> void:
	var groups := initial_groups
	var cascade := 0

	while groups.size() > 0:
		cascade += 1
		var multiplier := cascade

		var to_remove:     Array = []
		var removed_set          = {}
		var upgrades:      Array = []   # [tile, new_level, special_type]
		var detonate_queue: Array = []  # specials that need to chain-fire
		var any_match            = false
		var had_bomb_det         = false
		var had_cross_det        = false

		for group_dict in groups:
			var tiles: Array = group_dict["tiles"]
			var shape: int   = group_dict["shape"]

			# COLOR_BOMB tiles are immune to normal match resolution — they only
			# fire via the swap intercept, or are removed silently by BOMB/CROSS chains.
			var valid: Array = []
			for t in tiles:
				if not removed_set.has(t) and t.special_type != Tile.SPECIAL_COLOR_BOMB:
					valid.append(t)
			if valid.size() < 3:
				continue

			any_match = true

			# Check whether an existing special gem is in this group.
			# COLOR_BOMB can't be triggered this way — it fires via swap only.
			var existing_special: Tile = null
			for t: Tile in valid:
				if t.special_type != Tile.SPECIAL_NONE and \
				   t.special_type != Tile.SPECIAL_COLOR_BOMB:
					existing_special = t
					break

			if existing_special != null:
				# Fire the existing special — remove the whole group then chain-detonate.
				score += valid.size() * 10 * existing_special.level * multiplier
				for t in valid:
					if not removed_set.has(t):
						removed_set[t] = true
						board[t.row][t.col] = null
						to_remove.append(t)
				detonate_queue.append(existing_special)

			elif valid.size() < 4 or shape == Tile.SPECIAL_NONE:
				# Plain 3-match: remove all, no survivor, no special created.
				score += valid.size() * 10 * valid[0].level * multiplier
				for t in valid:
					if not removed_set.has(t):
						removed_set[t] = true
						board[t.row][t.col] = null
						to_remove.append(t)

			else:
				# 4+ match: remove all but one survivor, upgrade 1 tier, stamp special.
				var survivor: Tile = null
				for t in last_swapped_tiles:
					if valid.has(t):
						survivor = t
						break
				if survivor == null:
					survivor = valid[0]

				var new_level: int = min(survivor.level + 1, 6)
				score += valid.size() * 10 * survivor.level * multiplier
				upgrades.append([survivor, new_level, shape])

				for t in valid:
					if t != survivor and not removed_set.has(t):
						removed_set[t] = true
						board[t.row][t.col] = null
						to_remove.append(t)

		# --- Chain detonation BFS ---
		while not detonate_queue.is_empty():
			var sp: Tile = detonate_queue.pop_front()
			if not is_instance_valid(sp):
				continue

			# Record type before anything is freed.
			if sp.special_type == Tile.SPECIAL_BOMB:
				had_bomb_det = true
			elif sp.special_type == Tile.SPECIAL_CROSS:
				had_cross_det = true

			for t: Tile in _collect_special_zone(sp):
				if not removed_set.has(t):
					removed_set[t] = true
					board[t.row][t.col] = null
					to_remove.append(t)
					score += 10 * t.level * multiplier
					# Chain BOMB/CROSS; COLOR_BOMB is just silently removed.
					if t.special_type == Tile.SPECIAL_BOMB or \
					   t.special_type == Tile.SPECIAL_CROSS:
						detonate_queue.append(t)

		# Combo announcement from cascade 2 onward.
		if any_match and cascade >= 2:
			_show_combo(cascade)
			var note_idx: int = clamp(cascade - 2, 0, sfx_notes.size() - 1)
			_play_sfx(sfx_notes[note_idx])

		# 1. Scale matched tiles to zero then free them.
		if to_remove.size() > 0:
			_play_sfx(sfx_match)
			var tw := create_tween()
			tw.set_parallel(true)
			for t in to_remove:
				tw.tween_property(t, "scale", Vector2.ZERO, 0.15) \
					.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			await tw.finished
			for t in to_remove:
				if is_instance_valid(t):
					t.queue_free()

			# Screen shake based on what detonated.
			if had_bomb_det:
				_play_sfx(sfx_explosion)
				await _shake_board()
			elif had_cross_det:
				_play_sfx(sfx_lightning)
				await _shake_board_faint()

		# 2. Apply upgrades + pop animation.
		var live_upgrades: Array = []
		for entry in upgrades:
			if is_instance_valid(entry[0]) and not removed_set.has(entry[0]):
				entry[0].set_level(entry[1])
				entry[0].set_special(entry[2])
				live_upgrades.append(entry[0])
		if live_upgrades.size() > 0:
			var tw2 := create_tween()
			tw2.set_parallel(true)
			for t in live_upgrades:
				tw2.tween_property(t, "scale", Vector2(1.35, 1.35), 0.1) \
					.set_trans(Tween.TRANS_QUAD)
			await tw2.finished
			var tw3 := create_tween()
			tw3.set_parallel(true)
			for t in live_upgrades:
				tw3.tween_property(t, "scale", Vector2.ONE, 0.1) \
					.set_trans(Tween.TRANS_QUAD)
			await tw3.finished

		last_swapped_tiles = []

		# 3. Collapse + fill.
		await _animate_collapse()
		await _animate_fill()

		update_score_display()
		groups = _find_matches()

	_check_for_shuffle()


# ----- Special gem zone collectors ------------------------------------------

# Returns every board tile in the detonation zone of a BOMB or CROSS gem.
# The special tile itself is included so it gets freed along with the blast.
func _collect_special_zone(sp: Tile) -> Array:
	var zone: Array = []
	if sp.special_type == Tile.SPECIAL_BOMB:
		for dr in range(-1, 2):
			for dc in range(-1, 2):
				var nr: int = sp.row + dr
				var nc: int = sp.col + dc
				if nr < 0 or nr >= board_rows or nc < 0 or nc >= board_cols:
					continue
				if SHAPE[nr][nc] == 0:
					continue
				var t = board[nr][nc]
				if t != null:
					zone.append(t)

	elif sp.special_type == Tile.SPECIAL_CROSS:
		for c in range(board_cols):
			if SHAPE[sp.row][c] == 1:
				var t = board[sp.row][c]
				if t != null:
					zone.append(t)
		for r in range(board_rows):
			if SHAPE[r][sp.col] == 1:
				var t = board[r][sp.col]
				if t != null and not zone.has(t):
					zone.append(t)

	return zone


# ----- COLOR_BOMB activation ------------------------------------------------

# Fired from _attempt_swap() when either swapped tile is a COLOR_BOMB.
# Destroys the bomb itself and every gem at target_level on the board.
func _fire_color_bomb(bomb: Tile, target_level: int) -> void:
	var to_remove: Array = []
	var removed_set       = {}

	if is_instance_valid(bomb):
		board[bomb.row][bomb.col] = null
		removed_set[bomb] = true
		to_remove.append(bomb)

	for r in range(board_rows):
		for c in range(board_cols):
			var t = board[r][c]
			if t != null and t.level == target_level and not removed_set.has(t):
				removed_set[t] = true
				board[r][c] = null
				to_remove.append(t)

	score += to_remove.size() * 10 * target_level
	_play_sfx(sfx_color_bomb)

	var tw := create_tween()
	tw.set_parallel(true)
	for t in to_remove:
		tw.tween_property(t, "scale", Vector2.ZERO, 0.22) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tw.finished
	for t in to_remove:
		if is_instance_valid(t):
			t.queue_free()

	await _shake_board()
	await _animate_collapse()
	await _animate_fill()
	update_score_display()

	var matches := _find_matches()
	if matches.size() > 0:
		await _resolve_matches_animated(matches)
	else:
		_check_for_shuffle()


# ----- Gravity & fill -------------------------------------------------------

func _animate_collapse() -> void:
	for c in range(board_cols):
		var col_tiles: Array = []
		for r in range(board_rows):
			if SHAPE[r][c] == 1:
				var t = board[r][c]
				if t != null:
					col_tiles.append(t)
				board[r][c] = null
		var idx: int = col_tiles.size() - 1
		for r in range(board_rows - 1, -1, -1):
			if SHAPE[r][c] == 1:
				if idx >= 0:
					var t = col_tiles[idx]
					board[r][c] = t
					t.row = r; t.col = c
					idx -= 1

	var any := false
	var tw := create_tween()
	tw.set_parallel(true)
	for r in range(board_rows):
		for c in range(board_cols):
			var tile = board[r][c]
			if tile == null:
				continue
			var target := _cell_pos(r, c)
			if tile.position.distance_to(target) > 0.5:
				tw.tween_property(tile, "position", target, 0.28) \
					.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
				any = true
	if any:
		await tw.finished
		_play_sfx(sfx_tink)
	else:
		tw.kill()


func _animate_fill() -> void:
	var any := false
	var tw := create_tween()
	tw.set_parallel(true)

	for c in range(board_cols):
		var empty_rows: Array = []
		for r in range(board_rows):
			if SHAPE[r][c] == 1 and board[r][c] == null:
				empty_rows.append(r)

		var n := empty_rows.size()
		for i in range(n):
			var r: int = empty_rows[i]
			var tile := TILE_SCENE.instantiate()
			tile.row = r; tile.col = c; tile.game = self
			board[r][c] = tile
			board_container.add_child(tile)
			tile.set_level(randi_range(1, 4))

			var target := _cell_pos(r, c)
			tile.position = Vector2(target.x, -(n - i) * float(cell_size))

			var fall_dist: float = target.y - tile.position.y
			var dur: float = 0.15 + fall_dist / (float(cell_size) * 10.0)
			tw.tween_property(tile, "position", target, dur) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			any = true

	if any:
		await tw.finished
		_play_sfx(sfx_tink)
	else:
		tw.kill()


# ----- Screen shake ---------------------------------------------------------

func _shake_board() -> void:
	var origin := board_container.position
	var tw := create_tween()
	tw.tween_property(board_container, "position", origin + Vector2(5, -3),  0.04)
	tw.tween_property(board_container, "position", origin + Vector2(-4, 4),  0.04)
	tw.tween_property(board_container, "position", origin + Vector2(3, -2),  0.04)
	tw.tween_property(board_container, "position", origin + Vector2(-2, 1),  0.04)
	tw.tween_property(board_container, "position", origin,                   0.06)
	await tw.finished


# Gentler shake for CROSS (lightning-bolt) detonation.
func _shake_board_faint() -> void:
	var origin := board_container.position
	var tw := create_tween()
	tw.tween_property(board_container, "position", origin + Vector2(3, -2),  0.05)
	tw.tween_property(board_container, "position", origin + Vector2(-2, 2),  0.05)
	tw.tween_property(board_container, "position", origin + Vector2(2, -1),  0.05)
	tw.tween_property(board_container, "position", origin + Vector2(-1, 1),  0.05)
	tw.tween_property(board_container, "position", origin,                   0.08)
	await tw.finished


func _cell_pos(r: int, c: int) -> Vector2:
	return Vector2(c * float(cell_size) + cell_size * 0.5,
				   r * float(cell_size) + cell_size * 0.5)


# ----- Match detection ------------------------------------------------------
#
# Returns Array of Dictionaries: { "tiles": Array[Tile], "shape": int }
# shape mirrors Tile.SPECIAL_* — NONE for a plain 3-match, BOMB for a 4-5
# straight run, CROSS for any T/L/+ merge, COLOR_BOMB for a 6+ straight run.

func _find_matches() -> Array:
	var raw_runs: Array = []

	# Horizontal runs of 3+.
	for r in range(board_rows):
		var c := 0
		while c < board_cols:
			var tile = board[r][c]
			if tile != null:
				var run: Array = [tile]
				var cc := c + 1
				while cc < board_cols:
					var t = board[r][cc]
					if t != null and t.level == tile.level:
						run.append(t); cc += 1
					else:
						break
				if run.size() >= 3:
					raw_runs.append(run)
				c = cc
			else:
				c += 1

	# Vertical runs of 3+.
	for c in range(board_cols):
		var r := 0
		while r < board_rows:
			var tile = board[r][c]
			if tile != null:
				var run: Array = [tile]
				var rr := r + 1
				while rr < board_rows:
					var t = board[rr][c]
					if t != null and t.level == tile.level:
						run.append(t); rr += 1
					else:
						break
				if run.size() >= 3:
					raw_runs.append(run)
				r = rr
			else:
				r += 1

	# Merge overlapping runs into groups, tracking how many runs merged.
	var groups: Array   = []   # Array of { "tiles": Array, "run_count": int }
	var tile_to_group   = {}

	for run in raw_runs:
		var overlapping: Array = []
		for t in run:
			if tile_to_group.has(t):
				var gi: int = tile_to_group[t]
				if not overlapping.has(gi):
					overlapping.append(gi)

		if overlapping.is_empty():
			var idx: int = groups.size()
			groups.append({ "tiles": run.duplicate(), "run_count": 1 })
			for t in run:
				tile_to_group[t] = idx
		else:
			var main_idx: int = overlapping[0]
			# Absorb every other overlapping group into main.
			for i in range(1, overlapping.size()):
				var other_idx: int = overlapping[i]
				groups[main_idx]["run_count"] += groups[other_idx]["run_count"]
				for t_in in groups[other_idx]["tiles"]:
					if not groups[main_idx]["tiles"].has(t_in):
						groups[main_idx]["tiles"].append(t_in)
					tile_to_group[t_in] = main_idx
				groups[other_idx] = {}   # mark absorbed
			# Add the current run.
			groups[main_idx]["run_count"] += 1
			for t in run:
				if not groups[main_idx]["tiles"].has(t):
					groups[main_idx]["tiles"].append(t)
				tile_to_group[t] = main_idx

	# Classify each surviving group by shape.
	var result: Array = []
	for g in groups:
		if g.is_empty():
			continue
		var tiles: Array   = g["tiles"]
		var run_count: int = g["run_count"]
		if tiles.size() < 3:
			continue

		var shape: int
		if run_count >= 2:
			shape = Tile.SPECIAL_CROSS       # T / L / + intersection
		elif tiles.size() >= 5:
			shape = Tile.SPECIAL_COLOR_BOMB  # long streak
		elif tiles.size() >= 4:
			shape = Tile.SPECIAL_BOMB        # short 4-5 line
		else:
			shape = Tile.SPECIAL_NONE        # plain 3-match

		result.append({ "tiles": tiles, "shape": shape })

	return result


# ----- Shuffle & move validation --------------------------------------------

func _has_possible_matches() -> bool:
	# A COLOR_BOMB can fire with any adjacent gem.
	for r in range(board_rows):
		for c in range(board_cols):
			var t = board[r][c]
			if t != null and t.special_type == Tile.SPECIAL_COLOR_BOMB:
				for dir in [Vector2(1,0), Vector2(-1,0), Vector2(0,1), Vector2(0,-1)]:
					var nr := r + int(dir.y)
					var nc := c + int(dir.x)
					if nr >= 0 and nr < board_rows and nc >= 0 and nc < board_cols:
						if SHAPE[nr][nc] == 1 and board[nr][nc] != null:
							return true

	for r in range(board_rows):
		for c in range(board_cols):
			var tile = board[r][c]
			if tile == null:
				continue
			for dir in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
				var nr := r + int(dir.y)
				var nc := c + int(dir.x)
				if nr < 0 or nr >= board_rows or nc < 0 or nc >= board_cols:
					continue
				if SHAPE[nr][nc] == 0:
					continue
				var other = board[nr][nc]
				if other == null:
					continue
				board[r][c] = other; board[nr][nc] = tile
				tile.row = nr; tile.col = nc
				other.row = r; other.col = c
				var found := _find_matches().size() > 0
				board[r][c] = tile; board[nr][nc] = other
				tile.row = r; tile.col = c
				other.row = nr; other.col = nc
				if found:
					return true
	return false


func _shuffle_board() -> void:
	var tiles: Array = []
	for r in range(board_rows):
		for c in range(board_cols):
			var t = board[r][c]
			if t != null:
				tiles.append(t)
			board[r][c] = null
	tiles.shuffle()
	var idx: int = 0
	for r in range(board_rows):
		for c in range(board_cols):
			if SHAPE[r][c] == 1:
				var t = tiles[idx]
				t.row = r; t.col = c
				board[r][c] = t
				idx += 1
	_update_all_tile_positions()


func _check_for_shuffle() -> void:
	var did_shuffle := false
	var attempts := 0
	while not _has_possible_matches():
		_shuffle_board()
		did_shuffle = true
		attempts += 1
		if attempts > 20:
			break
	if did_shuffle:
		_play_sfx(sfx_shuffle)
		if shuffle_label != null:
			shuffle_label.modulate.a = 1.0
			shuffle_label.visible = true
			var tw := create_tween()
			tw.tween_interval(1.2)
			tw.tween_property(shuffle_label, "modulate:a", 0.0, 0.5)
			tw.tween_callback(func(): shuffle_label.visible = false)


# ----- Combo label ----------------------------------------------------------

func _show_combo(cascade: int) -> void:
	if combo_label == null:
		return
	# Kill any in-progress combo animation before starting a fresh one.
	if _combo_tween != null and _combo_tween.is_valid():
		_combo_tween.kill()

	var idx: int = clamp(cascade - 2, 0, COMBO_WORDS.size() - 1)
	combo_label.text       = COMBO_WORDS[idx]
	combo_label.modulate.a = 1.0
	combo_label.z_index    = 999
	combo_label.scale      = Vector2(0.4, 0.4)
	combo_label.visible    = true

	_combo_tween = create_tween()
	_combo_tween.tween_property(combo_label, "scale", Vector2(1.1, 1.1), 0.18) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_combo_tween.tween_property(combo_label, "scale", Vector2.ONE, 0.08)
	_combo_tween.tween_interval(0.55)
	_combo_tween.tween_property(combo_label, "modulate:a", 0.0, 0.35)
	_combo_tween.tween_callback(func(): combo_label.visible = false)
	var voice_idx: int = mini(idx, sfx_voices.size() - 1)
	_play_sfx(sfx_voices[voice_idx])


# ----- Score display --------------------------------------------------------

func update_score_display() -> void:
	if score_label == null:
		return
	_check_milestone()
	if _score_tween != null and _score_tween.is_valid():
		_score_tween.kill()
	_score_tween = create_tween()
	_score_tween.tween_method(
		_set_displayed_score,
		float(_displayed_score),
		float(score),
		0.45
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _set_displayed_score(v: float) -> void:
	_displayed_score = int(v)
	if score_label:
		score_label.text = "Score: %d" % _displayed_score


func _check_milestone() -> void:
	if score >= _next_milestone:
		_flash_screen()
		while _next_milestone <= score:
			_next_milestone *= 10


func _flash_screen() -> void:
	if _flash_overlay == null:
		return
	if _flash_overlay.color.a > 0.01:
		return
	var tw := create_tween()
	tw.tween_property(_flash_overlay, "color:a", 0.28, 0.08)
	tw.tween_property(_flash_overlay, "color:a", 0.0,  0.55) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


# ----- Audio helpers --------------------------------------------------------

func _play_sfx(player: AudioStreamPlayer) -> void:
	if player != null and player.stream != null:
		player.play()


func _play_sfx_delayed(player: AudioStreamPlayer, delay: float) -> void:
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	_play_sfx(player)
