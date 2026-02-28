#Vial.gd (alchemical_sort)
# Represents one alchemical bottle.  Instantiated purely in code — no .tscn.
class_name Vial
extends Control

signal tapped(vial: Vial)

# ---- configuration ----------------------------------------------------------
const MAX_LAYERS      := 5   # color layers each vial can hold
const SHEET_COLS      := 7   # columns in liquid_colors_all.png
const SHEET_ROWS      := 2   # rows    in liquid_colors_all.png
const BOTTLE_PAD_TOP  := 14  # pixels bottle art covers above the liquid
var VIAL_W: int       = 72   # derived from bottle.png in _build_visuals()
var VIAL_H: int       = 176  # derived from bottle.png in _build_visuals()

# ---- state ------------------------------------------------------------------
# _layers[0] = bottom-most color id, _layers[top_index()] = topmost.
# Color id 0 = empty slot.  IDs 1..N correspond to the game's color palette.
var _layers: Array[int] = []
var _palette: Array[Color] = []

# ---- fog-of-war state -------------------------------------------------------
# When _fog_mode is true, only layers at index >= _fog_reveal_from are visible;
# everything below is drawn in a neutral gray ("unknown").
# _fog_reveal_from only ever decreases — once a layer is revealed it stays so.
var _fog_mode: bool = false
var _fog_reveal_from: int = 0

# ---- visuals (built in setup) -----------------------------------------------
var _layer_rects:    Array[TextureRect]   = []
var _atlas_textures: Array[AtlasTexture]  = []   # one entry per color id (0-based)
var _outline: Panel = null


func _init() -> void:
	custom_minimum_size = Vector2(VIAL_W, VIAL_H)
	size = Vector2(VIAL_W, VIAL_H)
	mouse_filter = Control.MOUSE_FILTER_STOP
	pivot_offset = Vector2(VIAL_W * 0.5, VIAL_H * 0.5)


func _ready() -> void:
	# Re-apply size after Godot's layout pass, which can overwrite the value
	# set in _init() for Control children added via code.  This ensures the
	# full bottle rect is the tap target, not just the rendered outline.
	# Also future-proofs against transparent bottle sprites: the outer Control
	# owns all input so transparent pixels never leak clicks to the background.
	size = Vector2(VIAL_W, VIAL_H)
	mouse_filter = Control.MOUSE_FILTER_STOP


# Call after adding to scene tree; configures layers and builds visuals.
func setup(initial_layers: Array[int], color_palette: Array[Color]) -> void:
	_palette = color_palette.duplicate()
	_layers.clear()
	for v in initial_layers:
		_layers.append(v)
	while _layers.size() < MAX_LAYERS:
		_layers.append(0)
	_build_visuals()


# ---- public data API --------------------------------------------------------

func is_empty() -> bool:
	return top_index() < 0


func is_full() -> bool:
	return _layers[MAX_LAYERS - 1] != 0


func is_pure() -> bool:
	# True if all non-zero slots share the same color id (empty counts as pure).
	var first := 0
	for v in _layers:
		if v != 0:
			if first == 0:
				first = v
			elif v != first:
				return false
	return true


# Index of the highest occupied slot, or -1 if completely empty.
func top_index() -> int:
	for i in range(MAX_LAYERS - 1, -1, -1):
		if _layers[i] != 0:
			return i
	return -1


func top_color() -> int:
	var i := top_index()
	return _layers[i] if i >= 0 else 0


# How many consecutive same-color layers sit at the very top.
func top_run_count() -> int:
	var tc := top_color()
	if tc == 0:
		return 0
	var count := 0
	for i in range(MAX_LAYERS - 1, -1, -1):
		if _layers[i] == tc:
			count += 1
		elif _layers[i] == 0:
			continue   # skip empty slots above the run
		else:
			break
	return count


func free_slots() -> int:
	var count := 0
	for v in _layers:
		if v == 0:
			count += 1
	return count


# ---- fog of war -------------------------------------------------------------

# Call after setup() to activate fog mode.  Only the current top color-run is
# visible; layers below it are rendered as an opaque gray until uncovered.
func enable_fog() -> void:
	_fog_mode = true
	_fog_reveal_from = _top_run_start()
	_refresh_visuals()


# Call from Game.gd after animate_pour_out() completes so the newly exposed
# layer becomes visible.  _fog_reveal_from only ever decreases.
func reveal_top() -> void:
	if not _fog_mode:
		return
	_fog_reveal_from = mini(_fog_reveal_from, _top_run_start())
	_refresh_visuals()


# Index of the first layer in the current top color-run (the lowest layer that
# shares the same color as the topmost occupied slot, with no gap in between).
func _top_run_start() -> int:
	var ti := top_index()
	if ti < 0:
		return 0          # vial is empty — everything "revealed"
	var tc := _layers[ti]
	var i := ti
	while i > 0 and _layers[i - 1] == tc:
		i -= 1
	return i


# ---- snapshot / undo --------------------------------------------------------

func snapshot() -> Array[int]:
	var snap: Array[int] = []
	for v in _layers:
		snap.append(v)
	return snap


func get_layers() -> Array[int]:
	return _layers.duplicate()


func restore(snap: Array[int]) -> void:
	for i in range(MAX_LAYERS):
		_layers[i] = snap[i]
	_refresh_visuals()


# ---- animated pour ----------------------------------------------------------

func animate_pour_out(amount: int) -> void:
	# Identify the top `amount` occupied layer indices.
	var indices: Array[int] = []
	for i in range(MAX_LAYERS - 1, -1, -1):
		if _layers[i] != 0 and indices.size() < amount:
			indices.append(i)

	var tw := create_tween()
	tw.set_parallel(true)
	for idx in indices:
		tw.tween_property(_layer_rects[idx], "modulate:a", 0.0, 0.12) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tw.finished

	for idx in indices:
		_layers[idx] = 0
		_layer_rects[idx].modulate.a = 0.0


func animate_pour_in(color_id: int, amount: int) -> void:
	# Identify the lowest `amount` empty slots.
	var indices: Array[int] = []
	for i in range(MAX_LAYERS):
		if _layers[i] == 0 and indices.size() < amount:
			indices.append(i)

	for idx in indices:
		_layers[idx] = color_id
		if color_id >= 1 and color_id <= _atlas_textures.size():
			_layer_rects[idx].texture = _atlas_textures[color_id - 1]
		_layer_rects[idx].modulate = Color.WHITE
		_layer_rects[idx].modulate.a = 0.0

	var tw := create_tween()
	tw.set_parallel(true)
	for idx in indices:
		tw.tween_property(_layer_rects[idx], "modulate:a", 1.0, 0.14) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await tw.finished


# Quick scale-bounce when a vial becomes pure and full.
func celebrate() -> void:
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2(1.14, 1.14), 0.08) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", Vector2.ONE, 0.12) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# ---- selection --------------------------------------------------------------

func show_selected(v: bool) -> void:
	if _outline:
		_outline.visible = v


# ---- visuals (placeholder — swap with sprite art) ---------------------------

func _build_visuals() -> void:
	var sheet       := load("res://games/alchemical_sort/assets/liquid_colors_all.png") as Texture2D
	var bottle_tex  := load("res://games/alchemical_sort/assets/bottle.png") as Texture2D
	var inside_tex  := load("res://games/alchemical_sort/assets/bottle_inside.png") as Texture2D

	# Vial size comes from the bottle artwork.
	VIAL_W = bottle_tex.get_width()    # 72
	VIAL_H = bottle_tex.get_height()   # 176
	custom_minimum_size = Vector2(VIAL_W, VIAL_H)
	size               = Vector2(VIAL_W, VIAL_H)
	pivot_offset       = Vector2(VIAL_W * 0.5, VIAL_H * 0.5)

	# Liquid cell size from the sprite sheet.
	var cell_w: int = sheet.get_width()  / SHEET_COLS   # 64
	var cell_h: int = sheet.get_height() / SHEET_ROWS   # 32
	# Horizontal offset to center the 64-wide liquid inside the 72-wide bottle.
	var pad_x: int  = (VIAL_W - cell_w) / 2             # 4

	# Pre-build one AtlasTexture per color slot (row-major: left→right, top→bottom).
	_atlas_textures.clear()
	for r in range(SHEET_ROWS):
		for c in range(SHEET_COLS):
			var at := AtlasTexture.new()
			at.atlas  = sheet
			at.region = Rect2(c * cell_w, r * cell_h, cell_w, cell_h)
			_atlas_textures.append(at)

	# --- draw order: background → inside glass → liquid layers → bottle overlay → outline ---

	# 1. Inner glass texture at 70% opacity (behind the liquid).
	var inside := TextureRect.new()
	inside.texture      = inside_tex
	inside.stretch_mode = TextureRect.STRETCH_KEEP
	inside.size         = Vector2(VIAL_W, VIAL_H)
	inside.modulate.a   = 0.7
	inside.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(inside)

	# 3. Liquid layer rects — bottom (index 0) to top (index MAX_LAYERS-1).
	#    Offset by (pad_x, BOTTLE_PAD_TOP) so they sit inside the bottle's glass window.
	#    Integer positions → perfectly flush layers, no gaps.
	_layer_rects.clear()
	for i in range(MAX_LAYERS):
		var rect := TextureRect.new()
		rect.stretch_mode = TextureRect.STRETCH_KEEP
		rect.size         = Vector2(cell_w, cell_h)
		rect.position     = Vector2(pad_x, BOTTLE_PAD_TOP + (MAX_LAYERS - 1 - i) * cell_h)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_set_layer_color(rect, _layers[i], _fog_mode and i < _fog_reveal_from)
		add_child(rect)
		_layer_rects.append(rect)

	# 4. Bottle overlay — goes on top of the liquid so the glass frame is always visible.
	var overlay := TextureRect.new()
	overlay.texture      = bottle_tex
	overlay.stretch_mode = TextureRect.STRETCH_KEEP
	overlay.size         = Vector2(VIAL_W, VIAL_H)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)

	# 5. Selection outline — topmost so it's never obscured.
	var out_style := StyleBoxFlat.new()
	out_style.bg_color = Color(0, 0, 0, 0)
	out_style.border_color = Color(1.0, 0.85, 0.20, 1.0)
	out_style.set_border_width_all(2)
	out_style.set_corner_radius_all(4)
	_outline = Panel.new()
	_outline.add_theme_stylebox_override("panel", out_style)
	_outline.size = Vector2(VIAL_W, VIAL_H)
	_outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_outline.visible = false
	add_child(_outline)


# Assigns the correct atlas region and modulate for a layer.
# fog=true → dark-teal tint so the actual color isn't revealed.
func _set_layer_color(rect: TextureRect, cid: int, fog: bool) -> void:
	if cid > 0 and cid <= _atlas_textures.size():
		rect.texture  = _atlas_textures[cid - 1]
		rect.modulate = Color(0, 0, 0, 1) if fog else Color.WHITE
	else:
		rect.texture   = null
		rect.modulate.a = 0.0


func _refresh_visuals() -> void:
	for i in range(MAX_LAYERS):
		var rect: TextureRect = _layer_rects[i]
		_set_layer_color(rect, _layers[i], _fog_mode and i < _fog_reveal_from)
		if _layers[i] != 0:
			rect.modulate.a = 1.0


# ---- input ------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			tapped.emit(self)
