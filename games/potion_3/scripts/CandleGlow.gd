# CandleGlow.gd (potion_3) — the little shop candle on the counter.
# The glow is alchemical_sort's LampGlow: two additive halos breathing on noise,
# with an occasional gutter. Tapping the candle makes it flare and puff a few
# embers. This node's position is the candle sprite's top-left (kept on the
# 3-px art grid); FLAME is where the light comes from.
extends Node2D

const FRAMES := [
	preload("res://games/potion_3/assets/ui/candle_0.png"),
	preload("res://games/potion_3/assets/ui/candle_1.png"),
	preload("res://games/potion_3/assets/ui/candle_2.png"),
]
const FLAME := Vector2(16.5, 10.0)   # flame centre inside the 36×72 sprite

var _rng := RandomNumberGenerator.new()
var _noise := FastNoiseLite.new()
var _time := 0.0
var _sprite: Sprite2D
var _outer: Sprite2D
var _inner: Sprite2D
var _tap_heat := 0.0
var _tap_light := 0.0
var _gutter_wait := 0.0
var _gutter_age := 0.0
var _gutter_duration := 0.0
var _gutter_depth := 0.0
var _frame_wait := 0.0


func _ready() -> void:
	_rng.randomize()
	_noise.seed = _rng.randi()
	_noise.frequency = 1.0
	_gutter_wait = _rng.randf_range(4.0, 13.0)

	var halo_texture := _make_halo_texture()
	var glow_material := CanvasItemMaterial.new()
	glow_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	# Broad warm spill on the wall behind the candle, then a tighter core added
	# over the flame itself.
	_outer = _make_halo(halo_texture, glow_material, Vector2(2.6, 2.2))
	_outer.position = FLAME + Vector2(0, 9)

	_sprite = Sprite2D.new()
	_sprite.texture = FRAMES[0]
	_sprite.centered = false
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_sprite)

	_inner = _make_halo(halo_texture, glow_material, Vector2(0.6, 0.7))
	_inner.position = FLAME

	# Only the candle accepts input; ordinary GUI routing leaves the rest alone.
	# Kept narrow so it never reaches a dispenser crate on the counter.
	var tap_area := Control.new()
	tap_area.name = "CandleTapArea"
	tap_area.position = Vector2(-6, -18)
	tap_area.size = Vector2(48, 96)
	tap_area.mouse_filter = Control.MOUSE_FILTER_STOP
	tap_area.gui_input.connect(_on_candle_input.bind(tap_area))
	add_child(tap_area)
	_update_light(0.0)


func _on_candle_input(event: InputEvent, tap_area: Control) -> void:
	if not is_visible_in_tree():
		return
	var scene_root: Node = owner if owner != null else get_parent()
	var win_panel := scene_root.get_node_or_null("WinPanel") as Control
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
	tap_area.accept_event()
	_tap_heat = minf(_tap_heat + 0.65, 0.95)
	_frame_wait = 0.0
	_puff_embers()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	# Small integration steps keep the flicker stable through a dropped frame.
	var remaining := minf(delta, 0.25)
	while remaining > 0.0:
		var step := minf(remaining, 1.0 / 60.0)
		_time += step
		_update_light(step)
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
	_outer.modulate.a = 0.40 * warmth
	_inner.modulate.a = 0.62 * warmth
	_inner.scale = Vector2(0.6, 0.7) * (1.0 + (warmth - 1.0) * 0.12)

	# Flame frames: a lazy random flicker that quickens while the candle flares.
	_frame_wait -= delta
	if _frame_wait <= 0.0:
		var current := FRAMES.find(_sprite.texture)
		var next := (current + 1 + _rng.randi_range(0, 1)) % FRAMES.size()
		_sprite.texture = FRAMES[next]
		_frame_wait = _rng.randf_range(0.10, 0.24) / (1.0 + _tap_light * 3.0)


func _puff_embers() -> void:
	var fx := CPUParticles2D.new()
	var img := Image.create(3, 3, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	fx.texture = ImageTexture.create_from_image(img)
	fx.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	fx.position = FLAME
	fx.one_shot = true
	fx.explosiveness = 0.8
	fx.amount = 5
	fx.lifetime = 0.9
	fx.direction = Vector2.UP
	fx.spread = 28.0
	fx.gravity = Vector2(0, -20)
	fx.initial_velocity_min = 20.0
	fx.initial_velocity_max = 45.0
	fx.color = Color("efac28")
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 1))
	ramp.set_color(1, Color(1, 0.6, 0.3, 0))
	fx.color_ramp = ramp
	add_child(fx)
	fx.emitting = true
	fx.finished.connect(fx.queue_free)


func _make_halo_texture() -> Texture2D:
	var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in range(64):
		for x in range(64):
			var distance := Vector2(x - 31.5, y - 31.5).length() / 31.5
			var strength := pow(maxf(0.0, 1.0 - distance), 1.7)
			image.set_pixel(x, y, Color(1.0, 0.73, 0.25, strength))
	return ImageTexture.create_from_image(image)


func _make_halo(texture: Texture2D, glow_material: Material, halo_scale: Vector2) -> Sprite2D:
	var halo := Sprite2D.new()
	halo.texture = texture
	halo.scale = halo_scale
	halo.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	halo.material = glow_material
	add_child(halo)
	return halo
