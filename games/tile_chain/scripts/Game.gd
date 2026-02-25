#Game.gd (tile_chain)
extends Control

signal back_to_menu

const ROWS := 8 #8
const COLS := 5 #5
const CELL_SIZE := 90  # must match BoardCell.CELL_SIZE
const SAVE_PATH := "user://tile_chain_save.cfg"

# Combo milestone words — index 0 fires at ×10, escalating to index 6 at ×70+.
const COMBO_WORDS := [
	"GOOD!", "EXCELLENT!", "AWESOME!",
	"SPECTACULAR!", "EXTRAORDINARY!", "UNBELIEVABLE!", "INCONCEIVABLE!"
]

# Screen zones where border sparkles may appear (x, y, w, h in screen pixels).
const SPARKLE_ZONES: Array = [
	Rect2(115, 90,  39,  22),   # top rune strip
	Rect2(18,  194, 12,  91),   # left rune column (upper)
	Rect2(512, 228, 13, 152),   # right rune column
	Rect2(18,  698, 12,  98),   # left rune column (lower)
	Rect2(388, 866, 75,  17),   # bottom rune strip
]

var _cells: Array = []  # [row][col] -> BoardCell
var _selected: BoardCell = null
var _current_combo: int = 0
var _longest_combo: int = 0
var _reshuffling: bool = false
var _board_active: bool = false

# Resolved per game-start by _pick_random_tileset().
var _z_path: String = ""
var _a_path: String = ""
var _b_path: String = ""
var _c_path: String = ""

var _z_textures: Array[Texture2D] = []
var _a_textures: Array = []  # index 0 = null placeholder, 1..N = A-1..A-N
var _b_textures: Array = []
var _c_textures: Array = []

@onready var _combo_label: Label = $ComboLabel
@onready var _best_label: Label = $BestLabel
@onready var _shuffle_label: Label = $ShuffleLabel
@onready var _milestone_label: Label = $MilestoneLabel
@onready var _clear_panel: Control = $ClearPanel
@onready var _sfx_remove: AudioStreamPlayer = $SfxRemove
@onready var _sfx_break: AudioStreamPlayer = $SfxBreak
@onready var _sfx_milestone: AudioStreamPlayer = $SfxMilestone
@onready var _sparkle_template: AnimatedSprite2D = $SparkleTemplate


func _ready() -> void:
	_load_save()
	_sparkle_loop()
	# Belt-and-suspenders: wire in code so the button works even if the
	# .tscn connection was dropped by a Godot editor save/reload.
	var new_game_btn := $ClearPanel/NewGameButton as Button
	if new_game_btn and not new_game_btn.pressed.is_connected(_on_new_game_pressed):
		new_game_btn.pressed.connect(_on_new_game_pressed)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_on_back_pressed()


func prepare_board() -> void:
	_load_textures()
	_clear_board()
	_build_board()
	_current_combo = 0
	_selected = null
	_reshuffling = false
	_board_active = false
	_clear_panel.visible = false
	_update_ui()


func start_game() -> void:
	# Bloom cells into existence in a random order — like flowers opening.
	var cells_flat: Array = []
	for row in _cells:
		for cell in row:
			cells_flat.append(cell)
	cells_flat.shuffle()

	var total := cells_flat.size()
	var stagger := 1.8  # seconds over which all cells start blooming
	for i in range(total):
		var delay := float(i) / float(total) * stagger
		cells_flat[i].play_entrance(delay)

	# Activate early — first cells are visible and tappable within ~0.6 s;
	# the remaining bloom animation plays out in the background.
	await get_tree().create_timer(0.6).timeout
	if is_inside_tree():
		_board_active = true


# ----- Tileset ---------------------------------------------------------------

func _pick_random_tileset() -> void:
	var found: Array[int] = []
	for i in range(1, 20):
		if ResourceLoader.exists("res://games/tile_chain/assets/Set_%d/z-1.png" % i):
			found.append(i)
		else:
			break
	var n: int = found.pick_random() if found.size() > 0 else 1
	var base := "res://games/tile_chain/assets/Set_%d/" % n
	_z_path = base + "z-%d.png"
	_a_path = base + "A-%d.png"
	_b_path = base + "B-%d.png"
	_c_path = base + "C-%d.png"


func _load_textures() -> void:
	_pick_random_tileset()
	_z_textures.clear()
	_a_textures.clear()
	_b_textures.clear()
	_c_textures.clear()

	for i in range(1, 20):
		var p := _z_path % i
		if ResourceLoader.exists(p):
			_z_textures.append(load(p) as Texture2D)
		else:
			break

	_a_textures.append(null)
	for i in range(1, 30):
		var p := _a_path % i
		if ResourceLoader.exists(p):
			_a_textures.append(load(p) as Texture2D)
		else:
			break

	_b_textures.append(null)
	for i in range(1, 30):
		var p := _b_path % i
		if ResourceLoader.exists(p):
			_b_textures.append(load(p) as Texture2D)
		else:
			break

	_c_textures.append(null)
	for i in range(1, 30):
		var p := _c_path % i
		if ResourceLoader.exists(p):
			_c_textures.append(load(p) as Texture2D)
		else:
			break

	# Validate — warn in Output if a layer is missing tiles entirely.
	var set_n := _z_path.get_slice("/", _z_path.get_slice_count("/") - 2)
	if _z_textures.is_empty():
		push_warning("tile_chain: %s is missing z-tiles" % set_n)
	if _a_textures.size() <= 1:
		push_warning("tile_chain: %s is missing A-tiles" % set_n)
	if _b_textures.size() <= 1:
		push_warning("tile_chain: %s is missing B-tiles" % set_n)
	if _c_textures.size() <= 1:
		push_warning("tile_chain: %s is missing C-tiles" % set_n)


# ----- Board construction ----------------------------------------------------

func _clear_board() -> void:
	for row in _cells:
		for cell in row:
			if is_instance_valid(cell):
				cell.queue_free()
	_cells.clear()


# Generates `count` integers (1..variant_count) where every value appears
# an even number of times, so the board is always fully clearable.
func _generate_paired_layer(count: int, variant_count: int) -> Array[int]:
	var pool: Array[int] = []
	while pool.size() < count:
		var val := randi() % variant_count + 1
		pool.append(val)
		pool.append(val)
	pool.shuffle()
	return pool


func _build_board() -> void:
	var board_w := COLS * CELL_SIZE
	var board_h := ROWS * CELL_SIZE
	var origin_x := int((540.0 - board_w) / 2.0)
	var origin_y := int(80.0 + (810.0 - board_h) / 2.0)

	var a_count := _a_textures.size() - 1
	var b_count := _b_textures.size() - 1
	var c_count := _c_textures.size() - 1

	var total := ROWS * COLS
	var a_assign := _generate_paired_layer(total, a_count)
	var b_assign := _generate_paired_layer(total, b_count)
	var c_assign := _generate_paired_layer(total, c_count)

	var idx := 0
	for row in range(ROWS):
		var row_arr: Array = []
		for col in range(COLS):
			var cell := BoardCell.new()

			var z_idx := (row + col) % _z_textures.size()
			var z_tex: Texture2D = _z_textures[z_idx]

			var a_val: int = a_assign[idx]
			var b_val: int = b_assign[idx]
			var c_val: int = c_assign[idx]
			idx += 1

			cell.setup(z_tex, _a_textures[a_val], a_val,
					_b_textures[b_val], b_val,
					_c_textures[c_val], c_val)

			cell.position = Vector2(origin_x + col * CELL_SIZE, origin_y + row * CELL_SIZE)
			cell.tapped.connect(_on_cell_tapped)
			add_child(cell)
			row_arr.append(cell)
		_cells.append(row_arr)


# ----- Tap logic -------------------------------------------------------------

func _on_cell_tapped(cell: BoardCell) -> void:
	if not _board_active or _reshuffling:
		return

	# Tapping an empty cell never breaks the combo.
	if cell.is_empty():
		return

	# First tap: select this cell as anchor.
	if _selected == null:
		_selected = cell
		cell.show_outline(true)
		return

	# Tap the already-selected cell: deselect.
	if _selected == cell:
		cell.show_outline(false)
		_selected = null
		return

	# Find all layers shared between anchor and tapped cell.
	var shared := _find_shared(_selected, cell)

	if shared.is_empty():
		# No match — break the combo.
		_selected.show_outline(false)
		_current_combo = 0
		_update_ui()
		if _sfx_break.stream:
			_sfx_break.play()
		_selected = cell
		cell.show_outline(true)
		return

	# Remove shared elements from both cells.
	_selected.show_outline(false)
	for layer in shared:
		_selected.remove_element(layer)
		cell.remove_element(layer)

	if _sfx_remove.stream:
		_sfx_remove.play()

	_current_combo += 1
	if _current_combo > _longest_combo:
		_longest_combo = _current_combo
		_save_progress()

	# Milestone chime and pop every 10 combos.
	if _current_combo % 10 == 0:
		if _sfx_milestone.stream:
			_sfx_milestone.play()
		_show_milestone(_current_combo)

	_update_ui()

	# The tapped cell becomes the new anchor (preserved even if empty).
	if cell.is_empty():
		_selected = null
	else:
		_selected = cell
		cell.show_outline(true)

	# Check for dead or cleared board after animations settle.
	_check_dead_board()


func _find_shared(ca: BoardCell, cb: BoardCell) -> Array[String]:
	var ea := ca.get_elements()
	var eb := cb.get_elements()
	var shared: Array[String] = []
	for layer in ["a", "b", "c"]:
		if ea[layer] != 0 and ea[layer] == eb[layer]:
			shared.append(layer)
	return shared


func _is_board_cleared() -> bool:
	for row in _cells:
		for cell in row:
			if not cell.is_empty():
				return false
	return true


func _has_valid_move() -> bool:
	var non_empty: Array = []
	for row in _cells:
		for cell in row:
			if not cell.is_empty():
				non_empty.append(cell)
	for i in range(non_empty.size()):
		for j in range(i + 1, non_empty.size()):
			if not _find_shared(non_empty[i], non_empty[j]).is_empty():
				return true
	return false


func _check_dead_board() -> void:
	if _is_board_cleared():
		_on_board_cleared()
		return
	if _has_valid_move():
		return

	_reshuffling = true
	# Wait for spin-out animations to finish before reshuffling.
	await get_tree().create_timer(0.6).timeout

	# Reshuffle until a valid move exists (statistically instant).
	var attempts := 0
	while not _has_valid_move() and attempts < 20:
		_apply_reshuffle()
		attempts += 1

	# Flash the shuffle notice.
	_shuffle_label.modulate.a = 1.0
	_shuffle_label.visible = true
	var tw := create_tween()
	tw.tween_interval(1.0)
	tw.tween_property(_shuffle_label, "modulate:a", 0.0, 0.5)
	tw.tween_callback(func(): _shuffle_label.visible = false)

	_reshuffling = false


func _apply_reshuffle() -> void:
	# Collect remaining values per layer, keeping them paired (parity is
	# preserved because every match always removes exactly one pair).
	var a_pool: Array[int] = []
	var b_pool: Array[int] = []
	var c_pool: Array[int] = []
	var cells_a: Array = []
	var cells_b: Array = []
	var cells_c: Array = []

	for row in _cells:
		for cell in row:
			if cell.a_id != 0:
				a_pool.append(cell.a_id)
				cells_a.append(cell)
			if cell.b_id != 0:
				b_pool.append(cell.b_id)
				cells_b.append(cell)
			if cell.c_id != 0:
				c_pool.append(cell.c_id)
				cells_c.append(cell)

	a_pool.shuffle()
	b_pool.shuffle()
	c_pool.shuffle()

	for i in range(cells_a.size()):
		var v: int = a_pool[i]
		cells_a[i].set_element("a", _a_textures[v], v)
	for i in range(cells_b.size()):
		var v: int = b_pool[i]
		cells_b[i].set_element("b", _b_textures[v], v)
	for i in range(cells_c.size()):
		var v: int = c_pool[i]
		cells_c[i].set_element("c", _c_textures[v], v)


# ----- Board cleared ---------------------------------------------------------

func _on_board_cleared() -> void:
	_board_active = false
	if _selected:
		_selected.show_outline(false)
		_selected = null
	_clear_panel.move_to_front()  # must be last sibling to win input over board cells
	_clear_panel.visible = true


func _on_new_game_pressed() -> void:
	_clear_panel.visible = false
	prepare_board()
	start_game()


# ----- Save / load -----------------------------------------------------------

func _load_save() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		_longest_combo = cfg.get_value("progress", "longest_combo", 0)


func _save_progress() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "longest_combo", _longest_combo)
	cfg.save(SAVE_PATH)


# ----- Border sparkles -------------------------------------------------------

# Background coroutine: periodically spawns a sparkle in a random border zone.
func _sparkle_loop() -> void:
	while is_instance_valid(self) and is_inside_tree():
		await get_tree().create_timer(randf_range(3.0, 8.0)).timeout
		if not is_instance_valid(self) or not is_inside_tree():
			break
		_spawn_sparkle()


func _spawn_sparkle() -> void:
	var zone: Rect2 = SPARKLE_ZONES[randi() % SPARKLE_ZONES.size()]
	var px := randf_range(zone.position.x, zone.end.x)
	var py := randf_range(zone.position.y, zone.end.y)

	var spr := AnimatedSprite2D.new()
	spr.sprite_frames = _sparkle_template.sprite_frames
	spr.scale = _sparkle_template.scale
	spr.position = Vector2(px, py)
	# Random playback speed between 3 and 8 fps (base SpriteFrames speed is 5).
	spr.speed_scale = randf_range(3.0, 8.0) / 5.0
	spr.z_index = 5
	add_child(spr)
	spr.play("sparkle_star")
	spr.animation_finished.connect(spr.queue_free)


# ----- UI --------------------------------------------------------------------

func _update_ui() -> void:
	_combo_label.text = "Combo: %d" % _current_combo
	_best_label.text = "Best: %d" % _longest_combo


func _show_milestone(combo: int) -> void:
	if not _milestone_label:
		return
	var idx: int = clampi(int(combo / 10.0) - 1, 0, COMBO_WORDS.size() - 1)
	_milestone_label.text = COMBO_WORDS[idx] as String
	_milestone_label.modulate.a = 1.0
	_milestone_label.scale = Vector2(0.55, 0.55)
	_milestone_label.visible = true
	var tw := create_tween()
	tw.tween_property(_milestone_label, "scale", Vector2(1.0, 1.0), 0.22) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.75)
	tw.tween_property(_milestone_label, "modulate:a", 0.0, 0.38) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): if _milestone_label: _milestone_label.visible = false)


# ----- Navigation ------------------------------------------------------------

func _on_back_pressed() -> void:
	if _selected:
		_selected.show_outline(false)
		_selected = null
	back_to_menu.emit()
