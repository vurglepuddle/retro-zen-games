#FarmCell.gd (zen_farm)
# Pure data + status labels. All tile visuals are driven by TileMapLayers in Game.gd.
# call refresh_visual() after any state change; it updates labels and emits visual_changed.
class_name FarmCell
extends Control

const TILE_SIZE := 128   # 2 × 64 px tilemap tiles per game cell
const LOCK_SIGN_TEXTURE := "res://games/zen_farm/assets/sign.png"
const LOCK_SIGN_POSITION := Vector2(32.0, 18.0)
const LOCK_PRICE_TEXT_Y_OFFSET := 7.0 # Tweak this if the price needs to sit higher/lower on the sign.
const LOCK_PRICE_TEXT_HEIGHT := 34.0

enum TileState { SOIL, CROP, WILTED, WEED, LOCKED, GRASS, WATER }
enum SlotState { EMPTY, CROP, WILTED, WEED }

signal visual_changed   # Game.gd connects this to _refresh_cell_tilemap(cell)

# ── state ──────────────────────────────────────────────────────────────────
var state: TileState = TileState.SOIL
var is_water_plot: bool = false

# CROP / WILTED
var crop_id: int      = -1
var growth_stage: int = 0    # 0=seed 1=sprout 2=growing(2-tall) 3=mature(2-tall)
var time_in_stage: float = 0.0
var watered: bool    = false
var wilt_timer: float = 0.0

const SLOT_COUNT := 4
var slot_states: Array[int] = []
var slot_crop_ids: Array[int] = []
var slot_growth_stages: Array[int] = []
var slot_time_in_stage: Array[float] = []
var slot_watered: Array[bool] = []
var slot_wilt_timers: Array[float] = []
var slot_weed_atlas_coords: Array[Vector2i] = []

# LOCKED
var unlock_cost: int = 0

# Grid coordinates — set by Game when the cell is created; used for save/load.
var grid_row: int = 0
var grid_col: int = 0

# ── internal nodes ─────────────────────────────────────────────────────────
var _label: Label   # price or READY hint
var _sub:   Label   # water! / wilted! / Weed!
var _lock_sign: TextureRect

static var _font: FontFile


func _init() -> void:
	reset_slots()


func reset_slots() -> void:
	slot_states = []
	slot_crop_ids = []
	slot_growth_stages = []
	slot_time_in_stage = []
	slot_watered = []
	slot_wilt_timers = []
	slot_weed_atlas_coords = []
	for i in range(SLOT_COUNT):
		slot_states.append(SlotState.EMPTY)
		slot_crop_ids.append(-1)
		slot_growth_stages.append(0)
		slot_time_in_stage.append(0.0)
		slot_watered.append(false)
		slot_wilt_timers.append(0.0)
		slot_weed_atlas_coords.append(Vector2i(-1, -1))


func clear_slot(slot: int) -> void:
	if slot < 0 or slot >= SLOT_COUNT:
		return
	slot_states[slot] = SlotState.EMPTY
	slot_crop_ids[slot] = -1
	slot_growth_stages[slot] = 0
	slot_time_in_stage[slot] = 0.0
	slot_watered[slot] = false
	slot_wilt_timers[slot] = 0.0
	slot_weed_atlas_coords[slot] = Vector2i(-1, -1)
	refresh_summary_state()


func refresh_summary_state() -> void:
	if state == TileState.LOCKED:
		return
	var was_grass := state == TileState.GRASS
	var was_water := state == TileState.WATER or is_water_plot
	var has_crop := false
	var has_wilted := false
	var has_weed := false
	for slot in range(SLOT_COUNT):
		match slot_states[slot]:
			SlotState.WILTED:
				has_wilted = true
			SlotState.CROP:
				has_crop = true
			SlotState.WEED:
				has_weed = true
	if has_wilted:
		state = TileState.WILTED
	elif has_crop:
		state = TileState.CROP
	elif has_weed:
		state = TileState.WEED
	else:
		if was_water:
			state = TileState.WATER
		elif was_grass:
			state = TileState.GRASS
		else:
			state = TileState.SOIL


func has_active_crops() -> bool:
	for slot in range(SLOT_COUNT):
		if slot_states[slot] == SlotState.CROP or slot_states[slot] == SlotState.WILTED:
			return true
	return false


func has_ready_crop() -> bool:
	for slot in range(SLOT_COUNT):
		if slot_states[slot] == SlotState.CROP and slot_growth_stages[slot] == CropData.STAGE_MATURE:
			return true
	return false


func has_thirsty_crop() -> bool:
	for slot in range(SLOT_COUNT):
		if slot_states[slot] == SlotState.WILTED:
			return true
		if slot_states[slot] == SlotState.CROP \
				and slot_growth_stages[slot] < CropData.STAGE_MATURE \
				and not slot_watered[slot] \
				and not CropData.is_water_crop(slot_crop_ids[slot]):
			return true
	return false


func empty_slot_count() -> int:
	var count := 0
	for slot in range(SLOT_COUNT):
		if slot_states[slot] == SlotState.EMPTY:
			count += 1
	return count


func _ready() -> void:
	if not _font:
		_font = load("res://assets/font/vetka.ttf")

	custom_minimum_size = Vector2(TILE_SIZE, TILE_SIZE)
	size               = Vector2(TILE_SIZE, TILE_SIZE)
	mouse_filter       = MOUSE_FILTER_IGNORE

	_lock_sign = TextureRect.new()
	_lock_sign.texture = load(LOCK_SIGN_TEXTURE)
	_lock_sign.position = LOCK_SIGN_POSITION
	_lock_sign.size = Vector2(64.0, 64.0)
	_lock_sign.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_lock_sign.stretch_mode = TextureRect.STRETCH_KEEP
	_lock_sign.mouse_filter = MOUSE_FILTER_IGNORE
	_lock_sign.z_index = 5
	add_child(_lock_sign)

	_label = _make_label(
		LOCK_SIGN_POSITION.y + LOCK_PRICE_TEXT_Y_OFFSET,
		LOCK_SIGN_POSITION.x,
		LOCK_SIGN_POSITION.x + 64.0,
		LOCK_SIGN_POSITION.y + LOCK_PRICE_TEXT_Y_OFFSET + LOCK_PRICE_TEXT_HEIGHT
	)
	_label.add_theme_font_size_override("font_size", 36)
	_label.z_index = 6
	add_child(_label)

	_sub = _make_label(6, 4, TILE_SIZE - 4, TILE_SIZE - 4)
	_sub.offset_top = 56
	_sub.add_theme_font_size_override("font_size", 32)
	_sub.add_theme_constant_override("line_spacing", -16)
	_sub.z_index = 10
	add_child(_sub)

	refresh_visual()


func _make_label(top: float, left: float, right: float, bot: float) -> Label:
	var lbl := Label.new()
	lbl.offset_left   = left
	lbl.offset_top    = top
	lbl.offset_right  = right
	lbl.offset_bottom = bot
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_override("font", _font)
	lbl.add_theme_color_override("font_color",         Color("#ececd5"))
	lbl.add_theme_color_override("font_outline_color", Color("#8a3524"))
	lbl.add_theme_constant_override("outline_size", 6)
	lbl.mouse_filter = MOUSE_FILTER_IGNORE
	return lbl


func refresh_visual() -> void:
	if not _label:
		return

	refresh_summary_state()
	_label.text = ""
	_sub.text   = ""
	_lock_sign.visible = state == TileState.LOCKED
	_label.visible = state == TileState.LOCKED

	match state:
		TileState.LOCKED:
			_label.text = str(unlock_cost) + "c"
		TileState.WEED:
			#_sub.text = "Weed!"
			_sub.text = " "
		TileState.CROP, TileState.WILTED:
			if state == TileState.WILTED:
				_sub.text = " "
				#_sub.text = "wilted!"
			elif has_ready_crop():
				_sub.text = " "
				#_sub.text = "ready!"
			elif has_thirsty_crop():
				#_sub.text = "water!"
				_sub.text = " "

	visual_changed.emit()
