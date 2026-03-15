# Cell_triangular.gd — triangular cell layout (backed up, not active).
# To re-enable: rename this to Cell.gd and apply the matching Game.gd changes.
# See also Game_triangular_notes.gd for the Game.gd side.
#
# Key ideas:
#   - TRIANGLE_SIDE=175, TRIANGLE_H=151.554 (equilateral triangle bounding box)
#   - is_up flag: true=▲ (apex top), false=▽ (apex bottom); alternates by (row+col)%2
#   - Items at centroid + 0.40*(vertex-centroid) → clustered, inside triangle
#   - DRAW_SCALE=0.85 shrinks drawn bg toward centroid for visual gaps
#   - Hit detection: _point_in_triangle (cross-product sign test) in Game.gd
#   - Layout: 3 cols fixed, rows vary (Easy=3, Medium=4, Hard=5)
#   - CELL_GAP_X=20, CELL_GAP_Y=15 added to strides in Game.gd _build_cells()

# ---- original file contents below (class_name removed to avoid conflicts) ----

extends Control

const TRIANGLE_SIDE := 175.0
const TRIANGLE_H    := 151.554
const ITEM_SIZE     := 90
const SLOTS         := 3
const DRAW_SCALE    := 0.85

var is_up: bool = true
var _slots: Array[int]  = [0, 0, 0]
var _z_stack: Array     = []
var _item_textures: Dictionary = {}
var _slot_rects:    Array[TextureRect] = []
var _preview_rects: Array[TextureRect] = []
var _slot_selected: Array[bool]        = [false, false, false]


func _get_verts_local() -> PackedVector2Array:
	if is_up:
		return PackedVector2Array([
			Vector2(0.0,               TRIANGLE_H),
			Vector2(TRIANGLE_SIDE,     TRIANGLE_H),
			Vector2(TRIANGLE_SIDE / 2.0, 0.0),
		])
	else:
		return PackedVector2Array([
			Vector2(0.0,               0.0),
			Vector2(TRIANGLE_SIDE,     0.0),
			Vector2(TRIANGLE_SIDE / 2.0, TRIANGLE_H),
		])


func _get_slot_centers_local() -> Array[Vector2]:
	var verts := _get_verts_local()
	var cx := (verts[0].x + verts[1].x + verts[2].x) / 3.0
	var cy := (verts[0].y + verts[1].y + verts[2].y) / 3.0
	var centroid := Vector2(cx, cy)
	var result: Array[Vector2] = []
	for v in verts:
		result.append(centroid + 0.40 * (v - centroid))
	return result


func get_slot_center(slot_idx: int) -> Vector2:
	return _get_slot_centers_local()[slot_idx]


func get_triangle_vertices_global() -> Array[Vector2]:
	var verts := _get_verts_local()
	var result: Array[Vector2] = []
	for v in verts:
		result.append(global_position + v)
	return result


func setup(slots: Array, z_stack: Array, textures: Dictionary) -> void:
	_item_textures = textures
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
	for i in range(SLOTS):
		if _slots[i] == 0:
			return i
	return -1

func check_match() -> bool:
	return _slots[0] != 0 and _slots[0] == _slots[1] and _slots[1] == _slots[2]

func clear_match() -> void:
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

func show_slot_highlight(slot_idx: int, lit: bool) -> void:
	if slot_idx >= 0 and slot_idx < SLOTS:
		_slot_selected[slot_idx] = lit
		queue_redraw()

func hide_all_highlights() -> void:
	for i in range(SLOTS):
		_slot_selected[i] = false
	queue_redraw()

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


func _build_visuals() -> void:
	custom_minimum_size = Vector2(TRIANGLE_SIDE, TRIANGLE_H)
	size = Vector2(TRIANGLE_SIDE, TRIANGLE_H)
	var centers := _get_slot_centers_local()
	var half := ITEM_SIZE * 0.5
	_preview_rects.clear()
	for i in range(SLOTS):
		var prect := TextureRect.new()
		prect.expand_mode    = TextureRect.EXPAND_IGNORE_SIZE
		prect.stretch_mode   = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		prect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		prect.size           = Vector2(ITEM_SIZE, ITEM_SIZE)
		prect.position       = centers[i] - Vector2(half - 3.0, half - 3.0)
		prect.pivot_offset   = Vector2(half, half)
		prect.modulate       = Color(0.30, 0.30, 0.30, 0.7)
		prect.mouse_filter   = Control.MOUSE_FILTER_IGNORE
		add_child(prect)
		_preview_rects.append(prect)
	_slot_rects.clear()
	for i in range(SLOTS):
		var rect := TextureRect.new()
		rect.expand_mode    = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode   = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		rect.size           = Vector2(ITEM_SIZE, ITEM_SIZE)
		rect.position       = centers[i] - Vector2(half, half)
		rect.pivot_offset   = Vector2(half, half)
		rect.mouse_filter   = Control.MOUSE_FILTER_IGNORE
		add_child(rect)
		_slot_rects.append(rect)
	_refresh_all()


func _get_drawn_verts() -> PackedVector2Array:
	var verts := _get_verts_local()
	var cx := (verts[0].x + verts[1].x + verts[2].x) / 3.0
	var cy := (verts[0].y + verts[1].y + verts[2].y) / 3.0
	var c := Vector2(cx, cy)
	return PackedVector2Array([
		c + DRAW_SCALE * (verts[0] - c),
		c + DRAW_SCALE * (verts[1] - c),
		c + DRAW_SCALE * (verts[2] - c),
	])


func _draw() -> void:
	var dverts := _get_drawn_verts()
	draw_colored_polygon(dverts, Color(0.12, 0.14, 0.18, 0.6))
	draw_polyline(
		PackedVector2Array([dverts[0], dverts[1], dverts[2], dverts[0]]),
		Color(0.5, 0.5, 0.65, 0.35), 1.5)
	var centers := _get_slot_centers_local()
	for i in range(SLOTS):
		if _slot_selected[i]:
			var r := ITEM_SIZE * 0.5 + 4.0
			draw_circle(centers[i], r, Color(1.0, 0.85, 0.3, 0.22))
			draw_arc(centers[i], r, 0.0, TAU, 32, Color(1.0, 0.85, 0.3, 0.9), 2.0)


func _refresh_all() -> void:
	for i in range(SLOTS):
		_refresh_slot(i)
	_refresh_preview()
	queue_redraw()

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
