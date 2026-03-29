#FarmCell.gd (zen_farm)
# class_name FarmCell — one grid tile. Instantiated purely in code.
# Holds state data; call refresh_visual() after any state change.
class_name FarmCell
extends Control

const TILE_SIZE := 112

const _CROP_NAMES   := ["Carrot", "Lettuce", "Potato", "Tomato", "Pumpkin"]
const _STAGE_MATURE := 3

enum TileState { SOIL, CROP, WILTED, WEED, LOCKED }

# ── state ──────────────────────────────────────────────────────────────────
var state: TileState = TileState.SOIL

# CROP / WILTED
var crop_id: int      = -1
var growth_stage: int = 0    # 0=seed 1=sprout 2=growing(2-tall) 3=mature(2-tall)
var time_in_stage: float = 0.0
var watered: bool    = false
var wilt_timer: float = 0.0

# LOCKED
var unlock_cost: int = 0

# Grid coordinates — set by Game when the cell is created; used for save/load.
var grid_row: int = 0
var grid_col: int = 0

# ── atlas coordinates ─────────────────────────────────────────────────────
# Use tile-grid coords (col, row) as shown in the Godot tileset editor.
# Pixel position = col * _TS,  row * _TS.

const _TS := 112  # px per tile in the source PNG (16×16 art scaled 4×)

func _t(col: int, row: int) -> Rect2:
	return Rect2(col * _TS, row * _TS, _TS, _TS)

func _t2(col: int, row: int) -> Rect2:  # 2-tile-tall region
	return Rect2(col * _TS, row * _TS, _TS, _TS * 2)

# tileset.png — set col/row to match the Godot tileset editor coords
const _TILE_SOIL_COL  := 0;  const _TILE_SOIL_ROW  := 2   # tilled dirt
const _TILE_GRASS_COL := 16; const _TILE_GRASS_ROW := 5   # plain green (locked)
const _TILE_WEED_COL  := 6;  const _TILE_WEED_ROW  := 5   # mushroom (weed)

# objects.png — col = crop_id (0-4), row = stage start row
# Stages 0-1: 1 tile tall.  Stages 2-3: 2 tiles tall (top row given).
const _OBJ_SEED_ROW    := 2   # stage 0 — seed on ground
const _OBJ_SPROUT_ROW  := 3   # stage 1 — tiny sprout
const _OBJ_GROWING_ROW := 4   # stage 2 — immature plant (rows 4-5)
const _OBJ_MATURE_ROW  := 6   # stage 3 — mature plant   (rows 6-7)

# ── internal nodes ─────────────────────────────────────────────────────────
var _tile_spr:  TextureRect   # base ground sprite (fills cell exactly)
var _plant_spr: TextureRect   # plant overlay; 2-tall stages overflow upward
var _label: Label
var _sub:   Label

static var _font:    FontFile
static var _tileset: Texture2D
static var _objects: Texture2D


func _ready() -> void:
	if not _font:
		_font = load("res://assets/font/vetka.ttf")
	if not _tileset:
		_tileset = load("res://games/zen_farm/assets/tileset.png")
	if not _objects:
		_objects = load("res://games/zen_farm/assets/objects.png")

	custom_minimum_size = Vector2(TILE_SIZE, TILE_SIZE)
	size               = Vector2(TILE_SIZE, TILE_SIZE)
	mouse_filter       = MOUSE_FILTER_IGNORE

	# Ground tile — always fills the cell exactly.
	_tile_spr = _make_tex_rect()
	_tile_spr.set_anchors_preset(PRESET_FULL_RECT)
	add_child(_tile_spr)

	# Plant sprite — positioned manually so 2-tall stages can overflow upward.
	_plant_spr = _make_tex_rect()
	add_child(_plant_spr)

	_label = _make_label(8, 4, TILE_SIZE - 4, 62)
	_label.add_theme_font_size_override("font_size", 34)
	add_child(_label)

	_sub = _make_label(6, 4, TILE_SIZE - 4, TILE_SIZE - 4)
	_sub.offset_top = 50
	_sub.add_theme_font_size_override("font_size", 30)
	_sub.add_theme_constant_override("line_spacing", -18)
	add_child(_sub)

	refresh_visual()


func _make_tex_rect() -> TextureRect:
	var rect := TextureRect.new()
	rect.stretch_mode   = TextureRect.STRETCH_SCALE
	rect.texture_filter = TEXTURE_FILTER_NEAREST
	rect.mouse_filter   = MOUSE_FILTER_IGNORE
	return rect


func _make_label(top: float, left: float, right: float, bot: float) -> Label:
	var lbl := Label.new()
	lbl.offset_left   = left
	lbl.offset_top    = top
	lbl.offset_right  = right
	lbl.offset_bottom = bot
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_override("font", _font)
	lbl.add_theme_color_override("font_color",         Color.WHITE)
	lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	lbl.add_theme_constant_override("outline_size", 2)
	lbl.mouse_filter = MOUSE_FILTER_IGNORE
	return lbl


func _atlas(source: Texture2D, region: Rect2) -> AtlasTexture:
	var a := AtlasTexture.new()
	a.atlas  = source
	a.region = region
	return a


func _set_plant(obj_row: int, two_tall: bool) -> void:
	var col_x: int = crop_id * _TS
	var row_y: int = obj_row * _TS
	if two_tall:
		_plant_spr.texture = _atlas(_objects, Rect2(col_x, row_y, _TS, _TS * 2))
		_plant_spr.offset_left   = 0
		_plant_spr.offset_right  = TILE_SIZE
		_plant_spr.offset_top    = -TILE_SIZE
		_plant_spr.offset_bottom = TILE_SIZE
	else:
		_plant_spr.texture = _atlas(_objects, Rect2(col_x, row_y, _TS, _TS))
		_plant_spr.offset_left   = 0
		_plant_spr.offset_right  = TILE_SIZE
		_plant_spr.offset_top    = 0
		_plant_spr.offset_bottom = TILE_SIZE
	_plant_spr.visible = true


func refresh_visual() -> void:
	if not _tile_spr:
		return

	_plant_spr.visible  = false
	_tile_spr.modulate  = Color.WHITE
	_plant_spr.modulate = Color.WHITE
	_label.text = ""
	_sub.text   = ""

	match state:
		TileState.LOCKED:
			_tile_spr.texture = _atlas(_tileset, _t(_TILE_GRASS_COL, _TILE_GRASS_ROW))
			_label.text = str(unlock_cost) + "c"

		TileState.SOIL:
			_tile_spr.texture = _atlas(_tileset, _t(_TILE_SOIL_COL, _TILE_SOIL_ROW))

		TileState.WEED:
			_tile_spr.texture  = _atlas(_tileset, _t(_TILE_SOIL_COL, _TILE_SOIL_ROW))
			_plant_spr.texture = _atlas(_tileset, _t(_TILE_WEED_COL, _TILE_WEED_ROW))
			_plant_spr.offset_left   = 0
			_plant_spr.offset_right  = TILE_SIZE
			_plant_spr.offset_top    = 0
			_plant_spr.offset_bottom = TILE_SIZE
			_plant_spr.visible = true
			_sub.text = "Weed!"

		TileState.CROP, TileState.WILTED:
			_refresh_crop_visual()


func _refresh_crop_visual() -> void:
	_tile_spr.texture = _atlas(_tileset, _t(_TILE_SOIL_COL, _TILE_SOIL_ROW))

	if crop_id < 0 or crop_id >= _CROP_NAMES.size():
		_label.text = "?"
		return

	match growth_stage:
		0: _set_plant(_OBJ_SEED_ROW,    false)
		1: _set_plant(_OBJ_SPROUT_ROW,  false)
		2: _set_plant(_OBJ_GROWING_ROW, true)
		_: _set_plant(_OBJ_MATURE_ROW,  true)

	if state == TileState.WILTED:
		_plant_spr.modulate = Color(0.55, 0.50, 0.42)
		_sub.text = "wilted!"
	elif growth_stage == _STAGE_MATURE:
		_sub.text = "READY!"
	elif not watered:
		_sub.text = "water!"
