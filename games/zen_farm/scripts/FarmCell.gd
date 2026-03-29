#FarmCell.gd (zen_farm)
# Pure data + status labels. All tile visuals are driven by TileMapLayers in Game.gd.
# call refresh_visual() after any state change; it updates labels and emits visual_changed.
class_name FarmCell
extends Control

const TILE_SIZE := 128   # 2 × 64 px tilemap tiles per game cell

enum TileState { SOIL, CROP, WILTED, WEED, LOCKED }

signal visual_changed   # Game.gd connects this to _refresh_cell_tilemap(cell)

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

# ── internal nodes ─────────────────────────────────────────────────────────
var _label: Label   # price or READY hint
var _sub:   Label   # water! / wilted! / Weed!

static var _font: FontFile


func _ready() -> void:
	if not _font:
		_font = load("res://assets/font/vetka.ttf")

	custom_minimum_size = Vector2(TILE_SIZE, TILE_SIZE)
	size               = Vector2(TILE_SIZE, TILE_SIZE)
	mouse_filter       = MOUSE_FILTER_IGNORE

	_label = _make_label(8, 4, TILE_SIZE - 4, 68)
	_label.add_theme_font_size_override("font_size", 36)
	_label.z_index = 10
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
	lbl.add_theme_color_override("font_color",         Color.WHITE)
	lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	lbl.add_theme_constant_override("outline_size", 5)
	lbl.mouse_filter = MOUSE_FILTER_IGNORE
	return lbl


func refresh_visual() -> void:
	if not _label:
		return

	_label.text = ""
	_sub.text   = ""

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
			elif growth_stage == 3:
				_sub.text = " "
				#_sub.text = "ready!"
			elif not watered:
				#_sub.text = "water!"
				_sub.text = " "

	visual_changed.emit()
