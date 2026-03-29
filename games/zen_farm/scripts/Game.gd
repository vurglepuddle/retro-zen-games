#Game.gd (zen_farm)
extends Control

signal back_to_menu

# ── layout ──────────────────────────────────────────────────────────────────
const ROWS      := 5
const TILE_SIZE := FarmCell.TILE_SIZE
const GAP       := 0

var _cols: int = 4        # grows when all current tiles are bought

# manual pan (replaces ScrollContainer)
var _scroll_x:     int = 0
var _max_scroll_x: int = 0

# tap-vs-drag tracking (touch + mouse)
var _touch_start     := Vector2.ZERO
var _touch_drag_dist := 0.0
var _touch_cell: FarmCell = null

# ── tools ───────────────────────────────────────────────────────────────────
enum Tool { HAND, WATERING_CAN, SHEARS }
var _active_tool: Tool = Tool.HAND

# Watering can — capacity scales with upgrade level
var _can_level: int = 0   # 0 = 5 charges  |  1 = 10  |  2 = 20 (MAX)
var _can_water: int = 0

func _can_max() -> int:
	match _can_level:
		1: return 10
		2: return 20
	return 5

func _can_upgrade_cost() -> int:   # −1 = already MAX
	match _can_level:
		0: return 15
		1: return 35
	return -1

func _can_next_max() -> int:
	match _can_level:
		0: return 10
		1: return 20
	return 20

# Seed / shop panel state
var _seeds_open:    bool = false
var _shop_open:     bool = false
var _selected_crop: int  = -1   # -1 = nothing selected yet

# ── state ────────────────────────────────────────────────────────────────────
var _game_active: bool     = false   # true only while the player is in-session
var _cells: Array          = []
var _coins: int            = 10
var _inventory: Dictionary = {}
var _last_save_time: float = 0.0
var _decor_placed: Dictionary = {}   # Vector2i(col,row) → true; prevents re-RNG on refresh
var _wilt_map: TileMapLayer = null   # brown overlay on wilted tiles; built in _ready()
var _icon_container: Node2D = null        # parent for harvest-ready bounce icons
var _harvest_icons: Dictionary = {}       # Vector2i(col,row) → Sprite2D

# Weed spawning
var _weed_timer: float    = 0.0
var _weed_tip_shown: bool = false
const WEED_INTERVAL       := 45.0

# ── UI refs ──────────────────────────────────────────────────────────────────
@onready var _coins_label:    Label   = $TopBar/CoinsLabel
@onready var _mode_label:     Label   = $TopBar/ModeLabel
@onready var _status_label:   Label   = $StatusLabel
@onready var _grid_container: Control        = $FarmScroll/GridContainer
@onready var _terrain_map:   TileMapLayer   = $FarmScroll/TerrainMapLayer
@onready var _decor_map:     TileMapLayer   = $FarmScroll/DecorMapLayer
@onready var _plant_map:     TileMapLayer   = $FarmScroll/PlantMapLayer
@onready var _moisture_map:  TileMapLayer   = $FarmScroll/MoistureMapLayer

# ── tilemap constants ─────────────────────────────────────────────────────────
# TerrainMapLayer — terrain set 0
const TM_TERRAIN_SET  := 0
const TM_SOIL         := 0   # 47-tile autotile terrain
const TM_GRASS        := 1   # single grass tile terrain
# DecorMapLayer — terrain set 0
const DM_TERRAIN_SET  := 0
const DM_DECOR        := 0   # 16 random decor items
# PlantMapLayer — source id 0 (objects.png)
# atlas coords: col = crop_id (0-4), row = stage row
const PM_SOURCE       := 1
const PM_SEED_ROW     := 2   # stage 0 — seed (1-tall)
const PM_SPROUT_ROW   := 3   # stage 1 — sprout (1-tall)
const PM_GROWING_ROW  := 4   # stage 2 — growing (2-tall)
const PM_MATURE_ROW   := 6   # stage 3 — mature (2-tall)
@onready var _seed_panel:     Control = $SeedPanel
@onready var _inv_label:      Label   = $SeedPanel/InvLabel
@onready var _upgrade_panel:  Control = $UpgradePanel
@onready var _can_upgrade_btn: Button = $UpgradePanel/CanUpgradeBtn
@onready var _back_btn:       Button  = $BottomBar/BackButton
@onready var _seeds_btn:      Button  = $BottomBar/SeedsButton
@onready var _shop_btn:       Button  = $BottomBar/ShopButton
@onready var _sell_btn:       Button  = $BottomBar/SellButton
@onready var _status_timer:   Timer   = $StatusTimer

@onready var _hand_btn:       Button  = $ToolBar/HandBtn
@onready var _can_btn:        Button  = $ToolBar/CanBtn
@onready var _shears_btn:     Button  = $ToolBar/ShearsBtn
@onready var _well_panel:     Control = $WellPanel
@onready var _well_label:     Label   = $WellPanel/WellLabel
@onready var _tip_panel:      Control = $TipPanel

# ── SFX nodes ────────────────────────────────────────────────────────────────
@onready var _sfx_plant:    AudioStreamPlayer = $SfxPlant
@onready var _sfx_water:    AudioStreamPlayer = $SfxWater
@onready var _sfx_well:     AudioStreamPlayer = $SfxWellFill
@onready var _sfx_harvest:  AudioStreamPlayer = $SfxHarvest
@onready var _sfx_weedcut:  AudioStreamPlayer = $SfxWeedCut
@onready var _sfx_buy:      AudioStreamPlayer = $SfxBuyLand
@onready var _sfx_sell_snd: AudioStreamPlayer = $SfxSell
@onready var _sfx_upgrade:  AudioStreamPlayer = $SfxUpgrade
@onready var _sfx_crop_tap: AudioStreamPlayer = $SfxCropTap
@onready var _sfx_noaction: AudioStreamPlayer = $SfxNoAction


func _ready() -> void:
	_back_btn.pressed.connect(_on_back_pressed)
	_seeds_btn.pressed.connect(_on_seeds_btn_pressed)
	_shop_btn.pressed.connect(_on_shop_btn_pressed)
	_sell_btn.pressed.connect(_on_sell_pressed)
	$SeedPanel/LettuceBtn.pressed.connect(func(): _select_seed(CropData.LETTUCE))
	$SeedPanel/CarrotBtn.pressed.connect(func():  _select_seed(CropData.CARROT))
	$SeedPanel/PotatoBtn.pressed.connect(func():  _select_seed(CropData.POTATO))
	$SeedPanel/TomatoBtn.pressed.connect(func():  _select_seed(CropData.TOMATO))
	$SeedPanel/PumpkinBtn.pressed.connect(func(): _select_seed(CropData.PUMPKIN))
	_can_upgrade_btn.pressed.connect(_on_can_upgrade_pressed)
	_status_timer.timeout.connect(func(): _status_label.text = "")

	_hand_btn.pressed.connect(_on_hand_btn_pressed)
	_can_btn.pressed.connect(_on_can_btn_pressed)
	_shears_btn.pressed.connect(_on_shears_btn_pressed)
	_well_panel.gui_input.connect(_on_well_gui_input)
	$TipPanel/Card/GotItBtn.pressed.connect(func(): _tip_panel.visible = false)
	_load_sfx()
	_setup_wilt_overlay()
	_icon_container = Node2D.new()
	_icon_container.z_index = 10
	$FarmScroll.add_child(_icon_container)


func prepare_farm() -> void:
	_game_active = false
	_touch_cell  = null
	_cols = SaveManager.load_cols()
	_clear_cells()
	_build_cells()
	var loaded := SaveManager.load_game(self)
	if loaded:
		_update_lock_costs()
		_apply_offline_catchup()
		_upgrade_panel.visible = false
		_shop_open = false
	else:
		_coins         = 100000
		_can_water     = 0
		_can_level     = 0
		_active_tool   = Tool.HAND
		_seeds_open    = false
		_shop_open     = false
		_selected_crop = -1
		_inventory.clear()
		_weed_timer      = 0.0
		_weed_tip_shown  = false
		_last_save_time  = 0.0
		_seed_panel.visible    = false
		_upgrade_panel.visible = false
		_tip_panel.visible     = true
	_refresh_ui()
	# Defer so the ScrollContainer has completed its first layout pass before
	# we set custom_minimum_size — otherwise the scroll range isn't registered.
	_update_grid_size.call_deferred()


func start_game() -> void:
	_game_active = true
	_active_tool = Tool.HAND
	_seeds_open  = false
	_shop_open   = false
	_seed_panel.visible    = false
	_upgrade_panel.visible = false
	_refresh_ui()


# ── build ─────────────────────────────────────────────────────────────────
func _clear_cells() -> void:
	for c in _cells:
		if is_instance_valid(c):
			c.queue_free()
	_cells.clear()
	_decor_placed.clear()
	for icon in _harvest_icons.values():
		if is_instance_valid(icon): icon.queue_free()
	_harvest_icons.clear()


func _build_cells() -> void:
	for row in range(ROWS):
		for col in range(_cols):
			var cell := FarmCell.new()
			_grid_container.add_child(cell)
			cell.position = Vector2(col * (TILE_SIZE + GAP), row * (TILE_SIZE + GAP))
			cell.grid_row = row
			cell.grid_col = col
			cell.visual_changed.connect(_refresh_cell_tilemap.bind(cell))
			_cells.append(cell)
	_apply_initial_layout()
	_place_bottom_border_decor(0, _cols)
	_place_side_border_column(-1)          # left edge — placed once at build
	_place_side_border_column(_cols * 2)   # right edge
	_place_top_border_decor(0, _cols)
	_update_grid_size()


func _apply_initial_layout() -> void:
	for cell in _cells:
		cell.state       = FarmCell.TileState.LOCKED
		cell.unlock_cost = 2
		cell.refresh_visual()


# ── land unlock pricing ───────────────────────────────────────────────────
func _has_active_crops() -> bool:
	for cell in _cells:
		if cell.state == FarmCell.TileState.CROP or cell.state == FarmCell.TileState.WILTED:
			return true
	return false


func _update_grid_size() -> void:
	var stride    := TILE_SIZE + GAP
	var content_w := _cols * stride - GAP
	var left_x    := maxf(18.0, (540.0 - content_w) * 0.5)
	_max_scroll_x  = maxi(0, int(content_w + left_x + 18.0) - 540)
	_scroll_x      = clampi(_scroll_x, 0, _max_scroll_x)
	var pos := Vector2(left_x - _scroll_x, 34.0)
	_grid_container.position = pos
	_terrain_map.position    = pos
	_decor_map.position      = pos
	_plant_map.position      = pos
	if _wilt_map:           _wilt_map.position           = pos
	if _icon_container:     _icon_container.position     = pos
	if _moisture_map:       _moisture_map.position       = pos


func _apply_scroll(delta: int) -> void:
	_scroll_x = clampi(_scroll_x + delta, 0, _max_scroll_x)
	var stride    := TILE_SIZE + GAP
	var content_w := _cols * stride - GAP
	var left_x    := maxf(18.0, (540.0 - content_w) * 0.5)
	var pos := Vector2(left_x - _scroll_x, 34.0)
	_grid_container.position = pos
	_terrain_map.position    = pos
	_decor_map.position      = pos
	_plant_map.position      = pos
	if _wilt_map:           _wilt_map.position           = pos
	if _icon_container:     _icon_container.position     = pos
	if _moisture_map:       _moisture_map.position       = pos


# ── tilemap refresh ───────────────────────────────────────────────────────────
func _cell_coords(cell: FarmCell) -> Array[Vector2i]:
	var bx := cell.grid_col * 2
	var by := cell.grid_row * 2
	return [Vector2i(bx, by), Vector2i(bx+1, by), Vector2i(bx, by+1), Vector2i(bx+1, by+1)]


func _refresh_cell_tilemap(cell: FarmCell) -> void:
	if not _terrain_map or not _decor_map or not _plant_map:
		return
	var bx := cell.grid_col * 2
	var by := cell.grid_row * 2
	var all: Array[Vector2i] = [Vector2i(bx,by), Vector2i(bx+1,by), Vector2i(bx,by+1), Vector2i(bx+1,by+1)]

	# always clear plant layer first
	for c in all:
		_plant_map.erase_cell(c)

	var key := Vector2i(cell.grid_col, cell.grid_row)

	match cell.state:
		FarmCell.TileState.LOCKED:
			_terrain_map.set_cells_terrain_connect(all, TM_TERRAIN_SET, TM_GRASS)
			if not _decor_placed.has(key):
				_decor_map.set_cells_terrain_connect(all, DM_TERRAIN_SET, DM_DECOR)
				_decor_placed[key] = true
			# else: decor already placed this session — leave it as-is

		FarmCell.TileState.SOIL:
			_terrain_map.set_cells_terrain_connect(all, TM_TERRAIN_SET, TM_SOIL)
			for c in all:
				_decor_map.erase_cell(c)
			_decor_placed.erase(key)

		FarmCell.TileState.WEED:
			_terrain_map.set_cells_terrain_connect(all, TM_TERRAIN_SET, TM_SOIL)
			# one random decor tile as weed visual
			_decor_map.set_cells_terrain_connect(
				[Vector2i(bx+1, by+1)], DM_TERRAIN_SET, DM_DECOR)
			_decor_placed.erase(key)

		FarmCell.TileState.CROP, FarmCell.TileState.WILTED:
			_terrain_map.set_cells_terrain_connect(all, TM_TERRAIN_SET, TM_SOIL)
			for c in all:
				_decor_map.erase_cell(c)
			_decor_placed.erase(key)
			if cell.crop_id >= 0:
				var row: int
				match cell.growth_stage:
					0: row = PM_SEED_ROW
					1: row = PM_SPROUT_ROW
					2: row = PM_GROWING_ROW
					_: row = PM_MATURE_ROW
				var atlas := Vector2i(cell.crop_id, row)
				for c in all:
					_plant_map.set_cell(c, PM_SOURCE, atlas)

	# wilt overlay
	if _wilt_map:
		for c in all:
			_wilt_map.erase_cell(c)
		if cell.state == FarmCell.TileState.WILTED:
			for c in all:
				_wilt_map.set_cell(c, 0, Vector2i(0, 0))

	# moisture overlay — watered soil tile variant
	if _moisture_map:
		for c in all:
			_moisture_map.erase_cell(c)
		var is_watered := (cell.state == FarmCell.TileState.CROP or cell.state == FarmCell.TileState.WILTED) and cell.watered
		if is_watered:
			for c in all:
				_moisture_map.set_cell(c, 0, Vector2i(0, 0))

	# harvest-ready bounce icon
	var is_ready := cell.state == FarmCell.TileState.CROP and cell.growth_stage == 3
	if is_ready:
		_show_harvest_icon(cell)
	else:
		_hide_harvest_icon(key)


func _show_harvest_icon(cell: FarmCell) -> void:
	if not _icon_container:
		return
	var key := Vector2i(cell.grid_col, cell.grid_row)
	if _harvest_icons.has(key):
		return  # already showing
	var tex_path := "res://games/zen_farm/assets/harvest_ready.png"
	if not ResourceLoader.exists(tex_path):
		return  # texture not made yet — skip silently
	var icon := Sprite2D.new()
	icon.texture = load(tex_path)
	icon.position = Vector2(
		cell.grid_col * TILE_SIZE + TILE_SIZE * 0.5,
		cell.grid_row * TILE_SIZE - 24.0)
	_icon_container.add_child(icon)
	_harvest_icons[key] = icon
	var base_y := icon.position.y
	var tw := create_tween().set_loops()
	tw.tween_property(icon, "position:y", base_y - 8.0, 0.45) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(icon, "position:y", base_y, 0.45) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	icon.set_meta("tween", tw)


func _hide_harvest_icon(key: Vector2i) -> void:
	if not _harvest_icons.has(key):
		return
	var icon: Sprite2D = _harvest_icons[key]
	if icon.has_meta("tween"):
		(icon.get_meta("tween") as Tween).kill()
	icon.queue_free()
	_harvest_icons.erase(key)


func _setup_wilt_overlay() -> void:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.45, 0.22, 0.04, 0.50))
	var tex := ImageTexture.create_from_image(img)
	var source := TileSetAtlasSource.new()
	source.texture = tex
	source.texture_region_size = Vector2i(64, 64)
	source.create_tile(Vector2i(0, 0))
	var ts := TileSet.new()
	ts.tile_size = Vector2i(64, 64)
	ts.add_source(source, 0)
	_wilt_map = TileMapLayer.new()
	_wilt_map.tile_set = ts
	_wilt_map.z_index  = 7   # above PlantMapLayer (z_index 6)
	$FarmScroll.add_child(_wilt_map)


func _check_expansion() -> void:
	for cell in _cells:
		if cell.state == FarmCell.TileState.LOCKED:
			return
	_add_column()


func _add_column() -> void:
	_cols += 1
	var col := _cols - 1
	for row in range(ROWS):
		var cell := FarmCell.new()
		_grid_container.add_child(cell)
		cell.position = Vector2(col * (TILE_SIZE + GAP), row * (TILE_SIZE + GAP))
		cell.grid_row    = row
		cell.grid_col    = col
		cell.visual_changed.connect(_refresh_cell_tilemap.bind(cell))
		cell.state       = FarmCell.TileState.LOCKED
		cell.unlock_cost = _next_unlock_cost()
		cell.refresh_visual()
		_cells.append(cell)
	_place_bottom_border_decor(col, col + 2)
	_place_top_border_decor(col, col + 2)
	_place_side_border_column(_cols * 2)   # new right edge
	_update_grid_size()


func _place_top_border_decor(col_from: int, col_to: int) -> void:
	if not _terrain_map or not _decor_map:
		return
	var tiles: Array[Vector2i] = []
	for col in range(col_from, col_to):
		var bx := col * 2
		tiles.append(Vector2i(bx,     -1))
		tiles.append(Vector2i(bx + 1, -1))
	if tiles.size() > 0:
		_terrain_map.set_cells_terrain_connect(tiles, TM_TERRAIN_SET, TM_GRASS)
		_decor_map.set_cells_terrain_connect(tiles, DM_TERRAIN_SET, DM_DECOR)


func _place_bottom_border_decor(col_from: int, col_to: int) -> void:
	if not _terrain_map or not _decor_map:
		return
	var all_tiles: Array[Vector2i] = []
	var decor_tiles: Array[Vector2i] = []
	for col in range(col_from, col_to):
		var bx := col * 2
		for by in [ROWS * 2, ROWS * 2 + 1]:
			all_tiles.append(Vector2i(bx,     by))
			all_tiles.append(Vector2i(bx + 1, by))
		# decor only on the first row (64 px border); second row is plain grass for text
		decor_tiles.append(Vector2i(col * 2,     ROWS * 2))
		decor_tiles.append(Vector2i(col * 2 + 1, ROWS * 2))
	if all_tiles.size() > 0:
		_terrain_map.set_cells_terrain_connect(all_tiles, TM_TERRAIN_SET, TM_GRASS)
		_decor_map.set_cells_terrain_connect(decor_tiles, DM_TERRAIN_SET, DM_DECOR)


func _place_side_border_column(tx: int) -> void:
	if not _terrain_map or not _decor_map:
		return
	var tiles: Array[Vector2i] = []
	for row in range(-1, ROWS * 2 + 2):   # -1 = top border row, + both bottom border rows
		tiles.append(Vector2i(tx, row))
	_terrain_map.set_cells_terrain_connect(tiles, TM_TERRAIN_SET, TM_GRASS)
	_decor_map.set_cells_terrain_connect(tiles, DM_TERRAIN_SET, DM_DECOR)


func _tiles_owned() -> int:
	var count := 0
	for cell in _cells:
		if cell.state != FarmCell.TileState.LOCKED:
			count += 1
	return count


func _next_unlock_cost() -> int:
	var bought := _tiles_owned()
	if bought < 4:  return 2
	if bought < 8:  return 4
	if bought < 12: return 12
	if bought < 16: return 25
	return 50


func _update_lock_costs() -> void:
	var cost := _next_unlock_cost()
	for cell in _cells:
		if cell.state == FarmCell.TileState.LOCKED:
			cell.unlock_cost = cost
			cell.refresh_visual()


# Show a notification when a land purchase crosses a crop-unlock milestone.
# Returns the newly unlocked crop name, or "" if no milestone was crossed.
func _check_crop_unlocks(tiles_before: int) -> String:
	var tiles_now := _tiles_owned()
	var milestones := { 4: "Carrot", 8: "Potato", 12: "Tomato", 16: "Pumpkin" }
	for threshold in milestones:
		if tiles_before < threshold and tiles_now >= threshold:
			return milestones[threshold]
	return ""


# ── process ───────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	_tick_crops(delta)
	_tick_weeds(delta)


func _input(event: InputEvent) -> void:
	if not _game_active:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_touch_start     = event.position
			_touch_drag_dist = 0.0
			_touch_cell      = _cell_at(event.position)
		else:
			if _touch_drag_dist < 12.0 and _touch_cell != null:
				_on_cell_tapped(_touch_cell)
			_touch_cell = null
	elif event is InputEventScreenDrag:
		_touch_drag_dist += abs(event.relative.x)
		_apply_scroll(int(-event.relative.x))
	elif event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_touch_start     = event.position
			_touch_drag_dist = 0.0
			_touch_cell      = _cell_at(event.position)
		elif not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if _touch_drag_dist < 8.0 and _touch_cell != null:
				_on_cell_tapped(_touch_cell)
			_touch_cell = null
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_apply_scroll(-60)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_apply_scroll(60)
	elif event is InputEventMouseMotion:
		if event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_touch_drag_dist += abs(event.relative.x)
			_apply_scroll(int(-event.relative.x))


func _cell_at(pos: Vector2) -> FarmCell:
	for cell in _cells:
		if cell.get_global_rect().has_point(pos):
			return cell
	return null


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
		if not _weed_tip_shown:
			_weed_tip_shown = true
			_show_status("A weed appeared! Use SHEARS to cut it.")


# ── offline catch-up ──────────────────────────────────────────────────────
func _apply_offline_catchup() -> void:
	if _last_save_time <= 0.0:
		return
	var elapsed := Time.get_unix_time_from_system() - _last_save_time
	if elapsed <= 0.0:
		return

	for cell in _cells:
		if cell.state != FarmCell.TileState.CROP:
			continue
		if cell.growth_stage == CropData.STAGE_MATURE:
			continue
		var t := elapsed
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
	_seeds_open    = false
	_shop_open     = false
	_seed_panel.visible    = false
	_upgrade_panel.visible = false
	_refresh_ui()

func _on_can_btn_pressed() -> void:
	_active_tool   = Tool.WATERING_CAN
	_seeds_open    = false
	_shop_open     = false
	_seed_panel.visible    = false
	_upgrade_panel.visible = false
	_refresh_ui()

func _on_shears_btn_pressed() -> void:
	_active_tool   = Tool.SHEARS
	_seeds_open    = false
	_shop_open     = false
	_seed_panel.visible    = false
	_upgrade_panel.visible = false
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
		_play(_sfx_noaction)
		_show_status("Equip the Watering Can first.")
		return
	var cmax := _can_max()
	if _can_water == cmax:
		_play(_sfx_noaction)
		_show_status("Can is already full.")
		return
	_can_water = cmax
	_refresh_ui()
	_play(_sfx_well)
	_show_status("Can filled! (" + str(cmax) + "/" + str(cmax) + ")")
	SaveManager.save_game(self)


# ── cell tap handler ──────────────────────────────────────────────────────
func _on_cell_tapped(cell: FarmCell) -> void:
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


# HAND tool: unlock tiles; guide player toward the right tool otherwise
func _try_hand(cell: FarmCell) -> void:
	match cell.state:
		FarmCell.TileState.SOIL:
			_play(_sfx_noaction)
			_show_status("Tap SEEDS to plant.")
		FarmCell.TileState.WEED:
			_play(_sfx_noaction)
			_show_status("Use Shears to cut weeds.")
		FarmCell.TileState.CROP:
			_play(_sfx_crop_tap)
			if cell.growth_stage == CropData.STAGE_MATURE:
				_show_status("Ready! Use Shears to harvest.")
			elif not cell.watered:
				_show_status("Thirsty! Use Watering Can.")
			else:
				_show_status("Growing steadily.")
		FarmCell.TileState.WILTED:
			_play(_sfx_crop_tap)
			_show_status("Wilted! Use Watering Can.")
		FarmCell.TileState.LOCKED:
			var cost := _next_unlock_cost()
			if _coins >= cost:
				if _coins == cost and not _has_active_crops():
					_play(_sfx_noaction)
					_show_status("Keep 1c for seeds — can't spend your last coin!")
					return
				var tiles_before := _tiles_owned()
				_coins -= cost
				cell.state = FarmCell.TileState.SOIL
				cell.refresh_visual()
				_animate_unlock(cell)
				_update_lock_costs()
				_refresh_ui()
				_play(_sfx_buy)
				# Crop milestone message overrides generic unlock message
				var new_crop := _check_crop_unlocks(tiles_before)
				_show_status("Land unlocked!")
				if not new_crop.is_empty():
					_show_status(new_crop + " seeds unlocked!")
				_check_expansion()
				SaveManager.save_game(self)
			else:
				_play(_sfx_noaction)
				_show_status("Need " + str(cost) + " coins.")


# WATERING CAN tool
func _try_water_cell(cell: FarmCell) -> void:
	if _can_water <= 0:
		_play(_sfx_noaction)
		_show_status("Can is empty — fill at the Well.")
		return
	var cmax := _can_max()
	match cell.state:
		FarmCell.TileState.CROP:
			if cell.growth_stage == CropData.STAGE_MATURE:
				_play(_sfx_noaction)
				_show_status("Use Shears to harvest this one.")
			elif cell.watered:
				_play(_sfx_noaction)
				_show_status("Already watered.")
			else:
				cell.watered    = true
				cell.wilt_timer = 0.0
				cell.refresh_visual()
				_can_water -= 1
				_refresh_ui()
				_play(_sfx_water)
				_show_status("Watered! (" + str(_can_water) + "/" + str(cmax) + " left)")
				SaveManager.save_game(self)
		FarmCell.TileState.WILTED:
			cell.state      = FarmCell.TileState.CROP
			cell.watered    = true
			cell.wilt_timer = 0.0
			cell.refresh_visual()
			_can_water -= 1
			_refresh_ui()
			_play(_sfx_water)
			_show_status("Revived! (" + str(_can_water) + "/" + str(cmax) + " left)")
			SaveManager.save_game(self)
		_:
			_play(_sfx_noaction)
			_show_status("Nothing to water here.")


# SHEARS tool: harvest mature crops and cut weeds
func _try_shear(cell: FarmCell) -> void:
	match cell.state:
		FarmCell.TileState.CROP:
			if cell.growth_stage == CropData.STAGE_MATURE:
				var value := CropData.get_sell_value(cell.crop_id)
				_coins += value
				_inventory[cell.crop_id] = _inventory.get(cell.crop_id, 0) + 1
				cell.state         = FarmCell.TileState.SOIL
				cell.crop_id       = -1
				cell.growth_stage  = 0
				cell.time_in_stage = 0.0
				cell.watered       = false
				cell.wilt_timer    = 0.0
				cell.refresh_visual()
				_play(_sfx_harvest)
				_spawn_coin_float(cell, value)
				_show_status("Harvested! +" + str(value) + "c")
				_refresh_ui()
				SaveManager.save_game(self)
			elif cell.growth_stage == CropData.STAGE_SEED:
				# Uproot a freshly planted seed — refund half the seed cost
				var refund: int = maxi(1, CropData.get_seed_cost(cell.crop_id) >> 1)
				_coins += refund
				cell.state         = FarmCell.TileState.SOIL
				cell.crop_id       = -1
				cell.growth_stage  = 0
				cell.time_in_stage = 0.0
				cell.watered       = false
				cell.wilt_timer    = 0.0
				cell.refresh_visual()
				_play(_sfx_weedcut)
				_spawn_coin_float(cell, refund)
				_show_status("Seed uprooted. +" + str(refund) + "c back.")
				_refresh_ui()
				SaveManager.save_game(self)
			else:
				_play(_sfx_noaction)
				_show_status("Not ready yet — keep watering.")
		FarmCell.TileState.WEED:
			cell.state = FarmCell.TileState.SOIL
			cell.refresh_visual()
			_coins += 1
			_play(_sfx_weedcut)
			_spawn_coin_float(cell, 1)
			_show_status("Weed cut! +1c")
			_refresh_ui()
			SaveManager.save_game(self)
		_:
			_play(_sfx_noaction)
			_show_status("Nothing to cut here.")


# SEEDS panel: plant on soil
func _try_plant(cell: FarmCell) -> void:
	if _selected_crop == -1:
		_play(_sfx_noaction)
		_show_status("Pick a seed first!")
		return
	# Guard: can't plant an as-yet-locked crop (shouldn't happen since buttons
	# are disabled, but defensive check for save-load edge cases)
	if CropData.get_unlock_tile_count(_selected_crop) > _tiles_owned():
		_play(_sfx_noaction)
		_show_status("That seed isn't unlocked yet.")
		return
	var cost := CropData.get_seed_cost(_selected_crop)
	if _coins < cost:
		_play(_sfx_noaction)
		_show_status("Need " + str(cost) + "c — not enough coins.")
		return
	_coins -= cost
	cell.state         = FarmCell.TileState.CROP
	cell.crop_id       = _selected_crop
	cell.growth_stage  = CropData.STAGE_SEED
	cell.time_in_stage = 0.0
	cell.watered       = false
	cell.wilt_timer    = 0.0
	cell.refresh_visual()
	_play(_sfx_plant)
	_refresh_ui()
	_show_status("Planted " + CropData.crop_name(_selected_crop) + "!")
	SaveManager.save_game(self)


# ── seed panel button ─────────────────────────────────────────────────────
func _on_seeds_btn_pressed() -> void:
	if _seeds_open:
		_seeds_open = false
	else:
		_active_tool = Tool.HAND
		_shop_open   = false
		_upgrade_panel.visible = false
		_seeds_open = true
	_seed_panel.visible = _seeds_open
	_refresh_ui()


func _select_seed(crop_id: int) -> void:
	# Ignore taps on disabled (locked) buttons — GDScript can fire these
	# if the button was rapidly tapped; double-check unlock state
	if CropData.get_unlock_tile_count(crop_id) > _tiles_owned():
		return
	_selected_crop = crop_id
	_refresh_ui()
	_show_status("Selected: " + CropData.crop_name(crop_id))


# ── upgrade shop ─────────────────────────────────────────────────────────
func _on_shop_btn_pressed() -> void:
	if _shop_open:
		_shop_open = false
	else:
		_seeds_open = false
		_seed_panel.visible = false
		_shop_open = true
	_upgrade_panel.visible = _shop_open
	_refresh_ui()


func _on_can_upgrade_pressed() -> void:
	var cost := _can_upgrade_cost()
	if cost < 0:
		_play(_sfx_noaction)
		_show_status("Watering Can is already MAX level.")
		return
	if _coins < cost:
		_play(_sfx_noaction)
		_show_status("Need " + str(cost) + "c to upgrade.")
		return
	_coins -= cost
	_can_level += 1
	_can_water = mini(_can_water, _can_max())
	_refresh_ui()
	_play(_sfx_upgrade)
	_show_status("Can upgraded! Now " + str(_can_max()) + " charges.")
	SaveManager.save_game(self)


func _on_sell_pressed() -> void:
	var total := 0
	for cid in _inventory:
		var count: int = _inventory[cid]
		total += int(CropData.get_sell_value(cid) * 0.7 * count)
	if total == 0:
		_play(_sfx_noaction)
		_show_status("Nothing to sell.")
		return
	_coins += total
	_inventory.clear()
	_refresh_ui()
	_play(_sfx_sell_snd)
	_show_status("Sold for +" + str(total) + "c!")
	SaveManager.save_game(self)


func _on_back_pressed() -> void:
	_game_active = false
	SaveManager.save_game(self)
	back_to_menu.emit()


# ── SFX loading & playback ────────────────────────────────────────────────────
const _SFX_DIR := "res://games/zen_farm/assets/sfx/"

func _load_sfx() -> void:
	var entries := [
		[_sfx_plant,    "plant.mp3"],
		[_sfx_water,    "water.mp3"],
		[_sfx_well,     "well_fill.mp3"],
		[_sfx_harvest,  "harvest.mp3"],
		[_sfx_weedcut,  "weed_cut.mp3"],
		[_sfx_buy,      "buy_land.mp3"],
		[_sfx_sell_snd, "sell.mp3"],
		[_sfx_upgrade,  "upgrade.mp3"],
		[_sfx_crop_tap, "crop_tap.mp3"],
		[_sfx_noaction, "no_action.mp3"],
	]
	for e in entries:
		var path: String = _SFX_DIR + e[1]
		if ResourceLoader.exists(path):
			e[0].stream = load(path)


func _play(sfx: AudioStreamPlayer) -> void:
	if sfx and sfx.stream:
		sfx.play()


# ── UI refresh ────────────────────────────────────────────────────────────
func _refresh_ui() -> void:
	_coins_label.text = str(_coins) + " coins"
	var cmax := _can_max()

	# top-right: active tool indicator
	match _active_tool:
		Tool.HAND:
			_mode_label.text = "PLANTING" if _seeds_open else ("SHOP" if _shop_open else "HAND")
		Tool.WATERING_CAN:
			_mode_label.text = "CAN " + str(_can_water) + "/" + str(cmax)
		Tool.SHEARS:
			_mode_label.text = "SHEARS"

	# tool button highlights
	_hand_btn.modulate   = Color(1.6, 1.6, 1.0) if _active_tool == Tool.HAND          else Color.WHITE
	_can_btn.modulate    = Color(1.0, 1.6, 2.0) if _active_tool == Tool.WATERING_CAN  else Color.WHITE
	_shears_btn.modulate = Color(2.0, 1.4, 1.0) if _active_tool == Tool.SHEARS        else Color.WHITE

	# can button text shows current water level
	_can_btn.text = "CAN " + str(_can_water) + "/" + str(cmax)

	# well label
	_well_label.text = "WELL\ntap to fill"

	# bottom-bar button labels
	_seeds_btn.text = "CANCEL" if _seeds_open else "SEEDS"
	_shop_btn.text  = "CLOSE"  if _shop_open  else "SHOP"

	# ── seed panel ────────────────────────────────────────────────────────
	var owned := _tiles_owned()
	var crop_ids   := [CropData.LETTUCE, CropData.CARROT, CropData.POTATO,
					   CropData.TOMATO,  CropData.PUMPKIN]
	var crop_btns: Array[Button] = [
		$SeedPanel/LettuceBtn,
		$SeedPanel/CarrotBtn,
		$SeedPanel/PotatoBtn,
		$SeedPanel/TomatoBtn,
		$SeedPanel/PumpkinBtn,
	]
	for i in range(crop_ids.size()):
		var cid: int    = crop_ids[i]
		var btn: Button = crop_btns[i]
		var threshold: int = CropData.get_unlock_tile_count(cid)
		var unlocked: bool = owned >= threshold
		if unlocked:
			btn.disabled = false
			btn.modulate = Color.WHITE
			var mark := "> " if (_selected_crop != -1 and _selected_crop == cid) else ""
			btn.text = mark + CropData.crop_name(cid) \
				+ "  " + str(CropData.get_seed_cost(cid)) + "c"
		else:
			btn.disabled = true
			btn.modulate = Color(1, 1, 1, 0.38)
			btn.text = CropData.crop_name(cid) + " (" + str(threshold) + " tiles)"

	# inventory label in seed panel
	var parts: Array = []
	for cid in crop_ids:
		var cnt: int = _inventory.get(cid, 0)
		if cnt > 0:
			parts.append(CropData.crop_name(cid) + "×" + str(cnt))
	_inv_label.text = ("Harvested: " + ", ".join(parts)) if not parts.is_empty() else ""

	# ── upgrade panel ─────────────────────────────────────────────────────
	var upgrade_cost := _can_upgrade_cost()
	if upgrade_cost < 0:
		_can_upgrade_btn.text     = "Watering Can  MAX  (" + str(cmax) + " charges)"
		_can_upgrade_btn.disabled = true
		_can_upgrade_btn.modulate = Color(1, 1, 1, 0.45)
	else:
		_can_upgrade_btn.text = "Can Lv" + str(_can_level) + "→" + str(_can_level + 1) \
			+ "  (" + str(cmax) + "→" + str(_can_next_max()) + " charges)  " \
			+ str(upgrade_cost) + "c"
		_can_upgrade_btn.disabled = false
		_can_upgrade_btn.modulate = Color.WHITE


# ── animations ───────────────────────────────────────────────────────────────
func _animate_unlock(cell: FarmCell) -> void:
	cell.pivot_offset = Vector2(TILE_SIZE, TILE_SIZE) * 0.5
	var tw := cell.create_tween()
	tw.tween_property(cell, "scale", Vector2(1.12, 1.12), 0.11) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(cell, "scale", Vector2(1.0, 1.0), 0.18) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN_OUT)


func _spawn_coin_float(cell: FarmCell, amount: int) -> void:
	var lbl := Label.new()
	lbl.text = "+" + str(amount) + "c"
	lbl.add_theme_font_override("font", load("res://assets/font/vetka.ttf"))
	lbl.add_theme_font_size_override("font_size", 44)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.2, 1))
	lbl.add_theme_color_override("font_outline_color", Color(0.12, 0.08, 0.02, 1))
	lbl.add_theme_constant_override("outline_size", 3)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.z_index = 15
	lbl.size = Vector2(120, 60)
	lbl.position = cell.get_global_rect().position \
		+ Vector2(TILE_SIZE * 0.5 - 60, TILE_SIZE * 0.2)
	add_child(lbl)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(lbl, "position:y", lbl.position.y - 88, 1.1) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "modulate:a", 0.0, 1.1) \
		.set_trans(Tween.TRANS_LINEAR).set_delay(0.35)
	tw.chain().tween_callback(lbl.queue_free)


func _show_status(msg: String) -> void:
	_status_label.text = msg
	_status_timer.start(2.5)


# ── app background save ───────────────────────────────────────────────────
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_game_active = false
		back_to_menu.emit()
	elif what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		SaveManager.save_game(self)
