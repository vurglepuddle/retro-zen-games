#Game.gd (zen_farm)
extends Control

signal back_to_menu

# ── layout ──────────────────────────────────────────────────────────────────
const COLS        := 4
const ROWS        := 4
const TILE_SIZE   := FarmCell.TILE_SIZE
const GAP         := 8
const GRID_W      := COLS * (TILE_SIZE + GAP) - GAP   # 504
const GRID_H      := ROWS * (TILE_SIZE + GAP) - GAP   # 504
const GRID_X      := (540 - GRID_W) / 2.0             # 18

# ── tools ───────────────────────────────────────────────────────────────────
enum Tool { HAND, WATERING_CAN, SHEARS }
var _active_tool: Tool = Tool.HAND

# Watering can resource
const CAN_MAX    := 5
var _can_water: int = 0

# Seed panel state (independent of tool — opens/closes via SEEDS button)
var _seeds_open:    bool = false
var _selected_crop: int  = CropData.CARROT

# ── state ────────────────────────────────────────────────────────────────────
var _cells: Array       = []    # Array[FarmCell], row-major (row*COLS+col)
var _coins: int         = 8
var _inventory: Dictionary = {} # crop_id → count
var _last_save_time: float = 0.0

# Weed spawning
var _weed_timer: float  = 0.0
const WEED_INTERVAL     := 45.0

# ── UI refs ──────────────────────────────────────────────────────────────────
@onready var _coins_label:    Label   = $TopBar/CoinsLabel
@onready var _mode_label:     Label   = $TopBar/ModeLabel
@onready var _status_label:   Label   = $StatusLabel
@onready var _grid_container: Control = $GridContainer
@onready var _seed_panel:     Control = $SeedPanel
@onready var _inv_label:      Label   = $SeedPanel/InvLabel
@onready var _back_btn:       Button  = $BottomBar/BackButton
@onready var _seeds_btn:      Button  = $BottomBar/SeedsButton
@onready var _sell_btn:       Button  = $BottomBar/SellButton
@onready var _status_timer:   Timer   = $StatusTimer

@onready var _hand_btn:       Button  = $ToolBar/HandBtn
@onready var _can_btn:        Button  = $ToolBar/CanBtn
@onready var _shears_btn:     Button  = $ToolBar/ShearsBtn
@onready var _well_panel:     Control = $WellPanel
@onready var _well_label:     Label   = $WellPanel/WellLabel
@onready var _tip_panel:      Control = $TipPanel


func _ready() -> void:
	_back_btn.pressed.connect(_on_back_pressed)
	_seeds_btn.pressed.connect(_on_seeds_btn_pressed)
	_sell_btn.pressed.connect(_on_sell_pressed)
	$SeedPanel/CarrotBtn.pressed.connect(_on_carrot_selected)
	$SeedPanel/LettuceBtn.pressed.connect(_on_lettuce_selected)
	$SeedPanel/PotatoBtn.pressed.connect(_on_potato_selected)
	_status_timer.timeout.connect(_on_status_timeout)

	_hand_btn.pressed.connect(_on_hand_btn_pressed)
	_can_btn.pressed.connect(_on_can_btn_pressed)
	_shears_btn.pressed.connect(_on_shears_btn_pressed)
	_well_panel.gui_input.connect(_on_well_gui_input)
	$TipPanel/Card/GotItBtn.pressed.connect(_on_got_it_pressed)


func _crop_name(crop_id: int) -> String:
	const NAMES := ["Carrot", "Lettuce", "Potato"]
	return NAMES[crop_id] if crop_id >= 0 and crop_id < NAMES.size() else "?"

func _on_carrot_selected()  -> void: _select_seed(CropData.CARROT)
func _on_lettuce_selected() -> void: _select_seed(CropData.LETTUCE)
func _on_potato_selected()  -> void: _select_seed(CropData.POTATO)
func _on_status_timeout()   -> void: _status_label.text = ""


func _on_got_it_pressed() -> void:
	_tip_panel.visible = false


func prepare_farm() -> void:
	_clear_cells()
	_build_cells()
	var loaded := SaveManager.load_game(self)
	if loaded:
		_apply_offline_catchup()
	else:
		_coins        = 8
		_can_water    = 0
		_active_tool  = Tool.HAND
		_seeds_open   = false
		_inventory.clear()
		_weed_timer     = 0.0
		_last_save_time = 0.0
		_seed_panel.visible = false
		_tip_panel.visible  = true
	_refresh_ui()


func start_game() -> void:
	_active_tool = Tool.HAND
	_seeds_open  = false
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
	_apply_initial_layout()


# Starting state for a brand-new farm (overwritten by save on load).
# All 12 locked tiles share the same current price — player picks any spot.
# Cost steps up as more land is purchased (see _next_unlock_cost).
func _apply_initial_layout() -> void:
	for cell in _cells:
		cell.state       = FarmCell.TileState.LOCKED
		cell.unlock_cost = 2   # always the starting price; updated by _update_lock_costs after each purchase
		cell.refresh_visual()


# Cost of the NEXT land purchase, based on how many tiles have been unlocked
# beyond the starting 4.  All locked tiles always show the same price.
#   purchases 1–4  →  2 coins
#   purchases 5–8  →  4 coins
#   purchases 9–11 → 12 coins
#   purchase  12   → 25 coins
func _next_unlock_cost() -> int:
	var bought := 0
	for cell in _cells:
		if cell.state != FarmCell.TileState.LOCKED:
			bought += 1
	if bought < 4:  return 2
	if bought < 8:  return 4
	if bought < 12: return 12
	return 25


# Refresh the displayed cost on every remaining locked tile after a purchase.
func _update_lock_costs() -> void:
	var cost := _next_unlock_cost()
	for cell in _cells:
		if cell.state == FarmCell.TileState.LOCKED:
			cell.unlock_cost = cost
			cell.refresh_visual()


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

	var soil_indices: Array = []
	for i in range(_cells.size()):
		if _cells[i].state == FarmCell.TileState.SOIL:
			soil_indices.append(i)
	if soil_indices.is_empty():
		return

	var weed_count := 0
	for c in _cells:
		if c.state == FarmCell.TileState.WEED:
			weed_count += 1
	var max_weeds: int = max(1, int(soil_indices.size() * 0.3))
	if weed_count >= max_weeds:
		return

	if randf() < 0.4:
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

		var t := remaining
		while t > 0.0 and cell.growth_stage < CropData.STAGE_MATURE:
			if not cell.watered:
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
						cell.watered = false
				else:
					cell.time_in_stage += t
					t = 0.0
		cell.refresh_visual()


# ── tool buttons ─────────────────────────────────────────────────────────
func _on_hand_btn_pressed() -> void:
	_active_tool = Tool.HAND
	_refresh_ui()

func _on_can_btn_pressed() -> void:
	_active_tool = Tool.WATERING_CAN
	_seeds_open  = false
	_seed_panel.visible = false
	_refresh_ui()

func _on_shears_btn_pressed() -> void:
	_active_tool = Tool.SHEARS
	_seeds_open  = false
	_seed_panel.visible = false
	_refresh_ui()


# ── well ─────────────────────────────────────────────────────────────────
func _on_well_gui_input(event: InputEvent) -> void:
	var pressed := false
	if event is InputEventMouseButton:
		pressed = event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	elif event is InputEventScreenTouch:
		pressed = event.pressed
	if not pressed:
		return
	get_viewport().set_input_as_handled()

	if _active_tool != Tool.WATERING_CAN:
		_show_status("Equip the Watering Can first.")
		return
	if _can_water == CAN_MAX:
		_show_status("Can is already full.")
		return
	_can_water = CAN_MAX
	_refresh_ui()
	_show_status("Can filled! (" + str(CAN_MAX) + "/" + str(CAN_MAX) + ")")
	SaveManager.save_game(self)


# ── cell tap handler ──────────────────────────────────────────────────────
func _on_cell_tapped(cell: FarmCell) -> void:
	# SEEDS panel open: tap soil to plant, tap anything else to prompt
	if _seeds_open:
		if cell.state == FarmCell.TileState.SOIL:
			_try_plant(cell)
		else:
			_show_status("Choose an empty soil patch.")
		return

	match _active_tool:
		Tool.HAND:          _try_hand(cell)
		Tool.WATERING_CAN:  _try_water_cell(cell)
		Tool.SHEARS:        _try_shear(cell)


# HAND tool: unlock tiles; guide player toward the right tool for everything else
func _try_hand(cell: FarmCell) -> void:
	match cell.state:
		FarmCell.TileState.SOIL:
			_show_status("Tap SEEDS to plant.")
		FarmCell.TileState.WEED:
			_show_status("Use Shears to cut weeds.")
		FarmCell.TileState.CROP:
			if cell.growth_stage == CropData.STAGE_MATURE:
				_show_status("Ready! Use Shears to harvest.")
			elif not cell.watered:
				_show_status("Thirsty! Use Watering Can.")
			else:
				_show_status("Growing steadily.")
		FarmCell.TileState.WILTED:
			_show_status("Wilted! Use Watering Can.")
		FarmCell.TileState.LOCKED:
			var cost := _next_unlock_cost()
			if _coins >= cost:
				_coins -= cost
				cell.state = FarmCell.TileState.SOIL
				cell.refresh_visual()
				_update_lock_costs()
				_refresh_ui()
				_show_status("Land unlocked!")
				SaveManager.save_game(self)
			else:
				_show_status("Need " + str(cost) + " coins.")


# WATERING CAN tool: water crops; guide to well when empty
func _try_water_cell(cell: FarmCell) -> void:
	if _can_water <= 0:
		_show_status("Can is empty — fill at the Well.")
		return
	match cell.state:
		FarmCell.TileState.CROP:
			if cell.growth_stage == CropData.STAGE_MATURE:
				_show_status("Use Shears to harvest this one.")
			elif cell.watered:
				_show_status("Already watered.")
			else:
				cell.watered    = true
				cell.wilt_timer = 0.0
				cell.refresh_visual()
				_can_water -= 1
				_refresh_ui()
				_show_status("Watered! (" + str(_can_water) + "/" + str(CAN_MAX) + " left)")
				SaveManager.save_game(self)
		FarmCell.TileState.WILTED:
			cell.state      = FarmCell.TileState.CROP
			cell.watered    = true
			cell.wilt_timer = 0.0
			cell.refresh_visual()
			_can_water -= 1
			_refresh_ui()
			_show_status("Revived! (" + str(_can_water) + "/" + str(CAN_MAX) + " left)")
			SaveManager.save_game(self)
		_:
			_show_status("Nothing to water here.")


# SHEARS tool: harvest mature crops and cut weeds
func _try_shear(cell: FarmCell) -> void:
	match cell.state:
		FarmCell.TileState.CROP:
			if cell.growth_stage == CropData.STAGE_MATURE:
				var value := CropData.get_sell_value(cell.crop_id)
				_coins += value
				_inventory[cell.crop_id] = _inventory.get(cell.crop_id, 0) + 1
				cell.state        = FarmCell.TileState.SOIL
				cell.crop_id      = -1
				cell.growth_stage = 0
				cell.time_in_stage = 0.0
				cell.watered      = false
				cell.wilt_timer   = 0.0
				cell.refresh_visual()
				_show_status("Harvested! +" + str(value) + " coins")
				_refresh_ui()
				SaveManager.save_game(self)
			else:
				_show_status("Not ready yet — keep watering.")
		FarmCell.TileState.WEED:
			cell.state = FarmCell.TileState.SOIL
			cell.refresh_visual()
			_show_status("Weed cut!")
			SaveManager.save_game(self)
		_:
			_show_status("Nothing to cut here.")


# SEEDS panel: plant on soil
func _try_plant(cell: FarmCell) -> void:
	cell.state         = FarmCell.TileState.CROP
	cell.crop_id       = _selected_crop
	cell.growth_stage  = CropData.STAGE_SEED
	cell.time_in_stage = 0.0
	cell.watered       = false
	cell.wilt_timer    = 0.0
	cell.refresh_visual()
	_show_status("Planted " + _crop_name(_selected_crop) + "!")
	SaveManager.save_game(self)


# ── seed panel button ─────────────────────────────────────────────────────
func _on_seeds_btn_pressed() -> void:
	if _seeds_open:
		_seeds_open = false
	else:
		_active_tool = Tool.HAND   # always enter hand mode when opening seeds
		_seeds_open  = true
	_seed_panel.visible = _seeds_open
	_refresh_ui()


func _select_seed(crop_id: int) -> void:
	_selected_crop = crop_id
	_refresh_ui()
	_show_status("Selected: " + _crop_name(crop_id))


func _on_sell_pressed() -> void:
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

	# top-right: active tool + can level
	match _active_tool:
		Tool.HAND:
			_mode_label.text = "PLANTING" if _seeds_open else "HAND"
		Tool.WATERING_CAN:
			_mode_label.text = "CAN " + str(_can_water) + "/" + str(CAN_MAX)
		Tool.SHEARS:
			_mode_label.text = "SHEARS"

	# tool button highlight (brighter = active)
	_hand_btn.modulate   = Color(1.6, 1.6, 1.0) if _active_tool == Tool.HAND   else Color.WHITE
	_can_btn.modulate    = Color(1.0, 1.6, 2.0) if _active_tool == Tool.WATERING_CAN else Color.WHITE
	_shears_btn.modulate = Color(2.0, 1.4, 1.0) if _active_tool == Tool.SHEARS else Color.WHITE

	# can button text shows water level
	_can_btn.text = "CAN " + str(_can_water) + "/" + str(CAN_MAX)

	# well label
	_well_label.text = "WELL\ntap to fill"

	# seeds bottom button
	_seeds_btn.text = "CANCEL" if _seeds_open else "SEEDS"

	# seed panel highlights
	$SeedPanel/CarrotBtn.text  = ("► " if _selected_crop == CropData.CARROT  else "") + "Carrot"
	$SeedPanel/LettuceBtn.text = ("► " if _selected_crop == CropData.LETTUCE else "") + "Lettuce"
	$SeedPanel/PotatoBtn.text  = ("► " if _selected_crop == CropData.POTATO  else "") + "Potato"

	# inventory in seed panel
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
