# Cell.gd — one shelf on the potion_3 board.
# Holds 3 item slots side by side + a z-stack of layers below.
# Built entirely in code (no .tscn).

class_name PotionCell
extends Control

# --- Layout constants ---
const ITEM_ROTATION := 0.0   # set to -PI / 4.0 for 45° counter-clockwise
const SLOTS       := 3
const ITEM_SIZE   := 74 # 36
const PREVIEW_SIZE := 64 # 24
const SLOT_GAP    := -25 # 6
const SIDE_PAD    := 5 # 24
const TOP_PAD     := 16 # 16
const MID_GAP     := 2 # 6
const BOT_PAD     := 10 # 10

# Cell dimensions (fixed for grid layout — preview row always allocated).
#const CELL_W := SIDE_PAD * 2 + SLOTS * ITEM_SIZE + (SLOTS - 1) * SLOT_GAP   # 168
#const CELL_H := TOP_PAD + ITEM_SIZE + MID_GAP + PREVIEW_SIZE + BOT_PAD       # 102
const CELL_W := 168
const CELL_H := 130   # taller shelf; items stay at TOP_PAD, extra space below
# --- State ---
var _slots: Array[int] = [0, 0, 0]   # current visible items (0 = empty)
var _z_stack: Array     = []          # remaining layers below; each Array[int] of size 3
var _item_textures: Dictionary = {}   # shared ref from Game: item_id → Texture2D

# --- Visual nodes ---
var _slot_rects:      Array[TextureRect] = []
var _preview_rects:   Array[TextureRect] = []
var _slot_highlights: Array[Panel]       = []
var _bg: Panel = null


# ============================================================================
#  Public API
# ============================================================================

func setup(slots: Array, z_stack: Array, textures: Dictionary) -> void:
	_item_textures = textures
	# Strip all-zero layers — artifacts of sparse generation that would stall
	# the reveal logic by surfacing an invisible empty layer.
	_z_stack = []
	for layer in z_stack:
		var has_any := false
		for v in layer:
			if v != 0:
				has_any = true
				break
		if has_any:
			_z_stack.append(layer.duplicate())

	# Set top layer, then advance past any all-zero top layers immediately.
	_slots = [slots[0] as int, slots[1] as int, slots[2] as int]
	while not has_items() and not _z_stack.is_empty():
		var next: Array = _z_stack.pop_front()
		_slots = [next[0] as int, next[1] as int, next[2] as int]

	_build_visuals()


func get_item(slot_idx: int) -> int:
	return _slots[slot_idx]


func set_item(slot_idx: int, item_id: int) -> void:
	_slots[slot_idx] = item_id
	_refresh_slot(slot_idx)


func remove_item(slot_idx: int) -> void:
	_slots[slot_idx] = 0
	_refresh_slot(slot_idx)


func has_empty_slot() -> int:
	## Returns index of first empty slot, or -1.
	for i in range(SLOTS):
		if _slots[i] == 0:
			return i
	return -1


func check_match() -> bool:
	return _slots[0] != 0 and _slots[0] == _slots[1] and _slots[1] == _slots[2]


func clear_match() -> void:
	## Animate all 3 items vanishing, then reveal next z-layer.
	var tw := create_tween()
	for i in range(SLOTS):
		var rect := _slot_rects[i]
		tw.parallel().tween_property(rect, "scale", Vector2.ZERO, 0.25) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(rect, "modulate:a", 0.0, 0.25)
	await tw.finished
	_slots = [0, 0, 0]
	reveal_next_layer()


func reveal_next_layer() -> void:
	if _z_stack.is_empty():
		_refresh_all()
		return
	var next_layer: Array = _z_stack.pop_front()
	_slots = [next_layer[0] as int, next_layer[1] as int, next_layer[2] as int]
	# Fade-in animation for new items.
	_refresh_all()
	for i in range(SLOTS):
		if _slots[i] != 0:
			var rect := _slot_rects[i]
			rect.modulate.a = 0.0
			rect.scale = Vector2(0.5, 0.5)
			var tw := create_tween()
			tw.parallel().tween_property(rect, "modulate:a", 1.0, 0.2)
			tw.parallel().tween_property(rect, "scale", Vector2.ONE, 0.2) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func is_fully_empty() -> bool:
	for s in _slots:
		if s != 0:
			return false
	return _z_stack.is_empty()


func has_items() -> bool:
	for s in _slots:
		if s != 0:
			return true
	return false


func show_slot_highlight(slot_idx: int, show: bool) -> void:
	if slot_idx >= 0 and slot_idx < SLOTS:
		_slot_highlights[slot_idx].visible = show


func hide_all_highlights() -> void:
	for h in _slot_highlights:
		h.visible = false


func get_slot_center(slot_idx: int) -> Vector2:
	## Local-space center of a slot (used for move animations).
	var rect := _slot_rects[slot_idx]
	return rect.position + Vector2(ITEM_SIZE * 0.5, ITEM_SIZE * 0.5)


func get_slots_array() -> Array[int]:
	return _slots.duplicate()


func get_z_stack_copy() -> Array:
	var copy: Array = []
	for layer in _z_stack:
		copy.append(layer.duplicate())
	return copy


func restore(snap: Dictionary) -> void:
	_slots = [snap.slots[0] as int, snap.slots[1] as int, snap.slots[2] as int]
	_z_stack = []
	for layer in snap.z_stack:
		_z_stack.append(layer.duplicate())
	_refresh_all()


func layers_remaining() -> int:
	return _z_stack.size()


func set_slot_visible(slot_idx: int, vis: bool) -> void:
	_slot_rects[slot_idx].visible = vis


# ============================================================================
#  Visuals
# ============================================================================

func _build_visuals() -> void:
	custom_minimum_size = Vector2(CELL_W, CELL_H)
	size = Vector2(CELL_W, CELL_H)

	# 1. Background panel — subtle dark shelf.
	_bg = Panel.new()
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.12, 0.14, 0.18, 0.6)
	bg_style.corner_radius_top_left    = 6
	bg_style.corner_radius_top_right   = 6
	bg_style.corner_radius_bottom_left = 6
	bg_style.corner_radius_bottom_right = 6
	_bg.add_theme_stylebox_override("panel", bg_style)
	_bg.size = Vector2(CELL_W, CELL_H)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)

	# 2. Preview (next z-layer) — added FIRST so it renders behind main items.
	#    Each preview item sits at the same slot position, offset down+right to peek out.
	_preview_rects.clear()
	# Items sit on the shelf floor — anchored at the bottom of the cell.
	var slot_y := CELL_H - BOT_PAD - ITEM_SIZE
	var peek_offset := Vector2(0, -16)  # how far the stack peeks behind
	for i in range(SLOTS):
		var x := SIDE_PAD + i * (ITEM_SIZE + SLOT_GAP)
		var prect := TextureRect.new()
		prect.expand_mode    = TextureRect.EXPAND_IGNORE_SIZE
		prect.stretch_mode   = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		prect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		prect.size           = Vector2(ITEM_SIZE, ITEM_SIZE)
		prect.position       = Vector2(x + peek_offset.x, slot_y + peek_offset.y)
		prect.pivot_offset   = Vector2(ITEM_SIZE * 0.5, ITEM_SIZE * 0.5)
		prect.rotation       = ITEM_ROTATION
		prect.modulate       = Color(0.30, 0.30, 0.30, 0.7)
		prect.mouse_filter   = Control.MOUSE_FILTER_IGNORE
		add_child(prect)
		_preview_rects.append(prect)

	# 3. Main item slots — on top of preview.
	_slot_rects.clear()
	_slot_highlights.clear()
	for i in range(SLOTS):
		var x := SIDE_PAD + i * (ITEM_SIZE + SLOT_GAP)

		var rect := TextureRect.new()
		rect.expand_mode    = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode   = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		rect.size           = Vector2(ITEM_SIZE, ITEM_SIZE)
		rect.position       = Vector2(x, slot_y)
		rect.pivot_offset   = Vector2(ITEM_SIZE * 0.5, ITEM_SIZE * 0.5)
		rect.rotation       = ITEM_ROTATION
		rect.mouse_filter   = Control.MOUSE_FILTER_IGNORE
		add_child(rect)
		_slot_rects.append(rect)

		# Golden selection highlight (hidden by default).
		var highlight := Panel.new()
		var h_style := StyleBoxFlat.new()
		h_style.bg_color    = Color(0, 0, 0, 0)
		h_style.border_color = Color(1.0, 0.85, 0.3, 0.9)
		h_style.set_border_width_all(2)
		h_style.set_corner_radius_all(4)
		highlight.add_theme_stylebox_override("panel", h_style)
		highlight.size     = Vector2(ITEM_SIZE + 4, ITEM_SIZE + 4)
		highlight.position = Vector2(x - 2, slot_y - 2)
		highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
		highlight.visible  = false
		add_child(highlight)
		_slot_highlights.append(highlight)

	_refresh_all()


func _refresh_all() -> void:
	for i in range(SLOTS):
		_refresh_slot(i)
	_refresh_preview()


func _refresh_slot(idx: int) -> void:
	var rect := _slot_rects[idx]
	var item_id := _slots[idx]
	if item_id != 0 and _item_textures.has(item_id):
		rect.texture  = _item_textures[item_id]
		rect.modulate = Color.WHITE
		rect.scale    = Vector2.ONE
		rect.visible  = true
	else:
		rect.texture = null
		rect.visible = false


func _refresh_preview() -> void:
	if _z_stack.is_empty():
		for prect in _preview_rects:
			prect.visible = false
		return
	var next_layer: Array = _z_stack[0]
	for i in range(SLOTS):
		var prect := _preview_rects[i]
		var item_id: int = next_layer[i] as int
		if item_id != 0 and _item_textures.has(item_id):
			prect.texture = _item_textures[item_id]
			prect.visible = true
		else:
			prect.visible = false
