# Cell.gd — one vertical shelf on the potion_3 board.
# Holds 3 item slots stacked top-to-bottom + a z-stack of layers below.
# Built entirely in code (no .tscn).

class_name PotionCell
extends Control

# --- Layout constants ---
# 5 cols × 108 = 540px; 18px between adjacent items (9px each side inside cell).
# 3 rows × 270 + 2 × 9 gap = 828px board height → 372px left for UI.
const ITEM_SIZE    := 90
const SLOTS        := 3
const SIDE_PAD     := 9     # (CELL_W - ITEM_SIZE) / 2
const CELL_W       := 108
const CELL_H        := 270   # 3 × ITEM_SIZE
const VISUAL_INSET  := 4     # bg panel shrunk on all sides; items stay put
const SLOT_OVERLAP  := 12    # each slot nudged this many px into the one above (perspective)
const SLOT_Y_OFFSET   := 16    # shift the whole stack down inside the cell
const DISP_BG_PAD_H  := 2     # dispenser bg: px trimmed on each side horizontally
const DISP_BG_PAD_V  := -4     # dispenser bg: px trimmed on top and bottom

# --- State ---
var _slots: Array[int] = [0, 0, 0]   # current visible items (0 = empty)
var _z_stack: Array     = []          # remaining layers below; each Array[int] of size 3
var _item_textures: Dictionary = {}   # shared ref from Game: item_id → Texture2D
var _slot_mystery: Array[bool] = [false, false, false]  # mystery per current-layer slot
var _z_stack_mystery: Array     = []                    # parallel to _z_stack; Array[bool,bool,bool] per layer

# --- Special cell state ---
var _is_locked:     bool = false   # locked: items inaccessible until N matches made
var _is_dispenser:  bool = false   # dispenser: can take items but not place them back
var _unlock_counter: int = 0       # matches remaining to unlock this cell

# --- Visual nodes ---
var _slot_rects:      Array[TextureRect] = []
var _preview_rects:   Array[TextureRect] = []
var _slot_highlights: Array[Panel]       = []
var _mystery_panels:  Array[Panel]       = []
var _bg:           Panel = null
var _lock_overlay: Panel = null    # dark overlay drawn over a locked cell
var _lock_label:   Label = null    # shows remaining-match count on the overlay
var _disp_dots:    Array[ColorRect] = []   # indicator dots for dispenser depth
var _disp_total:   int = 0                 # total items at dispenser creation time

# --- Mystery silhouette shaders (shared across all cells) ---
# Colours are baked into the shader string to avoid uniform-setting issues.
# Top layer + drag:  very dark blue, almost black  — edit the vec4 in _get_mystery_mat()
# Preview layer:     light dusty blue              — edit the vec4 in _get_mystery_mat_prev()
static var _mystery_mat_top:  ShaderMaterial = null
static var _mystery_mat_prev: ShaderMaterial = null

static func _get_mystery_mat() -> ShaderMaterial:
	if _mystery_mat_top == null:
		var s := Shader.new()
		s.code = "shader_type canvas_item;\nvoid fragment() { float a = texture(TEXTURE, UV).a; COLOR = vec4(0.08, 0.08, 0.14, a); }"  # ← tweak RGB
		_mystery_mat_top = ShaderMaterial.new()
		_mystery_mat_top.shader = s
	return _mystery_mat_top

static func _get_mystery_mat_prev() -> ShaderMaterial:
	if _mystery_mat_prev == null:
		var s := Shader.new()
		s.code = "shader_type canvas_item;\nvoid fragment() { float a = texture(TEXTURE, UV).a; COLOR = vec4(0.10, 0.10, 0.14, a * 0.65); }"  # ← tweak RGB / alpha
		_mystery_mat_prev = ShaderMaterial.new()
		_mystery_mat_prev.shader = s
	return _mystery_mat_prev


# ============================================================================
#  Public API
# ============================================================================

func setup(slots: Array, z_stack: Array, textures: Dictionary) -> void:
	_item_textures = textures
	# Strip all-zero layers — artifacts of sparse generation.
	_z_stack = []
	for layer in z_stack:
		var has_any := false
		for v in layer:
			if v != 0:
				has_any = true
				break
		if has_any:
			_z_stack.append(layer.duplicate())

	_slots = [slots[0] as int, slots[1] as int, slots[2] as int]
	while not has_items() and not _z_stack.is_empty():
		var next: Array = _z_stack.pop_front()
		_slots = [next[0] as int, next[1] as int, next[2] as int]

	# Parallel mystery array — one [false,false,false] entry per z-stack layer.
	_z_stack_mystery = []
	for _li in range(_z_stack.size()):
		_z_stack_mystery.append([false, false, false])

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
	if _is_locked or _is_dispenser:
		return -1   # locked / dispenser cells can never receive items
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
		_slot_mystery = [false, false, false]
		_refresh_all()
		return
	var next_layer: Array = _z_stack.pop_front()
	_slots = [next_layer[0] as int, next_layer[1] as int, next_layer[2] as int]
	# Apply the mystery flags stored for this layer.
	if not _z_stack_mystery.is_empty():
		var mys: Array = _z_stack_mystery.pop_front()
		_slot_mystery = [mys[0] as bool, mys[1] as bool, mys[2] as bool]
	else:
		_slot_mystery = [false, false, false]
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
	if _is_locked:
		return false   # locked cells must be unlocked before they can be "cleared"
	for s in _slots:
		if s != 0:
			return false
	return _z_stack.is_empty()


func has_items() -> bool:
	for s in _slots:
		if s != 0:
			return true
	return false


func show_slot_highlight(slot_idx: int, lit: bool) -> void:
	if slot_idx >= 0 and slot_idx < SLOTS:
		_slot_highlights[slot_idx].visible = lit


func hide_all_highlights() -> void:
	for h in _slot_highlights:
		h.visible = false


func get_slot_center(slot_idx: int) -> Vector2:
	## Local-space center of a slot (used for move animations).
	return Vector2(SIDE_PAD + ITEM_SIZE * 0.5, slot_idx * ITEM_SIZE + ITEM_SIZE * 0.5)


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
	if snap.has("is_locked"):
		_is_locked       = snap.is_locked
		_unlock_counter  = snap.unlock_counter
		_update_lock_visual()
	_refresh_all()


func layers_remaining() -> int:
	return _z_stack.size()


func set_slot_visible(slot_idx: int, vis: bool) -> void:
	_slot_rects[slot_idx].visible = vis
	if slot_idx < _mystery_panels.size():
		_mystery_panels[slot_idx].visible = vis and _slot_mystery[slot_idx]


func set_slot_mystery(idx: int, val: bool) -> void:
	if idx < 0 or idx >= SLOTS:
		return
	_slot_mystery[idx] = val
	_refresh_slot(idx)


func is_slot_mystery(idx: int) -> bool:
	return idx < _slot_mystery.size() and _slot_mystery[idx]


func set_z_slot_mystery(layer_idx: int, slot_idx: int, val: bool) -> void:
	if layer_idx < 0 or layer_idx >= _z_stack_mystery.size():
		return
	if slot_idx < 0 or slot_idx >= 3:
		return
	_z_stack_mystery[layer_idx][slot_idx] = val
	if layer_idx == 0:
		_refresh_preview()


# ============================================================================
#  Special Cell Types — Dispenser / Locked / Scrolling-row visual
# ============================================================================

func is_locked() -> bool:
	return _is_locked


func is_dispenser() -> bool:
	return _is_dispenser


func get_unlock_counter() -> int:
	return _unlock_counter


func set_as_dispenser() -> void:
	## Converts this cell into a 1-slot-tall dispenser.
	## Items are stacked one-per-layer in slot 0; slots 1 and 2 are hidden.
	## Called AFTER setup() so _slot_rects etc. already exist.
	_is_dispenser = true

	# Collect every item from all slots + layers, keep them in slot-0 only.
	var all_items: Array[int] = []
	for s in _slots:
		if s != 0:
			all_items.append(s as int)
	for layer in _z_stack:
		for v in layer:
			if v != 0:
				all_items.append(v as int)
	if all_items.is_empty():
		_slots   = [0, 0, 0]
		_z_stack = []
	else:
		_slots   = [all_items[0], 0, 0]
		_z_stack = []
		for i in range(1, all_items.size()):
			_z_stack.append([all_items[i], 0, 0])

	# Collapse to single-slot height.
	custom_minimum_size = Vector2(CELL_W, ITEM_SIZE)
	size                = Vector2(CELL_W, ITEM_SIZE)

	# Resize and restyle the background panel.
	if _bg != null:
		_bg.size     = Vector2(CELL_W - DISP_BG_PAD_H * 2, ITEM_SIZE - DISP_BG_PAD_V * 2)
		_bg.position = Vector2(DISP_BG_PAD_H, DISP_BG_PAD_V)
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.10, 0.12, 0.26, 0.72)
		style.corner_radius_top_left     = 6
		style.corner_radius_top_right    = 6
		style.corner_radius_bottom_left  = 6
		style.corner_radius_bottom_right = 6
		_bg.add_theme_stylebox_override("panel", style)

	# Remove SLOT_Y_OFFSET from slot 0 — the single item fills the 90px cell flush.
	if not _slot_rects.is_empty():
		_slot_rects[0].position      = Vector2(SIDE_PAD, 0)
	if not _preview_rects.is_empty():
		_preview_rects[0].position   = Vector2(SIDE_PAD - 10, -4)
	if not _slot_highlights.is_empty():
		_slot_highlights[0].position = Vector2(SIDE_PAD - 2, -2)

	# Hide slots 1 and 2 — only slot 0 is the live dispensing slot.
	for i in range(1, SLOTS):
		if i < _slot_rects.size():
			_slot_rects[i].visible = false
		if i < _preview_rects.size():
			_preview_rects[i].visible = false
		if i < _slot_highlights.size():
			_slot_highlights[i].visible = false

	_refresh_all()

	# Depth indicator — a row of small dots at the bottom of the cell.
	_disp_total = _z_stack.size() + (1 if _slots[0] != 0 else 0)
	const DOT_W := 7
	const DOT_H := 5
	const DOT_GAP := 3
	var bar_w := _disp_total * DOT_W + (_disp_total - 1) * DOT_GAP
	var start_x := int((CELL_W - bar_w) / 2.0)
	for di in range(_disp_total):
		var dot := ColorRect.new()
		dot.size         = Vector2(DOT_W, DOT_H)
		dot.position     = Vector2(start_x + di * (DOT_W + DOT_GAP), ITEM_SIZE - DOT_H - 3)
		dot.color        = Color(0.55, 0.72, 1.0, 0.85)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(dot)
		_disp_dots.append(dot)
	_refresh_dispenser_indicator()


func set_as_locked(unlock_count: int) -> void:
	_is_locked      = true
	_unlock_counter = unlock_count
	# Hide previews — they'd poke out from under the overlay otherwise.
	for pr in _preview_rects:
		pr.visible = false
	# Dark overlay covers the FULL cell so no item graphics bleed out.
	_lock_overlay = Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.10, 0.92)
	style.corner_radius_top_left     = 6
	style.corner_radius_top_right    = 6
	style.corner_radius_bottom_left  = 6
	style.corner_radius_bottom_right = 6
	style.border_color = Color(0.45, 0.45, 0.65, 0.55)
	style.set_border_width_all(1)
	_lock_overlay.add_theme_stylebox_override("panel", style)
	_lock_overlay.size         = Vector2(CELL_W, CELL_H)
	_lock_overlay.position     = Vector2.ZERO
	_lock_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_lock_overlay)
	# Remaining-match counter in the centre of the overlay.
	_lock_label = Label.new()
	_lock_label.text = str(_unlock_counter)
	_lock_label.add_theme_font_override("font", load("res://assets/font/vetka.ttf"))
	_lock_label.add_theme_font_size_override("font_size", 32)
	_lock_label.add_theme_color_override("font_color", Color(0.65, 0.65, 0.85, 0.9))
	_lock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lock_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_lock_label.size         = _lock_overlay.size
	_lock_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lock_overlay.add_child(_lock_label)


func notify_match() -> bool:
	## Game calls this after every match anywhere on the board.
	## Returns true the moment this cell unlocks (counter just reached 0).
	if not _is_locked:
		return false
	_unlock_counter -= 1
	if _unlock_counter <= 0:
		_is_locked = false
		_animate_unlock()   # fire-and-forget
		return true
	if _lock_label != null:
		_lock_label.text = str(_unlock_counter)
	return false


func _refresh_dispenser_indicator() -> void:
	if not _is_dispenser or _disp_dots.is_empty():
		return
	var remaining := _z_stack.size() + (1 if _slots[0] != 0 else 0)
	for i in range(_disp_dots.size()):
		_disp_dots[i].visible = i < remaining


func set_scroll_row_visual() -> void:
	## Called by Game to tint cells that belong to a scrolling row.
	if _bg == null:
		return
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.16, 0.14, 0.10, 0.60)   # warm amber tint
	style.corner_radius_top_left     = 6
	style.corner_radius_top_right    = 6
	style.corner_radius_bottom_left  = 6
	style.corner_radius_bottom_right = 6
	_bg.add_theme_stylebox_override("panel", style)


func _update_lock_visual() -> void:
	if _lock_overlay == null:
		return
	_lock_overlay.visible  = _is_locked
	_lock_overlay.modulate = Color.WHITE
	if _lock_label != null:
		_lock_label.text = str(_unlock_counter)


func _animate_unlock() -> void:
	if _lock_overlay == null:
		return
	var tw := create_tween()
	tw.tween_property(_lock_overlay, "modulate:a", 0.0, 0.45) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await tw.finished
	if is_instance_valid(_lock_overlay):
		_lock_overlay.visible    = false
		_lock_overlay.modulate.a = 1.0   # reset so undo can re-show it
		_refresh_preview()               # show any previews now that we're unlocked


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
	bg_style.corner_radius_top_left     = 6
	bg_style.corner_radius_top_right    = 6
	bg_style.corner_radius_bottom_left  = 6
	bg_style.corner_radius_bottom_right = 6
	_bg.add_theme_stylebox_override("panel", bg_style)
	_bg.size     = Vector2(CELL_W - VISUAL_INSET * 2, CELL_H - VISUAL_INSET * 2)
	_bg.position = Vector2(VISUAL_INSET, VISUAL_INSET)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)

	# 2. Preview (next z-layer) — added first so it renders behind main items.
	#    Offset slightly right+down to suggest depth.
	_preview_rects.clear()
	for i in range(SLOTS):
		var prect := TextureRect.new()
		prect.expand_mode    = TextureRect.EXPAND_IGNORE_SIZE
		prect.stretch_mode   = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		prect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		prect.size           = Vector2(ITEM_SIZE, ITEM_SIZE)
		prect.position       = Vector2(SIDE_PAD - 2, SLOT_Y_OFFSET + i * (ITEM_SIZE - SLOT_OVERLAP) - 10)
		prect.pivot_offset   = Vector2(ITEM_SIZE * 0.5, ITEM_SIZE * 0.5)
		prect.modulate       = Color(0.2, 0.2, 0.2, 0.85)  # overwritten by _refresh_preview() — tweak there
		prect.mouse_filter   = Control.MOUSE_FILTER_IGNORE
		add_child(prect)
		_preview_rects.append(prect)

	# 3. Main item slots — on top of preview.
	_slot_rects.clear()
	_slot_highlights.clear()
	for i in range(SLOTS):
		var rect := TextureRect.new()
		rect.expand_mode    = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode   = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		rect.size           = Vector2(ITEM_SIZE, ITEM_SIZE)
		rect.position       = Vector2(SIDE_PAD, SLOT_Y_OFFSET + i * (ITEM_SIZE - SLOT_OVERLAP))
		rect.pivot_offset   = Vector2(ITEM_SIZE * 0.5, ITEM_SIZE * 0.5)
		rect.mouse_filter   = Control.MOUSE_FILTER_IGNORE
		add_child(rect)
		_slot_rects.append(rect)

		# Golden selection highlight.
		var highlight := Panel.new()
		var h_style := StyleBoxFlat.new()
		h_style.bg_color     = Color(0, 0, 0, 0)
		h_style.border_color = Color(1.0, 0.85, 0.3, 0.9)
		h_style.set_border_width_all(2)
		h_style.set_corner_radius_all(4)
		highlight.add_theme_stylebox_override("panel", h_style)
		highlight.size     = Vector2(ITEM_SIZE + 4, ITEM_SIZE + 4)
		highlight.position = Vector2(SIDE_PAD - 2, SLOT_Y_OFFSET + i * (ITEM_SIZE - SLOT_OVERLAP) - 2)
		highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
		highlight.visible  = false
		add_child(highlight)
		_slot_highlights.append(highlight)

	_refresh_all()

	# 4. Mystery overlays — transparent panel + "?" label over darkened sprite, hidden by default.
	_mystery_panels.clear()
	var mystery_font: Font = load("res://assets/font/vetka.ttf")
	for i in range(SLOTS):
		var mp := Panel.new()
		var mp_style := StyleBoxFlat.new()
		mp_style.bg_color = Color(0, 0, 0, 0)   # transparent — shader on the TextureRect handles the colour
		mp_style.set_corner_radius_all(6)
		mp.add_theme_stylebox_override("panel", mp_style)
		mp.size         = Vector2(ITEM_SIZE, ITEM_SIZE)
		mp.position     = _slot_rects[i].position
		mp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mp.visible      = false
		add_child(mp)
		var ql := Label.new()
		ql.text                  = "?"
		ql.size                  = mp.size
		ql.horizontal_alignment  = HORIZONTAL_ALIGNMENT_CENTER
		ql.vertical_alignment    = VERTICAL_ALIGNMENT_CENTER
		ql.mouse_filter          = Control.MOUSE_FILTER_IGNORE
		ql.add_theme_font_override("font", mystery_font)
		ql.add_theme_font_size_override("font_size", 44)
		ql.add_theme_color_override("font_color", Color(0.90, 0.88, 1.0, 0.95))
		mp.add_child(ql)
		_mystery_panels.append(mp)


func _refresh_all() -> void:
	for i in range(SLOTS):
		_refresh_slot(i)
	_refresh_preview()
	_refresh_dispenser_indicator()


func _refresh_slot(idx: int) -> void:
	var rect := _slot_rects[idx]
	var item_id := _slots[idx]
	var is_mystery := idx < _slot_mystery.size() and _slot_mystery[idx]
	if item_id != 0 and _item_textures.has(item_id):
		rect.scale   = Vector2.ONE
		rect.visible = true
		if is_mystery:
			rect.texture  = _item_textures[item_id]
			rect.material = _get_mystery_mat()
			rect.modulate = Color.WHITE
			if idx < _mystery_panels.size():
				_mystery_panels[idx].visible = true
		else:
			rect.texture  = _item_textures[item_id]
			rect.material = null
			rect.modulate = Color.WHITE
			if idx < _mystery_panels.size():
				_mystery_panels[idx].visible = false
	else:
		rect.texture = null
		rect.visible = false
		if idx < _mystery_panels.size():
			_mystery_panels[idx].visible = false
	if _is_dispenser:
		_refresh_dispenser_indicator()


func _refresh_preview() -> void:
	if _is_locked:
		for prect in _preview_rects:
			prect.visible = false
		return
	if _z_stack.is_empty():
		for prect in _preview_rects:
			prect.visible = false
		return
	var next_layer: Array = _z_stack[0]
	var next_mystery: Array = [false, false, false]
	if not _z_stack_mystery.is_empty():
		next_mystery = _z_stack_mystery[0]
	for i in range(SLOTS):
		# Dispenser cells only use slot 0; keep slots 1+ invisible.
		if _is_dispenser and i > 0:
			_preview_rects[i].visible = false
			continue
		var prect := _preview_rects[i]
		var item_id: int = next_layer[i] as int
		var is_mys: bool = next_mystery[i] as bool
		if item_id != 0 and _item_textures.has(item_id):
			prect.texture  = _item_textures[item_id]
			prect.modulate = Color(1.0, 1.0, 1.0, 0.85) if is_mys else Color(0.15, 0.15, 0.15, 0.50)
			prect.material = _get_mystery_mat_prev() if is_mys else null
			prect.visible  = true
		else:
			prect.material = null
			prect.visible  = false
