#Game.gd
extends Node2D

signal back_to_menu

const TILE_SCENE = preload("res://games/gem_match/scenes/Tile.tscn")

# Octagonal board (10 rows x 7 cols). 0 = empty cell, 1 = valid cell.
const SHAPE := [
	[0,1,1,1,1,1,0],
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

# Delay (seconds) before the fall SFX fires at game start — adjust in the
# inspector so the sound lands at the right moment for your audio clip.
@export_range(0.0, 2.0, 0.01)
var sfx_fall_delay: float = 0.03

var board_rows: int = SHAPE.size()
var board_cols: int = SHAPE[0].size()
var board: Array = []
var score: int = 0
var last_swapped_tiles: Array = []
# Tile that was upgraded to a star via a 5+ blue-gem match; detonates after landing.
var _charged_star = null

# True while any animation is running. Input is ignored during this time.
var _busy := false
var _drag_tile = null
var _drag_start := Vector2.ZERO

# Animated score counter — tweens the displayed number toward the real score.
var _displayed_score: int = 0
var _score_tween: Tween = null

# Combo announcer word list — index 0 fires on cascade 2, index 6 on cascade 8+.
const COMBO_WORDS := [
	"GOOD!", "EXCELLENT!", "AWESOME!",
	"SPECTACULAR!", "EXTRAORDINARY!", "UNBELIEVABLE!", "INCONCEIVABLE!"
]

# Hint system — after HINT_DELAY seconds of no input, pulse a valid swap pair.
const HINT_DELAY := 5.0
var _hint_timer: float = 0.0
var _hint_tiles: Array = []   # [tile_a, tile_b] currently hinting

# Guards _process so hints don't fire before start_game() is called.
var _game_active: bool = false

# Score milestone flash overlay (created in _ready).
var _flash_overlay: ColorRect = null
var _next_milestone: int = 1000

@onready var board_container: Node2D = $Board
@onready var score_label: Label = $ScoreLabel
@onready var shuffle_label: Label = $ShuffleLabel
@onready var combo_label: Label = $ComboLabel
@onready var back_button: Button = $BackButton

# Sound placeholder nodes — drop audio files in later without touching code.
@onready var sfx_swap: AudioStreamPlayer = $SfxSwap
@onready var sfx_match: AudioStreamPlayer = $SfxMatch
@onready var sfx_no_match: AudioStreamPlayer = $SfxNoMatch
@onready var sfx_shuffle: AudioStreamPlayer = $SfxShuffle
@onready var sfx_fall: AudioStreamPlayer = $SfxFall
@onready var sfx_explosion: AudioStreamPlayer = $SfxExplosion

# Ascending combo notes — note_1 fires on x2, note_2 on x3, … note_7 on x8+.
@onready var sfx_notes: Array = [
	$SfxNote1, $SfxNote2, $SfxNote3, $SfxNote4,
	$SfxNote5, $SfxNote6, $SfxNote7
]

# Voice announcer — one clip per combo word; assign MP3s in the inspector.
@onready var sfx_voices: Array = [
	$SfxVoiceGood, $SfxVoiceExcellent, $SfxVoiceAwesome,
	$SfxVoiceSpectacular, $SfxVoiceExtraordinary, $SfxVoiceUnbelievable, $SfxVoiceInconceivable
]


# ----- Setup ----------------------------------------------------------------

func _ready() -> void:
	# Build a full-screen flash overlay above everything else.
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	_flash_overlay = ColorRect.new()
	_flash_overlay.color = Color(1.0, 0.92, 0.4, 0.0)   # warm gold, fully transparent
	_flash_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_flash_overlay)

	back_button.pressed.connect(_go_back_to_menu)


# Called synchronously before the scene fade-in so the board background is
# visible but all gems are hidden — entrance animation reveals them.
func prepare_board() -> void:
	_game_active = false
	_next_milestone = 1000
	_busy = false
	_drag_tile = null
	_charged_star = null
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
	# Hide every tile — they reveal themselves during the entrance animation.
	for r in range(board_rows):
		for c in range(board_cols):
			if board[r][c] != null:
				board[r][c].modulate.a = 0.0


# Called after the fade-in completes; animates gems falling in, then activates.
func start_game() -> void:
	_play_sfx_delayed(sfx_fall, sfx_fall_delay)   # runs in background, doesn't block
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
				tile.row = r
				tile.col = c
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
	var vp := get_viewport_rect().size
	var board_w := board_cols * float(cell_size)
	var board_h := board_rows * float(cell_size)
	var ui_top := 70.0   # space reserved for the score label
	var margin := 10.0

	# Scale the entire board container so tiles fit within the viewport.
	var scale_x := (vp.x - margin * 2.0) / board_w
	var scale_y := (vp.y - ui_top - margin) / board_h
	var s: float = min(scale_x, scale_y)
	s = clamp(s, 0.1, 1.5)

	board_container.scale = Vector2(s, s)
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


# Gems fall in one column at a time, early tiles drifting slowly, later tiles
# zipping in — giving that "first slow, then faster" cascade feel.
func _animate_board_entrance() -> void:
	# Column-major order produces a left→right sweep across the board.
	var all_tiles: Array = []
	for c in range(board_cols):
		for r in range(board_rows):
			var t = board[r][c]
			if t != null:
				all_tiles.append(t)

	var n := all_tiles.size()
	if n == 0:
		return

	# Park every tile above the visible board at a randomised height.
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
		var progress := float(i) / float(max(n - 1, 1))   # 0 → 1

		# Stagger gap shrinks over time → creates the "building speed" sensation.
		cumulative_delay += lerp(0.035, 0.007, progress) + randf_range(-0.003, 0.003)

		# Fall duration: first tiles drift in, last ones zip past.
		var dur: float = lerpf(0.60, 0.20, progress) + randf_range(-0.05, 0.07)
		dur = clampf(dur, 0.15, 0.80)

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
	# Android back gesture / Escape key → return to menu.
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
	# Any touch resets the hint countdown.
	_hint_timer = 0.0
	_stop_hints()
	_drag_tile = tile
	_drag_start = press_pos


func _input(event: InputEvent) -> void:
	# Reset hint timer on any touch / click.
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
	# Scan the board for the first swap that produces a match.
	# Only check right + down to avoid duplicate pairs.
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
				# Temporarily swap to test.
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

	# Save visual positions before any change.
	var p1: Vector2 = tile.position
	var p2: Vector2 = other.position

	# Apply logical swap so row/col are correct, then animate visually.
	_swap_logic(tile, other)
	await _tween_two(tile, p2, other, p1, 0.15)

	last_swapped_tiles = [tile, other]
	var matches := _find_matches()

	if matches.size() == 0:
		# No match — slide both tiles back.
		_play_sfx(sfx_no_match)
		await _tween_two(tile, p1, other, p2, 0.15)
		_swap_logic(tile, other)
		last_swapped_tiles = []
	else:
		_play_sfx(sfx_swap)
		await _resolve_matches_animated(matches)

	_busy = false


# Swap board array and row/col without touching visual position.
func _swap_logic(t1, t2) -> void:
	var r1 = t1.row; var c1 = t1.col
	var r2 = t2.row; var c2 = t2.col
	board[r1][c1] = t2
	board[r2][c2] = t1
	t1.row = r2; t1.col = c2
	t2.row = r1; t2.col = c1


# Tween two tiles to target positions simultaneously.
func _tween_two(a, pa: Vector2, b, pb: Vector2, dur: float) -> void:
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(a, "position", pa, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(b, "position", pb, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	await tw.finished


# ----- Match resolution (animated) -----------------------------------------

func _resolve_matches_animated(initial_groups: Array) -> void:
	var groups := initial_groups
	var cascade := 0   # increments each wave; drives the combo multiplier

	while groups.size() > 0:
		cascade += 1
		var multiplier := cascade

		var to_remove: Array = []
		var removed_set := {}   # tile → true, prevents double-removal
		var upgrades: Array = []   # [[tile, new_level], ...]
		var any_match := false
		var had_lv6 := false

		for group in groups:
			# Skip tiles already consumed by an earlier group this pass.
			var valid: Array = []
			for t in group:
				if not removed_set.has(t):
					valid.append(t)
			if valid.size() < 3:
				continue

			any_match = true

			# ---- Level-6 special: clears the full 3×3 area around each gem ----
			var is_lv6 := true
			for t in valid:
				if t.level != 6:
					is_lv6 = false
					break

			if is_lv6:
				had_lv6 = true
				score += valid.size() * 10 * 6 * multiplier
				for t in valid:
					for dr in range(-1, 2):
						for dc in range(-1, 2):
							var nr: int = t.row + dr
							var nc: int = t.col + dc
							if nr < 0 or nr >= board_rows or nc < 0 or nc >= board_cols:
								continue
							var nearby = board[nr][nc]
							if nearby != null and not removed_set.has(nearby):
								removed_set[nearby] = true
								board[nearby.row][nearby.col] = null
								to_remove.append(nearby)
			else:
				# ---- Normal match: remove all but one, upgrade the survivor ----
				var up = null
				for t in last_swapped_tiles:
					if valid.has(t):
						up = t
						break
				if up == null:
					up = valid[0]

				# 5+ gems jump 2 tiers; 3-4 gems jump 1. Cap at level 6 (star).
				var tier_bonus := 2 if valid.size() >= 5 else 1
				var new_level: int = min(up.level + tier_bonus, 6)

				score += valid.size() * 10 * up.level * multiplier
				upgrades.append([up, new_level])

				# 5+ blue (lv5) gems → charged star: detonates 3×3 after landing.
				if valid.size() >= 5 and _charged_star == null:
					var all_blue := true
					for t in valid:
						if t.level != 5:
							all_blue = false
							break
					if all_blue:
						_charged_star = up

				for t in valid:
					if t != up and not removed_set.has(t):
						removed_set[t] = true
						board[t.row][t.col] = null
						to_remove.append(t)

		# From x2 onward: pop the combo label and play an ascending note.
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
				t.queue_free()
			if had_lv6:
				await _shake_board()

		# 2. Apply upgrade + pop animation.
		# Pre-filter: skip tiles that were swept into a level-6 blast this wave.
		var live_upgrades: Array = []
		for entry in upgrades:
			if is_instance_valid(entry[0]) and not removed_set.has(entry[0]):
				entry[0].set_level(entry[1])
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

		# 3. Collapse — tiles fall to fill gaps.
		await _animate_collapse()

		# 3b. Charged star: let it settle, then detonate 3×3 and re-collapse.
		if _charged_star != null:
			if is_instance_valid(_charged_star):
				await _explode_charged_star()
				await _animate_collapse()
			_charged_star = null

		# 4. Fill — new tiles fall in from above.
		await _animate_fill()

		update_score_display()
		groups = _find_matches()

	_check_for_shuffle()


# Gravity collapse with fall animation.
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
	else:
		tw.kill()


# Spawn new tiles above the board and animate them falling in.
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
	else:
		tw.kill()


func _shake_board() -> void:
	var origin := board_container.position
	var tw := create_tween()
	tw.tween_property(board_container, "position", origin + Vector2(5, -3), 0.04)
	tw.tween_property(board_container, "position", origin + Vector2(-4, 4), 0.04)
	tw.tween_property(board_container, "position", origin + Vector2(3, -2), 0.04)
	tw.tween_property(board_container, "position", origin + Vector2(-2, 1), 0.04)
	tw.tween_property(board_container, "position", origin, 0.06)
	await tw.finished


# Returns the local position inside board_container for a given cell.
func _cell_pos(r: int, c: int) -> Vector2:
	return Vector2(c * float(cell_size) + cell_size * 0.5,
				   r * float(cell_size) + cell_size * 0.5)


# ----- Match detection ------------------------------------------------------

func _find_matches() -> Array:
	var groups: Array = []
	# Horizontal runs
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
					groups.append(run)
				c = cc
			else:
				c += 1
	# Vertical runs
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
					groups.append(run)
				r = rr
			else:
				r += 1
	# Merge groups that share a tile (L-shapes, crosses, etc.)
	var final_groups: Array = []
	var tile_to_group := {}
	for group in groups:
		var indices: Array = []
		for t in group:
			if tile_to_group.has(t):
				var gi: int = tile_to_group[t]
				if not indices.has(gi):
					indices.append(gi)
		if indices.size() == 0:
			var idx: int = final_groups.size()
			final_groups.append(group.duplicate())
			for t in group:
				tile_to_group[t] = idx
		else:
			var main_idx: int = indices[0]
			for i in indices:
				if i != main_idx:
					for t_in in final_groups[i]:
						if not final_groups[main_idx].has(t_in):
							final_groups[main_idx].append(t_in)
						tile_to_group[t_in] = main_idx
					final_groups[i] = []
			for t in group:
				if not final_groups[main_idx].has(t):
					final_groups[main_idx].append(t)
				tile_to_group[t] = main_idx
	var cleaned: Array = []
	for group in final_groups:
		var uniq: Array = []
		var seen := {}
		for t in group:
			if not seen.has(t):
				uniq.append(t); seen[t] = true
		if uniq.size() >= 3:
			cleaned.append(uniq)
	return cleaned


# ----- Shuffle & move validation --------------------------------------------

func _has_possible_matches() -> bool:
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
	var idx: int = clamp(cascade - 2, 0, COMBO_WORDS.size() - 1)
	combo_label.text = COMBO_WORDS[idx]
	combo_label.modulate.a = 1.0
	combo_label.z_index = 999
	combo_label.scale = Vector2(0.4, 0.4)
	combo_label.visible = true
	var tw := create_tween()
	tw.tween_property(combo_label, "scale", Vector2(1.1, 1.1), 0.18) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(combo_label, "scale", Vector2.ONE, 0.08)
	tw.tween_interval(0.45)
	tw.tween_property(combo_label, "modulate:a", 0.0, 0.3)
	tw.tween_callback(func(): combo_label.visible = false)
	# Voice announcer — plays on top of the note ping.
	_play_sfx(sfx_voices[idx])


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


# ----- Score milestones -----------------------------------------------------

func _check_milestone() -> void:
	if score >= _next_milestone:
		_flash_screen()
		while _next_milestone <= score:
			_next_milestone *= 10


func _flash_screen() -> void:
	if _flash_overlay == null:
		return
	# Don't interrupt an in-progress flash.
	if _flash_overlay.color.a > 0.01:
		return
	var tw := create_tween()
	tw.tween_property(_flash_overlay, "color:a", 0.28, 0.08)
	tw.tween_property(_flash_overlay, "color:a", 0.0, 0.55) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


# ----- Charged-star explosion -----------------------------------------------

# Called after the star (produced from a 5+ blue-gem match) has settled into
# its board position via gravity.  Pulses briefly, then blasts the 3×3 zone.
func _explode_charged_star() -> void:
	var star = _charged_star
	_charged_star = null
	if not is_instance_valid(star):
		return

	# Wind-up pulse to telegraph the blast.
	var tw_pre := create_tween()
	tw_pre.tween_property(star, "scale", Vector2(1.55, 1.55), 0.18) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tw_pre.finished

	# Collect every tile in the 3×3 blast zone (the star itself included).
	var to_remove: Array = []
	for dr in range(-1, 2):
		for dc in range(-1, 2):
			var nr: int = star.row + dr
			var nc: int = star.col + dc
			if nr < 0 or nr >= board_rows or nc < 0 or nc >= board_cols:
				continue
			if SHAPE[nr][nc] == 0:
				continue
			var t = board[nr][nc]
			if t != null:
				board[nr][nc] = null
				to_remove.append(t)

	score += to_remove.size() * 10 * 6

	# Animate the blast.
	_play_sfx(sfx_explosion)
	var tw := create_tween()
	tw.set_parallel(true)
	for t in to_remove:
		tw.tween_property(t, "scale", Vector2.ZERO, 0.22) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tw.finished
	for t in to_remove:
		t.queue_free()

	await _shake_board()
	update_score_display()


# ----- Audio helpers --------------------------------------------------------

func _play_sfx(player: AudioStreamPlayer) -> void:
	if player != null and player.stream != null:
		player.play()


# Fires a sound after an optional delay without blocking the caller.
func _play_sfx_delayed(player: AudioStreamPlayer, delay: float) -> void:
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	_play_sfx(player)
