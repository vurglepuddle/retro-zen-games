#FarmCell.gd (zen_farm)
# class_name FarmCell — one grid tile. Instantiated purely in code.
# Holds state data; call refresh_visual() after any state change.
class_name FarmCell
extends Control

const TILE_SIZE := 120

# Local display tables — mirrors CropData constants to avoid cross-script static calls.
const _CROP_NAMES  := ["Carrot", "Lettuce", "Potato", "Tomato", "Pumpkin"]
const _CROP_COLORS := [
	Color(0.88, 0.48, 0.10),  # Carrot
	Color(0.28, 0.72, 0.28),  # Lettuce
	Color(0.62, 0.50, 0.28),  # Potato
	Color(0.90, 0.22, 0.12),  # Tomato
	Color(0.92, 0.50, 0.08),  # Pumpkin
]
const _STAGE_LABELS := ["seed", "sprout", "growing", "READY"]
const _STAGE_MATURE := 3

enum TileState { SOIL, CROP, WILTED, WEED, LOCKED }

# ── state ──────────────────────────────────────────────────────────────────
var state: TileState = TileState.SOIL

# CROP / WILTED
var crop_id: int      = -1
var growth_stage: int = 0    # 0=seed 1=sprout 2=growing 3=mature
var time_in_stage: float = 0.0
var watered: bool    = false
var wilt_timer: float = 0.0  # seconds without water after stage expired

# LOCKED
var unlock_cost: int = 0

signal tapped(cell)

# ── internal nodes ─────────────────────────────────────────────────────────
var _bg:     ColorRect
var _label:  Label    # top line (tile type / crop name)
var _sub:    Label    # bottom line (stage / status)
var _border: ColorRect  # 1 px inner border drawn by modulate hack

static var _font: FontFile  # shared across all cells

func _ready() -> void:
	if not _font:
		_font = load("res://assets/font/vetka.ttf")

	custom_minimum_size = Vector2(TILE_SIZE, TILE_SIZE)
	size               = Vector2(TILE_SIZE, TILE_SIZE)
	mouse_filter       = MOUSE_FILTER_STOP

	# background
	_bg = ColorRect.new()
	_bg.set_anchors_preset(PRESET_FULL_RECT)
	_bg.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_bg)

	# 1 px dark inner border
	_border = ColorRect.new()
	_border.color = Color(0, 0, 0, 0.45)
	_border.offset_left   = 0
	_border.offset_top    = 0
	_border.offset_right  = TILE_SIZE
	_border.offset_bottom = 1
	_border.mouse_filter  = MOUSE_FILTER_IGNORE
	add_child(_border)
	var _border_r := ColorRect.new()
	_border_r.color = Color(0, 0, 0, 0.45)
	_border_r.offset_left   = TILE_SIZE - 1
	_border_r.offset_top    = 0
	_border_r.offset_right  = TILE_SIZE
	_border_r.offset_bottom = TILE_SIZE
	_border_r.mouse_filter  = MOUSE_FILTER_IGNORE
	add_child(_border_r)

	# top label — crop name / tile type
	_label = _make_label(8, 4, TILE_SIZE - 4, 62)
	_label.add_theme_font_size_override("font_size", 42)
	add_child(_label)

	# bottom label — stage / status
	_sub = _make_label(6, 4, TILE_SIZE - 4, TILE_SIZE - 4)
	_sub.offset_top = 50
	_sub.add_theme_font_size_override("font_size", 38)
	_sub.add_theme_constant_override("line_spacing", -18)
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
	lbl.add_theme_constant_override("outline_size", 2)
	lbl.mouse_filter = MOUSE_FILTER_IGNORE
	return lbl


func refresh_visual() -> void:
	if not _bg:
		return
	match state:
		TileState.SOIL:
			_bg.color = Color(0.28, 0.19, 0.10)
			_label.text = "soil"
			_sub.text   = ""
		TileState.WEED:
			_bg.color = Color(0.22, 0.32, 0.14)
			_label.text = "Weed"
			_sub.text   = "tap!"
		TileState.LOCKED:
			_bg.color = Color(0.18, 0.18, 0.20)
			_label.text = "Locked"
			_sub.text   = str(unlock_cost) + "c"
		TileState.CROP, TileState.WILTED:
			_refresh_crop_visual()


func _refresh_crop_visual() -> void:
	var base_col: Color  = _CROP_COLORS[crop_id] if crop_id >= 0 and crop_id < _CROP_COLORS.size() else Color.WHITE
	var name_str: String = _CROP_NAMES[crop_id]  if crop_id >= 0 and crop_id < _CROP_NAMES.size()  else "?"

	if state == TileState.WILTED:
		_bg.color   = base_col.lerp(Color(0.35, 0.32, 0.28), 0.72)
		_label.text = name_str
		_sub.text   = "wilted\nwater!"
		return

	var brightness: float = 0.55 + 0.15 * growth_stage
	_bg.color   = base_col * brightness
	_label.text = name_str

	if growth_stage == _STAGE_MATURE:
		_sub.text = "READY\ntap!"
	else:
		var stage_str: String = _STAGE_LABELS[growth_stage] if growth_stage < _STAGE_LABELS.size() else "?"
		var water_str: String = "" if watered else "\nwater!"
		_sub.text = stage_str + water_str


# ── input ──────────────────────────────────────────────────────────────────
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			tapped.emit(self)
			accept_event()
	elif event is InputEventScreenTouch:
		if event.pressed:
			tapped.emit(self)
			accept_event()
