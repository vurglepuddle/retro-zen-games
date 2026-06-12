#BoardCell.gd
class_name BoardCell
extends Control

signal tapped(cell: BoardCell)

const CELL_SIZE := 90

var a_id: int = 0  # 1..N, 0 = removed
var b_id: int = 0
var c_id: int = 0

var _z_rect: TextureRect
var _a_rect: TextureRect
var _b_rect: TextureRect
var _c_rect: TextureRect
var _outline: Panel
var _halo: Panel       # soft outer glow shown with the selection outline

# Per-layer idle-spin guard flags.
var _spinning_a := false
var _spinning_b := false
var _spinning_c := false

# Selection pulse tween.
var _pulse_tween: Tween = null


func _init() -> void:
	custom_minimum_size = Vector2(CELL_SIZE, CELL_SIZE)
	size = Vector2(CELL_SIZE, CELL_SIZE)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	# Start three independent idle-spin loops with randomised offsets so the
	# whole board doesn't pulse in unison.  Minimum 4 s delay so loops never
	# fire during the ~2.5 s entrance animation.
	_idle_loop("a", randf_range(4.0, 9.0))
	_idle_loop("b", randf_range(4.0, 8.0))
	_idle_loop("c", randf_range(4.0, 7.0))
	_glint_loop(randf_range(6.0, 14.0))


func setup(z_tex: Texture2D, a_tex: Texture2D, a_val: int,
		b_tex: Texture2D, b_val: int, c_tex: Texture2D, c_val: int) -> void:
	a_id = a_val
	b_id = b_val
	c_id = c_val

	# Scale/spin pivot at the visual centre of the cell.
	pivot_offset = Vector2(CELL_SIZE * 0.5, CELL_SIZE * 0.5)

	_z_rect = _make_layer(z_tex)
	_a_rect = _make_layer(a_tex)
	_b_rect = _make_layer(b_tex)
	_c_rect = _make_layer(c_tex)

	# Z tile renders below bgsmall (z 100); A/B/C render above it.
	# z_as_relative=false makes these absolute in the canvas, ignoring parent z.
	_z_rect.z_as_relative = false
	_z_rect.z_index = 5
	for rect in [_a_rect, _b_rect, _c_rect]:
		rect.z_as_relative = false
		rect.z_index = 110

	# A/B/C start invisible and tiny so the board shows just the Z background
	# until play_entrance() blooms them in.  Pivot at centre for all transforms.
	for rect in [_a_rect, _b_rect, _c_rect]:
		rect.pivot_offset = Vector2(CELL_SIZE * 0.5, CELL_SIZE * 0.5)
		rect.modulate.a = 0.0
		rect.scale = Vector2(0.15, 0.15)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.border_width_left = 3
	style.border_width_right = 3
	style.border_width_top = 3
	style.border_width_bottom = 3
	style.border_color = Color(1, 0.85, 0.2, 0.95)
	_outline = Panel.new()
	_outline.add_theme_stylebox_override("panel", style)
	_outline.size = Vector2(CELL_SIZE, CELL_SIZE)
	_outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_outline.visible = false
	_outline.z_as_relative = false
	_outline.z_index = 115  # above A/B/C (110) and bgsmall (100)

	# Soft outer halo — a wider, fainter golden ring behind the outline that
	# breathes while the cell is selected.
	var halo_style := StyleBoxFlat.new()
	halo_style.bg_color = Color(0, 0, 0, 0)
	halo_style.set_border_width_all(5)
	halo_style.border_color = Color(1.0, 0.88, 0.35, 0.30)
	halo_style.set_corner_radius_all(8)
	_halo = Panel.new()
	_halo.add_theme_stylebox_override("panel", halo_style)
	_halo.size = Vector2(CELL_SIZE + 12, CELL_SIZE + 12)
	_halo.position = Vector2(-6, -6)
	_halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_halo.visible = false
	_halo.z_as_relative = false
	_halo.z_index = 114

	add_child(_z_rect)
	add_child(_a_rect)
	add_child(_b_rect)
	add_child(_c_rect)
	add_child(_halo)
	add_child(_outline)


func show_outline(v: bool) -> void:
	_outline.visible = v
	if _halo:
		_halo.visible = v
	if v:
		_start_pulse()
	else:
		_stop_pulse()


func is_empty() -> bool:
	return a_id == 0 and b_id == 0 and c_id == 0


func get_elements() -> Dictionary:
	return {"a": a_id, "b": b_id, "c": c_id}


func remove_element(layer: String) -> void:
	var rect: TextureRect = null
	match layer:
		"a":
			if a_id == 0:
				return
			rect = _a_rect
			a_id = 0
		"b":
			if b_id == 0:
				return
			rect = _b_rect
			b_id = 0
		"c":
			if c_id == 0:
				return
			rect = _c_rect
			c_id = 0
	if rect:
		_spin_out(rect)


func _spin_out(rect: TextureRect) -> void:
	rect.pivot_offset = Vector2(CELL_SIZE * 0.5, CELL_SIZE * 0.5)
	play_sparkle(8, 140.0, Color(1.0, 0.95, 0.75))
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(rect, "rotation_degrees", 180.0, 0.5) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(rect, "modulate:a", 0.0, 0.44)
	tw.tween_property(rect, "scale", Vector2(0.55, 0.55), 0.5) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)


# Pixel spark burst at the cell centre — removal pops and combo milestones.
static var _spark_tex: ImageTexture = null

func play_sparkle(count: int = 12, speed: float = 170.0,
		color: Color = Color(1.0, 0.93, 0.6)) -> void:
	if _spark_tex == null:
		var img := Image.create(3, 3, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_spark_tex = ImageTexture.create_from_image(img)
	var fx := CPUParticles2D.new()
	fx.texture = _spark_tex
	fx.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	fx.position = Vector2(CELL_SIZE * 0.5, CELL_SIZE * 0.5)
	fx.one_shot = true
	fx.explosiveness = 1.0
	fx.amount = count
	fx.lifetime = 0.5
	fx.direction = Vector2.RIGHT
	fx.spread = 180.0
	fx.gravity = Vector2(0, 200)
	fx.initial_velocity_min = speed * 0.3
	fx.initial_velocity_max = speed
	fx.scale_amount_min = 1.0
	fx.scale_amount_max = 2.2
	fx.color = color
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0.95))
	ramp.set_color(1, Color(1, 1, 1, 0.0))
	fx.color_ramp = ramp
	fx.z_as_relative = false
	fx.z_index = 118
	add_child(fx)
	fx.emitting = true
	fx.finished.connect(fx.queue_free)


# ----- Border glints -----------------------------------------------------------

# Background coroutine: occasionally a tiny glint sparkles on the tile
# border — quiet rune-glint life across the board.
func _glint_loop(initial_delay: float) -> void:
	await get_tree().create_timer(initial_delay).timeout
	while is_instance_valid(self) and is_inside_tree():
		await get_tree().create_timer(randf_range(7.0, 16.0)).timeout
		if not is_instance_valid(self) or not is_inside_tree():
			break
		if randf() < 0.35 and not is_empty():
			_play_glint()


func _play_glint() -> void:
	var p := Polygon2D.new()
	var arm := 6.0
	var th := 2.0
	p.polygon = PackedVector2Array([
		Vector2(-th, -arm), Vector2(th, -arm), Vector2(th, -th), Vector2(arm, -th),
		Vector2(arm, th), Vector2(th, th), Vector2(th, arm), Vector2(-th, arm),
		Vector2(-th, th), Vector2(-arm, th), Vector2(-arm, -th), Vector2(-th, -th),
	])
	var along := randf_range(10.0, CELL_SIZE - 10.0)
	match randi() % 4:
		0: p.position = Vector2(along, 4.0)
		1: p.position = Vector2(along, CELL_SIZE - 4.0)
		2: p.position = Vector2(4.0, along)
		_: p.position = Vector2(CELL_SIZE - 4.0, along)
	p.color = Color(1.0, 0.97, 0.82, 0.0)
	p.scale = Vector2(0.4, 0.4)
	p.z_as_relative = false
	p.z_index = 117
	add_child(p)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(p, "color:a", 0.9, 0.14).set_ease(Tween.EASE_OUT)
	tw.tween_property(p, "scale", Vector2.ONE, 0.18) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_property(p, "color:a", 0.0, 0.35).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(p.queue_free)


# Called by Game during a reshuffle — updates ID and texture, resets visual state.
func set_element(layer: String, tex: Texture2D, val: int) -> void:
	match layer:
		"a":
			_spinning_a = false
			a_id = val
			_a_rect.texture = tex
			_a_rect.modulate.a = 1.0
			_a_rect.rotation_degrees = 0.0
			_a_rect.scale = Vector2.ONE
		"b":
			_spinning_b = false
			b_id = val
			_b_rect.texture = tex
			_b_rect.modulate.a = 1.0
			_b_rect.rotation_degrees = 0.0
			_b_rect.scale = Vector2.ONE
		"c":
			_spinning_c = false
			c_id = val
			_c_rect.texture = tex
			_c_rect.modulate.a = 1.0
			_c_rect.rotation_degrees = 0.0
			_c_rect.scale = Vector2.ONE


# ----- Entrance animation ----------------------------------------------------

# Bloom this cell into existence after `delay` seconds.
# Cells start invisible/tiny; all layers spin as they appear, like a flower
# opening.  The board's `_board_active` flag blocks taps until all cells finish.
func play_entrance(delay: float) -> void:
	# Z tile is always visible (the "board").  Only A/B/C bloom in.
	# Initial invisible state is set in setup(), so there is no flash.
	var tw := create_tween()
	tw.tween_interval(delay)
	tw.tween_callback(func():
		if not is_instance_valid(self):
			return
		var tw2 := create_tween()
		tw2.set_parallel(true)
		# A layer — largest shape, spins most lazily.
		tw2.tween_property(_a_rect, "modulate:a", 1.0, 0.5) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw2.tween_property(_a_rect, "scale", Vector2.ONE, 0.5) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw2.tween_property(_a_rect, "rotation_degrees", 360.0, 0.55) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		# B layer.
		tw2.tween_property(_b_rect, "modulate:a", 1.0, 0.5) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw2.tween_property(_b_rect, "scale", Vector2.ONE, 0.5) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw2.tween_property(_b_rect, "rotation_degrees", 360.0, 0.45) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		# C layer — smallest shape, snappiest spin.
		tw2.tween_property(_c_rect, "modulate:a", 1.0, 0.5) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw2.tween_property(_c_rect, "scale", Vector2.ONE, 0.5) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw2.tween_property(_c_rect, "rotation_degrees", 360.0, 0.35) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		# Reset rotations once the longest tweener (A at 0.55 s) finishes.
		tw2.set_parallel(false)
		tw2.tween_callback(func():
			if not is_instance_valid(self):
				return
			_a_rect.rotation_degrees = 0.0
			_b_rect.rotation_degrees = 0.0
			_c_rect.rotation_degrees = 0.0
		)
	)


# ----- Selection pulse -------------------------------------------------------

func _start_pulse() -> void:
	_stop_pulse()
	_pulse_tween = create_tween()
	_pulse_tween.set_loops()
	# Scale breathes while the halo glow fades against it — a living selection.
	_pulse_tween.tween_property(self, "scale", Vector2(1.06, 1.06), 0.4) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_pulse_tween.parallel().tween_property(_halo, "modulate:a", 0.45, 0.4) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_pulse_tween.chain().tween_property(self, "scale", Vector2.ONE, 0.4) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_pulse_tween.parallel().tween_property(_halo, "modulate:a", 1.0, 0.4) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _stop_pulse() -> void:
	if _pulse_tween != null:
		_pulse_tween.kill()
		_pulse_tween = null
	scale = Vector2.ONE
	if _halo:
		_halo.modulate.a = 1.0


# ----- Idle spin animation ---------------------------------------------------

# Background coroutine: waits a random interval then maybe triggers an idle
# spin, repeating forever until the node leaves the tree.
func _idle_loop(layer: String, initial_delay: float) -> void:
	await get_tree().create_timer(initial_delay).timeout
	while is_instance_valid(self) and is_inside_tree():
		await get_tree().create_timer(randf_range(5.0, 10.0)).timeout
		if not is_instance_valid(self) or not is_inside_tree():
			break
		if randf() < 0.08:
			_do_idle_spin(layer)


# Attempts a single lazy 360° spin on the given layer.  Uses tween_callback
# to reset state so there is no await and no lifecycle issues on node free.
func _do_idle_spin(layer: String) -> void:
	# Never spin a selected cell — it would fight with the outline visually.
	if _outline.visible:
		return

	var rect: TextureRect = null
	match layer:
		"a":
			if a_id == 0 or _spinning_a:
				return
			rect = _a_rect
			_spinning_a = true
		"b":
			if b_id == 0 or _spinning_b:
				return
			rect = _b_rect
			_spinning_b = true
		"c":
			if c_id == 0 or _spinning_c:
				return
			rect = _c_rect
			_spinning_c = true

	# A is the largest shape so it turns the most lazily; C the fastest.
	var duration: float
	match layer:
		"a": duration = randf_range(1.1, 1.5)
		"b": duration = randf_range(0.85, 1.15)
		"c": duration = randf_range(0.65, 0.9)

	rect.pivot_offset = Vector2(CELL_SIZE * 0.5, CELL_SIZE * 0.5)
	var tw := create_tween()
	# Use relative target so the spin works regardless of current rotation value.
	tw.tween_property(rect, "rotation_degrees", rect.rotation_degrees + 360.0, duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# Reset via callback — no await needed, safe on node free.
	tw.tween_callback(func():
		if is_instance_valid(rect):
			rect.rotation_degrees = fmod(rect.rotation_degrees, 360.0)
		match layer:
			"a": _spinning_a = false
			"b": _spinning_b = false
			"c": _spinning_c = false
	)


# ----- Input -----------------------------------------------------------------

func _make_layer(tex: Texture2D) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.size = Vector2(CELL_SIZE, CELL_SIZE)
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			tapped.emit(self)
