#Game.gd (zen_farm)
extends Control

signal back_to_menu
signal rain_changed(is_raining: bool)
signal day_night_changed(night_amount: float)

# ── layout ──────────────────────────────────────────────────────────────────
const ROWS      := 5
const TILE_SIZE := FarmCell.TILE_SIZE
const GAP       := 0
const GRID_Y    := 96.0   # vertical offset of the farm grid from the top of FarmScroll
const MIN_EARLY_SCROLL_RANGE := 72

var _cols: int = 4        # grows when all current tiles are bought

# manual pan (replaces ScrollContainer)
var _scroll_x:     int = 0
var _min_scroll_x: int = 0
var _max_scroll_x: int = 0

# tap-vs-drag tracking (touch + mouse)
var _touch_start     := Vector2.ZERO
var _touch_drag_dist := 0.0
var _touch_start_msec: int = 0
var _touch_cell: FarmCell = null
var _touch_slot: int = 0
var _poke_active: bool = false
var _poke_tween: Tween = null

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
var _grass_toggle_unlocked: bool = false
var _water_toggle_unlocked: bool = false
var _decor_placed: Dictionary = {}   # Vector2i(col,row) → true; prevents re-RNG on refresh
var _static_decor_coverage: Dictionary = {} # Vector2i tile coord → true; saved no-decor cells too
var _static_decor_tiles: Dictionary = {}    # Vector2i tile coord → [layer, source, atlas, alt]
var _soil_placed: Dictionary = {}    # Vector2i(col,row) → true; prevents soil re-RNG on crop refresh
var _wilt_map: TileMapLayer = null        # brown overlay on wilted tiles; built in _ready()
var _rock_decor_map: TileMapLayer = null  # static decor layer for rocks (no sway shader)
var _locked_sign_front_map: TileMapLayer = null  # bottom locked decor tiles drawn over price signs
var _icon_container: Node2D = null        # parent for harvest-ready bounce icons
var _insect_container: Node2D = null      # parent for live butterflies/fireflies; scrolls with the field
var _inventory_icon_row: HBoxContainer = null
var _objects_texture: Texture2D = null
var _harvest_icons: Dictionary = {}       # Vector2i(col,row) → Sprite2D
var _harvest_icon_shown_once: Dictionary = {}  # Saving harvest icon state

# Weed spawning
var _weed_timer: float    = 0.0
var _weed_tip_shown: bool = false

var _is_raining:       bool           = false
var _rain_check_timer: float          = 0.0
var _rain_duration:    float          = 0.0
var _rain_overlay:     ColorRect      = null
var _rain_particles:   CPUParticles2D = null
var _rain_visual_layer: Node2D = null
var _rain_ground_layer: Node2D = null
var _rain_streaks: Array = []
var _rain_ground: Array = []

# day/night color grading
const DAY_NIGHT_CYCLE := 180.0
const DAY_PHASE := 0.30
const NIGHT_PHASE := 0.76
const GRASS_TOGGLE_COST := 100
const WATER_TOGGLE_COST := 100
const FIREFLY_PHASE_START := 0.62
const FIREFLY_PHASE_END := 0.92
const DAY_NIGHT_KEYS := [
	{"t": 0.00, "shadow": Color(0.34, 0.42, 0.68, 1.0), "mid": Color(0.72, 0.82, 1.0, 1.0), "highlight": Color(1.00, 0.88, 0.55, 1.0), "night": 0.40, "dusk": 0.00, "dawn": 0.90, "sat": 0.72, "exposure": 0.86, "contrast": 0.92, "lift": 0.030, "vignette": 0.22, "lamp": 0.54},
	{"t": 0.12, "shadow": Color(0.58, 0.55, 0.60, 1.0), "mid": Color(1.00, 0.95, 0.84, 1.0), "highlight": Color(1.00, 0.93, 0.70, 1.0), "night": 0.06, "dusk": 0.00, "dawn": 0.26, "sat": 1.04, "exposure": 1.00, "contrast": 1.00, "lift": 0.006, "vignette": 0.03, "lamp": 0.00},
	{"t": 0.30, "shadow": Color(0.88, 0.91, 0.92, 1.0), "mid": Color(1.00, 1.00, 1.00, 1.0), "highlight": Color(1.00, 1.00, 0.94, 1.0), "night": 0.00, "dusk": 0.00, "dawn": 0.00, "sat": 1.00, "exposure": 1.00, "contrast": 1.02, "lift": 0.000, "vignette": 0.00, "lamp": 0.00},
	{"t": 0.50, "shadow": Color(0.76, 0.74, 0.86, 1.0), "mid": Color(1.00, 0.92, 0.88, 1.0), "highlight": Color(1.00, 0.78, 0.58, 1.0), "night": 0.04, "dusk": 0.36, "dawn": 0.00, "sat": 1.08, "exposure": 0.98, "contrast": 1.02, "lift": 0.006, "vignette": 0.04, "lamp": 0.08},
	{"t": 0.64, "shadow": Color(0.20, 0.10, 0.58, 1.0), "mid": Color(0.78, 0.42, 1.00, 1.0), "highlight": Color(1.00, 0.62, 0.72, 1.0), "night": 0.42, "dusk": 0.92, "dawn": 0.00, "sat": 1.08, "exposure": 0.80, "contrast": 1.10, "lift": 0.022, "vignette": 0.25, "lamp": 0.52},
	{"t": 0.76, "shadow": Color(0.02, 0.06, 0.42, 1.0), "mid": Color(0.24, 0.16, 0.82, 1.0), "highlight": Color(0.62, 0.52, 1.00, 1.0), "night": 1.00, "dusk": 0.12, "dawn": 0.00, "sat": 1.40, "exposure": 0.52, "contrast": 1.24, "lift": 0.018, "vignette": 0.54, "lamp": 1.00},
	{"t": 0.92, "shadow": Color(0.04, 0.04, 0.36, 1.0), "mid": Color(0.30, 0.12, 0.70, 1.0), "highlight": Color(0.58, 0.56, 1.00, 1.0), "night": 0.96, "dusk": 0.00, "dawn": 0.18, "sat": 1.34, "exposure": 0.58, "contrast": 1.10, "lift": 0.020, "vignette": 0.48, "lamp": 0.96},
	{"t": 1.00, "shadow": Color(0.34, 0.42, 0.68, 1.0), "mid": Color(0.72, 0.82, 1.0, 1.0), "highlight": Color(1.00, 0.88, 0.55, 1.0), "night": 0.40, "dusk": 0.00, "dawn": 0.90, "sat": 0.72, "exposure": 0.86, "contrast": 0.92, "lift": 0.030, "vignette": 0.22, "lamp": 0.54},
]
var _day_seconds: float = DAY_NIGHT_CYCLE * 0.18
var _day_night_overlay: ColorRect = null
var _day_night_material: ShaderMaterial = null
var _firefly_texture: Texture2D = null
var _fireflies: Array = []
var _last_insect_mode: String = ""
var _night_amount: float = 0.0
var _lamp_amount: float = 0.0
var _last_audio_night_amount: float = -1.0

# ── butterflies ───────────────────────────────────────────────────────────────
const BUTTERFLY_COUNT := 3
var _butterflies: Array = []   # Array of {node, state, perched_cell, tween}
const FIREFLY_COUNT := 11
const INSECT_SPAWN_MARGIN := 150.0
const POKE_RADIUS := 80.0
const POKE_STRENGTH := 8.0
const POKE_RELEASE_FADE := 0.28
const TAP_MAX_DURATION_MSEC := 320
const TOUCH_GRASS_VOLUME_DB := -8.0
const TOUCH_GRASS_SILENT_DB := -42.0
const TOUCH_GRASS_FADE_IN := 0.22
const TOUCH_GRASS_FADE_OUT := 0.65
const WEED_INTERVAL       := 45.0
const HARVEST_ICON_Y_OFFSET := -18.0
const HARVEST_ICON_LIFETIME := 12.0

# ── rain ─────────────────────────────────────────────────────────────────────
const RAIN_CHECK_INTERVAL := 180.0   # seconds between roll attempts
const RAIN_CHANCE         := 0.25    # probability per check
const RAIN_DURATION_MIN   := 60.0
const RAIN_DURATION_MAX   := 120.0
const RAIN_STREAK_COUNT   := 74
const RAIN_GROUND_COUNT   := 34
const RAIN_AREA_SIZE      := Vector2(540.0, 814.0)
const RAIN_FALL_VECTOR    := Vector2(380.0, 690.0)

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
const TM_WATER        := 2
# DecorMapLayer — terrain set 0
const DM_SOURCE       := 1
const DM_TERRAIN_SET  := 0
const DM_DECOR        := 0   # 16 random decor items
# Atlas coords of rock tiles — these go on the static layer (no sway)
const ROCK_ATLAS_COORDS := [Vector2i(11, 5), Vector2i(12, 5), Vector2i(13, 5)]
const WATER_WEED_ATLAS_COORDS := [
	Vector2i(0, 5), Vector2i(1, 5), Vector2i(2, 5), Vector2i(3, 5),
	Vector2i(11, 5), Vector2i(12, 5), Vector2i(13, 5),
]
# PlantMapLayer — source id 0 (objects.png)
# atlas coords: col = crop_id (0-4), row = stage row
const PM_SOURCE       := 1
const PM_SEED_ROW     := 2   # stage 0 — seed (1-tall)
const PM_SPROUT_ROW   := 3   # stage 1 — sprout (1-tall)
const PM_GROWING_ROW  := 4   # stage 2 — growing (2-tall)
const PM_MATURE_ROW   := 6   # stage 3 — mature (2-tall)
const PM_PACK_ROW     := 0   # seed packet icons for the seed menu
const PM_BLOSSOM_ROW  := 1   # harvested blossom icons for inventory counts
const PM_TILE_SIZE    := 64
const SEED_BUTTON_ICON_TEXT_GAP := -4
const SEED_BUTTON_FONT_SIZE := 34
@onready var _seed_panel:     Control = $SeedPanel
@onready var _inv_label:      Label   = $SeedPanel/InvLabel
@onready var _upgrade_panel:  Control = $UpgradePanel
@onready var _can_upgrade_btn: Button = $UpgradePanel/CanUpgradeBtn
@onready var _grass_toggle_btn: Button = $UpgradePanel/GrassToggleBtn
@onready var _water_toggle_btn: Button = $UpgradePanel/WaterToggleBtn
@onready var _back_btn:       Button  = $BottomBar/BackButton
@onready var _seeds_btn:      Button  = $BottomBar/SeedsButton
@onready var _shop_btn:       Button  = $BottomBar/ShopButton
@onready var _sell_btn:       Button  = $BottomBar/SellButton
@onready var _status_timer:   Timer   = $StatusTimer

@onready var _hand_btn:       Button  = $ToolBar/HandBtn
@onready var _can_btn:        Button  = $ToolBar/CanBtn
@onready var _shears_btn:     Button  = $ToolBar/ShearsBtn
@onready var _well_panel:         Control          = $WellPanel
@onready var _well_label:         Label            = $WellPanel/WellLabel
@onready var _tip_panel:          Control          = $TipPanel
@onready var _rain_template:      AnimatedSprite2D = $FarmScroll/Rain


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
var _sfx_soil_toggle: AudioStreamPlayer = null
var _sfx_soil_till: AudioStreamPlayer = null
var _sfx_water_plop: AudioStreamPlayer = null
var _sfx_touch_grass: AudioStreamPlayer = null
var _sfx_touch_water: AudioStreamPlayer = null
var _sfx_touch_soil: AudioStreamPlayer = null
var _active_touch_loop: AudioStreamPlayer = null


func _ready() -> void:
	_back_btn.pressed.connect(_on_back_pressed)
	_seeds_btn.pressed.connect(_on_seeds_btn_pressed)
	_shop_btn.pressed.connect(_on_shop_btn_pressed)
	_sell_btn.pressed.connect(_on_sell_pressed)
	_grass_toggle_btn.pressed.connect(_on_grass_toggle_upgrade_pressed)
	_water_toggle_btn.pressed.connect(_on_water_toggle_upgrade_pressed)
	$SeedPanel/LavenderBtn.pressed.connect(func(): _select_seed(CropData.LAVENDER))
	$SeedPanel/RoseBtn.pressed.connect(func():  _select_seed(CropData.ROSE))
	$SeedPanel/DaisyBtn.pressed.connect(func():  _select_seed(CropData.DAISY))
	$SeedPanel/SunflowerBtn.pressed.connect(func():  _select_seed(CropData.SUNFLOWER))
	$SeedPanel/HydrangeaBtn.pressed.connect(func(): _select_seed(CropData.HYDRANGEA))
	$SeedPanel/TulipBtn.pressed.connect(func(): _select_seed(CropData.TULIP))
	$SeedPanel/LotusBtn.pressed.connect(func(): _select_seed(CropData.LOTUS))
	_can_upgrade_btn.pressed.connect(_on_can_upgrade_pressed)
	_status_timer.timeout.connect(func(): _status_label.text = "")

	_hand_btn.pressed.connect(_on_hand_btn_pressed)
	_can_btn.pressed.connect(_on_can_btn_pressed)
	_shears_btn.pressed.connect(_on_shears_btn_pressed)
	_well_panel.gui_input.connect(_on_well_gui_input)
	$TipPanel/Card/GotItBtn.pressed.connect(func(): _tip_panel.visible = false)
	_sfx_soil_toggle = AudioStreamPlayer.new()
	_sfx_soil_toggle.name = "SfxSoilToggle"
	add_child(_sfx_soil_toggle)
	_sfx_soil_till = AudioStreamPlayer.new()
	_sfx_soil_till.name = "SfxSoilTill"
	add_child(_sfx_soil_till)
	_sfx_water_plop = AudioStreamPlayer.new()
	_sfx_water_plop.name = "SfxWaterPlop"
	add_child(_sfx_water_plop)
	_sfx_touch_grass = AudioStreamPlayer.new()
	_sfx_touch_grass.name = "SfxTouchGrass"
	_sfx_touch_grass.volume_db = TOUCH_GRASS_SILENT_DB
	add_child(_sfx_touch_grass)
	_sfx_touch_water = AudioStreamPlayer.new()
	_sfx_touch_water.name = "SfxTouchWater"
	_sfx_touch_water.volume_db = TOUCH_GRASS_SILENT_DB
	add_child(_sfx_touch_water)
	_sfx_touch_soil = AudioStreamPlayer.new()
	_sfx_touch_soil.name = "SfxTouchSoil"
	_sfx_touch_soil.volume_db = TOUCH_GRASS_SILENT_DB
	add_child(_sfx_touch_soil)
	_load_sfx()
	_objects_texture = load("res://games/zen_farm/assets/objects.png")
	_setup_seed_panel_icons()
	_setup_wilt_overlay()
	_setup_day_night_overlay()
	_icon_container = Node2D.new()
	_icon_container.z_index = 10
	$FarmScroll.add_child(_icon_container)
	_insect_container = Node2D.new()
	_insect_container.z_index = 0
	$FarmScroll.add_child(_insect_container)

	var mat := ShaderMaterial.new()
	mat.shader = load("res://games/zen_farm/assets/plant_sway.gdshader")
	mat.set_shader_parameter("use_tall_tiles", true)
	_plant_map.material = mat
	_configure_poke_material(mat)

	# Decor sway — same shader, much gentler; rocks go on a separate static layer
	var decor_mat := ShaderMaterial.new()
	decor_mat.shader = mat.shader
	decor_mat.set_shader_parameter("wind_strength", 5.0)
	decor_mat.set_shader_parameter("wind_speed",    1.0)
	decor_mat.set_shader_parameter("wind_spread",   0.038)
	_configure_poke_material(decor_mat)
	_decor_map.material = decor_mat

	_rock_decor_map = TileMapLayer.new()
	_rock_decor_map.z_index   = _decor_map.z_index
	_rock_decor_map.tile_set  = _decor_map.tile_set
	$FarmScroll.add_child(_rock_decor_map)

	_locked_sign_front_map = TileMapLayer.new()
	_locked_sign_front_map.name = "LockedSignFrontMap"
	_locked_sign_front_map.z_index = 7
	_locked_sign_front_map.tile_set = _decor_map.tile_set
	$FarmScroll.add_child(_locked_sign_front_map)

	_rain_overlay = ColorRect.new()
	_rain_overlay.color = Color(0.35, 0.50, 0.75, 0.0)
	_rain_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rain_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rain_overlay.z_index = 9
	$FarmScroll.add_child(_rain_overlay)

	# rain streak texture: 2×10 px light-blue rectangle — no external asset needed
	var img := Image.create(2, 10, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.82, 0.90, 1.0, 0.70))
	_rain_particles = CPUParticles2D.new()
	_rain_particles.texture           = ImageTexture.create_from_image(img)
	_rain_particles.emitting          = false
	_rain_particles.amount            = 220
	_rain_particles.lifetime          = 1.2
	_rain_particles.emission_shape       = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_rain_particles.emission_rect_extents = Vector2(310.0, 1.0)
	_rain_particles.direction         = Vector2(0.12, 1.0).normalized()
	_rain_particles.spread            = 2.0
	_rain_particles.initial_velocity_min = 550.0
	_rain_particles.initial_velocity_max = 800.0
	_rain_particles.gravity  = Vector2.ZERO
	_rain_particles.position = Vector2(270.0, -5.0)
	_rain_particles.z_index  = 10
	$FarmScroll.add_child(_rain_particles)
	_setup_rain_sprites()
	_update_day_night(0.0)


func prepare_farm() -> void:
	_game_active = false
	_touch_cell  = null
	_cols = SaveManager.load_cols()
	_clear_cells()
	_build_cells()
	var loaded := SaveManager.load_game(self)
	if loaded:
		_restore_static_decor_snapshot()
		_update_lock_costs()
		_apply_offline_catchup()
		_upgrade_panel.visible = false
		_shop_open = false
	else:
		_coins         = 10000
		_can_water     = 0
		_can_level     = 0
		_active_tool   = Tool.HAND
		_seeds_open    = false
		_shop_open     = false
		_selected_crop = -1
		_grass_toggle_unlocked = false
		_water_toggle_unlocked = false
		_inventory.clear()
		_weed_timer      = 0.0
		_weed_tip_shown  = false
		_last_save_time  = 0.0
		_seed_panel.visible    = false
		_upgrade_panel.visible = false
		_tip_panel.visible     = true
	# reset rain state each session
	_is_raining = false
	_rain_check_timer = 0.0
	_rain_duration = 0.0
	if _rain_overlay:
		_rain_overlay.color.a = 0.0
	if _rain_particles:
		_rain_particles.emitting = false
	_set_rain_sprites_active(false, true)
	rain_changed.emit(false)
	_last_insect_mode = ""
	_clear_fireflies()
	_update_day_night(0.0)
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
	_clear_butterflies()
	_last_insect_mode = ""
	_sync_day_night_insects()


# ── build ─────────────────────────────────────────────────────────────────
func _clear_cells() -> void:
	_clear_butterflies()
	_clear_fireflies()
	# clear all tilemap layers so border decor from prior session doesn't linger
	if _terrain_map:    _terrain_map.clear()
	if _decor_map:      _decor_map.clear()
	if _rock_decor_map: _rock_decor_map.clear()
	if _locked_sign_front_map: _locked_sign_front_map.clear()
	if _plant_map:      _plant_map.clear()
	if _wilt_map:       _wilt_map.clear()
	if _moisture_map:   _moisture_map.clear()
	for c in _cells:
		if is_instance_valid(c):
			c.queue_free()
	_cells.clear()
	_decor_placed.clear()
	_static_decor_coverage.clear()
	_static_decor_tiles.clear()
	_soil_placed.clear()
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
		cell.reset_slots()
		cell.unlock_cost = 2
		cell.refresh_visual()


# ── land unlock pricing ───────────────────────────────────────────────────
func _has_active_crops() -> bool:
	for cell in _cells:
		if cell.has_active_crops():
			return true
	return false


func _update_grid_size() -> void:
	var stride    := TILE_SIZE + GAP
	var content_w := _cols * stride - GAP
	var left_x    := maxf(18.0, (540.0 - content_w) * 0.5)
	var natural_max := maxi(0, int(content_w + left_x + 18.0) - 540)
	var extra_range := maxi(0, MIN_EARLY_SCROLL_RANGE - natural_max)
	var extra_left := int(extra_range * 0.5)
	_min_scroll_x = -extra_left
	_max_scroll_x = natural_max + extra_range - extra_left
	_scroll_x = clampi(_scroll_x, _min_scroll_x, _max_scroll_x)
	var pos := Vector2(left_x - _scroll_x, GRID_Y)
	_grid_container.position = pos
	_terrain_map.position    = pos
	_decor_map.position      = pos
	if _rock_decor_map:     _rock_decor_map.position     = pos
	if _locked_sign_front_map: _locked_sign_front_map.position = pos
	_plant_map.position      = pos
	if _wilt_map:           _wilt_map.position           = pos
	if _icon_container:     _icon_container.position     = pos
	if _insect_container:   _insect_container.position   = pos
	if _moisture_map:       _moisture_map.position       = pos


func _apply_scroll(delta: int) -> void:
	_scroll_x = clampi(_scroll_x + delta, _min_scroll_x, _max_scroll_x)
	var stride    := TILE_SIZE + GAP
	var content_w := _cols * stride - GAP
	var left_x    := maxf(18.0, (540.0 - content_w) * 0.5)
	var pos := Vector2(left_x - _scroll_x, GRID_Y)
	_grid_container.position = pos
	_terrain_map.position    = pos
	_decor_map.position      = pos
	if _rock_decor_map:     _rock_decor_map.position     = pos
	if _locked_sign_front_map: _locked_sign_front_map.position = pos
	_plant_map.position      = pos
	if _wilt_map:           _wilt_map.position           = pos
	if _icon_container:     _icon_container.position     = pos
	if _insect_container:   _insect_container.position   = pos
	if _moisture_map:       _moisture_map.position       = pos


# ── tilemap refresh ───────────────────────────────────────────────────────────
func _cell_coords(cell: FarmCell) -> Array[Vector2i]:
	var bx := cell.grid_col * 2
	var by := cell.grid_row * 2
	return [Vector2i(bx, by), Vector2i(bx+1, by), Vector2i(bx, by+1), Vector2i(bx+1, by+1)]


func _slot_coord(cell: FarmCell, slot: int) -> Vector2i:
	var bx := cell.grid_col * 2
	var by := cell.grid_row * 2
	return Vector2i(bx + slot % 2, by + (slot >> 1))


func _locked_sign_front_coords(cell: FarmCell) -> Array[Vector2i]:
	var bx := cell.grid_col * 2
	var by := cell.grid_row * 2
	return [Vector2i(bx, by + 1), Vector2i(bx + 1, by + 1)]


func _slot_key(cell: FarmCell, slot: int) -> Vector3i:
	return Vector3i(cell.grid_col, cell.grid_row, slot)


func _sync_legacy_cell_fields(cell: FarmCell) -> void:
	cell.crop_id = -1
	cell.growth_stage = 0
	cell.time_in_stage = 0.0
	cell.watered = false
	cell.wilt_timer = 0.0
	for slot in range(FarmCell.SLOT_COUNT):
		if cell.slot_states[slot] == FarmCell.SlotState.CROP or cell.slot_states[slot] == FarmCell.SlotState.WILTED:
			cell.crop_id = cell.slot_crop_ids[slot]
			cell.growth_stage = cell.slot_growth_stages[slot]
			cell.time_in_stage = cell.slot_time_in_stage[slot]
			cell.watered = cell.slot_watered[slot]
			cell.wilt_timer = cell.slot_wilt_timers[slot]
			break


func _capture_tile(layer: TileMapLayer, coord: Vector2i) -> Array:
	if not layer:
		return []
	var source_id := layer.get_cell_source_id(coord)
	if source_id == -1:
		return []
	return [layer, source_id, layer.get_cell_atlas_coords(coord), layer.get_cell_alternative_tile(coord)]


func _clear_decor_at(coord: Vector2i) -> void:
	_decor_map.erase_cell(coord)
	if _rock_decor_map:
		_rock_decor_map.erase_cell(coord)
	if _locked_sign_front_map:
		_locked_sign_front_map.erase_cell(coord)


func _capture_static_decor_at(coord: Vector2i) -> Array:
	var layers := [
		["sign_front", _locked_sign_front_map],
		["rock", _rock_decor_map],
		["decor", _decor_map],
	]
	for entry in layers:
		var layer := entry[1] as TileMapLayer
		if not layer:
			continue
		var source_id := layer.get_cell_source_id(coord)
		if source_id != -1:
			return [entry[0], source_id, layer.get_cell_atlas_coords(coord), layer.get_cell_alternative_tile(coord)]
	return []


func _set_static_decor_at(coord: Vector2i, snapshot: Array) -> void:
	if snapshot.size() < 4:
		return
	var layer_name := String(snapshot[0])
	var layer := _decor_map
	if layer_name == "rock" and _rock_decor_map:
		layer = _rock_decor_map
	elif layer_name == "sign_front" and _locked_sign_front_map:
		layer = _locked_sign_front_map
	layer.set_cell(coord, int(snapshot[1]), snapshot[2], int(snapshot[3]))


func _store_static_decor_coords(coords: Array[Vector2i]) -> void:
	for coord in coords:
		_static_decor_coverage[coord] = true
		var snapshot := _capture_static_decor_at(coord)
		if snapshot.is_empty():
			_static_decor_tiles.erase(coord)
		else:
			_static_decor_tiles[coord] = snapshot


func _apply_static_decor_coords(coords: Array[Vector2i]) -> void:
	for coord in coords:
		_clear_decor_at(coord)
	for coord in coords:
		if _static_decor_tiles.has(coord):
			_set_static_decor_at(coord, _static_decor_tiles[coord])


func _has_static_decor_coords(coords: Array[Vector2i]) -> bool:
	for coord in coords:
		if not _static_decor_coverage.has(coord):
			return false
	return true


func _invalidate_static_decor_coords(coords: Array[Vector2i]) -> void:
	for coord in coords:
		_static_decor_coverage.erase(coord)
		_static_decor_tiles.erase(coord)


func _invalidate_static_decor_for_cell(cell: FarmCell) -> void:
	_invalidate_static_decor_coords(_cell_coords(cell))


func _restore_static_decor_snapshot() -> void:
	var coords: Array[Vector2i] = []
	for coord in _static_decor_coverage.keys():
		if coord is Vector2i:
			coords.append(coord)
	_apply_static_decor_coords(coords)


func _clear_locked_sign_front(cell: FarmCell) -> void:
	if not _locked_sign_front_map:
		return
	for coord in _locked_sign_front_coords(cell):
		_locked_sign_front_map.erase_cell(coord)


func _move_locked_sign_front(cell: FarmCell) -> void:
	if not _locked_sign_front_map or not _decor_map:
		return
	for coord in _locked_sign_front_coords(cell):
		var source_id := _decor_map.get_cell_source_id(coord)
		var source_layer := _decor_map
		if source_id == -1 and _rock_decor_map:
			source_id = _rock_decor_map.get_cell_source_id(coord)
			source_layer = _rock_decor_map
		if source_id == -1:
			if _locked_sign_front_map.get_cell_source_id(coord) == -1:
				_locked_sign_front_map.erase_cell(coord)
			continue
		_locked_sign_front_map.set_cell(
			coord,
			source_id,
			source_layer.get_cell_atlas_coords(coord),
			source_layer.get_cell_alternative_tile(coord)
		)
		source_layer.erase_cell(coord)


func _is_valid_water_weed_atlas_coord(atlas_coord: Vector2i) -> bool:
	return atlas_coord in WATER_WEED_ATLAS_COORDS


func _random_water_weed_atlas_coord() -> Vector2i:
	return WATER_WEED_ATLAS_COORDS[randi() % WATER_WEED_ATLAS_COORDS.size()]


func _water_weed_atlas_for_slot(cell: FarmCell, slot: int) -> Vector2i:
	var atlas_coord := cell.slot_weed_atlas_coords[slot]
	if not _is_valid_water_weed_atlas_coord(atlas_coord):
		atlas_coord = _random_water_weed_atlas_coord()
		cell.slot_weed_atlas_coords[slot] = atlas_coord
	return atlas_coord


func _set_water_weed_decor(coord: Vector2i, atlas_coord: Vector2i) -> void:
	if atlas_coord in ROCK_ATLAS_COORDS and _rock_decor_map:
		_rock_decor_map.set_cell(coord, DM_SOURCE, atlas_coord)
	else:
		_decor_map.set_cell(coord, DM_SOURCE, atlas_coord)


func _refresh_cell_tilemap(cell: FarmCell) -> void:
	if not _terrain_map or not _decor_map or not _plant_map:
		return
	cell.refresh_summary_state()
	_sync_legacy_cell_fields(cell)
	var all := _cell_coords(cell)

	# Always clear crop-related layers first. Locked cells keep their decor until bought.
	for c in all:
		_plant_map.erase_cell(c)
		if _wilt_map:
			_wilt_map.erase_cell(c)
		if _moisture_map:
			_moisture_map.erase_cell(c)

	var key := Vector2i(cell.grid_col, cell.grid_row)
	if cell.state != FarmCell.TileState.LOCKED:
		_clear_locked_sign_front(cell)

	if cell.state == FarmCell.TileState.LOCKED or cell.state == FarmCell.TileState.GRASS:
		_soil_placed.erase(key)
		_terrain_map.set_cells_terrain_connect(all, TM_TERRAIN_SET, TM_GRASS)
		if not _decor_placed.has(key):
			if _has_static_decor_coords(all):
				_apply_static_decor_coords(all)
			elif randf() > 0.3:
				_decor_map.set_cells_terrain_connect(all, DM_TERRAIN_SET, DM_DECOR)
				_move_rocks_from_decor(all)
			if cell.state == FarmCell.TileState.LOCKED:
				_move_locked_sign_front(cell)
			_store_static_decor_coords(all)
			_decor_placed[key] = true
		for slot in range(FarmCell.SLOT_COUNT):
			_hide_slot_harvest_icon(cell, slot)
		return

	if not _soil_placed.has(key):
		var terrain := TM_WATER if cell.is_water_plot else TM_SOIL
		_terrain_map.set_cells_terrain_connect(all, TM_TERRAIN_SET, terrain)
		_soil_placed[key] = true
	_decor_placed.erase(key)
	_invalidate_static_decor_for_cell(cell)
	var existing_weed_tiles := {}
	for slot in range(FarmCell.SLOT_COUNT):
		if cell.slot_states[slot] != FarmCell.SlotState.WEED:
			continue
		if cell.is_water_plot:
			continue
		var coord := _slot_coord(cell, slot)
		var existing := _capture_tile(_decor_map, coord)
		if existing.is_empty():
			existing = _capture_tile(_rock_decor_map, coord)
		if not existing.is_empty():
			existing_weed_tiles[coord] = existing

	for c in all:
		_decor_map.erase_cell(c)
		if _rock_decor_map:
			_rock_decor_map.erase_cell(c)

	for slot in range(FarmCell.SLOT_COUNT):
		var coord := _slot_coord(cell, slot)
		match cell.slot_states[slot]:
			FarmCell.SlotState.WEED:
				if existing_weed_tiles.has(coord):
					var preserved: Array = existing_weed_tiles[coord]
					var layer: TileMapLayer = preserved[0]
					layer.set_cell(coord, int(preserved[1]), preserved[2], int(preserved[3]))
				elif cell.is_water_plot:
					_set_water_weed_decor(coord, _water_weed_atlas_for_slot(cell, slot))
				else:
					var one: Array[Vector2i] = [coord]
					_decor_map.set_cells_terrain_connect(one, DM_TERRAIN_SET, DM_DECOR)
					_move_rocks_from_decor(one)
			FarmCell.SlotState.CROP, FarmCell.SlotState.WILTED:
				var row: int
				match cell.slot_growth_stages[slot]:
					CropData.STAGE_SEED: row = PM_SEED_ROW
					CropData.STAGE_SPROUT: row = PM_SPROUT_ROW
					CropData.STAGE_GROWING: row = PM_GROWING_ROW
					_: row = PM_MATURE_ROW
				_plant_map.set_cell(coord, PM_SOURCE, Vector2i(cell.slot_crop_ids[slot], row))
				if cell.slot_states[slot] == FarmCell.SlotState.WILTED and _wilt_map:
					_wilt_map.set_cell(coord, 0, Vector2i(0, 0))
				if cell.slot_watered[slot] and _moisture_map and not CropData.is_water_crop(cell.slot_crop_ids[slot]):
					_moisture_map.set_cell(coord, 0, Vector2i(0, 0))
			_:
				pass

		if cell.slot_states[slot] == FarmCell.SlotState.CROP \
				and cell.slot_growth_stages[slot] == CropData.STAGE_MATURE:
			_show_slot_harvest_icon(cell, slot)
		else:
			_hide_slot_harvest_icon(cell, slot)
	return

	match cell.state:
		FarmCell.TileState.LOCKED:
			_terrain_map.set_cells_terrain_connect(all, TM_TERRAIN_SET, TM_GRASS)
			if not _decor_placed.has(key):
				if randf() > 0.3:   # 70% chance of decor, 30% plain grass
					_decor_map.set_cells_terrain_connect(all, DM_TERRAIN_SET, DM_DECOR)
					_move_rocks_from_decor(all)
				_decor_placed[key] = true
			# else: decor already decided this session — leave it as-is

		FarmCell.TileState.SOIL:
			_terrain_map.set_cells_terrain_connect(all, TM_TERRAIN_SET, TM_SOIL)
			for c in all:
				_decor_map.erase_cell(c)
				if _rock_decor_map: _rock_decor_map.erase_cell(c)
			_decor_placed.erase(key)

		FarmCell.TileState.WEED:
			_terrain_map.set_cells_terrain_connect(all, TM_TERRAIN_SET, TM_SOIL)
			# cover all 4 tilemap tiles so the weed is clearly visible
			_decor_map.set_cells_terrain_connect(all, DM_TERRAIN_SET, DM_DECOR)
			_move_rocks_from_decor(all)
			_decor_placed.erase(key)

		FarmCell.TileState.CROP, FarmCell.TileState.WILTED:
			_terrain_map.set_cells_terrain_connect(all, TM_TERRAIN_SET, TM_SOIL)
			for c in all:
				_decor_map.erase_cell(c)
				if _rock_decor_map: _rock_decor_map.erase_cell(c)
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


func _show_slot_harvest_icon(cell: FarmCell, slot: int) -> void:
	if not _icon_container:
		return

	var key := _slot_key(cell, slot)
	if _harvest_icon_shown_once.get(key, false) or _harvest_icons.has(key):
		return

	var tex_path := "res://games/zen_farm/assets/harvest_ready.png"
	if not ResourceLoader.exists(tex_path):
		return

	var icon := Sprite2D.new()
	icon.texture = load(tex_path)
	var slot_col := slot % 2
	var slot_row := slot >> 1
	icon.position = Vector2(
		cell.grid_col * TILE_SIZE + slot_col * 64.0 + 32.0,
		cell.grid_row * TILE_SIZE + slot_row * 64.0 + HARVEST_ICON_Y_OFFSET
	)
	_icon_container.add_child(icon)
	_harvest_icons[key] = icon

	var base_y := icon.position.y
	var tw := create_tween().set_loops()
	tw.tween_property(icon, "position:y", base_y - 8.0, 0.45) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(icon, "position:y", base_y, 0.45) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	icon.set_meta("tween", tw)

	get_tree().create_timer(HARVEST_ICON_LIFETIME).timeout.connect(func():
		if not is_instance_valid(icon):
			return
		tw.kill()
		var fade := create_tween()
		fade.tween_property(icon, "modulate:a", 0.0, 1.0)
		fade.tween_callback(func():
			if is_instance_valid(icon):
				_harvest_icons.erase(key)
				_harvest_icon_shown_once[key] = true
				icon.queue_free()
		)
	)


func _hide_slot_harvest_icon(cell: FarmCell, slot: int) -> void:
	var key := _slot_key(cell, slot)
	if not _harvest_icons.has(key):
		return
	var icon: Sprite2D = _harvest_icons[key]
	if icon.has_meta("tween"):
		(icon.get_meta("tween") as Tween).kill()
	icon.queue_free()
	_harvest_icons.erase(key)


func _show_harvest_icon(cell: FarmCell) -> void:
	if not _icon_container:
		return

	var key := Vector2i(cell.grid_col, cell.grid_row)

	if _harvest_icon_shown_once.get(key, false):
		return

	if _harvest_icons.has(key):
		return  # already showing

	var tex_path := "res://games/zen_farm/assets/harvest_ready.png"
	if not ResourceLoader.exists(tex_path):
		return  # texture not made yet — skip silently

	var icon := Sprite2D.new()
	icon.texture = load(tex_path)
	icon.position = Vector2(
		cell.grid_col * TILE_SIZE + TILE_SIZE * 0.5,
		cell.grid_row * TILE_SIZE - 24.0
	)
	_icon_container.add_child(icon)
	_harvest_icons[key] = icon

	var base_y := icon.position.y
	var tw := create_tween().set_loops()
	tw.tween_property(icon, "position:y", base_y - 8.0, 0.45) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(icon, "position:y", base_y, 0.45) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	icon.set_meta("tween", tw)

	get_tree().create_timer(30.0).timeout.connect(func():
		if not is_instance_valid(icon):
			return
		tw.kill()
		var fade := create_tween()
		fade.tween_property(icon, "modulate:a", 0.0, 1.0)
		fade.tween_callback(func():
			if is_instance_valid(icon):
				_harvest_icons.erase(key)
				_harvest_icon_shown_once[key] = true
				icon.queue_free()
		)
	)


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
		cell.reset_slots()
		cell.unlock_cost = _next_unlock_cost()
		cell.refresh_visual()
		_cells.append(cell)
	_place_bottom_border_decor(col, col + 2)
	_place_top_border_decor(col, col + 3)
	_place_side_border_column(_cols * 2)   # new right edge
	_update_grid_size()


func _place_top_border_decor(col_from: int, col_to: int) -> void:
	if not _terrain_map or not _decor_map:
		return

	var tiles: Array[Vector2i] = []
	var decor_tiles: Array[Vector2i] = []

	# include decorative edge columns too
	var bx_from := col_from * 2 - 1
	var bx_to   := col_to   * 2

	for bx in range(bx_from, bx_to + 1):
		tiles.append(Vector2i(bx, -1))
		tiles.append(Vector2i(bx, -2))

		if randf() > 0.3:
			decor_tiles.append(Vector2i(bx, -1))
		if randf() > 0.3:
			decor_tiles.append(Vector2i(bx, -2))

	if tiles.size() > 0:
		_terrain_map.set_cells_terrain_connect(tiles, TM_TERRAIN_SET, TM_GRASS)

	if decor_tiles.size() > 0:
		_decor_map.set_cells_terrain_connect(decor_tiles, DM_TERRAIN_SET, DM_DECOR)
		_move_rocks_from_decor(decor_tiles)
	_store_static_decor_coords(tiles)


func _place_bottom_border_decor(col_from: int, col_to: int) -> void:
	if not _terrain_map or not _decor_map:
		return
	var all_tiles: Array[Vector2i] = []
	var decor_tiles: Array[Vector2i] = []
	for col in range(col_from, col_to):
		var bx := col * 2
		for by in [ROWS * 2, ROWS * 2 + 1, ROWS * 2 + 2]:
			all_tiles.append(Vector2i(bx,     by))
			all_tiles.append(Vector2i(bx + 1, by))
		# decor only on the first row (64 px border); 70% chance per column
		if randf() > 0.3:
			decor_tiles.append(Vector2i(col * 2,     ROWS * 2))
			decor_tiles.append(Vector2i(col * 2 + 1, ROWS * 2))
	if all_tiles.size() > 0:
		_terrain_map.set_cells_terrain_connect(all_tiles, TM_TERRAIN_SET, TM_GRASS)
		if decor_tiles.size() > 0:
			_decor_map.set_cells_terrain_connect(decor_tiles, DM_TERRAIN_SET, DM_DECOR)
			_move_rocks_from_decor(decor_tiles)
		_store_static_decor_coords(all_tiles)


func _place_side_border_column(tx: int) -> void:
	if not _terrain_map or not _decor_map:
		return
	var tiles: Array[Vector2i] = []
	var decor_tiles: Array[Vector2i] = []
	for row in range(-1, ROWS * 2 + 3):   # -1 = top border row, + three bottom border rows
		tiles.append(Vector2i(tx, row))
		if randf() > 0.3:   # 70% chance of decor per tile
			decor_tiles.append(Vector2i(tx, row))
	_terrain_map.set_cells_terrain_connect(tiles, TM_TERRAIN_SET, TM_GRASS)
	if decor_tiles.size() > 0:
		_decor_map.set_cells_terrain_connect(decor_tiles, DM_TERRAIN_SET, DM_DECOR)
		_move_rocks_from_decor(decor_tiles)
	_store_static_decor_coords(tiles)


func _move_rocks_from_decor(tiles: Array[Vector2i]) -> void:
	if not _rock_decor_map:
		return
	for coord in tiles:
		var atlas := _decor_map.get_cell_atlas_coords(coord)
		if atlas in ROCK_ATLAS_COORDS:
			var src := _decor_map.get_cell_source_id(coord)
			var alt := _decor_map.get_cell_alternative_tile(coord)
			_decor_map.erase_cell(coord)
			_rock_decor_map.set_cell(coord, src, atlas, alt)


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
	var milestones := { 4: "Rose", 8: "Daisy", 12: "Sunflower", 16: "Hydrangea", 20: "Tulip" }
	for threshold in milestones:
		if tiles_before < threshold and tiles_now >= threshold:
			return milestones[threshold]
	return ""


# ── process ───────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	_update_day_night(delta)
	_tick_crops(delta)
	_tick_weeds(delta)
	_tick_rain(delta)
	_tick_fireflies()


# -- day/night ---------------------------------------------------------------
func _setup_day_night_overlay() -> void:
	_day_night_material = ShaderMaterial.new()
	_day_night_material.shader = load("res://games/zen_farm/assets/day_night_grade.gdshader")

	_day_night_overlay = ColorRect.new()
	_day_night_overlay.color = Color.WHITE
	_day_night_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_day_night_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_day_night_overlay.z_index = 8
	_day_night_overlay.material = _day_night_material
	$FarmScroll.add_child(_day_night_overlay)

	_firefly_texture = _make_radial_texture(96, Color(1.0, 0.90, 0.38, 0.92))


func _make_radial_texture(size: int, color: Color) -> Texture2D:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size * 0.5, size * 0.5)
	var radius := size * 0.5
	for y in range(size):
		for x in range(size):
			var d := center.distance_to(Vector2(x, y)) / radius
			var a := pow(clampf(1.0 - d, 0.0, 1.0), 2.55)
			var px := color
			px.a *= a
			img.set_pixel(x, y, px)
	return ImageTexture.create_from_image(img)


func _update_day_night(delta: float) -> void:
	if _game_active:
		_day_seconds = fposmod(_day_seconds + delta, DAY_NIGHT_CYCLE)
	var phase := _day_seconds / DAY_NIGHT_CYCLE
	var params := _day_night_params(phase)
	_night_amount = float(params["night"])
	_lamp_amount = float(params["lamp"])

	if _day_night_material:
		_day_night_material.set_shader_parameter("shadow_tint", params["shadow"])
		_day_night_material.set_shader_parameter("mid_tint", params["mid"])
		_day_night_material.set_shader_parameter("highlight_tint", params["highlight"])
		_day_night_material.set_shader_parameter("night_amount", params["night"])
		_day_night_material.set_shader_parameter("dusk_amount", params["dusk"])
		_day_night_material.set_shader_parameter("dawn_amount", params["dawn"])
		_day_night_material.set_shader_parameter("saturation", params["sat"])
		_day_night_material.set_shader_parameter("exposure", params["exposure"])
		_day_night_material.set_shader_parameter("contrast", params["contrast"])
		_day_night_material.set_shader_parameter("lift", params["lift"])
		_day_night_material.set_shader_parameter("vignette_strength", params["vignette"])

	if absf(_night_amount - _last_audio_night_amount) > 0.02:
		_last_audio_night_amount = _night_amount
		day_night_changed.emit(_night_amount)
	_sync_day_night_insects()


func _day_night_params(phase: float) -> Dictionary:
	var previous: Dictionary = DAY_NIGHT_KEYS[0]
	for i in range(1, DAY_NIGHT_KEYS.size()):
		var next: Dictionary = DAY_NIGHT_KEYS[i]
		var next_t := float(next["t"])
		if phase <= next_t:
			var prev_t := float(previous["t"])
			var span := maxf(0.001, next_t - prev_t)
			var u := smoothstep(0.0, 1.0, clampf((phase - prev_t) / span, 0.0, 1.0))
			var shadow_a: Color = previous["shadow"]
			var shadow_b: Color = next["shadow"]
			var mid_a: Color = previous["mid"]
			var mid_b: Color = next["mid"]
			var highlight_a: Color = previous["highlight"]
			var highlight_b: Color = next["highlight"]
			return {
				"shadow": shadow_a.lerp(shadow_b, u),
				"mid": mid_a.lerp(mid_b, u),
				"highlight": highlight_a.lerp(highlight_b, u),
				"night": lerpf(float(previous["night"]), float(next["night"]), u),
				"dusk": lerpf(float(previous["dusk"]), float(next["dusk"]), u),
				"dawn": lerpf(float(previous["dawn"]), float(next["dawn"]), u),
				"sat": lerpf(float(previous["sat"]), float(next["sat"]), u),
				"exposure": lerpf(float(previous["exposure"]), float(next["exposure"]), u),
				"contrast": lerpf(float(previous["contrast"]), float(next["contrast"]), u),
				"lift": lerpf(float(previous["lift"]), float(next["lift"]), u),
				"vignette": lerpf(float(previous["vignette"]), float(next["vignette"]), u),
				"lamp": lerpf(float(previous["lamp"]), float(next["lamp"]), u),
			}
		previous = next
	return DAY_NIGHT_KEYS[0]


func _sync_day_night_insects() -> void:
	if not _game_active:
		return
	var target := "none"
	if _is_raining:
		target = "none"
	elif _should_show_fireflies():
		target = "night"
	elif _night_amount <= 0.12:
		target = "day"
	elif _last_insect_mode == "day" and _night_amount < 0.30:
		target = "day"

	if target == _last_insect_mode:
		return

	if target != "day":
		_flee_butterflies()
	if target != "night":
		_flee_fireflies()

	if target == "day" and _butterflies.is_empty():
		_setup_butterflies()
	elif target == "night" and _fireflies.is_empty():
		_setup_fireflies()

	_last_insect_mode = target


func _should_show_fireflies() -> bool:
	var phase := _day_seconds / DAY_NIGHT_CYCLE
	return _night_amount >= 0.30 and phase >= FIREFLY_PHASE_START and phase < FIREFLY_PHASE_END


func _jump_day_night_to(phase: float) -> void:
	_day_seconds = clampf(phase, 0.0, 0.999) * DAY_NIGHT_CYCLE
	_last_insect_mode = ""
	_update_day_night(0.0)


func _farm_point_can_poke(pos: Vector2) -> bool:
	if not _terrain_map:
		return false
	var coord := _terrain_map.local_to_map(_terrain_map.to_local(pos))
	return _terrain_map.get_used_rect().has_point(coord)


func _farm_point_can_poke_visuals(pos: Vector2) -> bool:
	if not _farm_point_can_poke(pos):
		return false
	var cell := _cell_at(pos)
	if cell == null or not cell.is_water_plot:
		return true
	var slot := _cell_slot_at(cell, pos)
	return cell.slot_states[slot] == FarmCell.SlotState.CROP \
		or cell.slot_states[slot] == FarmCell.SlotState.WILTED \
		or cell.slot_states[slot] == FarmCell.SlotState.WEED


func _configure_poke_material(mat: ShaderMaterial) -> void:
	if not mat:
		return
	mat.set_shader_parameter("poke_pos", Vector2(-9999.0, -9999.0))
	mat.set_shader_parameter("poke_amount", 0.0)
	mat.set_shader_parameter("poke_radius", POKE_RADIUS)
	mat.set_shader_parameter("poke_strength", POKE_STRENGTH)


func _set_poke_shader_param(param: StringName, value: Variant) -> void:
	for layer in [_plant_map, _decor_map]:
		if not layer:
			continue
		var mat := layer.material as ShaderMaterial
		if mat:
			mat.set_shader_parameter(param, value)


func _set_poke_pos(pos: Vector2) -> void:
	for layer in [_plant_map, _decor_map]:
		if not layer:
			continue
		var mat := layer.material as ShaderMaterial
		if mat:
			mat.set_shader_parameter(&"poke_pos", pos)


func _touch_loop_for_pos(pos: Vector2) -> AudioStreamPlayer:
	var cell := _cell_at(pos)
	if cell:
		if cell.is_water_plot:
			var slot := _cell_slot_at(cell, pos)
			if cell.slot_states[slot] == FarmCell.SlotState.CROP \
					and CropData.is_water_crop(cell.slot_crop_ids[slot]):
				return _sfx_touch_grass
			return _sfx_touch_water
		if cell.state == FarmCell.TileState.SOIL and cell.empty_slot_count() == FarmCell.SLOT_COUNT:
			return _sfx_touch_soil
	return _sfx_touch_grass


func _touch_is_tap(max_drag: float) -> bool:
	return _touch_drag_dist < max_drag \
		and Time.get_ticks_msec() - _touch_start_msec <= TAP_MAX_DURATION_MSEC


func _kill_touch_loop_tween(player: AudioStreamPlayer) -> void:
	if not player:
		return
	if player.has_meta("touch_tween"):
		var tw: Tween = player.get_meta("touch_tween")
		if tw and is_instance_valid(tw):
			tw.kill()
		player.remove_meta("touch_tween")


func _fade_in_touch_loop(player: AudioStreamPlayer) -> void:
	if not player or not player.stream:
		return
	_kill_touch_loop_tween(player)
	if not player.playing:
		player.volume_db = TOUCH_GRASS_SILENT_DB
		player.play()
	var tw := create_tween()
	player.set_meta("touch_tween", tw)
	tw.tween_property(player, "volume_db", TOUCH_GRASS_VOLUME_DB, TOUCH_GRASS_FADE_IN) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _fade_out_touch_loop(player: AudioStreamPlayer) -> void:
	if not player or not player.playing:
		return
	_kill_touch_loop_tween(player)
	var tw := create_tween()
	player.set_meta("touch_tween", tw)
	tw.tween_property(player, "volume_db", TOUCH_GRASS_SILENT_DB, TOUCH_GRASS_FADE_OUT) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func():
		if player and player != _active_touch_loop:
			player.stop()
			player.remove_meta("touch_tween")
	)


func _start_touch_loop(pos: Vector2) -> void:
	var next_loop := _touch_loop_for_pos(pos)
	if next_loop == _active_touch_loop:
		return
	if _active_touch_loop:
		_fade_out_touch_loop(_active_touch_loop)
	_active_touch_loop = next_loop
	_fade_in_touch_loop(_active_touch_loop)


func _fade_out_active_touch_loop() -> void:
	if not _active_touch_loop:
		return
	var old_loop := _active_touch_loop
	_active_touch_loop = null
	_fade_out_touch_loop(old_loop)


func _fade_out_poke_visuals() -> void:
	if not _poke_active:
		return
	_poke_active = false
	if _poke_tween and is_instance_valid(_poke_tween):
		_poke_tween.kill()
	_poke_tween = create_tween()
	_poke_tween.tween_method(
		func(v: float): _set_poke_shader_param(&"poke_amount", v),
		1.0,
		0.0,
		POKE_RELEASE_FADE
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _update_poke(pos: Vector2) -> void:
	if not _farm_point_can_poke(pos):
		_end_poke()
		return
	_start_touch_loop(pos)
	if not _farm_point_can_poke_visuals(pos):
		_fade_out_poke_visuals()
		return
	if _poke_tween and is_instance_valid(_poke_tween):
		_poke_tween.kill()
		_poke_tween = null
	_poke_active = true
	_set_poke_pos(pos)
	_set_poke_shader_param(&"poke_amount", 1.0)


func _end_poke() -> void:
	_fade_out_active_touch_loop()
	_fade_out_poke_visuals()


func _input(event: InputEvent) -> void:
	if not _game_active:
		return
	# DEBUG: R toggles rain, D jumps to day, N jumps to night.
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_R:
				if _is_raining:
					_stop_rain()
				else:
					_start_rain()
			KEY_D:
				_jump_day_night_to(DAY_PHASE)
			KEY_N:
				_jump_day_night_to(NIGHT_PHASE)
	if event is InputEventScreenTouch:
		if event.pressed:
			_update_poke(event.position)
			_touch_start     = event.position
			_touch_start_msec = Time.get_ticks_msec()
			_touch_drag_dist = 0.0
			_touch_cell      = _cell_at(event.position)
			_touch_slot      = _cell_slot_at(_touch_cell, event.position)
		else:
			_end_poke()
			if _touch_is_tap(12.0) and _touch_cell != null:
				_on_cell_tapped(_touch_cell, _touch_slot)
			_touch_cell = null
	elif event is InputEventScreenDrag:
		_touch_drag_dist += abs(event.relative.x)
		_apply_scroll(int(-event.relative.x))
		_update_poke(event.position)
	elif event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_update_poke(event.position)
			_touch_start     = event.position
			_touch_start_msec = Time.get_ticks_msec()
			_touch_drag_dist = 0.0
			_touch_cell      = _cell_at(event.position)
			_touch_slot      = _cell_slot_at(_touch_cell, event.position)
		elif not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_end_poke()
			if _touch_is_tap(8.0) and _touch_cell != null:
				_on_cell_tapped(_touch_cell, _touch_slot)
			_touch_cell = null
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_apply_scroll(-60)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_apply_scroll(60)
	elif event is InputEventMouseMotion:
		if event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_touch_drag_dist += abs(event.relative.x)
			_apply_scroll(int(-event.relative.x))
			_update_poke(event.position)


func _cell_at(pos: Vector2) -> FarmCell:
	for cell in _cells:
		if cell.get_global_rect().has_point(pos):
			return cell
	return null


func _cell_slot_at(cell: FarmCell, pos: Vector2) -> int:
	if cell == null:
		return 0
	var rect := cell.get_global_rect()
	var local := pos - rect.position
	var col := 0 if local.x < TILE_SIZE * 0.5 else 1
	var row := 0 if local.y < TILE_SIZE * 0.5 else 1
	return row * 2 + col


func _tick_crops(delta: float) -> void:
	for cell in _cells:
		if not cell.has_active_crops():
			continue
		var changed := false
		for slot in range(FarmCell.SLOT_COUNT):
			if cell.slot_states[slot] != FarmCell.SlotState.CROP:
				continue
			if cell.slot_growth_stages[slot] == CropData.STAGE_MATURE:
				continue
			var is_water_crop := CropData.is_water_crop(cell.slot_crop_ids[slot])
			if is_water_crop and not cell.slot_watered[slot]:
				cell.slot_watered[slot] = true
				cell.slot_wilt_timers[slot] = 0.0
				changed = true
			if _is_raining and not cell.slot_watered[slot]:
				cell.slot_watered[slot] = true
				cell.slot_wilt_timers[slot] = 0.0
				changed = true
			var dur: float = CropData.get_stage_durations(cell.slot_crop_ids[slot])[cell.slot_growth_stages[slot]]
			if not cell.slot_watered[slot]:
				cell.slot_wilt_timers[slot] += delta
				if cell.slot_wilt_timers[slot] >= dur * 2.0:
					cell.slot_states[slot] = FarmCell.SlotState.WILTED
					changed = true
			else:
				cell.slot_time_in_stage[slot] += delta
				if cell.slot_time_in_stage[slot] >= dur:
					cell.slot_time_in_stage[slot] -= dur
					cell.slot_growth_stages[slot] += 1
					cell.slot_wilt_timers[slot] = 0.0
					if cell.slot_growth_stages[slot] < CropData.STAGE_MATURE and not is_water_crop:
						cell.slot_watered[slot] = false
					changed = true
		if changed:
			cell.refresh_visual()


func _tick_weeds(delta: float) -> void:
	_weed_timer += delta
	if _weed_timer < WEED_INTERVAL:
		return
	_weed_timer = 0.0

	var soil_slots: Array = []
	for i in range(_cells.size()):
		var cell: FarmCell = _cells[i]
		if cell.state == FarmCell.TileState.LOCKED or cell.state == FarmCell.TileState.GRASS:
			continue
		for slot in range(FarmCell.SLOT_COUNT):
			if cell.slot_states[slot] == FarmCell.SlotState.EMPTY:
				soil_slots.append(Vector2i(i, slot))
	if soil_slots.is_empty():
		return

	var weed_count := 0
	for c in _cells:
		for slot in range(FarmCell.SLOT_COUNT):
			if (c as FarmCell).slot_states[slot] == FarmCell.SlotState.WEED:
				weed_count += 1
	var max_weeds: int = max(1, int(soil_slots.size() * 0.3))
	if weed_count >= max_weeds:
		return

	if randf() < 0.4:
		var pick: Vector2i = soil_slots[randi() % soil_slots.size()]
		var cell: FarmCell = _cells[pick.x]
		cell.slot_states[pick.y] = FarmCell.SlotState.WEED
		if cell.is_water_plot:
			cell.slot_weed_atlas_coords[pick.y] = _random_water_weed_atlas_coord()
		else:
			cell.slot_weed_atlas_coords[pick.y] = Vector2i(-1, -1)
		cell.refresh_visual()
		if not _weed_tip_shown:
			_weed_tip_shown = true
			_show_status("A weed appeared! Use SHEARS to cut it.")


# ── rain ─────────────────────────────────────────────────────────────────────
func _tick_rain(delta: float) -> void:
	if not _game_active:
		return
	if _is_raining:
		_tick_rain_sprites(delta)
		_rain_duration -= delta
		if _rain_duration <= 0.0:
			_stop_rain()
	else:
		_rain_check_timer += delta
		if _rain_check_timer >= RAIN_CHECK_INTERVAL:
			_rain_check_timer = 0.0
			if randf() < RAIN_CHANCE:
				_start_rain()


func _setup_rain_sprites() -> void:
	if not _rain_template:
		return
	_rain_template.visible = false
	_rain_visual_layer = Node2D.new()
	_rain_visual_layer.name = "RainVisualLayer"
	_rain_visual_layer.z_index = 12
	_rain_visual_layer.visible = false
	_rain_visual_layer.modulate.a = 0.0
	$FarmScroll.add_child(_rain_visual_layer)

	# Puddle layer sits just below the decor and plant tilemaps (z=1, z=6) but
	# above the terrain/moisture tilemaps (z=0). Same z=0, inserted before
	# DecorMapLayer so tree order puts it below decor/plants/GridContainer.
	_rain_ground_layer = Node2D.new()
	_rain_ground_layer.name = "RainGroundLayer"
	_rain_ground_layer.z_index = 0
	_rain_ground_layer.visible = false
	$FarmScroll.add_child(_rain_ground_layer)
	$FarmScroll.move_child(_rain_ground_layer, _decor_map.get_index())

	for i in range(RAIN_STREAK_COUNT):
		var sprite := _rain_template.duplicate() as AnimatedSprite2D
		sprite.visible = true
		sprite.animation = &"rain"
		sprite.frame = randi() % maxi(1, sprite.sprite_frames.get_frame_count(&"rain"))
		sprite.stop()
		sprite.scale = Vector2.ONE * randf_range(1.1, 1.8)
		sprite.modulate.a = randf_range(0.45, 0.85)
		sprite.position = Vector2(randf_range(-80.0, RAIN_AREA_SIZE.x + 40.0), randf_range(-80.0, RAIN_AREA_SIZE.y + 20.0))
		_rain_visual_layer.add_child(sprite)
		_rain_streaks.append({"node": sprite, "speed": randf_range(0.75, 1.35)})

	var ground_frame_count := _rain_template.sprite_frames.get_frame_count(&"rain_on_ground")
	for i in range(RAIN_GROUND_COUNT):
		var sprite := _rain_template.duplicate() as AnimatedSprite2D
		sprite.visible = false
		sprite.z_index = 0
		sprite.animation = &"rain_on_ground"
		sprite.frame = randi() % maxi(1, ground_frame_count)
		sprite.stop()
		sprite.scale = Vector2.ONE * randf_range(1.0, 1.7)
		sprite.modulate.a = randf_range(0.25, 0.55)
		sprite.position = Vector2(randf_range(8.0, RAIN_AREA_SIZE.x - 8.0), randf_range(64.0, RAIN_AREA_SIZE.y - 12.0))
		_rain_ground_layer.add_child(sprite)
		# hidden_timer: delay before first appearance; visible_timer: how long to show
		_rain_ground.append({"node": sprite, "hidden_timer": randf_range(0.0, 1.8), "visible_timer": 0.0, "showing": false})


func _hide_rain_ground_sprites() -> void:
	for g in _rain_ground:
		(g["node"] as AnimatedSprite2D).visible = false
		g["showing"] = false
		g["hidden_timer"] = randf_range(0.0, 1.8)
		g["visible_timer"] = 0.0
	if _rain_ground_layer:
		_rain_ground_layer.visible = false


func _set_rain_sprites_active(active: bool, instant: bool = false) -> void:
	if not _rain_visual_layer:
		return
	_rain_visual_layer.visible = true
	if active:
		if _rain_ground_layer:
			_rain_ground_layer.visible = true
		for fly in _rain_streaks:
			var sprite := fly["node"] as AnimatedSprite2D
			sprite.position = Vector2(randf_range(-80.0, RAIN_AREA_SIZE.x + 40.0), randf_range(-80.0, RAIN_AREA_SIZE.y + 20.0))
			sprite.frame = randi() % maxi(1, sprite.sprite_frames.get_frame_count(&"rain"))
			sprite.stop()
		for g in _rain_ground:
			(g["node"] as AnimatedSprite2D).visible = false
			g["showing"] = false
			g["hidden_timer"] = randf_range(0.0, 1.2)
			g["visible_timer"] = 0.0
		if instant:
			_rain_visual_layer.modulate.a = 1.0
		else:
			create_tween().tween_property(_rain_visual_layer, "modulate:a", 1.0, 0.8)
	else:
		_hide_rain_ground_sprites()
		if instant:
			_rain_visual_layer.modulate.a = 0.0
			_rain_visual_layer.visible = false
		else:
			var tw := create_tween()
			tw.tween_property(_rain_visual_layer, "modulate:a", 0.0, 1.3)
			tw.tween_callback(func():
				if _rain_visual_layer and not _is_raining:
					_rain_visual_layer.visible = false
			)


func _tick_rain_sprites(delta: float) -> void:
	for fly in _rain_streaks:
		var sprite := fly["node"] as AnimatedSprite2D
		sprite.position += RAIN_FALL_VECTOR * float(fly["speed"]) * delta
		if sprite.position.y > RAIN_AREA_SIZE.y + 36.0 or sprite.position.x > RAIN_AREA_SIZE.x + 44.0:
			sprite.frame = randi() % maxi(1, sprite.sprite_frames.get_frame_count(&"rain"))
			if randf() < 0.38:
				# Enter from the left edge — covers the bottom-left corner that
				# top-only spawns never reach with a rightward fall vector.
				sprite.position = Vector2(randf_range(-40.0, 0.0), randf_range(-20.0, RAIN_AREA_SIZE.y + 10.0))
			else:
				sprite.position = Vector2(randf_range(-30.0, RAIN_AREA_SIZE.x + 10.0), randf_range(-120.0, -10.0))

	var gfc := (_rain_template.sprite_frames.get_frame_count(&"rain_on_ground") if _rain_template else 3)
	for g in _rain_ground:
		if g["showing"]:
			g["visible_timer"] -= delta
			if g["visible_timer"] <= 0.0:
				(g["node"] as AnimatedSprite2D).visible = false
				g["showing"] = false
				g["hidden_timer"] = randf_range(0.25, 1.8)
		else:
			g["hidden_timer"] -= delta
			if g["hidden_timer"] <= 0.0:
				var sp := g["node"] as AnimatedSprite2D
				sp.frame = randi() % maxi(1, gfc)
				sp.visible = true
				g["showing"] = true
				g["visible_timer"] = randf_range(0.28, 0.48)


func _start_rain() -> void:
	_is_raining = true
	_rain_duration = randf_range(RAIN_DURATION_MIN, RAIN_DURATION_MAX)
	# water all crops and revive wilted immediately
	for cell in _cells:
		var changed := false
		for slot in range(FarmCell.SLOT_COUNT):
			if cell.slot_states[slot] == FarmCell.SlotState.CROP \
					and not cell.slot_watered[slot] \
					and cell.slot_growth_stages[slot] < CropData.STAGE_MATURE:
				cell.slot_watered[slot] = true
				cell.slot_wilt_timers[slot] = 0.0
				changed = true
			elif cell.slot_states[slot] == FarmCell.SlotState.WILTED:
				cell.slot_states[slot] = FarmCell.SlotState.CROP
				cell.slot_watered[slot] = true
				cell.slot_wilt_timers[slot] = 0.0
				changed = true
		if changed:
			cell.refresh_visual()
	_rain_particles.emitting = false
	_set_rain_sprites_active(true)
	var tw := create_tween()
	tw.tween_property(_rain_overlay, "color:a", 0.18, 1.5)
	_show_status("It's raining! Crops are being watered.")
	_flee_butterflies()
	_flee_fireflies()
	rain_changed.emit(true)


func _stop_rain() -> void:
	_is_raining = false
	_rain_particles.emitting = false
	_set_rain_sprites_active(false)
	var tw := create_tween()
	tw.tween_property(_rain_overlay, "color:a", 0.0, 2.0)
	_show_status("The rain has stopped.")
	rain_changed.emit(false)
	get_tree().create_timer(8.0).timeout.connect(func():
		if not _is_raining and _game_active:
			_last_insect_mode = ""
			_sync_day_night_insects()
	)


# ── offline catch-up ──────────────────────────────────────────────────────
func _apply_offline_catchup() -> void:
	if _last_save_time <= 0.0:
		return
	var elapsed := Time.get_unix_time_from_system() - _last_save_time
	if elapsed <= 0.0:
		return

	for cell in _cells:
		if not cell.has_active_crops():
			continue
		for slot in range(FarmCell.SLOT_COUNT):
			if cell.slot_states[slot] != FarmCell.SlotState.CROP:
				continue
			if cell.slot_growth_stages[slot] == CropData.STAGE_MATURE:
				continue
			var is_water_crop := CropData.is_water_crop(cell.slot_crop_ids[slot])
			if is_water_crop:
				cell.slot_watered[slot] = true
				cell.slot_wilt_timers[slot] = 0.0
			var t := elapsed
			while t > 0.0 and cell.slot_growth_stages[slot] < CropData.STAGE_MATURE:
				if not cell.slot_watered[slot]:
					var dur: float = CropData.get_stage_durations(cell.slot_crop_ids[slot])[cell.slot_growth_stages[slot]]
					var can_wilt := minf(t, dur * 2.0 - cell.slot_wilt_timers[slot])
					cell.slot_wilt_timers[slot] += can_wilt
					t -= can_wilt
					if cell.slot_wilt_timers[slot] >= dur * 2.0:
						cell.slot_states[slot] = FarmCell.SlotState.WILTED
					break
				else:
					var dur: float = CropData.get_stage_durations(cell.slot_crop_ids[slot])[cell.slot_growth_stages[slot]]
					var left: float = dur - cell.slot_time_in_stage[slot]
					if t >= left:
						t -= left
						cell.slot_time_in_stage[slot] = 0.0
						cell.slot_growth_stages[slot] += 1
						cell.slot_wilt_timers[slot] = 0.0
						if cell.slot_growth_stages[slot] < CropData.STAGE_MATURE and not is_water_crop:
							cell.slot_watered[slot] = false
					else:
						cell.slot_time_in_stage[slot] += t
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
		_active_tool = Tool.WATERING_CAN
		_seeds_open = false
		_shop_open = false
		_seed_panel.visible = false
		_upgrade_panel.visible = false
		_refresh_ui()
		_show_status("Watering Can selected.")
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
func _on_cell_tapped(cell: FarmCell, slot: int) -> void:
	_scatter_butterfly_from(cell)

	if _seeds_open:
		if cell.state != FarmCell.TileState.LOCKED and cell.slot_states[slot] == FarmCell.SlotState.EMPTY:
			_try_plant(cell, slot)
		else:
			_show_status("Choose an empty soil patch.")
		return

	match _active_tool:
		Tool.HAND:          _try_hand(cell, slot)
		Tool.WATERING_CAN:  _try_water_cell(cell)
		Tool.SHEARS:        _try_shear(cell, slot)


func _toggle_empty_plot_surface(cell: FarmCell) -> void:
	if cell.empty_slot_count() != FarmCell.SLOT_COUNT:
		_play(_sfx_noaction)
		_show_status("Clear the plot first.")
		return
	var key := Vector2i(cell.grid_col, cell.grid_row)
	_decor_placed.erase(key)
	_invalidate_static_decor_for_cell(cell)
	_soil_placed.erase(key)
	if cell.is_water_plot or cell.state == FarmCell.TileState.WATER:
		cell.is_water_plot = false
		cell.state = FarmCell.TileState.SOIL
		_show_status("Tilled.")
		_play(_sfx_soil_till)
	elif cell.state == FarmCell.TileState.GRASS:
		if _water_toggle_unlocked:
			cell.is_water_plot = true
			cell.state = FarmCell.TileState.WATER
			_show_status("Made water.")
			_play(_sfx_water_plop)
		else:
			cell.state = FarmCell.TileState.SOIL
			_show_status("Tilled.")
			_play(_sfx_soil_till)
	else:
		cell.is_water_plot = false
		cell.state = FarmCell.TileState.GRASS
		_show_status("Made grassy.")
		_play(_sfx_soil_toggle)
	cell.refresh_visual()
	SaveManager.save_game(self)


# HAND tool: unlock tiles; guide player toward the right tool otherwise
func _try_hand(cell: FarmCell, slot: int) -> void:
	match cell.state:
		FarmCell.TileState.SOIL:
			if (_grass_toggle_unlocked or _water_toggle_unlocked) and cell.empty_slot_count() == FarmCell.SLOT_COUNT:
				_toggle_empty_plot_surface(cell)
			else:
				_play(_sfx_noaction)
				_show_status("Tap SEEDS to plant.")
		FarmCell.TileState.GRASS:
			if _grass_toggle_unlocked or _water_toggle_unlocked:
				_toggle_empty_plot_surface(cell)
			else:
				_play(_sfx_noaction)
				_show_status("Buy the grass tool in SHOP.")
		FarmCell.TileState.WATER:
			if _grass_toggle_unlocked or _water_toggle_unlocked:
				_toggle_empty_plot_surface(cell)
			else:
				_play(_sfx_noaction)
				_show_status("Buy the water tool in SHOP.")
		FarmCell.TileState.WEED:
			_play(_sfx_noaction)
			if cell.slot_states[slot] == FarmCell.SlotState.WEED:
				_show_status("Use Shears to cut this weed.")
			else:
				_show_status("Tap SEEDS to plant.")
		FarmCell.TileState.CROP:
			_play(_sfx_crop_tap)
			if cell.slot_states[slot] == FarmCell.SlotState.EMPTY:
				_show_status("Tap SEEDS to plant.")
			elif cell.slot_states[slot] == FarmCell.SlotState.WEED:
				_show_status("Use Shears to cut this weed.")
			elif cell.slot_growth_stages[slot] == CropData.STAGE_MATURE:
				_show_status("Ready! Use Shears to harvest.")
			elif not cell.slot_watered[slot]:
				_show_status("Thirsty! Use Watering Can.")
			else:
				_show_status("Growing steadily.")
		FarmCell.TileState.WILTED:
			_play(_sfx_crop_tap)
			if cell.slot_states[slot] == FarmCell.SlotState.WILTED:
				_show_status("Wilted! Use Watering Can.")
			else:
				_show_status("Watering Can can help this plot.")
		FarmCell.TileState.LOCKED:
			if _tip_panel.visible:
				return
			var cost := _next_unlock_cost()
			if _coins >= cost:
				if _coins == cost and not _has_active_crops():
					_play(_sfx_noaction)
					_show_status("Keep 1c for seeds - can't spend your last coin!")
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
		_show_status("Can is empty - fill at the Well.")
		return
	var cmax := _can_max()
	var watered_any := false
	var revived_any := false
	for slot in range(FarmCell.SLOT_COUNT):
		if cell.slot_states[slot] == FarmCell.SlotState.WILTED:
			cell.slot_states[slot] = FarmCell.SlotState.CROP
			cell.slot_watered[slot] = true
			cell.slot_wilt_timers[slot] = 0.0
			watered_any = true
			revived_any = true
		elif cell.slot_states[slot] == FarmCell.SlotState.CROP \
				and cell.slot_growth_stages[slot] < CropData.STAGE_MATURE \
				and not cell.slot_watered[slot]:
			cell.slot_watered[slot] = true
			cell.slot_wilt_timers[slot] = 0.0
			watered_any = true
	if watered_any:
		cell.refresh_visual()
		_can_water -= 1
		_refresh_ui()
		_play(_sfx_water)
		var verb := "Revived" if revived_any else "Watered"
		_show_status(verb + "! (" + str(_can_water) + "/" + str(cmax) + " left)")
		SaveManager.save_game(self)
	else:
		_play(_sfx_noaction)
		_show_status("Nothing needs water here.")
	return
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

# Helper for the state
func _clear_harvest_icon_state(cell: FarmCell) -> void:
	var key := Vector2i(cell.grid_col, cell.grid_row)
	_harvest_icon_shown_once.erase(key)

	if _harvest_icons.has(key):
		var icon = _harvest_icons[key]
		_harvest_icons.erase(key)
		if is_instance_valid(icon):
			var tw = icon.get_meta("tween", null)
			if tw:
				tw.kill()
			icon.queue_free()


func _clear_slot_harvest_icon_state(cell: FarmCell, slot: int) -> void:
	var key := _slot_key(cell, slot)
	_harvest_icon_shown_once.erase(key)
	_hide_slot_harvest_icon(cell, slot)


# SHEARS tool: harvest mature crops and cut weeds
func _try_shear(cell: FarmCell, slot: int) -> void:
	match cell.slot_states[slot]:
		FarmCell.SlotState.CROP:
			if cell.slot_growth_stages[slot] == CropData.STAGE_MATURE:
				var value := CropData.get_sell_value(cell.slot_crop_ids[slot])
				_coins += value
				_inventory[cell.slot_crop_ids[slot]] = _inventory.get(cell.slot_crop_ids[slot], 0) + 1
				cell.clear_slot(slot)
				_clear_slot_harvest_icon_state(cell, slot)
				cell.refresh_visual()
				_play(_sfx_harvest)
				_spawn_coin_float(cell, value)
				_show_status("Harvested! +" + str(value) + "c")
				_refresh_ui()
				SaveManager.save_game(self)
			elif cell.slot_growth_stages[slot] == CropData.STAGE_SEED:
				var refund: int = maxi(1, CropData.get_seed_cost(cell.slot_crop_ids[slot]) >> 1)
				_coins += refund
				cell.clear_slot(slot)
				_clear_slot_harvest_icon_state(cell, slot)
				cell.refresh_visual()
				_play(_sfx_weedcut)
				_spawn_coin_float(cell, refund)
				_show_status("Seed uprooted. +" + str(refund) + "c back.")
				_refresh_ui()
				SaveManager.save_game(self)
			else:
				_play(_sfx_noaction)
				if CropData.is_water_crop(cell.slot_crop_ids[slot]):
					_show_status("Not ready yet.")
				else:
					_show_status("Not ready yet - keep watering.")
		FarmCell.SlotState.WILTED:
			_play(_sfx_noaction)
			_show_status("Wilted! Use Watering Can.")
		FarmCell.SlotState.WEED:
			cell.clear_slot(slot)
			_clear_slot_harvest_icon_state(cell, slot)
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
	return
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
				_clear_harvest_icon_state(cell)
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
				_clear_harvest_icon_state(cell)
				cell.refresh_visual()
				_play(_sfx_weedcut)
				_spawn_coin_float(cell, refund)
				_show_status("Seed uprooted. +" + str(refund) + "c back.")
				_refresh_ui()
				SaveManager.save_game(self)

			else:
				_play(_sfx_noaction)
				_show_status("Not ready yet - keep watering.")

		FarmCell.TileState.WEED:
			cell.state = FarmCell.TileState.SOIL
			_clear_harvest_icon_state(cell)
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
func _try_plant(cell: FarmCell, slot: int) -> void:
	if _selected_crop == -1:
		_play(_sfx_noaction)
		_show_status("Pick a seed first!")
		return
	if cell.state == FarmCell.TileState.LOCKED or cell.slot_states[slot] != FarmCell.SlotState.EMPTY:
		_play(_sfx_noaction)
		_show_status("Choose an empty soil patch.")
		return
	var selected_is_water_crop := CropData.is_water_crop(_selected_crop)
	if selected_is_water_crop and not _water_toggle_unlocked:
		_play(_sfx_noaction)
		_show_status("Unlock water in SHOP first.")
		return
	if cell.state == FarmCell.TileState.GRASS:
		_play(_sfx_noaction)
		_show_status("Till this plot first.")
		return
	if selected_is_water_crop and not cell.is_water_plot:
		_play(_sfx_noaction)
		_show_status("Plant lotus in water.")
		return
	if not selected_is_water_crop and cell.is_water_plot:
		_play(_sfx_noaction)
		_show_status("Choose soil for this seed.")
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
		_show_status("Need " + str(cost) + "c - not enough coins.")
		return
	_coins -= cost
	cell.slot_states[slot] = FarmCell.SlotState.CROP
	cell.slot_crop_ids[slot] = _selected_crop
	cell.slot_growth_stages[slot] = CropData.STAGE_SEED
	cell.slot_time_in_stage[slot] = 0.0
	cell.slot_watered[slot] = _is_raining or selected_is_water_crop
	cell.slot_wilt_timers[slot] = 0.0
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
	if CropData.is_water_crop(crop_id) and not _water_toggle_unlocked:
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


func _on_grass_toggle_upgrade_pressed() -> void:
	if _grass_toggle_unlocked:
		_play(_sfx_noaction)
		_show_status("Grass toggle already unlocked.")
		return
	if _coins < GRASS_TOGGLE_COST:
		_play(_sfx_noaction)
		_show_status("Need " + str(GRASS_TOGGLE_COST) + "c to unlock grass.")
		return
	_coins -= GRASS_TOGGLE_COST
	_grass_toggle_unlocked = true
	_refresh_ui()
	_play(_sfx_upgrade)
	_show_status("Grass toggle unlocked!")
	SaveManager.save_game(self)


func _on_water_toggle_upgrade_pressed() -> void:
	if _water_toggle_unlocked:
		_play(_sfx_noaction)
		_show_status("Water toggle already unlocked.")
		return
	if _coins < WATER_TOGGLE_COST:
		_play(_sfx_noaction)
		_show_status("Need " + str(WATER_TOGGLE_COST) + "c to unlock water.")
		return
	_coins -= WATER_TOGGLE_COST
	_water_toggle_unlocked = true
	_refresh_ui()
	_play(_sfx_upgrade)
	_show_status("Water toggle unlocked! Lotus seeds available.")
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
		[_sfx_soil_toggle, "soil_stuff2.mp3"],
		[_sfx_soil_till, "soil_till.mp3"],
		[_sfx_water_plop, "water_plop.mp3"],
		[_sfx_touch_grass, "touch_grass.mp3"],
		[_sfx_touch_water, "touch_water.mp3"],
		[_sfx_touch_soil, "touching_soil.mp3"],
	]
	for e in entries:
		var path: String = _SFX_DIR + e[1]
		if ResourceLoader.exists(path):
			e[0].stream = load(path)
	for loop_sfx in [_sfx_touch_grass, _sfx_touch_water, _sfx_touch_soil]:
		if loop_sfx and loop_sfx.stream:
			if loop_sfx.stream is AudioStreamMP3:
				(loop_sfx.stream as AudioStreamMP3).loop = true
			loop_sfx.volume_db = TOUCH_GRASS_SILENT_DB


func _play(sfx: AudioStreamPlayer) -> void:
	if sfx and sfx.stream:
		sfx.play()


func _crop_icon(crop_id: int, atlas_row: int, tall: bool = false) -> AtlasTexture:
	var tex := AtlasTexture.new()
	tex.atlas = _objects_texture
	var height := PM_TILE_SIZE * (2 if tall else 1)
	tex.region = Rect2(crop_id * PM_TILE_SIZE, atlas_row * PM_TILE_SIZE, PM_TILE_SIZE, height)
	return tex


func _seed_buttons() -> Array[Button]:
	return [
		$SeedPanel/LavenderBtn,
		$SeedPanel/RoseBtn,
		$SeedPanel/DaisyBtn,
		$SeedPanel/SunflowerBtn,
		$SeedPanel/HydrangeaBtn,
		$SeedPanel/TulipBtn,
		$SeedPanel/LotusBtn,
	]


func _seed_crop_ids() -> Array[int]:
	return [
		CropData.LAVENDER,
		CropData.ROSE,
		CropData.DAISY,
		CropData.SUNFLOWER,
		CropData.HYDRANGEA,
		CropData.TULIP,
		CropData.LOTUS,
	]


func _setup_seed_panel_icons() -> void:
	for btn in _seed_buttons():
		btn.expand_icon = false
		btn.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.clip_text = true
		btn.add_theme_constant_override("h_separation", SEED_BUTTON_ICON_TEXT_GAP)
		btn.add_theme_font_size_override("font_size", SEED_BUTTON_FONT_SIZE)

	_inv_label.visible = false
	_inventory_icon_row = HBoxContainer.new()
	_inventory_icon_row.name = "InventoryIconRow"
	_inventory_icon_row.position = _inv_label.position + Vector2(-5.0, -9.0)
	_inventory_icon_row.size = Vector2(292.0, 52.0)
	_inventory_icon_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_inventory_icon_row.add_theme_constant_override("separation", 8)
	_inventory_icon_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_seed_panel.add_child(_inventory_icon_row)


func _make_inventory_icon_count(crop_id: int, count: int) -> HBoxContainer:
	var item := HBoxContainer.new()
	item.custom_minimum_size = Vector2(46.0, 48.0)
	item.alignment = BoxContainer.ALIGNMENT_CENTER
	item.add_theme_constant_override("separation", -3)
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var icon := TextureRect.new()
	icon.texture = _crop_icon(crop_id, PM_BLOSSOM_ROW)
	icon.custom_minimum_size = Vector2(24.0, 46.0)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item.add_child(icon)

	var label := Label.new()
	label.text = "x" + str(count)
	label.custom_minimum_size = Vector2(24.0, 44.0)
	label.add_theme_font_override("font", load("res://assets/font/vetka.ttf"))
	label.add_theme_font_size_override("font_size", 26)
	label.add_theme_color_override("font_color", Color(0.572549, 0.215686, 0.0627451, 1))
	label.add_theme_color_override("font_outline_color", Color(0.05, 0.1, 0.04, 1))
	label.add_theme_constant_override("outline_size", 2)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item.add_child(label)
	return item


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
	var crop_ids := _seed_crop_ids()
	var crop_btns := _seed_buttons()
	for i in range(crop_ids.size()):
		var cid: int    = crop_ids[i]
		var btn: Button = crop_btns[i]
		var threshold: int = CropData.get_unlock_tile_count(cid)
		var unlocked: bool = owned >= threshold and (not CropData.is_water_crop(cid) or _water_toggle_unlocked)
		btn.icon = _crop_icon(cid, PM_PACK_ROW)
		btn.tooltip_text = CropData.crop_name(cid)
		if unlocked:
			btn.disabled = false
			btn.modulate = Color(1.25, 1.18, 0.76, 1.0) if _selected_crop == cid else Color.WHITE
			btn.text = str(CropData.get_seed_cost(cid)) + "c"
		else:
			btn.disabled = true
			btn.modulate = Color(1, 1, 1, 0.38)
			btn.text = "W" if CropData.is_water_crop(cid) else str(threshold)

	# inventory label in seed panel
	var parts: Array = []
	for cid in crop_ids:
		var cnt: int = _inventory.get(cid, 0)
		if cnt > 0:
			parts.append(CropData.crop_name(cid) + "×" + str(cnt))
	_inv_label.text = ("Harvested: " + ", ".join(parts)) if not parts.is_empty() else ""

	# ── upgrade panel ─────────────────────────────────────────────────────
	if _inventory_icon_row:
		for child in _inventory_icon_row.get_children():
			child.queue_free()
		for cid in crop_ids:
			var cnt: int = _inventory.get(cid, 0)
			if cnt > 0:
				_inventory_icon_row.add_child(_make_inventory_icon_count(cid, cnt))

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

	if _grass_toggle_unlocked:
		_grass_toggle_btn.text = "Grass Toggle  OWNED"
		_grass_toggle_btn.disabled = true
		_grass_toggle_btn.modulate = Color(1, 1, 1, 0.45)
	else:
		_grass_toggle_btn.text = "Grass Toggle  " + str(GRASS_TOGGLE_COST) + "c"
		_grass_toggle_btn.disabled = false
		_grass_toggle_btn.modulate = Color.WHITE

	if _water_toggle_unlocked:
		_water_toggle_btn.text = "Water Toggle  OWNED"
		_water_toggle_btn.disabled = true
		_water_toggle_btn.modulate = Color(1, 1, 1, 0.45)
	else:
		_water_toggle_btn.text = "Water Toggle  " + str(WATER_TOGGLE_COST) + "c"
		_water_toggle_btn.disabled = false
		_water_toggle_btn.modulate = Color.WHITE


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


# ── butterflies ──────────────────────────────────────────────────────────────
func _insect_parent() -> Node:
	return _insect_container if _insect_container else $FarmScroll


func _visible_content_rect() -> Rect2:
	var pos := Vector2.ZERO
	if _insect_container:
		pos = _insect_container.position
	return Rect2(Vector2(-pos.x, -pos.y), Vector2(540.0, 814.0))


func _offscreen_content_pos(side: int) -> Vector2:
	var rect := _visible_content_rect()
	match side:
		0:
			return Vector2(rect.position.x - INSECT_SPAWN_MARGIN, randf_range(rect.position.y, rect.end.y))
		1:
			return Vector2(rect.end.x + INSECT_SPAWN_MARGIN, randf_range(rect.position.y, rect.end.y))
		2:
			return Vector2(randf_range(rect.position.x, rect.end.x), rect.position.y - INSECT_SPAWN_MARGIN)
		_:
			return Vector2(randf_range(rect.position.x, rect.end.x), rect.end.y + INSECT_SPAWN_MARGIN)


func _setup_butterflies() -> void:
	if _is_raining or _night_amount >= 0.30:
		return
	var templates: Array = []
	for tname in ["Butterfly1", "Butterfly2", "Butterfly3"]:
		var t := get_node_or_null("FarmScroll/" + tname) as AnimatedSprite2D
		if t:
			templates.append(t)
	if templates.is_empty():
		return
	var count := randi() % (BUTTERFLY_COUNT + 1)  # 0–3
	for i in count:
		var sprite := (templates[randi() % templates.size()] as AnimatedSprite2D).duplicate() as AnimatedSprite2D
		if sprite == null:
			continue
		sprite.position = _butterfly_offscreen_pos()
		sprite.z_index = 10
		sprite.visible  = true
		sprite.scale    = Vector2(1.0, 1.0)
		sprite.play("default", randf_range(0.8, 1.3))
		sprite.frame          = randi() % 4
		sprite.frame_progress = randf()
		_insect_parent().add_child(sprite)
		var bfly := {"node": sprite, "state": "flying", "perched_cell": null, "perched_slot": -1, "tween": null}
		_butterflies.append(bfly)
		get_tree().create_timer(randf_range(0.5, 4.0) * i).timeout.connect(func():
			if _butterflies.has(bfly) and is_instance_valid(bfly["node"]):
				_butterfly_wander(bfly)
		)


func _clear_butterflies() -> void:
	for bfly in _butterflies:
		if bfly.get("tween") and is_instance_valid(bfly["tween"]):
			bfly["tween"].kill()
		if is_instance_valid(bfly["node"]):
			bfly["node"].queue_free()
	_butterflies.clear()


func _setup_fireflies() -> void:
	if _firefly_texture == null:
		return
	var add_mat := CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	var count := FIREFLY_COUNT - randi() % 4
	for i in range(count):
		var sprite := Sprite2D.new()
		sprite.texture = _firefly_texture
		sprite.position = _firefly_offscreen_pos()
		sprite.scale = Vector2.ONE * randf_range(0.34, 0.72)
		sprite.z_index = 10
		sprite.modulate = Color(1.0, 0.82, 0.28, 0.0)
		sprite.material = add_mat
		_insect_parent().add_child(sprite)
		var fly := {
			"node": sprite,
			"tween": null,
			"base_alpha": randf_range(0.48, 0.85),
			"flicker_speed": randf_range(2.0, 4.8),
			"flicker_offset": randf_range(0.0, TAU),
		}
		_fireflies.append(fly)
		get_tree().create_timer(randf_range(0.10, 0.34) * float(i + 1)).timeout.connect(func():
			if _fireflies.has(fly) and is_instance_valid(fly["node"]):
				_firefly_wander(fly)
		)


func _clear_fireflies() -> void:
	for fly in _fireflies:
		if fly.get("tween") and is_instance_valid(fly["tween"]):
			fly["tween"].kill()
		if is_instance_valid(fly["node"]):
			fly["node"].queue_free()
	_fireflies.clear()


func _flee_fireflies() -> void:
	for fly in _fireflies.duplicate():
		if not is_instance_valid(fly["node"]):
			_fireflies.erase(fly)
			continue
		if fly.get("tween") and is_instance_valid(fly["tween"]):
			fly["tween"].kill()
		var node := fly["node"] as Sprite2D
		var rect := _visible_content_rect()
		var target := Vector2(randf_range(rect.position.x, rect.end.x), rect.position.y - INSECT_SPAWN_MARGIN)
		var tw := create_tween()
		fly["tween"] = tw
		tw.tween_property(node, "position", target, randf_range(1.8, 3.8)).set_trans(Tween.TRANS_SINE)
		tw.parallel().tween_property(node, "modulate:a", 0.0, 1.2)
		tw.tween_callback(func():
			if is_instance_valid(node):
				node.queue_free()
			_fireflies.erase(fly)
		)


func _tick_fireflies() -> void:
	if _fireflies.is_empty():
		return
	var now := Time.get_ticks_msec() * 0.001
	for fly in _fireflies.duplicate():
		if not is_instance_valid(fly["node"]):
			_fireflies.erase(fly)
			continue
		var node := fly["node"] as Sprite2D
		var flicker := 0.62 + 0.38 * sin(now * float(fly["flicker_speed"]) + float(fly["flicker_offset"]))
		node.modulate.a = clampf(_lamp_amount * float(fly["base_alpha"]) * flicker, 0.0, 0.95)


func _firefly_offscreen_pos() -> Vector2:
	return _offscreen_content_pos(randi() % 4)


func _firefly_wander_pos() -> Vector2:
	var grid_w := maxf(float(_cols) * TILE_SIZE, 64.0)
	return Vector2(
		randf_range(28.0, grid_w - 28.0),
		randf_range(-34.0, ROWS * TILE_SIZE + 40.0)
	)


func _firefly_wander(fly: Dictionary) -> void:
	if not _fireflies.has(fly) or not is_instance_valid(fly["node"]):
		return
	var node := fly["node"] as Sprite2D
	var start := node.position
	var target := _firefly_wander_pos()
	var mid := (start + target) * 0.5 + Vector2(randf_range(-38.0, 38.0), randf_range(-48.0, 36.0))
	var dur := clampf(start.distance_to(target) / 48.0, 2.4, 6.4)
	var pause := randf_range(0.3, 1.8)
	var tw := create_tween()
	fly["tween"] = tw
	tw.tween_property(node, "position", mid, dur * 0.5).set_trans(Tween.TRANS_SINE)
	tw.tween_property(node, "position", target, dur * 0.5).set_trans(Tween.TRANS_SINE)
	tw.tween_interval(pause)
	tw.tween_callback(func():
		if _fireflies.has(fly) and not _is_raining and _should_show_fireflies():
			_firefly_wander(fly)
	)


func _butterfly_offscreen_pos() -> Vector2:
	return _offscreen_content_pos(randi() % 3)


func _butterfly_wander_pos() -> Vector2:
	var grid_w := maxf(float(_cols) * TILE_SIZE, 64.0)
	var fallback := Vector2(20.0, -60.0)
	for attempt in range(12):
		var candidate := Vector2(
			randf_range(20.0, grid_w - 20.0),
			randf_range(-60.0, ROWS * TILE_SIZE - 60.0)
		)
		if attempt == 0:
			fallback = candidate
		if _butterfly_can_rest_at(candidate):
			return candidate
	return fallback


func _cell_at_content_pos(pos: Vector2) -> FarmCell:
	var col := int(floor(pos.x / TILE_SIZE))
	var row := int(floor(pos.y / TILE_SIZE))
	if col < 0 or col >= _cols or row < 0 or row >= ROWS:
		return null
	for cell in _cells:
		var farm_cell := cell as FarmCell
		if farm_cell.grid_col == col and farm_cell.grid_row == row:
			return farm_cell
	return null


func _slot_at_content_pos(pos: Vector2) -> int:
	var local_x := fposmod(pos.x, TILE_SIZE)
	var local_y := fposmod(pos.y, TILE_SIZE)
	var col := 0 if local_x < TILE_SIZE * 0.5 else 1
	var row := 0 if local_y < TILE_SIZE * 0.5 else 1
	return row * 2 + col


func _butterfly_can_rest_at(pos: Vector2) -> bool:
	var cell := _cell_at_content_pos(pos)
	if cell == null or not cell.is_water_plot:
		return true
	return _butterfly_can_land_on_slot(cell, _slot_at_content_pos(pos))


func _butterfly_can_land_on_slot(cell: FarmCell, slot: int) -> bool:
	if cell.slot_states[slot] != FarmCell.SlotState.CROP:
		return false
	if not cell.is_water_plot:
		return true
	return CropData.is_water_crop(cell.slot_crop_ids[slot]) \
		and cell.slot_growth_stages[slot] == CropData.STAGE_MATURE


func _butterfly_slot_is_taken(cell: FarmCell, slot: int) -> bool:
	for b in _butterflies:
		if b.get("perched_cell") == cell and int(b.get("perched_slot", -1)) == slot:
			return true
	return false


func _butterfly_wander(bfly: Dictionary) -> void:
	if not is_instance_valid(bfly["node"]):
		return
	bfly["state"] = "flying"
	bfly["perched_cell"] = null
	bfly["perched_slot"] = -1

	# 25% chance to try landing on a safe crop slot. Water is only safe if
	# there is an actual mature lotus blossom there.
	if randf() < 0.25:
		var eligible: Array = []
		for cell in _cells:
			for slot in range(FarmCell.SLOT_COUNT):
				if _butterfly_can_land_on_slot(cell, slot) and not _butterfly_slot_is_taken(cell, slot):
					eligible.append({"cell": cell, "slot": slot})
		if not eligible.is_empty():
			var pick: Dictionary = eligible[randi() % eligible.size()]
			_butterfly_perch(bfly, pick["cell"], int(pick["slot"]))
			return

	var node_pos: Vector2 = bfly["node"].position

	# 15% chance to fly off a screen edge and re-enter from another
	if randf() < 0.15:
		var exit_dir := randi() % 3   # 0=left, 1=right, 2=up
		var exit_pos := _offscreen_content_pos(exit_dir)
		var exit_dur := clampf(node_pos.distance_to(exit_pos) / 110.0, 1.2, 4.0)
		var exit_tw := create_tween()
		bfly["tween"] = exit_tw
		exit_tw.tween_property(bfly["node"], "position", exit_pos, exit_dur).set_trans(Tween.TRANS_SINE)
		exit_tw.tween_callback(func():
			if not _butterflies.has(bfly) or not is_instance_valid(bfly["node"]) or bfly["state"] != "flying":
				return
			# re-enter from a random opposite edge
			var entry: Vector2
			match exit_dir:
				0: entry = _offscreen_content_pos(1)
				1: entry = _offscreen_content_pos(0)
				_: entry = _offscreen_content_pos(3)
			bfly["node"].position = entry
			_butterfly_wander(bfly)
		)
		return

	# Normal lazy wander — slow arc through a midpoint, pause at destination
	var target := _butterfly_wander_pos()
	var mid: Vector2 = (node_pos + target) * 0.5 + Vector2(randf_range(-60.0, 60.0), randf_range(-50.0, 50.0))
	var dur := clampf(node_pos.distance_to(target) / 110.0, 2.0, 5.5)
	var pause := randf_range(1.5, 4.0)   # linger at destination before next move

	var tw := create_tween()
	bfly["tween"] = tw
	tw.tween_property(bfly["node"], "position", mid,    dur * 0.5).set_trans(Tween.TRANS_SINE)
	tw.tween_property(bfly["node"], "position", target, dur * 0.5).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func():
		if _butterflies.has(bfly) and is_instance_valid(bfly["node"]) and _butterfly_can_rest_at(target):
			(bfly["node"] as AnimatedSprite2D).stop()
	)
	tw.tween_interval(pause)
	tw.tween_callback(func():
		if _butterflies.has(bfly) and is_instance_valid(bfly["node"]) and bfly["state"] == "flying":
			(bfly["node"] as AnimatedSprite2D).play("default", randf_range(0.8, 1.3))
			_butterfly_wander(bfly)
	)


func _butterfly_perch(bfly: Dictionary, cell: FarmCell, slot: int) -> void:
	bfly["state"] = "perching"
	bfly["perched_cell"] = cell
	bfly["perched_slot"] = slot
	var slot_col := slot % 2
	var slot_row := slot >> 1
	var dest := Vector2(
		cell.grid_col * TILE_SIZE + slot_col * 64.0 + 32.0,
		cell.grid_row * TILE_SIZE + slot_row * 64.0 + 32.0
	) + Vector2(randf_range(-8.0, 8.0), -18.0)
	var bfly_pos: Vector2 = bfly["node"].position
	var dist: float = bfly_pos.distance_to(dest)
	var dur   := clampf(dist / 60.0, 1.5, 5.0)

	var tw := create_tween()
	bfly["tween"] = tw
	tw.tween_property(bfly["node"], "position", dest, dur).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func():
		if not _butterflies.has(bfly) or not is_instance_valid(bfly["node"]) or bfly["state"] != "perching":
			return
		if not _butterfly_can_land_on_slot(cell, slot):
			_butterfly_wander(bfly)
			return
		bfly["state"] = "perched"
		(bfly["node"] as AnimatedSprite2D).stop()
		get_tree().create_timer(randf_range(4.0, 12.0)).timeout.connect(func():
			if _butterflies.has(bfly) and bfly["state"] == "perched" and is_instance_valid(bfly["node"]):
				(bfly["node"] as AnimatedSprite2D).play("default", randf_range(0.8, 1.3))
				_butterfly_wander(bfly)
		)
	)


func _scatter_butterfly_from(cell: FarmCell) -> void:
	for bfly in _butterflies:
		if bfly["perched_cell"] == cell:
			_butterfly_flee_one(bfly)
			return


func _flee_butterflies() -> void:
	for bfly in _butterflies.duplicate():
		_butterfly_flee_one(bfly)


func _butterfly_flee_one(bfly: Dictionary) -> void:
	if not is_instance_valid(bfly["node"]):
		_butterflies.erase(bfly)
		return
	bfly["state"] = "fleeing"
	bfly["perched_cell"] = null
	bfly["perched_slot"] = -1
	if bfly.get("tween") and is_instance_valid(bfly["tween"]):
		bfly["tween"].kill()
	(bfly["node"] as AnimatedSprite2D).play("default", randf_range(0.8, 1.3))
	var flee_x := randf_range(0.0, float(_cols) * TILE_SIZE)
	var flee_y := -TILE_SIZE * 2.5
	var tw := create_tween()
	bfly["tween"] = tw
	tw.tween_property(bfly["node"], "position", Vector2(flee_x, flee_y), 4) \
		.set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func():
		if is_instance_valid(bfly["node"]):
			bfly["node"].queue_free()
		_butterflies.erase(bfly)
	)


# ── app background save ───────────────────────────────────────────────────
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_game_active = false
		back_to_menu.emit()
	elif what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		SaveManager.save_game(self)
