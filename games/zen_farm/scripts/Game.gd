#Game.gd (zen_farm)
extends Control

signal back_to_menu

# ── layout ──────────────────────────────────────────────────────────────────
const COLS        := 4
const ROWS        := 4
const TILE_SIZE   := FarmCell.TILE_SIZE
const GAP         := 8
const GRID_W      := COLS * (TILE_SIZE + GAP) - GAP   # 300
const GRID_H      := ROWS * (TILE_SIZE + GAP) - GAP   # 300
const GRID_X      := (540 - GRID_W) / 2.0             # 120
const GRID_Y      := 130

# ── modes ───────────────────────────────────────────────────────────────────
enum Mode { DEFAULT, PLANT }
var _mode: Mode = Mode.DEFAULT
var _selected_crop: int = CropData.CARROT

# ── state ────────────────────────────────────────────────────────────────────
var _cells: Array       = []    # Array[FarmCell], row-major (row*COLS+col)
var _coins: int         = 10
var _inventory: Dictionary = {} # crop_id → count
var _last_save_time: float = 0.0

# Weed spawning
var _weed_timer: float  = 0.0
const WEED_INTERVAL     := 45.0   # seconds between weed-spawn attempts

# ── UI refs ──────────────────────────────────────────────────────────────────
@onready var _coins_label:    Label   = $TopBar/CoinsLabel
@onready var _mode_label:     Label   = $TopBar/ModeLabel
@onready var _status_label:   Label   = $StatusLabel
@onready var _grid_container: Control = $GridContainer
@onready var _seed_panel:     Control = $SeedPanel
@onready var _inv_label:      Label   = $SeedPanel/InvLabel
@onready var _back_btn:       Button  = $BottomBar/BackButton
@onready var _plant_btn:      Button  = $BottomBar/PlantButton
@onready var _sell_btn:       Button  = $BottomBar/SellButton
@onready var _status_timer:   Timer   = $StatusTimer


func _ready() -> void:
	_back_btn.pressed.connect(_on_back_pressed)
	_plant_btn.pressed.connect(_on_plant_pressed)
	_sell_btn.pressed.connect(_on_sell_pressed)
	$SeedPanel/CarrotBtn.pressed.connect(_on_carrot_selected)
	$SeedPanel/LettuceBtn.pressed.connect(_on_lettuce_selected)
	$SeedPanel/PotatoBtn.pressed.connect(_on_potato_selected)
	_status_timer.timeout.connect(_on_status_timeout)


func _crop_name(crop_id: int) -> String:
	const NAMES := ["Carrot", "Lettuce", "Potato"]
	return NAMES[crop_id] if crop_id >= 0 and crop_id < NAMES.size() else "?"

func _on_carrot_selected()  -> void: _select_seed(CropData.CARROT)
func _on_lettuce_selected() -> void: _select_seed(CropData.LETTUCE)
func _on_potato_selected()  -> void: _select_seed(CropData.POTATO)
func _on_status_timeout()   -> void: _status_label.text = ""


func prepare_farm() -> void:
	_clear_cells()
	_build_cells()
	var loaded := SaveManager.load_game(self)
	if loaded:
		_apply_offline_catchup()
	_refresh_ui()


func start_game() -> void:
	_mode = Mode.DEFAULT
	_seed_panel.visible = false
	_refresh_ui()


# ── build ─────────────────────────────────────────────────────────────────
func _clear_cells() -> void:
	for c in _cells:
		if is_instance_valid(c):
			c.queue_free()
	_cells.clear()


func _build_cells() -> void:
	for row in range(ROWS):
		for col in range(COLS):
			var cell := FarmCell.new()
			_grid_container.add_child(cell)
			cell.position = Vector2(col * (TILE_SIZE + GAP), row * (TILE_SIZE + GAP))
			cell.tapped.connect(_on_cell_tapped)
			_cells.append(cell)


# ── process ───────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	_tick_crops(delta)
	_tick_weeds(delta)


func _tick_crops(delta: float) -> void:
	for cell in _cells:
		if cell.state != FarmCell.TileState.CROP:
			continue
		if cell.growth_stage == CropData.STAGE_MATURE:
			continue
		var dur: float = CropData.get_stage_durations(cell.crop_id)[cell.growth_stage]
		if not cell.watered:
			cell.wilt_timer += delta
			if cell.wilt_timer >= dur * 2.0:
				cell.state = FarmCell.TileState.WILTED
				cell.refresh_visual()
		else:
			cell.time_in_stage += delta
			if cell.time_in_stage >= dur:
				cell.time_in_stage -= dur
				cell.growth_stage  += 1
				cell.wilt_timer     = 0.0
				if cell.growth_stage < CropData.STAGE_MATURE:
					cell.watered = false
				cell.refresh_visual()


func _tick_weeds(delta: float) -> void:
	_weed_timer += delta
	if _weed_timer < WEED_INTERVAL:
		return
	_weed_timer = 0.0

	# collect empty soil indices
	var soil_indices: Array = []
	for i in range(_cells.size()):
		if _cells[i].state == FarmCell.TileState.SOIL:
			soil_indices.append(i)
	if soil_indices.is_empty():
		return

	# cap at 30% weeds of empty tiles
	var weed_count := 0
	for c in _cells:
		if c.state == FarmCell.TileState.WEED:
			weed_count += 1
	var max_weeds: int = max(1, int(soil_indices.size() * 0.3))
	if weed_count >= max_weeds:
		return

	# random spawn on one soil tile
	if randf() < 0.4:  # 40% chance each interval
		var idx: int = soil_indices[randi() % soil_indices.size()]
		_cells[idx].state = FarmCell.TileState.WEED
		_cells[idx].refresh_visual()


# ── offline catch-up ──────────────────────────────────────────────────────
func _apply_offline_catchup() -> void:
	if _last_save_time <= 0.0:
		return
	var elapsed := Time.get_unix_time_from_system() - _last_save_time
	if elapsed <= 0.0:
		return

	var remaining := elapsed
	for cell in _cells:
		if cell.state != FarmCell.TileState.CROP:
			continue
		if cell.growth_stage == CropData.STAGE_MATURE:
			continue

		# process stages using offline time
		var t := remaining
		while t > 0.0 and cell.growth_stage < CropData.STAGE_MATURE:
			if not cell.watered:
				# count wilt exposure
				var dur: float = CropData.get_stage_durations(cell.crop_id)[cell.growth_stage]
				var can_wilt := minf(t, dur * 2.0 - cell.wilt_timer)
				cell.wilt_timer += can_wilt
				t -= can_wilt
				if cell.wilt_timer >= dur * 2.0:
					cell.state = FarmCell.TileState.WILTED
				break
			else:
				var dur: float = CropData.get_stage_durations(cell.crop_id)[cell.growth_stage]
				var left: float = dur - cell.time_in_stage
				if t >= left:
					t -= left
					cell.time_in_stage = 0.0
					cell.growth_stage  += 1
					cell.wilt_timer     = 0.0
					if cell.growth_stage < CropData.STAGE_MATURE:
						cell.watered = false  # would need watering offline → wilt next iter
				else:
					cell.time_in_stage += t
					t = 0.0
		cell.refresh_visual()


# ── cell tap handler ──────────────────────────────────────────────────────
func _on_cell_tapped(cell: FarmCell) -> void:
	match _mode:
		Mode.PLANT:
			_try_plant(cell)
		Mode.DEFAULT:
			_try_interact(cell)


func _try_plant(cell: FarmCell) -> void:
	if cell.state != FarmCell.TileState.SOIL:
		_show_status("Need empty soil to plant.")
		return
	# spend a seed (free in MVP — seeds assumed available)
	cell.state        = FarmCell.TileState.CROP
	cell.crop_id      = _selected_crop
	cell.growth_stage = CropData.STAGE_SEED
	cell.time_in_stage = 0.0
	cell.watered      = false
	cell.wilt_timer   = 0.0
	cell.refresh_visual()
	_show_status("Planted " + _crop_name(_selected_crop) + "!")
	SaveManager.save_game(self)


func _try_interact(cell: FarmCell) -> void:
	match cell.state:
		FarmCell.TileState.SOIL:
			_show_status("Tap PLANT to sow seeds.")

		FarmCell.TileState.WEED:
			cell.state = FarmCell.TileState.SOIL
			cell.refresh_visual()
			_show_status("Pulled a weed.")
			SaveManager.save_game(self)

		FarmCell.TileState.CROP:
			if cell.growth_stage == CropData.STAGE_MATURE:
				# harvest
				var value := CropData.get_sell_value(cell.crop_id)
				_coins += value
				_inventory[cell.crop_id] = _inventory.get(cell.crop_id, 0) + 1
				cell.state       = FarmCell.TileState.SOIL
				cell.crop_id     = -1
				cell.growth_stage = 0
				cell.time_in_stage = 0.0
				cell.watered     = false
				cell.wilt_timer  = 0.0
				cell.refresh_visual()
				_show_status("Harvested! +" + str(value) + " coins")
				_refresh_ui()
				SaveManager.save_game(self)
			elif not cell.watered:
				# water it
				cell.watered    = true
				cell.wilt_timer = 0.0
				cell.refresh_visual()
				_show_status("Watered!")
				SaveManager.save_game(self)
			else:
				_show_status("Already watered — growing.")

		FarmCell.TileState.WILTED:
			# watering recovers wilted crop
			cell.state      = FarmCell.TileState.CROP
			cell.watered    = true
			cell.wilt_timer = 0.0
			cell.refresh_visual()
			_show_status("Revived! Keep watering.")
			SaveManager.save_game(self)

		FarmCell.TileState.LOCKED:
			if _coins >= cell.unlock_cost:
				_coins -= cell.unlock_cost
				cell.state = FarmCell.TileState.SOIL
				cell.refresh_visual()
				_refresh_ui()
				_show_status("Land unlocked!")
				SaveManager.save_game(self)
			else:
				_show_status("Need " + str(cell.unlock_cost) + " coins.")


# ── mode buttons ──────────────────────────────────────────────────────────
func _on_plant_pressed() -> void:
	if _mode == Mode.PLANT:
		_mode = Mode.DEFAULT
		_seed_panel.visible = false
	else:
		_mode = Mode.PLANT
		_seed_panel.visible = true
	_refresh_ui()


func _select_seed(crop_id: int) -> void:
	_selected_crop = crop_id
	_refresh_ui()
	_show_status("Selected: " + _crop_name(crop_id))


func _on_sell_pressed() -> void:
	# Sell all harvested items at market rate (~70% of sell value)
	var total := 0
	for cid in _inventory:
		var count: int = _inventory[cid]
		total += int(CropData.get_sell_value(cid) * 0.7 * count)
	if total == 0:
		_show_status("Nothing to sell.")
		return
	_coins += total
	_inventory.clear()
	_refresh_ui()
	_show_status("Sold for +" + str(total) + " coins!")
	SaveManager.save_game(self)


func _on_back_pressed() -> void:
	SaveManager.save_game(self)
	back_to_menu.emit()


# ── UI refresh ────────────────────────────────────────────────────────────
func _refresh_ui() -> void:
	_coins_label.text = str(_coins) + " coins"

	match _mode:
		Mode.DEFAULT:
			_mode_label.text = ""
			_plant_btn.text  = "PLANT"
		Mode.PLANT:
			_mode_label.text = "PLANT MODE"
			_plant_btn.text  = "CANCEL"

	# seed panel seed highlight
	$SeedPanel/CarrotBtn.text  = ("► " if _selected_crop == CropData.CARROT  else "") + "Carrot"
	$SeedPanel/LettuceBtn.text = ("► " if _selected_crop == CropData.LETTUCE else "") + "Lettuce"
	$SeedPanel/PotatoBtn.text  = ("► " if _selected_crop == CropData.POTATO  else "") + "Potato"

	# inventory label
	var parts: Array = []
	for cid in [CropData.CARROT, CropData.LETTUCE, CropData.POTATO]:
		var cnt: int = _inventory.get(cid, 0)
		if cnt > 0:
			parts.append(_crop_name(cid) + "×" + str(cnt))
	_inv_label.text = ("Harvested: " + ", ".join(parts)) if not parts.is_empty() else ""


func _show_status(msg: String) -> void:
	_status_label.text = msg
	_status_timer.start(2.5)


# ── app background save ───────────────────────────────────────────────────
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		back_to_menu.emit()
	elif what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		SaveManager.save_game(self)
