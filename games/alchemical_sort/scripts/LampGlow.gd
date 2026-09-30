extends Node2D

# Soft light over the lantern painted into alchbg2.png. This node's position
# marks the flame, so the whole effect can be moved in the scene Inspector.
var _rng := RandomNumberGenerator.new()
var _noise := FastNoiseLite.new()
var _time := 0.0
var _outer: Sprite2D
var _inner: Sprite2D
var _tap_area: Control
var _tap_heat := 0.0
var _tap_light := 0.0
var _gutter_wait := 0.0
var _gutter_age := 0.0
var _gutter_duration := 0.0
var _gutter_depth := 0.0
var _bugs: Array[Bug] = []

enum Flight { HOVER, FLEE, HIDDEN, RETURN }

class Bug:
	extends RefCounted
	var node: Node2D
	var home: Vector2
	var shelter: Vector2
	var velocity := Vector2.ZERO
	var target: Vector2
	var course_wait := 0.0
	var phase := 0.0
	var state := Flight.HOVER
	var quiet_left := 0.0
	var age := 0.0
	var duration := 1.0
	var start: Vector2
	var bend: Vector2
	var visibility := 1.0
	var start_visibility := 1.0
	var wants_return := false


func _ready() -> void:
	_rng.randomize()
	_noise.seed = _rng.randi()
	_noise.frequency = 1.0
	_gutter_wait = _rng.randf_range(4.0, 13.0)
	var halo_texture := _make_halo_texture()
	var glow_material := CanvasItemMaterial.new()
	glow_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD

	_outer = _make_halo(halo_texture, glow_material, Vector2(2.0, 1.7))
	_outer.position.y = 8.0
	_inner = _make_halo(halo_texture, glow_material, Vector2(0.85, 0.92))

	var bug_texture := _make_bug_texture()
	# A small reusable pool gives every new group its own size without popping
	# existing bugs out of view or accumulating nodes after repeated taps.
	for home in [Vector2(-43, 39), Vector2(42, 46), Vector2(-25, 67), Vector2(15, 78), Vector2(-61, 65)]:
		_add_bug(home, halo_texture, bug_texture, glow_material)
	_choose_group()
	for bug in _bugs:
		if not bug.wants_return:
			bug.state = Flight.HIDDEN
			bug.visibility = 0.0
			bug.node.position = bug.shelter
		_update_bug(bug, 0.0)

	# Only the painted lantern accepts input; ordinary GUI routing leaves
	# the board and Undo button alone.
	_tap_area = Control.new()
	_tap_area.name = "LampTapArea"
	_tap_area.position = Vector2(-29, -42)
	_tap_area.size = Vector2(58, 91)
	_tap_area.mouse_filter = Control.MOUSE_FILTER_STOP
	_tap_area.gui_input.connect(_on_lamp_input)
	add_child(_tap_area)
	_update_light(0.0)


func _on_lamp_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	var win_panel := get_parent().get_node_or_null("WinPanel") as Control
	if win_panel != null and win_panel.visible:
		return
	# Godot can synthesize a mouse event from a touch: handle the original once.
	if event is InputEventMouseButton:
		if event.device == InputEvent.DEVICE_ID_EMULATION or event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
			return
	elif event is InputEventScreenTouch:
		if not event.pressed:
			return
	else:
		return
	_tap_area.accept_event()
	_shoo()


func _shoo() -> void:
	_tap_heat = minf(_tap_heat + 0.65, 0.95)
	_choose_group()
	for bug in _bugs:
		# Every tap restarts the quiet period, even while already in cover.
		bug.quiet_left = _rng.randf_range(5.0, 10.0)
		if bug.state == Flight.HIDDEN or bug.state == Flight.FLEE:
			continue
		bug.state = Flight.FLEE
		bug.age = 0.0
		bug.duration = _rng.randf_range(0.65, 1.05)
		bug.start = bug.node.position
		bug.start_visibility = bug.visibility
		bug.bend = bug.start.lerp(bug.shelter, 0.5) + Vector2(0, -_rng.randf_range(12.0, 23.0))


func _choose_group() -> void:
	var candidates := _bugs.duplicate()
	for bug in _bugs:
		bug.wants_return = false
	for index in range(_rng.randi_range(1, 5)):
		var pick := _rng.randi_range(0, candidates.size() - 1)
		candidates[pick].wants_return = true
		candidates.remove_at(pick)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	# Small integration steps keep steering stable through a dropped frame.
	var remaining := minf(delta, 0.25)
	while remaining > 0.0:
		var step := minf(remaining, 1.0 / 60.0)
		_time += step
		_update_light(step)
		for bug in _bugs:
			_update_bug(bug, step)
		remaining -= step


func _update_light(delta: float) -> void:
	_gutter_wait -= delta
	if _gutter_wait <= 0.0:
		_gutter_age = 0.0
		_gutter_duration = _rng.randf_range(0.45, 1.1)
		_gutter_depth = _rng.randf_range(0.22, 0.46)
		_gutter_wait = _gutter_duration + _rng.randf_range(4.0, 13.0)
	_gutter_age += delta
	var gutter := 0.0
	if _gutter_age < _gutter_duration:
		var progress := _gutter_age / _gutter_duration
		# Quick sag, lingering recovery; no repeated on/off pulse.
		gutter = _gutter_depth * smoothstep(0.0, 0.14, progress) * (1.0 - smoothstep(0.18, 1.0, progress))
	_tap_heat *= exp(-3.8 * delta)
	_tap_light = lerpf(_tap_light, _tap_heat, 1.0 - exp(-22.0 * delta))
	var warmth := 1.0 + 0.16 * _noise.get_noise_1d(_time * 0.55) + 0.065 * _noise.get_noise_1d(_time * 5.3 + 100.0)
	warmth = warmth - gutter + _tap_light
	# Both halos belong to one flame. Keep the broad spill quieter than the core.
	_outer.modulate.a = 0.40 * warmth
	_inner.modulate.a = 0.62 * warmth
	_inner.scale = Vector2(0.85, 0.92) * (1.0 + (warmth - 1.0) * 0.07)


func _make_halo_texture() -> Texture2D:
	var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in range(64):
		for x in range(64):
			var distance := Vector2(x - 31.5, y - 31.5).length() / 31.5
			var strength := pow(maxf(0.0, 1.0 - distance), 1.7)
			image.set_pixel(x, y, Color(1.0, 0.73, 0.25, strength))
	return ImageTexture.create_from_image(image)


func _make_bug_texture() -> Texture2D:
	var image := Image.create(5, 3, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	image.set_pixel(0, 0, Color(1.0, 0.88, 0.49, 0.45))
	image.set_pixel(4, 0, Color(1.0, 0.88, 0.49, 0.45))
	image.set_pixel(1, 1, Color(1.0, 0.78, 0.29, 0.8))
	image.set_pixel(2, 1, Color(1.0, 0.97, 0.69))
	image.set_pixel(3, 1, Color(1.0, 0.78, 0.29, 0.8))
	return ImageTexture.create_from_image(image)


func _make_halo(texture: Texture2D, glow_material: Material, halo_scale: Vector2) -> Sprite2D:
	var halo := Sprite2D.new()
	halo.texture = texture
	halo.scale = halo_scale
	halo.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	halo.material = glow_material
	add_child(halo)
	return halo


func _add_bug(home: Vector2, halo_texture: Texture2D, bug_texture: Texture2D, glow_material: Material) -> void:
	var bug := Node2D.new()
	bug.position = home + Vector2(_rng.randf_range(-5.0, 5.0), _rng.randf_range(-5.0, 5.0))
	bug.modulate.a = _rng.randf_range(0.35, 0.8)
	add_child(bug)

	var halo := Sprite2D.new()
	halo.texture = halo_texture
	halo.scale = Vector2(0.48, 0.48)
	halo.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	halo.material = glow_material
	halo.modulate.a = 0.72
	bug.add_child(halo)

	var body := Sprite2D.new()
	body.texture = bug_texture
	body.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bug.add_child(body)

	var flight := Bug.new()
	flight.node = bug
	flight.home = home
	flight.shelter = Vector2(-78, 18) if home.x < 0 else Vector2(87, 89)
	flight.target = home
	flight.phase = _rng.randf_range(200.0, 2000.0)
	_bugs.append(flight)


func _update_bug(bug: Bug, delta: float) -> void:
	bug.quiet_left = maxf(0.0, bug.quiet_left - delta)
	bug.age += delta
	match bug.state:
		Flight.HOVER:
			bug.course_wait -= delta
			if bug.course_wait <= 0.0:
				bug.target = bug.home + Vector2(_rng.randf_range(-21.0, 21.0), _rng.randf_range(-15.0, 17.0))
				bug.course_wait = _rng.randf_range(0.7, 2.6)
			var drift := Vector2(_noise.get_noise_1d(_time * 1.7 + bug.phase), _noise.get_noise_1d(_time * 2.1 + bug.phase + 70.0))
			var desired := ((bug.target - bug.node.position) * 0.85 + drift * 11.0).limit_length(17.0)
			bug.velocity = bug.velocity.lerp(desired, 1.0 - exp(-2.8 * delta))
			bug.node.position += bug.velocity * delta
		Flight.FLEE:
			var progress := clampf(bug.age / bug.duration, 0.0, 1.0)
			var travel := 1.0 - pow(1.0 - progress, 2.0)
			bug.node.position = _curve(bug.start, bug.bend, bug.shelter, travel)
			bug.visibility = bug.start_visibility * (1.0 - smoothstep(0.2, 0.95, progress))
			if progress >= 1.0:
				bug.state = Flight.HIDDEN
		Flight.HIDDEN:
			if bug.wants_return and bug.quiet_left <= 0.0:
				bug.state = Flight.RETURN
				bug.age = 0.0
				bug.duration = _rng.randf_range(2.8, 4.2)
				bug.start = bug.node.position
				bug.target = bug.home + Vector2(_rng.randf_range(-8.0, 8.0), _rng.randf_range(-6.0, 6.0))
				bug.bend = bug.start.lerp(bug.target, 0.5) + Vector2(0, _rng.randf_range(8.0, 19.0))
		Flight.RETURN:
			var progress := clampf(bug.age / bug.duration, 0.0, 1.0)
			bug.node.position = _curve(bug.start, bug.bend, bug.target, smoothstep(0.0, 1.0, progress))
			bug.visibility = smoothstep(0.0, 0.8, progress)
			if progress >= 1.0:
				bug.state = Flight.HOVER
				bug.velocity = Vector2.ZERO
				bug.course_wait = 0.0
	# Independent, non-looping glow, multiplied by visibility so a hidden bug
	# cannot reappear because an old breathing tween is still running.
	var brightness := 0.66 + 0.30 * _noise.get_noise_1d(_time * 0.65 + bug.phase)
	bug.node.modulate.a = brightness * bug.visibility


func _curve(start: Vector2, bend: Vector2, finish: Vector2, weight: float) -> Vector2:
	return start.lerp(bend, weight).lerp(bend.lerp(finish, weight), weight)
