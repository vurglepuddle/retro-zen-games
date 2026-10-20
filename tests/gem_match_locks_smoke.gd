extends SceneTree
## Gem Match locked gems + idle-spin landing. Run with isolated APPDATA:
## .godot/gem_test_user (no saves are written; the guard keeps it honest).

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)


func _run() -> void:
	var isolated := ProjectSettings.globalize_path("res://.godot/gem_test_user/").replace("\\", "/")
	if not OS.get_user_data_dir().replace("\\", "/").begins_with(isolated):
		push_error("Use the isolated gem_test_user APPDATA directory.")
		quit(2)
		return
	_timeout()
	root.get_node("AudioManager")._audio_unlocked = true
	await _spin_lands_on_first_frame()
	await _locks()
	print("GEM LOCKS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _timeout() -> void:
	await create_timer(60.0).timeout
	push_error("Gem lock checks timed out.")
	quit(3)


# The idle spin must end exactly on frame 1 (index 0) after one turn, without
# flashing frame 2 first (the old 1.1 s timer overran the 1.0 s animation).
func _spin_lands_on_first_frame() -> void:
	var tile = load("res://games/gem_match/scenes/Tile.tscn").instantiate()
	root.add_child(tile)
	tile.set_level(3)
	await process_frame
	var anim: AnimatedSprite2D = tile.get_node("Tile")
	tile._idle_timer = 0.0
	var seen: Array = []
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 1400:
		await process_frame
		seen.append(anim.frame)
		if not tile._spinning and seen.size() > 5:
			break
	check(not tile._spinning, "Spin: idle spin ends after one turn")
	check(anim.frame == 0 and not anim.is_playing(), "Spin: rests on frame 1")
	var last13 := seen.rfind(13)
	check(last13 >= 0, "Spin: the turn reaches the last frame")
	var after := seen.slice(last13 + 1)
	check(not after.has(1), "Spin: no frame-2 flash after the last frame (saw %s)" % [after])
	# 6_red does not loop: it must also come back to frame 1.
	tile.set_level(6)
	tile._idle_timer = 0.0
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 1800:
		await process_frame
		if not tile._spinning and Time.get_ticks_msec() - t0 > 200:
			break
	check(not tile._spinning and anim.frame == 0, "Spin: non-looping 6_red returns to frame 1")
	tile.queue_free()
	await process_frame


func _count_fx(game, anim_name: StringName) -> int:
	var n := 0
	var layer = game._fx_layer()
	for child in layer.get_children():
		if child is AnimatedSprite2D and child.animation == anim_name:
			n += 1
	return n


func _flat_board(game) -> void:
	# No three-in-a-row anywhere: horizontal neighbours differ by 1, vertical by 2.
	for r in range(game.board_rows):
		for c in range(game.board_cols):
			var t = game.board[r][c]
			if t == null:
				continue
			t.set_level((2 * r + c) % 6 + 1)
			t.set_locked(false)
	game._pending_unlocks.clear()


func _locks() -> void:
	# Tier order: ... topaz -> teal star -> heart -> sun (max). Suns never spawn.
	check(Tile.ANIM_NAMES[5] == "7_star" and Tile.ANIM_NAMES[6] == "4_pink" and Tile.ANIM_NAMES[7] == "2_yellow",
		"Tiers: teal star -> heart -> sun at the top")
	seed(4242)
	var game = load("res://games/gem_match/scenes/Game.tscn").instantiate()
	root.add_child(game)
	game.prepare_board()
	var suns := 0
	for r in range(game.board_rows):
		for c in range(game.board_cols):
			if game.board[r][c] != null and game.board[r][c].level == 7:
				suns += 1
	check(suns == 0, "Tiers: a new board has no suns (they come only from upgrades)")
	check(game._count_locked() == game.LOCK_START_COUNT, "Locks: a new board starts with %d locked gems" % game.LOCK_START_COUNT)
	var lock_sprites := 0
	for r in range(game.board_rows):
		for c in range(game.board_cols):
			var t = game.board[r][c]
			if t != null and t.locked and t._lock_sprite != null and t._lock_sprite.visible:
				lock_sprites += 1
	check(lock_sprites == game.LOCK_START_COUNT, "Locks: every locked gem shows the padlock overlay")
	await game.start_game()
	check(game._game_active, "Locks: game starts with locks on the board")
	check(game._count_locked() == game.LOCK_START_COUNT, "Locks: start shuffle keeps the lock count")

	# A. A locked gem cannot be swapped (either side of the swap).
	_flat_board(game)
	var a = game.board[5][3]
	var b = game.board[5][4]
	a.set_locked(true)
	game._attempt_swap(a, Vector2(1, 0))
	check(game.board[5][3] == a and game.board[5][4] == b and not game._busy, "Locks: dragging a locked gem does nothing")
	game._attempt_swap(b, Vector2(-1, 0))
	check(game.board[5][3] == a and game.board[5][4] == b and not game._busy, "Locks: dragging onto a locked gem does nothing")
	check(game.score == 0, "Locks: refused swaps score nothing")

	# B. A locked gem never matches and breaks runs; unlocked it matches again.
	_flat_board(game)
	for c in [2, 3, 4]:
		game.board[5][c].set_level(6)
	game.board[5][3].set_locked(true)
	check(game._find_matches().is_empty(), "Locks: a locked gem breaks a run of three")
	game.board[5][3].set_locked(false)
	check(game._find_matches().size() == 1, "Locks: once unlocked the same gem completes the run")

	# C. A match right beside a locked gem breaks its lock; the gem survives.
	_flat_board(game)
	for c in [1, 2, 3]:
		game.board[8][c].set_level(5)
	var beside = game.board[7][2]        # above the middle of the match
	var diagonal = game.board[7][4]      # diagonal neighbour of the run's end: stays locked
	beside.set_level(1)
	beside.set_locked(true)
	diagonal.set_locked(true)
	game._game_active = false            # stop after collapse, before the random refill
	await game._resolve_matches_animated(game._find_matches())
	check(is_instance_valid(beside) and not beside.locked, "Locks: matching beside a locked gem unlocks it")
	check(is_instance_valid(beside) and beside.row == 8 and beside.col == 2, "Locks: the unlocked gem stays and falls with gravity")
	check(is_instance_valid(diagonal) and diagonal.locked, "Locks: only orthogonal neighbours of a match unlock")
	await create_timer(0.6).timeout
	check(is_instance_valid(beside) and not beside._lock_sprite.visible, "Locks: the break animation hides the padlock")

	# D. A bomb blast breaks a lock in its 3x3 zone instead of destroying the gem.
	game.prepare_board()
	await game.start_game()
	_flat_board(game)
	for c in [1, 2, 3]:
		game.board[3][c].set_level(4)
	game.board[3][3].set_special(Tile.SPECIAL_BOMB)
	var in_blast = game.board[4][4]
	in_blast.set_locked(true)
	var outside = game.board[6][6]
	outside.set_locked(true)
	game._game_active = false
	await game._resolve_matches_animated(game._find_matches())
	check(is_instance_valid(in_blast) and not in_blast.locked, "Locks: a bomb blast unlocks a locked gem in range")
	check(is_instance_valid(outside) and outside.locked, "Locks: gems outside the blast stay locked")
	var embers := 0
	for n in game.board_container.get_children():
		if n is AnimatedSprite2D and n.animation == &"ember_linger":
			embers += 1
	check(embers > 0, "FX: a bomb leaves embers smouldering on the board")

	# D2. A match close by (not touching) startles a padlock; it stays locked.
	game.prepare_board()                 # D stopped before the refill: start from a full board
	await game.start_game()
	_flat_board(game)
	var near_lock = game.board[2][2]
	near_lock.set_locked(true)
	game._flinch_locks_near([game.board[4][3]])        # two rows away
	await create_timer(0.05).timeout
	check(near_lock.locked and near_lock._lock_sprite.position.y < -0.5, "FX: a nearby match makes the padlock flinch")
	var far_lock = game.board[9][6]
	far_lock.set_locked(true)
	game._flinch_locks_near([game.board[4][3]])
	await create_timer(0.05).timeout
	check(is_equal_approx(far_lock._lock_sprite.position.y, 0.0), "FX: distant matches leave padlocks alone")

	# D3. The moon sheds a star toward a neighbour while the board is idle.
	game._game_active = true
	game._busy = false
	var moon_tile = game.board[5][3]
	moon_tile.set_special(Tile.SPECIAL_COLOR_BOMB)
	var before := _count_fx(game, &"twinkle")
	game.moon_star_drift(moon_tile)
	check(_count_fx(game, &"twinkle") == before + 1, "FX: the moon sheds a drifting star")
	game._busy = true
	game.moon_star_drift(moon_tile)
	check(_count_fx(game, &"twinkle") == before + 1, "FX: no star drift while the board is busy")
	game._busy = false

	# E. A colour bomb's level clear unlocks locked gems of that level.
	game.prepare_board()
	await game.start_game()
	_flat_board(game)
	var bomb = game.board[0][0]
	bomb.set_special(Tile.SPECIAL_COLOR_BOMB)
	var target_level: int = game.board[5][2].level
	var locked_same = game.board[5][2]
	locked_same.set_locked(true)
	var freed_same = null
	for r in range(game.board_rows):
		for c in range(game.board_cols):
			var t = game.board[r][c]
			if t != null and t != locked_same and t != bomb and t.level == target_level:
				freed_same = t
	game._game_active = false
	await game._fire_color_bomb_level_clear(bomb, target_level)
	await process_frame
	check(is_instance_valid(locked_same) and not locked_same.locked, "Locks: colour bomb unlocks same-level locked gems")
	check(freed_same == null or not is_instance_valid(freed_same), "Locks: colour bomb still clears unlocked same-level gems")

	# F. Refill never exceeds the lock cap; hints never point at a locked gem.
	game.prepare_board()
	await game.start_game()
	var cap: int = game._lock_cap()
	var n := 0
	for r in range(game.board_rows):
		for c in range(game.board_cols):
			var t = game.board[r][c]
			if t != null and not t.locked and n < cap - game._count_locked():
				t.set_locked(true); n += 1
	for c in range(game.board_cols):
		var t = game.board[0][c]
		if t != null and not t.locked:
			t.queue_free()
			game.board[0][c] = null
	await game._animate_fill()
	check(game._count_locked() <= cap, "Locks: refill respects the lock cap (%d)" % cap)
	var pair: Array = game._find_hint_pair()
	check(pair.is_empty() or (not pair[0].locked and not pair[1].locked), "Locks: hints never use a locked gem")

	game.stop_game()
	game.queue_free()
	await process_frame
