#Game.gd
extends Node2D

var _game_generation: int = 0
var _operation_tweens: Array[Tween] = []

const _SaveFile = preload("res://scripts/SafeConfig.gd")

signal back_to_menu
signal play_again

const TILE_SCENE = preload("res://games/gem_match/scenes/Tile.tscn")
const SHOCKWAVE_SHADER = preload("res://games/gem_match/assets/shockwave.gdshader")

# Octagonal board (11 rows x 7 cols). 0 = empty cell, 1 = valid cell.
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

const TIMED_DURATION      := 90.0
const TIME_BONUS_CHANCE   := 0.06   # timed mode: chance a new gem carries +5..10 s
const TIMED_SAVE_PATH     := "user://gem_match_save.cfg"
const LEVEL_BASE_TARGET   := 1000   # score to beat level 1
const LEVEL_TARGET_SCALE  := 1.3    # each level needs 30% more than the last
const LEVEL_TIME_BONUS    := 5.0    # seconds granted on each level-up

# Locked gems: can't be swapped or matched. A match beside one (up/down/left/
# right) or any special blast that reaches it breaks the lock; the gem stays.
const LOCK_START_COUNT    := 4      # locked gems on a new board
const LOCK_SPAWN_CHANCE   := 0.035  # chance a falling replacement gem arrives locked
const LOCK_MAX_ON_BOARD   := 8      # no new locks while this many are on the board
const LOCK_LEVEL_BONUS    := 1      # level mode: +1 allowed lock per level reached
const LOCK_MAX_CAP        := 14
var _pending_unlocks: Dictionary = {}

# Hint system — after HINT_DELAY seconds of no input, pulse a valid swap pair.
const HINT_DELAY := 5.0
var _hint_timer: float = 0.0
var _hint_tiles: Array = []

var _game_active: bool = false

var _timed_mode:       bool  = false
var _time_remaining:   float = 0.0
var _timer_label:      Label = null
var _game_over_panel:  Control = null
var _go_title_label:   Label = null
var _go_level_label:   Label = null
var _go_score_label:   Label = null
var _go_best_label:    Label = null

var _level_mode:        bool  = false
var _timed_level:       int   = 1
var _level_score_start: int   = 0
var _level_target:      int   = 0
var _leveling_up:       bool  = false
var _score_bar_bg:      ColorRect = null
var _score_bar_fill:    ColorRect = null
var _level_label:       Label = null

# Score milestone flash overlay.
var _flash_overlay: ColorRect = null
var _next_milestone: int = 1000

# Explosion FX: clipped layer for shockwaves, sparks and pixel-art FX sprites.
var _fx_clip: Control = null
var _dim_rect: ColorRect = null
const FX_FRAMES := preload("res://games/gem_match/assets/fx/fx_frames.tres")
const EMBER_TEXTURE := preload("res://games/gem_match/assets/fx/ember_4x.png")
const VOID_WAVE_LEAD := 0.25   # the moon's eclipse forms before its wave starts eating gems
# Shard/ring tint per gem tier (v3 colours, order of Tile.ANIM_NAMES):
# moonstone, emerald, sapphire, topaz, teal star, rose heart, citrine sun.
const GEM_FX_COLORS := [
	Color("c2cef4"), Color("5cd84b"), Color("4a95ff"), Color("ff962c"),
	Color("77ebdf"), Color("ff8ab6"), Color("ffd43c"),
]

@onready var board_container: Node2D = $Board
@onready var score_label: Label      = $ScoreLabel
@onready var shuffle_label: Label    = $ShuffleLabel
@onready var combo_label: Label      = $ComboLabel
@onready var back_button: TextureButton = $Back_Button
@onready var _bg:     Sprite2D = $Bg
@onready var _bg_top: Sprite2D = $BgTop

@onready var sfx_swap:      AudioStreamPlayer = $SfxSwap
@onready var sfx_match:     AudioStreamPlayer = $SfxMatch
@onready var sfx_no_match:  AudioStreamPlayer = $SfxNoMatch
@onready var sfx_shuffle:   AudioStreamPlayer = $SfxShuffle
@onready var sfx_fall:      AudioStreamPlayer = $SfxFall
@onready var sfx_explosion: AudioStreamPlayer = $SfxExplosion
@onready var sfx_lightning:  AudioStreamPlayer = $SfxLightning
@onready var sfx_color_bomb: AudioStreamPlayer = $SfxColorBomb
@onready var sfx_tink:       AudioStreamPlayer = $SfxTink
@onready var sfx_click: AudioStreamPlayer = $SfxClick

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

	#back_button.pressed.connect(_go_back_to_menu)
	_build_timer_label()
	_build_score_bar()
	_build_game_over_panel()


func set_timed_mode(timed: bool) -> void:
	_timed_mode = timed
	_level_mode = false


func set_level_mode(level: bool) -> void:
	_level_mode = level
	_timed_mode = level  # level mode implies timed


func _build_timer_label() -> void:
	_timer_label = Label.new()
	_timer_label.visible = false
	_timer_label.z_index = 999
	var vp_w := get_viewport_rect().size.x
	_timer_label.position = Vector2(vp_w - 200.0, 4.0)
	_timer_label.size = Vector2(190.0, 48.0)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_timer_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	var font := load("res://assets/font/vetka.ttf") as FontFile
	_timer_label.add_theme_font_override("font", font)
	_timer_label.add_theme_font_size_override("font_size", 40)
	_timer_label.add_theme_color_override("font_color", Color(1, 0.945, 0.627))
	_timer_label.add_theme_color_override("font_outline_color", Color(0.22, 0.16, 0.15))
	_timer_label.add_theme_constant_override("outline_size", 5)
	add_child(_timer_label)


func _build_score_bar() -> void:
	var vp  := get_viewport_rect().size
	var bar_x := 20.0
	var bar_y := 56.0
	var bar_w := vp.x - 40.0
	var bar_h := 12.0
	var font  := load("res://assets/font/vetka.ttf") as FontFile

	# "Lv.N" label — top-left, shown only in level mode.
	_level_label = Label.new()
	_level_label.visible = false
	_level_label.z_index = 999
	_level_label.position = Vector2(10.0, 2.0)
	_level_label.size     = Vector2(180.0, 52.0)
	_level_label.add_theme_font_override("font", font)
	_level_label.add_theme_font_size_override("font_size", 36)
	_level_label.add_theme_color_override("font_color", Color(1, 0.945, 0.627))
	_level_label.add_theme_color_override("font_outline_color", Color(0.22, 0.16, 0.15))
	_level_label.add_theme_constant_override("outline_size", 4)
	add_child(_level_label)

	# Progress bar background.
	_score_bar_bg = ColorRect.new()
	_score_bar_bg.color        = Color(0.08, 0.08, 0.14, 0.75)
	_score_bar_bg.position     = Vector2(bar_x, bar_y)
	_score_bar_bg.size         = Vector2(bar_w, bar_h)
	_score_bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_score_bar_bg.visible      = false
	_score_bar_bg.z_index      = 998
	add_child(_score_bar_bg)

	# Progress bar fill.
	_score_bar_fill = ColorRect.new()
	_score_bar_fill.color        = Color(1.0, 0.82, 0.1, 0.92)
	_score_bar_fill.position     = Vector2(bar_x, bar_y)
	_score_bar_fill.size         = Vector2(0.0, bar_h)
	_score_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_score_bar_fill.visible      = false
	_score_bar_fill.z_index      = 999
	add_child(_score_bar_fill)


func _build_game_over_panel() -> void:
	var vp_size := get_viewport_rect().size
	_game_over_panel = Control.new()
	_game_over_panel.position = Vector2.ZERO
	_game_over_panel.size = vp_size
	_game_over_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_game_over_panel.visible = false
	_game_over_panel.z_index = 1100

	var bg := ColorRect.new()
	bg.color = Color(0.10, 0.08, 0.05, 0.80)
	bg.position = Vector2.ZERO
	bg.size = vp_size
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_game_over_panel.add_child(bg)
	var card := TextureRect.new()
	card.name = "ResultCard"
	card.texture = preload("res://games/gem_match/assets/ui/ui_pass/result_card.png")
	card.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	card.position = vp_size * 0.5 - Vector2(216.0, 282.0)
	card.size = Vector2(432.0, 564.0)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_game_over_panel.add_child(card)

	var vbox := VBoxContainer.new()
	vbox.name = "Content"
	var vp := get_viewport_rect().size
	vbox.position = Vector2(vp.x / 2.0 - 174.0, vp.y / 2.0 - 218.0)
	vbox.size = Vector2(348.0, 436.0)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 12)
	_game_over_panel.add_child(vbox)

	var font := load("res://assets/font/vetka.ttf") as FontFile

	_go_title_label = Label.new()
	_go_title_label.text = "TIME'S UP!"
	_go_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_go_title_label.add_theme_font_override("font", font)
	_go_title_label.add_theme_font_size_override("font_size", 58)
	_go_title_label.add_theme_color_override("font_color", Color("efcc54"))
	_go_title_label.add_theme_color_override("font_outline_color", Color(0.15, 0.1, 0.1))
	_go_title_label.add_theme_constant_override("outline_size", 2)
	vbox.add_child(_go_title_label)

	# Level reached — only visible in level mode.
	_go_level_label = Label.new()
	_go_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_go_level_label.add_theme_font_override("font", font)
	_go_level_label.add_theme_font_size_override("font_size", 38)
	_go_level_label.add_theme_color_override("font_color", Color(1, 0.945, 0.627))
	_go_level_label.add_theme_color_override("font_outline_color", Color(0.15, 0.1, 0.1))
	_go_level_label.add_theme_constant_override("outline_size", 2)
	_go_level_label.visible = false
	vbox.add_child(_go_level_label)

	_go_score_label = Label.new()
	_go_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_go_score_label.add_theme_font_override("font", font)
	_go_score_label.add_theme_font_size_override("font_size", 38)
	_go_score_label.add_theme_color_override("font_color", Color("fff1a0"))
	_go_score_label.add_theme_color_override("font_outline_color", Color(0.1, 0.1, 0.1))
	_go_score_label.add_theme_constant_override("outline_size", 2)
	vbox.add_child(_go_score_label)

	_go_best_label = Label.new()
	_go_best_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_go_best_label.add_theme_font_override("font", font)
	_go_best_label.add_theme_font_size_override("font_size", 34)
	_go_best_label.add_theme_color_override("font_color", Color(1, 0.945, 0.627))
	_go_best_label.add_theme_color_override("font_outline_color", Color(0.2, 0.15, 0.1))
	_go_best_label.add_theme_constant_override("outline_size", 2)
	vbox.add_child(_go_best_label)

	var btn_again := Button.new()
	btn_again.name = "PlayAgainButton"
	btn_again.text = "PLAY AGAIN"
	btn_again.theme = preload("res://games/gem_match/assets/ui/ui_pass/action_buttons.tres")
	btn_again.custom_minimum_size = Vector2(0, 80)
	btn_again.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	btn_again.add_theme_font_override("font", font)
	btn_again.add_theme_font_size_override("font_size", 40)
	btn_again.add_theme_color_override("font_color", Color(1, 0.945, 0.627))
	btn_again.add_theme_color_override("font_outline_color", Color(0.22, 0.16, 0.15))
	btn_again.add_theme_constant_override("outline_size", 2)
	btn_again.pressed.connect(func():
		if sfx_click and sfx_click.stream: sfx_click.play()
		_game_over_panel.visible = false
		play_again.emit()
	)
	vbox.add_child(btn_again)

	var btn_menu := Button.new()
	btn_menu.name = "MenuButton"
	btn_menu.text = "MENU"
	btn_menu.theme = preload("res://games/gem_match/assets/ui/ui_pass/action_buttons.tres")
	btn_menu.custom_minimum_size = Vector2(0, 80)
	btn_menu.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	btn_menu.add_theme_font_override("font", font)
	btn_menu.add_theme_font_size_override("font_size", 40)
	btn_menu.add_theme_color_override("font_color", Color(1, 0.945, 0.627))
	btn_menu.add_theme_color_override("font_outline_color", Color(0.22, 0.16, 0.15))
	btn_menu.add_theme_constant_override("outline_size", 2)
	btn_menu.pressed.connect(func():
		if sfx_click and sfx_click.stream: sfx_click.play()
		_game_over_panel.visible = false
		_go_back_to_menu()
	)
	vbox.add_child(btn_menu)

	add_child(_game_over_panel)


func back_button_pressed() -> void:
	if sfx_click.stream: sfx_click.play()
	_go_back_to_menu()




func prepare_board() -> void:
	stop_game()
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
	_time_remaining    = TIMED_DURATION
	_timed_level       = 1
	_leveling_up       = false
	_level_score_start = 0
	_level_target      = _level_target_for(1)
	if _timer_label:
		_timer_label.visible = _timed_mode
		_update_timer_display()
	if _level_label:
		_level_label.visible = _level_mode
		_update_level_label()
	if _score_bar_bg:
		_score_bar_bg.visible = _level_mode
	if _score_bar_fill:
		_score_bar_fill.visible = _level_mode
		_score_bar_fill.size.x  = 0.0
	if _game_over_panel:
		_game_over_panel.visible = false


func start_game() -> void:
	var generation := _game_generation
	_play_sfx_delayed(sfx_fall, sfx_fall_delay)
	await _animate_board_entrance()
	if generation != _game_generation:
		return
	await _check_for_shuffle()
	if generation != _game_generation:
		return
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
	_place_start_locks()


func _place_start_locks() -> void:
	var cells: Array = []
	for r in range(board_rows):
		for c in range(board_cols):
			if board[r][c] != null:
				cells.append(board[r][c])
	cells.shuffle()
	for i in range(mini(LOCK_START_COUNT, cells.size())):
		cells[i].set_locked(true)


func _lock_cap() -> int:
	var cap := LOCK_MAX_ON_BOARD
	if _level_mode:
		cap += (_timed_level - 1) * LOCK_LEVEL_BONUS
	return mini(cap, LOCK_MAX_CAP)


func _count_locked() -> int:
	var n := 0
	for r in range(board_rows):
		for c in range(board_cols):
			var t = board[r][c]
			if t != null and t.locked:
				n += 1
	return n


func _is_locked(t) -> bool:
	return t != null and is_instance_valid(t) and t.locked


# Breaks every lock queued in _pending_unlocks (from blasts and neighbouring
# matches). The gems stay on the board and can match from the next cascade.
func _apply_pending_unlocks() -> void:
	if _pending_unlocks.is_empty():
		return
	for t in _pending_unlocks.keys():
		if is_instance_valid(t) and t.locked:
			t.unlock_animated()
			_spawn_fx("shatter", t.position + Vector2(0, 6), 0.03, Color(0.82, 0.8, 0.9), randf() * TAU, 3)
			_spawn_fx("twinkle", t.position + Vector2(0, 14), 0.08, Color(1.0, 0.85, 0.35), 0.0, 4)
	_pending_unlocks.clear()
	_play_sfx(sfx_tink)


func _queue_unlocks_beside(tiles: Array) -> void:
	for t in tiles:
		if not is_instance_valid(t):
			continue
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nr: int = t.row + d.y
			var nc: int = t.col + d.x
			if nr < 0 or nr >= board_rows or nc < 0 or nc >= board_cols or SHAPE[nr][nc] == 0:
				continue
			var n = board[nr][nc]
			if _is_locked(n):
				_pending_unlocks[n] = true


func _pick_start_level(r: int, c: int) -> int:
	var candidates: Array = [1, 2, 3, 4, 5, 6]
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
	_bg.position     = Vector2(vp.x / 2.0, vp.y / 2.0)
	_bg_top.position = Vector2(vp.x / 2.0, _bg_top.position.y)


func _update_all_tile_positions() -> void:
	for r in range(board_rows):
		for c in range(board_cols):
			var tile = board[r][c]
			if tile != null:
				tile.row = r
				tile.col = c
				tile.update_position(Vector2(cell_size, cell_size))


func _animate_board_entrance() -> void:
	var generation := _game_generation
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

	var tw := _board_tween()
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
	if generation != _game_generation:
		return


# ----- Input ----------------------------------------------------------------

func _go_back_to_menu() -> void:
	stop_game()
	_game_active = false
	_stop_hints()
	for child in get_children():
		if child is AudioStreamPlayer and child != sfx_click:
			child.stop()
	back_to_menu.emit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _game_active:
		_go_back_to_menu()


func _process(delta: float) -> void:
	if not _game_active:
		return
	if _timed_mode:
		_time_remaining -= delta
		if _time_remaining <= 0.0:
			_time_remaining = 0.0
			_update_timer_display()
			_game_active = false
			_time_up()
			return
		_update_timer_display()
	if _busy:
		_hint_timer = 0.0
		if not _hint_tiles.is_empty():
			_stop_hints()
		return
	_hint_timer += delta
	if _hint_timer >= HINT_DELAY and _hint_tiles.is_empty():
		_start_hint()


func start_drag(tile, press_pos: Vector2) -> void:
	if not _game_active or _busy:
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
			for dir in [Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0), Vector2(0, -1)]:
				var nr := r + int(dir.y)
				var nc := c + int(dir.x)
				if nr < 0 or nr >= board_rows or nc < 0 or nc >= board_cols:
					continue
				if SHAPE[nr][nc] == 0:
					continue
				var adj = board[nr][nc]
				if adj != null and not adj.locked:
					return [t, adj]

	for r in range(board_rows):
		for c in range(board_cols):
			var tile = board[r][c]
			if tile == null or tile.locked:
				continue
			for dir in [Vector2(1, 0), Vector2(0, 1)]:
				var nr := r + int(dir.y)
				var nc := c + int(dir.x)
				if nr < 0 or nr >= board_rows or nc < 0 or nc >= board_cols:
					continue
				if SHAPE[nr][nc] == 0:
					continue
				var other = board[nr][nc]
				if other == null or other.locked:
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
	var generation := _game_generation
	if not _game_active or _busy:
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
	# Locked gems refuse to move: rattle the lock, nothing else happens.
	if _is_locked(tile) or _is_locked(other):
		for t in [tile, other]:
			if _is_locked(t):
				t.rattle_lock()
		_play_sfx(sfx_no_match)
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
		if generation != _game_generation:
			return
		_swap_logic(tile, other)
		await _tween_two(tile, p1, other, p2, 0.10)
		if generation != _game_generation:
			return
		await _fire_color_bomb(color_bomb, bomb_target)
		if generation != _game_generation:
			return
		if _level_mode:
			await _check_level_up()
			if generation != _game_generation:
				return
		_busy = false
		return

	# --- Normal match logic. ---
	_swap_logic(tile, other)
	await _tween_two(tile, p2, other, p1, 0.15)
	if generation != _game_generation:
		return

	last_swapped_tiles = [tile, other]
	var matches := _find_matches()

	if matches.size() == 0:
		_play_sfx(sfx_no_match)
		await _tween_two(tile, p1, other, p2, 0.15)
		if generation != _game_generation:
			return
		_swap_logic(tile, other)
		last_swapped_tiles = []
	else:
		_play_sfx(sfx_swap)
		await _resolve_matches_animated(matches)
		if generation != _game_generation:
			return
		if _level_mode:
			await _check_level_up()
			if generation != _game_generation:
				return

	_busy = false


func _swap_logic(t1, t2) -> void:
	var r1 = t1.row; var c1 = t1.col
	var r2 = t2.row; var c2 = t2.col
	board[r1][c1] = t2
	board[r2][c2] = t1
	t1.row = r2; t1.col = c2
	t2.row = r1; t2.col = c1


func _tween_two(a, pa: Vector2, b, pb: Vector2, dur: float) -> void:
	var generation := _game_generation
	var tw := _board_tween()
	tw.set_parallel(true)
	tw.tween_property(a, "position", pa, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(b, "position", pb, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	await tw.finished
	if generation != _game_generation:
		return


# ----- Match resolution (animated) -----------------------------------------

func _resolve_matches_animated(initial_groups: Array) -> void:
	var generation := _game_generation
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
		var bomb_flash_centers: Array = []
		var matched_step: Array = []     # every gem matched this cascade step
		var cross_flash_centers: Array = []

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
			# A match breaks the locks on gems right beside it.
			_queue_unlocks_beside(valid)
			matched_step.append_array(valid)

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
				# Queue EVERY special in the group — matching a bomb with a
				# cross fires both (group tiles leave the board before chain
				# detonation, so the blast-zone collector can't pick them up).
				# Plain suns (max tier) in the group also explode as BOMB.
				for t in valid:
					if t.special_type == Tile.SPECIAL_BOMB or \
					   t.special_type == Tile.SPECIAL_CROSS:
						detonate_queue.append(t)
					elif t.level == 7 and t.special_type == Tile.SPECIAL_NONE:
						t.special_type = Tile.SPECIAL_BOMB
						detonate_queue.append(t)

			elif valid[0].level == 7:
				# Suns are the max tier -- they can't upgrade, so they explode (3x3 BOMB each).
				score += valid.size() * 10 * 7 * multiplier
				for t in valid:
					if not removed_set.has(t):
						removed_set[t] = true
						board[t.row][t.col] = null
						to_remove.append(t)
						t.special_type = Tile.SPECIAL_BOMB
						detonate_queue.append(t)

			else:
				# Any 3+ match: one survivor upgrades 1 tier; shape sets the special:
				# NONE for a plain 3-match, BOMB/CROSS/COLOR_BOMB for 4+ / T-L-+ / 5+.
				var survivor: Tile = null
				for t in last_swapped_tiles:
					if valid.has(t):
						survivor = t
						break
				if survivor == null:
					survivor = valid[0]

				var new_level: int = min(survivor.level + 1, 7)
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
				bomb_flash_centers.append({r = sp.row, c = sp.col})
			elif sp.special_type == Tile.SPECIAL_CROSS:
				had_cross_det = true
				cross_flash_centers.append({r = sp.row, c = sp.col})

			for t: Tile in _collect_special_zone(sp):
				if t.locked:
					# A blast breaks the lock instead of destroying the gem.
					_pending_unlocks[t] = true
					continue
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
			_spawn_cascade_sparkle(cascade)
			var note_idx: int = clamp(cascade - 2, 0, sfx_notes.size() - 1)
			_play_sfx(sfx_notes[note_idx])

		_flinch_locks_near(matched_step)
		_apply_pending_unlocks()

		# 1. Scale matched tiles to zero then free them.
		if to_remove.size() > 0:
			for center in bomb_flash_centers:
				_fx_fire_blast(center.r, center.c)
			for center in cross_flash_centers:
				_fx_lightning(center.r, center.c)
			_play_sfx(sfx_match)
			_collect_time_bonus(to_remove)
			var tw := _board_tween()
			tw.set_parallel(true)
			for t in to_remove:
				_fx_shatter(t)
				tw.tween_property(t, "scale", Vector2.ZERO, 0.15) \
					.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			await tw.finished
			if generation != _game_generation:
				return
			for t in to_remove:
				if is_instance_valid(t):
					t.queue_free()

			# Screen shake based on what detonated.
			if had_bomb_det:
				_play_sfx(sfx_explosion)
				await _shake_board()
				if generation != _game_generation:
					return
			elif had_cross_det:
				_play_sfx(sfx_lightning)
				await _shake_board_faint()
				if generation != _game_generation:
					return

		# 2. Apply upgrades + pop animation.
		var live_upgrades: Array = []
		for entry in upgrades:
			if is_instance_valid(entry[0]) and not removed_set.has(entry[0]):
				entry[0].set_level(entry[1])
				entry[0].set_special(entry[2])
				live_upgrades.append(entry[0])
		if live_upgrades.size() > 0:
			for t in live_upgrades:
				_spawn_fx("upgrade_ring", t.position, 0.0, _gem_fx_color(t.level).lightened(0.35), 0.0, 4)
			var tw2 := _board_tween()
			tw2.set_parallel(true)
			for t in live_upgrades:
				tw2.tween_property(t, "scale", Vector2(1.35, 1.35), 0.1) \
					.set_trans(Tween.TRANS_QUAD)
			await tw2.finished
			if generation != _game_generation:
				return
			var tw3 := _board_tween()
			tw3.set_parallel(true)
			for t in live_upgrades:
				tw3.tween_property(t, "scale", Vector2.ONE, 0.1) \
					.set_trans(Tween.TRANS_QUAD)
			await tw3.finished
			if generation != _game_generation:
				return

		last_swapped_tiles = []

		# 3. Collapse + fill.
		await _animate_collapse()
		if generation != _game_generation:
			return
		if not _game_active:
			return
		await _animate_fill()
		if generation != _game_generation:
			return
		if not _game_active:
			return

		update_score_display()
		groups = _find_matches()

	await _check_for_shuffle()
	if generation != _game_generation:
		return


# ----- Special gem zone collectors ------------------------------------------

# Returns every board tile in the detonation zone of a BOMB or CROSS gem.
# The special tile itself is included so it gets freed along with the blast.
func _collect_special_zone(sp: Tile) -> Array:
	return _collect_special_zone_at(sp.row, sp.col, sp.special_type)


func _collect_special_zone_at(origin_row: int, origin_col: int, special_type: int) -> Array:
	var zone: Array = []
	if special_type == Tile.SPECIAL_BOMB:
		for dr in range(-1, 2):
			for dc in range(-1, 2):
				var nr: int = origin_row + dr
				var nc: int = origin_col + dc
				if nr < 0 or nr >= board_rows or nc < 0 or nc >= board_cols:
					continue
				if SHAPE[nr][nc] == 0:
					continue
				var t = board[nr][nc]
				if t != null:
					zone.append(t)

	elif special_type == Tile.SPECIAL_CROSS:
		for c in range(board_cols):
			if SHAPE[origin_row][c] == 1:
				var t = board[origin_row][c]
				if t != null:
					zone.append(t)
		for r in range(board_rows):
			if SHAPE[r][origin_col] == 1:
				var t = board[r][origin_col]
				if t != null and not zone.has(t):
					zone.append(t)

	return zone


# ----- COLOR_BOMB activation ------------------------------------------------

# Fired from _attempt_swap() when either swapped tile is a COLOR_BOMB.
func _fire_color_bomb(bomb: Tile, target: Tile) -> void:
	var generation := _game_generation
	var target_level := 1
	var target_special := Tile.SPECIAL_NONE
	if is_instance_valid(target):
		target_level = target.level
		target_special = target.special_type

	if target_special == Tile.SPECIAL_COLOR_BOMB:
		await _fire_color_bomb_clear_board(bomb)
		if generation != _game_generation:
			return
		return

	# Suns (max tier) already explode as bombs when matched, so moon + sun
	# copies that same behavior to every sun on the board.
	if target_level == 7 and target_special == Tile.SPECIAL_NONE:
		target_special = Tile.SPECIAL_BOMB

	if target_special == Tile.SPECIAL_BOMB or target_special == Tile.SPECIAL_CROSS:
		await _fire_color_bomb_special_copy(bomb, target_level, target_special)
		if generation != _game_generation:
			return
		return

	await _fire_color_bomb_level_clear(bomb, target_level)
	if generation != _game_generation:
		return


# Destroys the bomb itself and every gem at target_level on the board.
func _fire_color_bomb_level_clear(bomb: Tile, target_level: int) -> void:
	var generation := _game_generation
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
				if t.locked:
					_pending_unlocks[t] = true
					continue
				removed_set[t] = true
				board[r][c] = null
				to_remove.append(t)
	_apply_pending_unlocks()

	score += to_remove.size() * 10 * target_level
	_play_sfx(sfx_color_bomb)
	_collect_time_bonus(to_remove)

	# The moon eclipses and the board dims; once the eclipse has formed, a wave
	# rolls outward and each caught gem is swallowed by a vortex in turn.
	var br: int = bomb.row if is_instance_valid(bomb) else int(board_rows / 2.0)
	var bc: int = bomb.col if is_instance_valid(bomb) else int(board_cols / 2.0)
	_fx_void_core(br, bc, 4.5)
	var max_delay := 0.0
	for t in to_remove:
		if not is_instance_valid(t):
			continue
		var delay: float = VOID_WAVE_LEAD + Vector2(t.row - br, t.col - bc).length() * 0.045
		max_delay = maxf(max_delay, delay)
		if t != bomb:
			_fx_void_devour(t, delay)
		var seq := _board_tween()
		seq.tween_interval(delay)
		seq.tween_property(t, "scale", Vector2(1.18, 1.18), 0.07) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		seq.tween_property(t, "scale", Vector2.ZERO, 0.15) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await get_tree().create_timer(max_delay + 0.24).timeout
	if generation != _game_generation:
		return
	for t in to_remove:
		if is_instance_valid(t):
			t.queue_free()

	await _shake_board()
	if generation != _game_generation:
		return
	await _animate_collapse()
	if generation != _game_generation:
		return
	if not _game_active:
		return
	await _animate_fill()
	if generation != _game_generation:
		return
	if not _game_active:
		return
	update_score_display()

	var matches := _find_matches()
	if matches.size() > 0:
		await _resolve_matches_animated(matches)
		if generation != _game_generation:
			return
	else:
		await _check_for_shuffle()
		if generation != _game_generation:
			return


func _fire_color_bomb_clear_board(bomb: Tile) -> void:
	var generation := _game_generation
	var to_remove: Array = []
	var removed_set       = {}

	for r in range(board_rows):
		for c in range(board_cols):
			if SHAPE[r][c] == 1:
				_mark_tile_for_removal(board[r][c], to_remove, removed_set)
	_apply_pending_unlocks()

	for t: Tile in to_remove:
		score += 10 * t.level
	_play_sfx(sfx_color_bomb)
	_collect_time_bonus(to_remove)
	await _animate_color_bomb_removal(to_remove, bomb, 7.0)
	if generation != _game_generation:
		return
	await _finish_color_bomb_resolution()
	if generation != _game_generation:
		return


func _fire_color_bomb_special_copy(bomb: Tile, target_level: int, copied_special: int) -> void:
	var generation := _game_generation
	var to_remove: Array = []
	var removed_set       = {}
	var origins: Array = []

	_mark_tile_for_removal(bomb, to_remove, removed_set)

	for r in range(board_rows):
		for c in range(board_cols):
			var t = board[r][c]
			if t != null and t.level == target_level:
				origins.append({r = r, c = c})

	for origin in origins:
		for t: Tile in _collect_special_zone_at(origin.r, origin.c, copied_special):
			_mark_tile_for_removal(t, to_remove, removed_set)
	_apply_pending_unlocks()

	for t: Tile in to_remove:
		score += 10 * t.level
	_play_sfx(sfx_color_bomb)
	_collect_time_bonus(to_remove)
	if copied_special == Tile.SPECIAL_BOMB:
		_play_sfx(sfx_explosion)
	elif copied_special == Tile.SPECIAL_CROSS:
		_play_sfx(sfx_lightning)

	await _animate_color_bomb_special_copy(to_remove, origins, copied_special, bomb)
	if generation != _game_generation:
		return
	await _finish_color_bomb_resolution()
	if generation != _game_generation:
		return


func _mark_tile_for_removal(t: Tile, to_remove: Array, removed_set: Dictionary) -> void:
	if not is_instance_valid(t) or removed_set.has(t):
		return
	if t.locked:
		# Colour-bomb waves break locks rather than destroying the gem.
		_pending_unlocks[t] = true
		return
	removed_set[t] = true
	if t.row >= 0 and t.row < board_rows and t.col >= 0 and t.col < board_cols:
		if board[t.row][t.col] == t:
			board[t.row][t.col] = null
	to_remove.append(t)


func _animate_color_bomb_removal(to_remove: Array, bomb: Tile, radius_cells: float = 4.5) -> void:
	var generation := _game_generation
	var br: int = bomb.row if is_instance_valid(bomb) else int(board_rows / 2.0)
	var bc: int = bomb.col if is_instance_valid(bomb) else int(board_cols / 2.0)
	_fx_void_core(br, bc, radius_cells)

	var max_delay := 0.0
	for t in to_remove:
		if not is_instance_valid(t):
			continue
		var delay: float = VOID_WAVE_LEAD + Vector2(t.row - br, t.col - bc).length() * 0.045
		max_delay = maxf(max_delay, delay)
		if t != bomb:
			_fx_void_devour(t, delay)
		var seq := _board_tween()
		seq.tween_interval(delay)
		seq.tween_property(t, "scale", Vector2(1.18, 1.18), 0.07) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		seq.tween_property(t, "scale", Vector2.ZERO, 0.15) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await get_tree().create_timer(max_delay + 0.24).timeout
	if generation != _game_generation:
		return
	for t in to_remove:
		if is_instance_valid(t):
			t.queue_free()

	await _shake_board()
	if generation != _game_generation:
		return


func _animate_color_bomb_special_copy(
		to_remove: Array, origins: Array, copied_special: int, bomb: Tile) -> void:
	var generation := _game_generation
	var br: int = bomb.row if is_instance_valid(bomb) else int(board_rows / 2.0)
	var bc: int = bomb.col if is_instance_valid(bomb) else int(board_cols / 2.0)
	_fx_void_core(br, bc, 4.5)

	# Every copied special goes off once the eclipse has formed, nearest first.
	var last_blast := VOID_WAVE_LEAD
	for origin in origins:
		var delay: float = VOID_WAVE_LEAD + Vector2(origin.r - br, origin.c - bc).length() * 0.03
		last_blast = maxf(last_blast, delay)
		var blast := _board_tween()
		blast.tween_interval(delay)
		if copied_special == Tile.SPECIAL_BOMB:
			blast.tween_callback(_fx_fire_blast.bind(origin.r, origin.c))
		elif copied_special == Tile.SPECIAL_CROSS:
			blast.tween_callback(_fx_lightning.bind(origin.r, origin.c))

	var tw := _board_tween()
	tw.tween_interval(last_blast)
	tw.set_parallel(true)
	tw.chain().tween_interval(0.0)   # new step after the wait; the shrinks below run together in it
	for t in to_remove:
		if is_instance_valid(t):
			tw.tween_callback(_fx_shatter.bind(t))
			tw.tween_property(t, "scale", Vector2.ZERO, 0.18) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tw.finished
	if generation != _game_generation:
		return
	for t in to_remove:
		if is_instance_valid(t):
			t.queue_free()

	if copied_special == Tile.SPECIAL_BOMB:
		await _shake_board()
		if generation != _game_generation:
			return
	elif copied_special == Tile.SPECIAL_CROSS:
		await _shake_board_faint()
		if generation != _game_generation:
			return


func _finish_color_bomb_resolution() -> void:
	var generation := _game_generation
	await _animate_collapse()
	if generation != _game_generation:
		return
	if not _game_active:
		return
	await _animate_fill()
	if generation != _game_generation:
		return
	if not _game_active:
		return
	update_score_display()

	var matches := _find_matches()
	if matches.size() > 0:
		await _resolve_matches_animated(matches)
		if generation != _game_generation:
			return
	else:
		await _check_for_shuffle()
		if generation != _game_generation:
			return


# ----- Gravity & fill -------------------------------------------------------

func _animate_collapse() -> void:
	var generation := _game_generation
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
	var tw := _board_tween()
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
		if generation != _game_generation:
			return
		_play_sfx(sfx_tink)
	else:
		tw.kill()


func _animate_fill() -> void:
	var generation := _game_generation
	var any := false
	var tw := _board_tween()
	tw.set_parallel(true)
	var locks_left: int = maxi(0, _lock_cap() - _count_locked())

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
			tile.set_level(randi_range(1, 6))
			if locks_left > 0 and randf() < LOCK_SPAWN_CHANCE:
				tile.set_locked(true)
				locks_left -= 1
			elif _timed_mode and randf() < TIME_BONUS_CHANCE:
				tile.set_time_bonus(randi_range(5, 10))

			var target := _cell_pos(r, c)
			tile.position = Vector2(target.x, -(n - i) * float(cell_size))

			var fall_dist: float = target.y - tile.position.y
			var dur: float = 0.15 + fall_dist / (float(cell_size) * 10.0)
			tw.tween_property(tile, "position", target, dur) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			any = true

	if any:
		await tw.finished
		if generation != _game_generation:
			return
		_play_sfx(sfx_tink)
	else:
		tw.kill()


# Timed mode: sum the time bonuses on removed gems, extend the clock, and
# float a golden "+N s" up from the last bonus gem. Call with tiles still
# valid (before queue_free).
func _collect_time_bonus(tiles: Array) -> void:
	if not _timed_mode:
		return
	var total := 0
	var at: Tile = null
	for t in tiles:
		if is_instance_valid(t) and t is Tile and t.time_bonus > 0:
			total += t.time_bonus
			at = t
	if total <= 0:
		return
	_time_remaining = minf(_time_remaining + float(total), TIMED_DURATION)
	_update_timer_display()

	var lbl := Label.new()
	var ls := LabelSettings.new()
	ls.font = load("res://assets/font/vetka.ttf")
	ls.font_size = 46
	ls.font_color = Color(1.0, 0.88, 0.3)
	ls.outline_size = 11
	ls.outline_color = Color(0.3, 0.15, 0.0, 0.95)
	lbl.label_settings = ls
	lbl.text = "+%d s" % total
	lbl.z_index = 30
	lbl.position = at.position + Vector2(-44, -70)
	board_container.add_child(lbl)
	var tw := _board_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "position:y", lbl.position.y - 52.0, 0.85) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.85) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(lbl.queue_free)


# ----- Screen shake ---------------------------------------------------------

func _shake_board() -> void:
	var generation := _game_generation
	var origin := board_container.position
	var tw := _board_tween()
	tw.tween_property(board_container, "position", origin + Vector2(5, -3),  0.04)
	tw.tween_property(board_container, "position", origin + Vector2(-4, 4),  0.04)
	tw.tween_property(board_container, "position", origin + Vector2(3, -2),  0.04)
	tw.tween_property(board_container, "position", origin + Vector2(-2, 1),  0.04)
	tw.tween_property(board_container, "position", origin,                   0.06)
	await tw.finished
	if generation != _game_generation:
		return


# Gentler shake for CROSS (lightning-bolt) detonation.
func _shake_board_faint() -> void:
	var generation := _game_generation
	var origin := board_container.position
	var tw := _board_tween()
	tw.tween_property(board_container, "position", origin + Vector2(3, -2),  0.05)
	tw.tween_property(board_container, "position", origin + Vector2(-2, 2),  0.05)
	tw.tween_property(board_container, "position", origin + Vector2(2, -1),  0.05)
	tw.tween_property(board_container, "position", origin + Vector2(-1, 1),  0.05)
	tw.tween_property(board_container, "position", origin,                   0.08)
	await tw.finished
	if generation != _game_generation:
		return


func _cell_pos(r: int, c: int) -> Vector2:
	return Vector2(c * float(cell_size) + cell_size * 0.5,
				   r * float(cell_size) + cell_size * 0.5)


# ----- Match detection ------------------------------------------------------
#
# Returns Array of Dictionaries: { "tiles": Array[Tile], "shape": int }
# shape mirrors Tile.SPECIAL_* — NONE for a plain 3-match, BOMB for a 4
# straight run, CROSS for any T/L/+ merge, COLOR_BOMB for a 5+ straight run.

func _find_matches() -> Array:
	var raw_runs: Array = []

	# Horizontal runs of 3+. Locked gems never match and break runs.
	for r in range(board_rows):
		var c := 0
		while c < board_cols:
			var tile = board[r][c]
			if tile != null and tile.special_type != Tile.SPECIAL_COLOR_BOMB and not tile.locked:
				var run: Array = [tile]
				var cc := c + 1
				while cc < board_cols:
					var t = board[r][cc]
					if _tiles_match_for_run(tile, t):
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
			if tile != null and tile.special_type != Tile.SPECIAL_COLOR_BOMB and not tile.locked:
				var run: Array = [tile]
				var rr := r + 1
				while rr < board_rows:
					var t = board[rr][c]
					if _tiles_match_for_run(tile, t):
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


func _tiles_match_for_run(a: Tile, b: Tile) -> bool:
	return b != null and not b.locked and b.special_type != Tile.SPECIAL_COLOR_BOMB and b.level == a.level


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
						if SHAPE[nr][nc] == 1 and board[nr][nc] != null and not board[nr][nc].locked:
							return true

	for r in range(board_rows):
		for c in range(board_cols):
			var tile = board[r][c]
			if tile == null or tile.locked:
				continue
			for dir in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
				var nr := r + int(dir.y)
				var nc := c + int(dir.x)
				if nr < 0 or nr >= board_rows or nc < 0 or nc >= board_cols:
					continue
				if SHAPE[nr][nc] == 0:
					continue
				var other = board[nr][nc]
				if other == null or other.locked:
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
	var generation := _game_generation
	if _has_possible_matches():
		return

	_play_sfx(sfx_shuffle)

	# Show "Shuffling..." label (fire-and-forget fade).
	if shuffle_label != null:
		shuffle_label.modulate.a = 1.0
		shuffle_label.visible = true
		var tw_lbl := _board_tween()
		tw_lbl.tween_interval(2.2)
		tw_lbl.tween_property(shuffle_label, "modulate:a", 0.0, 0.5)
		tw_lbl.tween_callback(func(): shuffle_label.visible = false)

	# Collect all tiles, then shrink them to nothing.
	var all_tiles: Array = []
	for r in range(board_rows):
		for c in range(board_cols):
			if board[r][c] != null:
				all_tiles.append(board[r][c])
	var tw_shrink := _board_tween().set_parallel(true)
	for tile in all_tiles:
		tw_shrink.tween_property(tile, "scale", Vector2.ZERO, 0.42) \
			.set_ease(Tween.EASE_IN)
	await tw_shrink.finished
	if generation != _game_generation:
		return

	# Shuffle while tiles are invisible (positions teleport at scale=0).
	var attempts := 0
	while not _has_possible_matches():
		_shuffle_board()
		attempts += 1
		if attempts > 20:
			break

	# Pop tiles back with a springy overshoot.
	var tw_grow := _board_tween().set_parallel(true)
	for tile in all_tiles:
		tw_grow.tween_property(tile, "scale", Vector2.ONE, 0.52) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	await tw_grow.finished
	if generation != _game_generation:
		return


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

	_combo_tween = _board_tween()
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
	_update_score_bar()
	if _score_tween != null and _score_tween.is_valid():
		_score_tween.kill()
	_score_tween = _board_tween()
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
	var tw := _board_tween()
	tw.tween_property(_flash_overlay, "color:a", 0.28, 0.08)
	tw.tween_property(_flash_overlay, "color:a", 0.0,  0.55) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


# ----- Explosion shockwave + sparks ------------------------------------------

# Lazily created Control that clips shockwaves/sparks to the board rect so
# nothing bleeds onto the background art outside the gem field.
func _fx_layer() -> Control:
	if _fx_clip == null or not is_instance_valid(_fx_clip):
		_fx_clip = Control.new()
		_fx_clip.clip_contents = true
		_fx_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_fx_clip.position = Vector2.ZERO
		_fx_clip.size = Vector2(board_cols * cell_size, board_rows * cell_size)
		_fx_clip.z_index = 11
		board_container.add_child(_fx_clip)
	return _fx_clip


# Expanding pixel-block ring (shockwave.gdshader) centered on a board cell.
# `cross` swaps the circle for a plus-shaped wavefront (CROSS gems).
func _spawn_shockwave(r: int, c: int, color: Color, radius_cells: float,
		duration: float = 0.45, cross: bool = false) -> void:
	if not is_instance_valid(board_container):
		return
	var rect := ColorRect.new()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.size = Vector2.ONE * cell_size * radius_cells * 2.0
	rect.position = Vector2((c + 0.5) * cell_size, (r + 0.5) * cell_size) - rect.size * 0.5
	var mat := ShaderMaterial.new()
	mat.shader = SHOCKWAVE_SHADER
	mat.set_shader_parameter("ring_color", color)
	mat.set_shader_parameter("cross_shape", cross)
	# Blocks of 2 art pixels (8 board px), the same grid as the gem and FX art.
	mat.set_shader_parameter("grid_cells", rect.size.x / 8.0)
	# Must be set explicitly before tweening: an unset shader parameter reads
	# back as null, which makes tween_property reject the property path.
	mat.set_shader_parameter("progress", 0.0)
	rect.material = mat
	_fx_layer().add_child(rect)
	var tw := _board_tween()
	tw.tween_property(mat, "shader_parameter/progress", 1.0, duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(rect.queue_free)


# ----- Pixel-art FX sprites ---------------------------------------------------
#
# All effect animations live in assets/fx/fx_frames.tres (4x pixel art; source
# .aseprite files in art_src/gem_match/fx/). White-based ones (shatter,
# twinkle, upgrade_ring) are tinted with the gem colour.

# One-shot effect at a board-space position; frees itself when it finishes.
func _spawn_fx(anim_name: String, pos: Vector2, delay: float = 0.0,
		tint: Color = Color.WHITE, rot: float = 0.0, z: int = 1) -> AnimatedSprite2D:
	if not is_instance_valid(board_container):
		return null
	var fx := AnimatedSprite2D.new()
	fx.sprite_frames = FX_FRAMES
	fx.animation = anim_name
	fx.position = pos
	fx.rotation = rot
	fx.modulate = tint
	fx.z_index = z
	fx.animation_finished.connect(fx.queue_free)
	_fx_layer().add_child(fx)
	if delay > 0.0:
		fx.visible = false
		var tw := _board_tween()
		tw.tween_interval(delay)
		tw.tween_callback(func():
			if is_instance_valid(fx):
				fx.visible = true
				fx.play())
	else:
		fx.play()
	return fx


func _gem_fx_color(lv: int) -> Color:
	return GEM_FX_COLORS[clampi(lv, 1, GEM_FX_COLORS.size()) - 1]


# Glass shards in the gem's own colour as it leaves the board.
func _fx_shatter(t: Tile, delay: float = 0.0) -> void:
	if is_instance_valid(t):
		_spawn_fx("shatter", t.position, delay, _gem_fx_color(t.level), randf() * TAU)


# BOMB: a fireball over the 3x3, flame puffs rippling outward, flying embers.
func _fx_fire_blast(r: int, c: int) -> void:
	_spawn_fx("fire_blast", _cell_pos(r, c), 0.0, Color.WHITE, 0.0, 3)
	for dr in range(-1, 2):
		for dc in range(-1, 2):
			var nr: int = r + dr
			var nc: int = c + dc
			if nr >= 0 and nr < board_rows and nc >= 0 and nc < board_cols and SHAPE[nr][nc] == 1:
				_spawn_fx("flame_puff", _cell_pos(nr, nc) + Vector2(randf_range(-8, 8), randf_range(-8, 8)),
						0.05 + maxi(absi(dr), absi(dc)) * 0.06, Color.WHITE, 0.0, 2)
	_spawn_sparks(r, c, Color(1.0, 0.78, 0.3), 18, 340.0)
	_leave_embers(r, c)


# A few embers smoulder on the scorched cells for a second after a bomb. They
# sit behind the gems, so they glow in the gaps as the new gems fall in.
func _leave_embers(r: int, c: int) -> void:
	if not is_instance_valid(board_container):
		return
	var cells: Array = []
	for dr in range(-1, 2):
		for dc in range(-1, 2):
			var nr: int = r + dr
			var nc: int = c + dc
			if nr >= 0 and nr < board_rows and nc >= 0 and nc < board_cols and SHAPE[nr][nc] == 1:
				cells.append(Vector2i(nc, nr))
	cells.shuffle()
	for i in range(mini(4, cells.size())):
		var cell: Vector2i = cells[i]
		var ember := AnimatedSprite2D.new()
		ember.sprite_frames = FX_FRAMES
		ember.animation = "ember_linger"
		ember.z_index = -1          # on the board floor, under the gems
		ember.position = _cell_pos(cell.y, cell.x) + Vector2(randf_range(-30, 30), randf_range(-24, 30))
		ember.visible = false
		ember.animation_finished.connect(ember.queue_free)
		board_container.add_child(ember)
		var tw := _board_tween()
		tw.tween_interval(0.3 + randf() * 0.25)
		tw.tween_callback(func():
			if is_instance_valid(ember):
				ember.visible = true
				ember.play())


# Now and then the moon sheds a star that arcs onto a neighbouring gem and
# twinkles out there. Called by the moon tile; only while the board is idle.
func moon_star_drift(moon: Tile) -> void:
	if not _game_active or _busy or not is_instance_valid(moon):
		return
	var options: Array = []
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
			Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
		var nr: int = moon.row + d.y
		var nc: int = moon.col + d.x
		if nr >= 0 and nr < board_rows and nc >= 0 and nc < board_cols and board[nr][nc] != null:
			options.append(board[nr][nc])
	if options.is_empty():
		return
	var target: Tile = options.pick_random()
	var mote := _spawn_fx("twinkle", moon.position + Vector2(12, -16), 0.0, Color(0.93, 0.84, 1.0), 0.0, 6)
	if mote == null:
		return
	mote.stop()
	mote.frame = 1                  # a small star while it travels
	var start: Vector2 = mote.position
	var end: Vector2 = target.position + Vector2(randf_range(-16, 16), randf_range(-18, 6))
	var peak: Vector2 = (start + end) * 0.5 + Vector2(0, -34)
	var tw := _board_tween()
	tw.tween_method(func(t: float):
		if is_instance_valid(mote):
			mote.position = start.lerp(peak, t).lerp(peak.lerp(end, t), t), 0.0, 1.0, 0.75) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func():
		if is_instance_valid(mote):
			mote.play())            # finishes the twinkle on the gem, then frees itself


# Locked gems near a match (within two cells) that the match didn't free
# give a little start.
func _flinch_locks_near(matched: Array) -> void:
	if matched.is_empty():
		return
	for r in range(board_rows):
		for c in range(board_cols):
			var t = board[r][c]
			if not _is_locked(t) or _pending_unlocks.has(t):
				continue
			for m in matched:
				if is_instance_valid(m) and maxi(absi(m.row - r), absi(m.col - c)) <= 2:
					t.flinch_lock(randf() * 0.06)
					break


# CROSS: bolts crackle along the whole row and column from an electric burst.
func _fx_lightning(r: int, c: int) -> void:
	_spawn_fx("bolt_core", _cell_pos(r, c), 0.0, Color.WHITE, 0.0, 4)
	for nc in range(board_cols):
		if SHAPE[r][nc] == 1 and nc != c:
			var bolt := _spawn_fx("bolt_h", _cell_pos(r, nc), absi(nc - c) * 0.025)
			if bolt: bolt.flip_v = randf() < 0.5
	for nr in range(board_rows):
		if SHAPE[nr][c] == 1 and nr != r:
			var bolt := _spawn_fx("bolt_h", _cell_pos(nr, c), absi(nr - r) * 0.025, Color.WHITE, PI * 0.5)
			if bolt: bolt.flip_v = randf() < 0.5
	for i in range(4):
		var along_row := i % 2 == 0
		var zc: int = randi() % board_cols if along_row else c
		var zr: int = r if along_row else randi() % board_rows
		if SHAPE[zr][zc] == 1:
			_spawn_fx("zap", _cell_pos(zr, zc) + Vector2(randf_range(-20, 20), randf_range(-20, 20)),
					0.08 + randf() * 0.15, Color.WHITE, 0.0, 5)
	_spawn_sparks(r, c, Color(0.62, 0.92, 1.0), 12, 300.0)


# COLOR_BOMB: the moon eclipses, the board dims and a void ring rolls out.
func _fx_void_core(r: int, c: int, radius_cells: float = 4.5) -> void:
	_spawn_fx("void_core", _cell_pos(r, c), 0.0, Color.WHITE, 0.0, 6)
	_spawn_shockwave(r, c, Color(0.62, 0.3, 1.0, 0.5), radius_cells, 0.7)
	_dim_board(0.42, 0.95)


# A gem caught by the moon is swallowed by a little vortex, spinning as it shrinks.
func _fx_void_devour(t: Tile, delay: float) -> void:
	if not is_instance_valid(t):
		return
	_spawn_fx("void_devour", t.position, delay, Color.WHITE, randf() * TAU, 2)
	var spin := _board_tween()
	spin.tween_interval(delay + 0.05)
	spin.tween_property(t, "rotation", t.rotation + TAU * 0.75, 0.3) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


# Darkens the board (not the effects above it) for a moment.
func _dim_board(strength: float, duration: float) -> void:
	if not is_instance_valid(board_container):
		return
	if _dim_rect == null or not is_instance_valid(_dim_rect):
		_dim_rect = ColorRect.new()
		_dim_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_dim_rect.color = Color(0.07, 0.02, 0.13, 0.0)
		_dim_rect.position = Vector2.ZERO
		_dim_rect.size = Vector2(board_cols * cell_size, board_rows * cell_size)
		_dim_rect.z_index = 10
		board_container.add_child(_dim_rect)
	var tw := _board_tween()
	tw.tween_property(_dim_rect, "color:a", strength, duration * 0.25)
	tw.tween_interval(duration * 0.35)
	tw.tween_property(_dim_rect, "color:a", 0.0, duration * 0.4)


# Board-wide glitter that grows with the cascade count: pixel twinkles at
# random cells over a third of a second. Higher cascades shift the twinkles
# cooler — gold toward white-blue.
func _spawn_cascade_sparkle(cascade: int) -> void:
	var count: int = clampi(3 + cascade * 2, 5, 14)
	var cool := clampf((cascade - 2) * 0.12, 0.0, 0.7)
	var color := Color(1.0, 0.9, 0.5).lerp(Color(0.7, 0.88, 1.0), cool)
	for i in range(count):
		var r := randi() % board_rows
		var c := randi() % board_cols
		if SHAPE[r][c] == 0:
			continue
		_spawn_fx("twinkle", _cell_pos(r, c) + Vector2(randf_range(-30, 30), randf_range(-30, 30)),
				randf() * 0.35, color, 0.0, 6)


# Debris burst of pixel embers (assets/fx/ember_4x.png): one fixed size, so
# every particle sits on the same 4x pixel grid as the gems.
func _spawn_sparks(r: int, c: int, color: Color, count: int = 18,
		speed: float = 300.0) -> void:
	if not is_instance_valid(board_container):
		return
	var fx := CPUParticles2D.new()
	fx.position = Vector2((c + 0.5) * cell_size, (r + 0.5) * cell_size)
	fx.texture = EMBER_TEXTURE
	fx.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	fx.one_shot = true
	fx.explosiveness = 1.0
	fx.amount = count
	fx.lifetime = 0.6
	fx.direction = Vector2.RIGHT
	fx.spread = 180.0
	fx.gravity = Vector2(0, 420)
	fx.initial_velocity_min = speed * 0.3
	fx.initial_velocity_max = speed
	fx.scale_amount_min = 1.0
	fx.scale_amount_max = 1.0
	fx.color = color
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 1))
	ramp.set_color(1, Color(1, 1, 1, 0))
	fx.color_ramp = ramp
	_fx_layer().add_child(fx)
	fx.emitting = true
	fx.finished.connect(fx.queue_free)


# ----- Audio helpers --------------------------------------------------------

func _play_sfx(player: AudioStreamPlayer) -> void:
	if player != null and player.stream != null:
		player.play()


func _play_sfx_delayed(player: AudioStreamPlayer, delay: float) -> void:
	var generation := _game_generation
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
		if generation != _game_generation:
			return
	_play_sfx(player)


# ----- Timed mode -----------------------------------------------------------

func _update_timer_display() -> void:
	if _timer_label == null:
		return
	var secs := int(ceil(_time_remaining))
	var m    := int(secs / 60.0)
	var s    := secs % 60
	_timer_label.text = "%d:%02d" % [m, s]
	if _time_remaining <= 10.0:
		_timer_label.add_theme_color_override("font_color", Color(1, 0.25, 0.2))
	else:
		_timer_label.add_theme_color_override("font_color", Color(1, 0.945, 0.627))


func _time_up() -> void:
	_stop_hints()
	for child in get_children():
		if child is AudioStreamPlayer and child != sfx_click:
			child.stop()
	_show_game_over_panel()


func _load_timed_best() -> int:
	var cfg := ConfigFile.new()
	if _SaveFile.load_config(cfg, TIMED_SAVE_PATH) == OK:
		return cfg.get_value("timed", "best_score", 0)
	return 0


func _save_timed_best() -> void:
	if score <= _load_timed_best():
		return
	var cfg := ConfigFile.new()
	_SaveFile.load_config(cfg, TIMED_SAVE_PATH)
	cfg.set_value("timed", "best_score", score)
	_SaveFile.save_config(cfg, TIMED_SAVE_PATH)


func _show_game_over_panel() -> void:
	if _game_over_panel == null:
		return
	if _level_mode:
		var prev_best := _load_level_best()
		_save_level_best(_timed_level)
		var is_new := _timed_level > prev_best
		_go_title_label.text    = "TIME'S UP!"
		_go_level_label.visible = true
		_go_level_label.text    = "Level %d reached" % _timed_level
		_go_score_label.text    = "Score: %d" % score
		_go_best_label.text     = "NEW BEST!" if is_new else ("Best: Level %d" % _load_level_best())
		_go_best_label.add_theme_color_override(
			"font_color", Color(1, 0.82, 0.1) if is_new else Color(1, 0.945, 0.627))
	else:
		var prev_best := _load_timed_best()
		_save_timed_best()
		var new_best  := _load_timed_best()
		_go_title_label.text    = "TIME'S UP!"
		_go_level_label.visible = false
		_go_score_label.text    = "Score: %d" % score
		_go_best_label.text     = "NEW BEST!" if score > prev_best else "Best: %d" % new_best
		_go_best_label.add_theme_color_override(
			"font_color", Color(1, 0.82, 0.1) if score > prev_best else Color(1, 0.945, 0.627))
	_game_over_panel.modulate.a = 0.0
	_game_over_panel.visible    = true
	var tw := _board_tween()
	tw.tween_property(_game_over_panel, "modulate:a", 1.0, 0.4).set_ease(Tween.EASE_OUT)


func _load_level_best() -> int:
	var cfg := ConfigFile.new()
	if _SaveFile.load_config(cfg, TIMED_SAVE_PATH) == OK:
		return cfg.get_value("level", "best_level", 0)
	return 0


func _save_level_best(reached: int) -> void:
	if reached <= _load_level_best():
		return
	var cfg := ConfigFile.new()
	_SaveFile.load_config(cfg, TIMED_SAVE_PATH)
	cfg.set_value("level", "best_level", reached)
	_SaveFile.save_config(cfg, TIMED_SAVE_PATH)


# ----- Level mode -----------------------------------------------------------

func _level_target_for(level: int) -> int:
	return int(float(LEVEL_BASE_TARGET) * pow(LEVEL_TARGET_SCALE, level - 1))


func _update_score_bar() -> void:
	if _score_bar_fill == null or not _level_mode:
		return
	var bar_w    := get_viewport_rect().size.x - 40.0
	var progress := clampf(float(score - _level_score_start) / float(_level_target), 0.0, 1.0)
	_score_bar_fill.size.x = bar_w * progress


func _update_level_label() -> void:
	if _level_label != null:
		_level_label.text = "Lv.%d" % _timed_level


func _show_level_up_banner() -> void:
	if combo_label == null:
		return
	if _combo_tween != null and _combo_tween.is_valid():
		_combo_tween.kill()
	combo_label.text       = "LEVEL %d!" % _timed_level
	combo_label.modulate.a = 1.0
	combo_label.z_index    = 999
	combo_label.scale      = Vector2(0.4, 0.4)
	combo_label.visible    = true
	_combo_tween = _board_tween()
	_combo_tween.tween_property(combo_label, "scale", Vector2(1.2, 1.2), 0.22) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_combo_tween.tween_property(combo_label, "scale", Vector2.ONE, 0.10)
	_combo_tween.tween_interval(0.80)
	_combo_tween.tween_property(combo_label, "modulate:a", 0.0, 0.30)
	_combo_tween.tween_callback(func(): combo_label.visible = false)
	_play_sfx(sfx_match)


func _check_level_up() -> void:
	var generation := _game_generation
	if not _level_mode or _leveling_up:
		return
	if score - _level_score_start < _level_target:
		return
	_leveling_up = true
	_timed_level       += 1
	_level_score_start  = score
	_level_target       = _level_target_for(_timed_level)
	_time_remaining     = minf(_time_remaining + LEVEL_TIME_BONUS, TIMED_DURATION)
	_update_level_label()
	_show_level_up_banner()
	_update_score_bar()
	# Brief yield so the banner tween kicks off before we unblock.
	await get_tree().create_timer(0.05).timeout
	if generation != _game_generation:
		return
	_leveling_up = false


func _board_tween() -> Tween:
	var tween := create_tween()
	_operation_tweens.append(tween)
	tween.finished.connect(_forget_tween.bind(tween.get_instance_id()), CONNECT_ONE_SHOT)
	return tween


func stop_game() -> void:
	_game_generation += 1
	for tween in _operation_tweens:
		if tween.is_valid():
			tween.kill()
	_operation_tweens.clear()
	_game_active = false
	_busy = false
	_drag_tile = null
	_stop_hints()


func request_back() -> void:
	_go_back_to_menu()


func _forget_tween(instance_id: int) -> void:
	for tween in _operation_tweens:
		if tween.get_instance_id() == instance_id:
			_operation_tweens.erase(tween)
			return
