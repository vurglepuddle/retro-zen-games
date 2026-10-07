# Cell.gd — one vertical shelf on the potion_3 board.
# Holds 3 item slots stacked top-to-bottom + a z-stack of layers below.
# Built entirely in code (no .tscn).

class_name PotionCell
extends Control

# --- Layout constants ---
# 5 cols × 108 = 540px; 18px between adjacent items (9px each side inside cell).
# 3 rows × 270 + 2 × 6 gap = 822px board height → 378px left for UI.
# The art is drawn on the items' pixel grid: 1 art px = 3 game px (items are
# 30 px drawn at 90), so offsets below are kept to multiples of 3.
const ITEM_SIZE    := 90
const SLOTS        := 3
const SIDE_PAD     := 9     # (CELL_W - ITEM_SIZE) / 2
const CELL_W       := 108
const CELL_H        := 270   # 3 × ITEM_SIZE
const SLOT_OVERLAP  := 12    # each slot nudged this many px into the one above (perspective)
const SLOT_Y_OFFSET   := 15    # shift the whole stack down inside the cell
const DISP_BG_Y      := -3     # small box sits 1 art px higher so its rim shows above the item
const LOCK_FONT_SIZE := 48     # locked-cell counter
const LOCK_SEAL_Y    := 132    # centre of the lid's wax seal (art row 44); x is CELL_W / 2

# Box frames are 35 art px wide, so neighbouring boxes in a row are exactly
# 1 art px (3 px) apart. Each box sits flush left in its cell.
const BOX_W       := 105
const BOX_H       := 267   # large box body; its handle hangs 3 px lower, into the row gap
const SMALL_BOX_H := 99
const FRAME_INSET := 6     # rim + dark inner line, 1 art px each
const SHADOW_PAD  := 12    # 4 art px of shadow on every side of a frame
const IND_W       := 33
const IND_H       := 15
# The three pips inside Indicator_Lit.png; the middle one is 1 art px wider.
const IND_PIPS := [Rect2(3, 3, 6, 9), Rect2(12, 3, 9, 9), Rect2(24, 3, 6, 9)]

# --- Art (games/potion_3/assets/ui, sources in art_src/potion_3) ---
const TEX_FRAME       := preload("res://games/potion_3/assets/ui/Box_Large_Frame.png")  # 105×270, handle at the bottom
const TEX_FRAME_SMALL := preload("res://games/potion_3/assets/ui/Box_Small_Frame.png")  # 105×99
const TEX_IND_LIT     := preload("res://games/potion_3/assets/ui/Indicator_Lit.png")    # 33×15, 3 pips
const TEX_IND_CLEARED := preload("res://games/potion_3/assets/ui/Indicator_Cleared.png")
const TEX_LOCK        := preload("res://games/potion_3/assets/ui/Box_Large_Lock.png")   # 105×267 sealed lid, covers the box body
const TEX_SELECT      := preload("res://games/potion_3/assets/ui/select_frame.png")     # 96×96 corner brackets

# Box insides: one neutral slate, a touch bluer on the conveyor row and a touch
# redder on the hazard-belt crates. Next-layer previews are mixed toward it so
# they read as sunk into the box (see _get_preview_mat).
const FILL_NEUTRAL  := Color("2b2c31")
const FILL_CONVEYOR := Color("292c36")
const FILL_BELT     := Color("322a2d")
const SHADOW_COLOR  := Color("16120e")
const WAX_RED       := Color("550f0a")   # lock counter outline, from the wax seal

enum Box { SHELF, CONVEYOR, CRATE, BELT_CRATE }
const BOX_FILLS := [FILL_NEUTRAL, FILL_CONVEYOR, FILL_NEUTRAL, FILL_BELT]

# --- Previous box art: off for now, PNGs and art_src sources kept ---
# Drawn boxes with velvet linings and amber ColorRect depth pips. To bring it
# back, restore these and the "Previous box art" lines in _build_visuals(),
# _dress_box(), set_as_dispenser(), set_scroll_row_visual() and
# _refresh_dispenser_indicator() (_bg was the box TextureRect).
# const TEX_BOX       := preload("res://games/potion_3/assets/ui/box_shelf.png")       # 108×270
# const TEX_BOX_CONV  := preload("res://games/potion_3/assets/ui/box_conveyor.png")    # 108×270, belt along the bottom
# const TEX_BOX_SMALL := preload("res://games/potion_3/assets/ui/box_small.png")       # 108×96 dispenser crate
# const TEX_BOX_BELT  := preload("res://games/potion_3/assets/ui/box_small_belt.png")  # 108×96 hazard-belt crate
# const TEX_LOCK      := preload("res://games/potion_3/assets/ui/lock_cover.png")      # 108×270 sealed lid (seal at y 135)
# const LINING_SHELF    := Color("183f39")   # teal velvet   (box_shelf, box_small)
# const LINING_CONVEYOR := Color("121238")   # indigo velvet (box_conveyor)
# const LINING_BELT     := Color("550f0a")   # red velvet    (box_small_belt)
# const PIP_LIT    := Color("efac28")
# const PIP_EMPTY  := Color("2a1d0d")
# const DISP_PIP_Y := 81   # depth pips on the dispenser crate's front lip
# const BELT_PIP_Y := 69   # …and on the hazard-belt crate's lip (it sits on a belt)
# const BOX_TEXTURES := [TEX_BOX, TEX_BOX_CONV, TEX_BOX_SMALL, TEX_BOX_BELT]
# const BOX_LININGS  := [LINING_SHELF, LINING_CONVEYOR, LINING_SHELF, LINING_BELT]

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
var _slot_highlights: Array[TextureRect] = []
var _mystery_panels:  Array[Panel]       = []
var _box:         Control = null       # shadow + fill; moved/resized by _dress_box()
var _box_shadow:  ColorRect = null
var _box_fill:    ColorRect = null
var _box_frame:   TextureRect = null
var _lining:      Color = FILL_NEUTRAL # box fill; previews fade toward it
var _lock_overlay: Control = null   # sealed lid drawn over a locked cell
var _lock_label:   Label = null    # remaining-match count, printed on the wax seal
var _lock_seal:    Node2D = null   # rotating arcane circle around the wax seal
var _unlock_tween: Tween = null    # overlay fade-out; killed if undo re-locks mid-fade
var _disp_pips:    Array[TextureRect] = []   # lit pips over the depth indicator, one per item
# Previous box art:
# var _disp_dots:    Array[ColorRect] = []   # indicator dots for dispenser depth
# var _disp_total:   int = 0                 # total items at dispenser creation time

# --- Mystery silhouette materials (shared across all cells) ---
# Both use mystery_item.gdshader: a SOLID swirling-smoke cutout (binarized
# alpha), so overlapping silhouettes never show through each other.
# Top layer + drag: near-black blue. Preview layer: lighter dusty blue.
static var _mystery_mat_top:  ShaderMaterial = null
static var _mystery_mat_prev: ShaderMaterial = null

static func _get_mystery_mat() -> ShaderMaterial:
	if _mystery_mat_top == null:
		_mystery_mat_top = ShaderMaterial.new()
		_mystery_mat_top.shader = load("res://games/potion_3/assets/mystery_item.gdshader")
	return _mystery_mat_top

static var _preview_mats: Dictionary = {}   # lining colour (html) → ShaderMaterial

# Next-layer preview: darkened and mixed toward the box's velvet lining
# (preview_item.gdshader) but SOLID, so previews that overlap never show
# through each other. One shared material per lining colour.
static func _get_preview_mat(lining: Color = FILL_NEUTRAL) -> ShaderMaterial:
	var key := lining.to_html()
	if not _preview_mats.has(key):
		var mat := ShaderMaterial.new()
		mat.shader = load("res://games/potion_3/assets/preview_item.gdshader")
		mat.set_shader_parameter("fog_color", lining)
		_preview_mats[key] = mat
	return _preview_mats[key]


static func _make_art_rect(tex: Texture2D) -> TextureRect:
	## Pixel-art TextureRect at the texture's own size. EXPAND_IGNORE_SIZE keeps
	## the texture out of the minimum size — Control caches that while outside
	## the tree, which would stop set_as_dispenser() from shrinking the rect.
	var r := TextureRect.new()
	r.texture        = tex
	r.expand_mode    = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode   = TextureRect.STRETCH_SCALE
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	r.mouse_filter   = Control.MOUSE_FILTER_IGNORE
	r.size           = tex.get_size()
	return r

static func _get_mystery_mat_prev() -> ShaderMaterial:
	if _mystery_mat_prev == null:
		_mystery_mat_prev = ShaderMaterial.new()
		_mystery_mat_prev.shader = load("res://games/potion_3/assets/mystery_item.gdshader")
		_mystery_mat_prev.set_shader_parameter("base_color", Color(0.15, 0.17, 0.25))
		_mystery_mat_prev.set_shader_parameter("swirl_color", Color(0.22, 0.25, 0.36))
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
	## Animate all 3 items dissolving — swirl out + spark puff — then reveal
	## the next z-layer.
	var tw := create_tween()
	for i in range(SLOTS):
		var rect := _slot_rects[i]
		_spawn_dissolve_sparks(i)
		tw.parallel().tween_property(rect, "scale", Vector2.ZERO, 0.25) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(rect, "rotation", randf_range(-0.9, 0.9), 0.25) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(rect, "modulate:a", 0.0, 0.25)
	await tw.finished
	# Rects are reused for the next layer — undo the dissolve spin.
	for rect in _slot_rects:
		rect.rotation = 0.0
	_slots = [0, 0, 0]
	reveal_next_layer()


# Small puff of pixel sparks where a matched item dissolves.
static var _dissolve_spark_tex: ImageTexture = null

func _spawn_dissolve_sparks(idx: int) -> void:
	if _dissolve_spark_tex == null:
		var img := Image.create(3, 3, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_dissolve_spark_tex = ImageTexture.create_from_image(img)
	var fx := CPUParticles2D.new()
	fx.texture = _dissolve_spark_tex
	fx.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	fx.position = get_slot_center(idx)
	fx.one_shot = true
	fx.explosiveness = 1.0
	fx.amount = 10
	fx.lifetime = 0.45
	fx.direction = Vector2.RIGHT
	fx.spread = 180.0
	fx.gravity = Vector2(0, 240)
	fx.initial_velocity_min = 40.0
	fx.initial_velocity_max = 130.0
	fx.scale_amount_min = 1.0
	fx.scale_amount_max = 2.4
	fx.color = Color(1.0, 0.95, 0.75)
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0.95))
	ramp.set_color(1, Color(1, 1, 1, 0.0))
	fx.color_ramp = ramp
	fx.z_index = 30
	add_child(fx)
	fx.emitting = true
	fx.finished.connect(fx.queue_free)


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


func get_snapshot() -> Dictionary:
	## Full logical state for undo — items, hidden layers, mystery flags, lock.
	return {
		slots           = get_slots_array(),
		z_stack         = get_z_stack_copy(),
		slot_mystery    = _slot_mystery.duplicate(),
		z_stack_mystery = _z_stack_mystery.duplicate(true),
		is_locked       = _is_locked,
		unlock_counter  = _unlock_counter,
	}


func restore(snap: Dictionary) -> void:
	_slots = [snap.slots[0] as int, snap.slots[1] as int, snap.slots[2] as int]
	_z_stack = []
	for layer in snap.z_stack:
		_z_stack.append(layer.duplicate())
	var mys: Array = snap.slot_mystery
	_slot_mystery = [mys[0] as bool, mys[1] as bool, mys[2] as bool]
	_z_stack_mystery = (snap.z_stack_mystery as Array).duplicate(true)
	_is_locked      = snap.is_locked
	_unlock_counter = snap.unlock_counter
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
	size = Vector2(CELL_W, ITEM_SIZE)

	# Swap the tall box for a small one.
	if _box != null:
		_dress_box(Box.CRATE)

	# Remove SLOT_Y_OFFSET from slot 0 — the single item fills the 90px cell flush.
	if not _slot_rects.is_empty():
		_slot_rects[0].position      = Vector2(SIDE_PAD, 0)
	if not _preview_rects.is_empty():
		_preview_rects[0].position   = Vector2(SIDE_PAD - 9, -3)
	if not _slot_highlights.is_empty():
		_slot_highlights[0].position = Vector2(SIDE_PAD - 3, -3)

	# Hide slots 1 and 2 — only slot 0 is the live dispensing slot.
	for i in range(1, SLOTS):
		if i < _slot_rects.size():
			_slot_rects[i].visible = false
		if i < _preview_rects.size():
			_preview_rects[i].visible = false
		if i < _slot_highlights.size():
			_slot_highlights[i].visible = false

	_refresh_all()

	# Depth indicator, centred on the small box's bottom edge and drawn over the
	# item's base like a label on the box front. Indicator_Cleared is the base;
	# a lit pip (cut from Indicator_Lit) sits on top for each item still inside.
	var ind_pos := _box.position + Vector2((BOX_W - IND_W) * 0.5, SMALL_BOX_H - IND_H)
	var ind := _make_art_rect(TEX_IND_CLEARED)
	ind.position = ind_pos
	add_child(ind)
	for region: Rect2 in IND_PIPS:
		var lit := AtlasTexture.new()
		lit.atlas  = TEX_IND_LIT
		lit.region = region
		var pip := _make_art_rect(lit)
		pip.position = ind_pos + region.position
		add_child(pip)
		_disp_pips.append(pip)
	_refresh_dispenser_indicator()

	# Previous box art: amber ColorRect pips on the crate's front lip.
	# _disp_total = _z_stack.size() + (1 if _slots[0] != 0 else 0)
	# const PIP := 6       # 2×2 art px
	# const PIP_GAP := 3
	# var bar_w := _disp_total * PIP + (_disp_total - 1) * PIP_GAP
	# var start_x := int(roundf((CELL_W - bar_w) / 6.0)) * 3
	# for di in range(_disp_total):
	# 	var dot := ColorRect.new()
	# 	dot.size         = Vector2(PIP, PIP)
	# 	dot.position     = Vector2(start_x + di * (PIP + PIP_GAP), DISP_PIP_Y)
	# 	dot.color        = PIP_LIT
	# 	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 	add_child(dot)
	# 	_disp_dots.append(dot)


func set_as_locked(unlock_count: int) -> void:
	_is_locked      = true
	_unlock_counter = unlock_count
	# Hide previews — they'd poke out from under the overlay otherwise.
	for pr in _preview_rects:
		pr.visible = false
	# Sealed lid covers the FULL cell so no item graphics bleed out: planks tied
	# with twine under a red wax seal (lock_cover.png). It sits on top of the
	# box frame, so the frame is already there when the lid fades on unlock.
	_lock_overlay = _make_art_rect(TEX_LOCK)
	add_child(_lock_overlay)
	# Remaining-match counter, printed on the wax seal.
	var seal_center := Vector2(CELL_W * 0.5, LOCK_SEAL_Y)
	_lock_label = Label.new()
	_lock_label.text = str(_unlock_counter)
	_lock_label.add_theme_font_override("font", load("res://assets/font/vetka.ttf"))
	_lock_label.add_theme_font_size_override("font_size", LOCK_FONT_SIZE)
	_lock_label.add_theme_color_override("font_color", Color.WHITE)
	_lock_label.add_theme_color_override("font_outline_color", WAX_RED)
	_lock_label.add_theme_constant_override("outline_size", 6)
	_lock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lock_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_lock_label.size         = Vector2(CELL_W, CELL_H)
	# vetka's digits sit high and a little left inside their line box, so plain
	# centring leaves the ink off the seal's centre. Nudge it back (ratios of the
	# font size, measured from rendered glyphs, so they hold if the size changes).
	_lock_label.position     = seal_center - _lock_label.size * 0.5 \
		+ Vector2(roundf(LOCK_FONT_SIZE * 0.06), roundf(LOCK_FONT_SIZE * 0.15))
	_lock_label.pivot_offset = seal_center - _lock_label.position
	_lock_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Magical seal: a slowly rotating arcane circle around the wax seal. Added
	# before the label so the number stays on top.
	_lock_seal = Node2D.new()
	_lock_seal.position = seal_center
	_lock_seal.draw.connect(_draw_lock_seal)
	_lock_overlay.add_child(_lock_seal)
	_lock_overlay.add_child(_lock_label)
	var seal_tw := _lock_seal.create_tween().set_loops()
	seal_tw.tween_property(_lock_seal, "rotation", TAU, 14.0).from(0.0)


# Arcane seal: outer ring, rotating inner dashes, diamonds at the cardinal
# points — gilt (amber/cream from the item palette) drawn around the wax seal,
# with 3 px strokes so it matches the art's pixel weight.
func _draw_lock_seal() -> void:
	if _lock_seal == null:
		return
	var faint  := Color(0.937, 0.675, 0.157, 0.55)   # #efac28
	var bright := Color(0.937, 0.847, 0.631, 0.9)    # #efd8a1
	_lock_seal.draw_arc(Vector2.ZERO, 38.0, 0.0, TAU, 48, faint, 3.0, false)
	for i in range(8):
		var a0 := float(i) * TAU / 8.0
		_lock_seal.draw_arc(Vector2.ZERO, 34.0, a0, a0 + TAU / 16.0, 6, bright, 3.0, false)
	for i in range(4):
		var ang := float(i) * TAU / 4.0
		var p := Vector2(cos(ang), sin(ang)) * 38.0
		_lock_seal.draw_colored_polygon(PackedVector2Array([
			p + Vector2(0, -6), p + Vector2(6, 0),
			p + Vector2(0, 6), p + Vector2(-6, 0),
		]), bright)


func _thump_lock_label() -> void:
	## The seal's number gives a small press when a match counts it down.
	if _lock_label == null:
		return
	_lock_label.scale = Vector2(1.3, 1.3)
	var tw := _lock_label.create_tween()
	tw.tween_property(_lock_label, "scale", Vector2.ONE, 0.22) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


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
		_thump_lock_label()
	return false


func _refresh_dispenser_indicator() -> void:
	if not _is_dispenser or _disp_pips.is_empty():
		return
	var remaining := _z_stack.size() + (1 if _slots[0] != 0 else 0)
	for i in range(_disp_pips.size()):
		_disp_pips[i].visible = i < remaining
	# Previous box art:
	# for i in range(_disp_dots.size()):
	# 	_disp_dots[i].color = PIP_LIT if i < remaining else PIP_EMPTY


func set_scroll_row_visual() -> void:
	## Called by Game for cells that ride a conveyor: the scrolling grid row's
	## boxes get a bluer inside, the hazard belt's small boxes a redder one.
	if _box == null:
		return
	if _is_dispenser:
		_dress_box(Box.BELT_CRATE)
		# Previous box art: pips sat higher on the belt crate's lip.
		# for dot in _disp_dots:
		# 	dot.position.y = BELT_PIP_Y
	else:
		_dress_box(Box.CONVEYOR)
	_refresh_preview()


func _dress_box(kind: Box) -> void:
	## Shapes the box for a Box kind (tall box or small one), tints its inside
	## and sizes its shadow. Also picks the colour next-layer previews fade toward.
	var small := kind == Box.CRATE or kind == Box.BELT_CRATE
	var body := Vector2(BOX_W, SMALL_BOX_H if small else BOX_H)
	_box.position        = Vector2(0, DISP_BG_Y if small else 0)
	_box_frame.position  = _box.position   # a cell child of its own, see _build_visuals()
	_box_frame.texture   = TEX_FRAME_SMALL if small else TEX_FRAME
	_box_frame.size      = _box_frame.texture.get_size()
	_box_fill.color      = BOX_FILLS[kind]
	_box_fill.position   = Vector2(FRAME_INSET, FRAME_INSET)
	_box_fill.size       = body - Vector2(FRAME_INSET, FRAME_INSET) * 2.0
	_box_shadow.position = -Vector2(SHADOW_PAD, SHADOW_PAD)
	_box_shadow.size     = body + Vector2(SHADOW_PAD, SHADOW_PAD) * 2.0
	_lining              = BOX_FILLS[kind]
	# Previous box art:
	# var art := _bg as TextureRect
	# art.texture  = BOX_TEXTURES[kind]
	# art.size     = art.texture.get_size()
	# art.position = Vector2(0, DISP_BG_Y if small else 0)
	# _lining      = BOX_LININGS[kind]


func _update_lock_visual() -> void:
	if _lock_overlay == null:
		return
	# An undo right after an unlock must not let the fade finish and hide the
	# overlay of a cell that is locked again.
	if _unlock_tween != null and _unlock_tween.is_valid():
		_unlock_tween.kill()
	_lock_overlay.visible  = _is_locked
	_lock_overlay.modulate = Color.WHITE
	if _lock_label != null:
		_lock_label.text = str(_unlock_counter)


func _animate_unlock() -> void:
	if _lock_overlay == null:
		return
	_unlock_tween = create_tween()
	_unlock_tween.tween_property(_lock_overlay, "modulate:a", 0.0, 0.45) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_unlock_tween.tween_callback(func():
		_lock_overlay.visible    = false
		_lock_overlay.modulate.a = 1.0   # reset so undo can re-show it
		_refresh_preview())              # show any previews now that we're unlocked


# ============================================================================
#  Visuals
# ============================================================================

func _build_visuals() -> void:
	# No custom_minimum_size: it is cached while the node is outside the tree,
	# so set_as_dispenser() could never shrink the rect below 270 px — the
	# invisible bottom 180 px swallowed taps meant for the BACK button.
	size = Vector2(CELL_W, CELL_H)
	# Game._input does all hit-testing; the cell itself must never eat GUI
	# clicks (it sits above the BACK / UNDO / RESTART buttons in tree order).
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 1. The box: shadow and slate inside (the frame goes on after the
	#    previews). Conveyor / dispenser / belt cells re-dress it later. The
	#    shadow draws at z −1, under every box on the board but over the shop
	#    Backdrop (z −2), so a neighbour's shadow never covers a frame and
	#    missing rows or crates cast no shadow.
	_box = Control.new()
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box_shadow = ColorRect.new()
	_box_shadow.color        = SHADOW_COLOR
	_box_shadow.z_index      = -1
	_box_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box_fill = ColorRect.new()
	_box_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box_frame = _make_art_rect(TEX_FRAME)
	_box.add_child(_box_shadow)
	_box.add_child(_box_fill)
	_dress_box(Box.SHELF)
	add_child(_box)
	# Previous box art: a wooden display box lined with teal velvet.
	# _bg = _make_art_rect(TEX_BOX)

	# 2. Preview (next z-layer) — added first so it renders behind main items.
	#    Offset slightly left+up (one art px, three) to suggest depth.
	_preview_rects.clear()
	for i in range(SLOTS):
		var prect := TextureRect.new()
		prect.expand_mode    = TextureRect.EXPAND_IGNORE_SIZE
		prect.stretch_mode   = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		prect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		prect.size           = Vector2(ITEM_SIZE, ITEM_SIZE)
		prect.position       = Vector2(SIDE_PAD - 3, SLOT_Y_OFFSET + i * (ITEM_SIZE - SLOT_OVERLAP) - 9)
		prect.pivot_offset   = Vector2(ITEM_SIZE * 0.5, ITEM_SIZE * 0.5)
		prect.material       = _get_preview_mat(_lining)   # look is set in _refresh_preview() / the shaders
		prect.mouse_filter   = Control.MOUSE_FILTER_IGNORE
		add_child(prect)
		_preview_rects.append(prect)

	# 2b. Box frame over the previews, so the rim always clips them (a small
	#     box's preview reaches past its inside); items still draw on top.
	add_child(_box_frame)

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

		# Golden corner-bracket selection highlight (select_frame.png, 1 art px outside the item).
		var highlight := _make_art_rect(TEX_SELECT)
		highlight.position = Vector2(SIDE_PAD - 3, SLOT_Y_OFFSET + i * (ITEM_SIZE - SLOT_OVERLAP) - 3)
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
			# Darkening/fade lives in the shaders (opaque output) — tweak there.
			prect.modulate = Color.WHITE
			prect.material = _get_mystery_mat_prev() if is_mys else _get_preview_mat(_lining)
			prect.visible  = true
		else:
			prect.material = null
			prect.visible  = false
