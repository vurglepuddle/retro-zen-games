# CandleGlow.gd (potion_3) — the little shop candle on the counter.
# The glow is alchemical_sort's LampGlow: two additive halos breathing on noise,
# with an occasional gutter, and the same shy light mites hovering around the
# flame. Tapping the candle makes it flare, puffs a few embers and shoos the
# mites off into the dark; a few drift back once it has been quiet a while.
# Holding it pinches the flame out (a wisp of smoke, the mites leave, the
# crackle stops); a tap relights it. On a win it flares and the mites dance.
# This node's position is the candle sprite's top-left (kept on the 3-px art
# grid); FLAME is where the light comes from.
extends Node2D

## Lit or snuffed, shared by every candle: the menu and the game are one shop.
static var lit := true

## Light mites hovering around the flame.
@export var mites := true
## Where startled mites flee to, relative to the flame: up and out into the dark.
@export var shelter_left := Vector2(-84, -110)
@export var shelter_right := Vector2(76, -120)

const FRAMES := [
	preload("res://games/potion_3/assets/ui/candle_0.png"),
	preload("res://games/potion_3/assets/ui/candle_1.png"),
	preload("res://games/potion_3/assets/ui/candle_2.png"),
]
const UNLIT := preload("res://games/potion_3/assets/ui/candle_out.png")
const FLAME := Vector2(35.5, 10.0)   # flame centre inside the 69×69 sprite
const WICK := Vector2(37.5, 16.5)
const SNUFF_HOLD := 0.6              # seconds of holding that pinch the flame out
const LISTENERS := &"potion3_candle" # told candle_lit_changed(lit), e.g. Main's crackle
const CELEBRATE_GROUP := &"potion3_celebrate"
# Optional: drop these files in and they play.
const SNUFF_SOUND := "res://games/potion_3/assets/sfx/candle_snuff.mp3"
const LIGHT_SOUND := "res://games/potion_3/assets/sfx/candle_light.mp3"
const CANDLE_SFX_DB := -10.0   # both recordings are loud next to the shop's other sounds

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
var _bugs: Array[Bug] = []
var _shown_lit := true
var _flame := 1.0          # 0 = out, 1 = burning; eased so the light fades rather than blinks
var _holding := false
var _hold_time := 0.0
var _sfx_snuff: AudioStreamPlayer
var _sfx_light: AudioStreamPlayer

enum Flight { HOVER, FLEE, HIDDEN, RETURN, DANCE }

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
	var orbit := 0.0


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

	if mites:
		var bug_texture := _make_bug_texture()
		# Homes hug the candle: a little above the flame and a little below it,
		# beside the wax, never far down the counter.
		for home in [Vector2(-30, -24), Vector2(27, -32), Vector2(-8, -46), Vector2(33, 13), Vector2(-34, 17)]:
			_add_bug(FLAME + home, halo_texture, bug_texture, glow_material)
		_choose_group()
		for bug in _bugs:
			if not bug.wants_return:
				bug.state = Flight.HIDDEN
				bug.visibility = 0.0
				bug.node.position = bug.shelter
			_update_bug(bug, 0.0)

	# Only the candle accepts input; ordinary GUI routing leaves the rest alone.
	# Kept narrow so it never reaches a dispenser crate on the counter.
	var tap_area := Control.new()
	tap_area.name = "CandleTapArea"
	tap_area.position = Vector2(-6, -18)
	tap_area.size = Vector2(48, 96)
	tap_area.mouse_filter = Control.MOUSE_FILTER_STOP
	tap_area.gui_input.connect(_on_candle_input.bind(tap_area))
	add_child(tap_area)
	add_to_group(CELEBRATE_GROUP)
	_sfx_snuff = _optional_player(SNUFF_SOUND)
	_sfx_light = _optional_player(LIGHT_SOUND)
	_apply_lit(false)
	_update_light(0.0)


func _optional_player(path: String) -> AudioStreamPlayer:
	if not ResourceLoader.exists(path):
		return null
	var player := AudioStreamPlayer.new()
	player.stream = load(path)
	player.volume_db = CANDLE_SFX_DB
	add_child(player)
	return player


func _on_candle_input(event: InputEvent, tap_area: Control) -> void:
	if not is_visible_in_tree():
		return
	var scene_root: Node = owner if owner != null else get_parent()
	var win_panel := scene_root.get_node_or_null("WinPanel") as Control
	if win_panel != null and win_panel.visible:
		return
	# Godot can synthesize a mouse event from a touch: handle the original once.
	var pressed := false
	if event is InputEventMouseButton:
		if event.device == InputEvent.DEVICE_ID_EMULATION or event.button_index != MOUSE_BUTTON_LEFT:
			return
		pressed = event.pressed
	elif event is InputEventScreenTouch:
		pressed = event.pressed
	else:
		return
	tap_area.accept_event()
	if pressed:
		if not lit:
			relight()
			return
		# Held long enough, the fingers pinch the flame out (see _process).
		_holding = true
		_hold_time = 0.0
	elif _holding:
		_holding = false
		_flare()


func _flare() -> void:
	_tap_heat = minf(_tap_heat + 0.65, 0.95)
	_frame_wait = 0.0
	_puff_embers()
	_shoo()


func snuff() -> void:
	if not lit:
		return
	lit = false
	_apply_lit(true)
	get_tree().call_group(LISTENERS, "candle_lit_changed", false)


func relight() -> void:
	if lit:
		return
	lit = true
	_apply_lit(true)
	get_tree().call_group(LISTENERS, "candle_lit_changed", true)


func _apply_lit(animated: bool) -> void:
	_shown_lit = lit
	_holding = false
	if not lit:
		_sprite.texture = UNLIT
		if not animated:
			_flame = 0.0
			for bug in _bugs:
				_hide_bug(bug)
			return
		_puff_smoke()
		if _sfx_snuff:
			_sfx_snuff.play()
		# No light, nothing to dance around: every mite leaves and stays away.
		_shoo()
		for bug in _bugs:
			bug.wants_return = false
		return
	_sprite.texture = FRAMES[0]
	_frame_wait = 0.0
	if not animated:
		_flame = 1.0
		return
	_flame = 0.15
	_tap_heat = 0.9
	_puff_embers()
	if _sfx_light:
		_sfx_light.play()
	# The light draws a few of them back after a moment.
	_choose_group()
	for bug in _bugs:
		bug.quiet_left = _rng.randf_range(2.5, 6.0)


## The game was won: flare up and set the mites dancing round the flame.
func celebrate() -> void:
	if not is_visible_in_tree():
		return
	if not lit:
		relight()
	_tap_heat = 0.95
	_frame_wait = 0.0
	_puff_embers(9)
	for i in _bugs.size():
		var bug := _bugs[i]
		bug.state = Flight.DANCE
		bug.age = 0.0
		bug.duration = 2.6
		bug.start = bug.node.position
		bug.start_visibility = bug.visibility
		bug.orbit = TAU * i / _bugs.size()
		bug.wants_return = true


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	# Small integration steps keep the flicker stable through a dropped frame.
	var remaining := minf(delta, 0.25)
	while remaining > 0.0:
		var step := minf(remaining, 1.0 / 60.0)
		_time += step
		_update_light(step)
		for bug in _bugs:
			_update_bug(bug, step)
		remaining -= step
	# The other candle (menu or game) may have been snuffed or relit meanwhile.
	if _shown_lit != lit:
		_apply_lit(false)
	if _holding:
		_hold_time += delta
		if _hold_time >= SNUFF_HOLD:
			snuff()


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
	_flame = move_toward(_flame, 1.0 if lit else 0.0, delta * (2.5 if lit else 5.0))
	var warmth := 1.0 + 0.16 * _noise.get_noise_1d(_time * 0.55) + 0.065 * _noise.get_noise_1d(_time * 5.3 + 100.0)
	warmth = warmth - gutter + _tap_light
	# Pinching: the light shrinks under the fingers before it goes out.
	var pinch := smoothstep(0.08, SNUFF_HOLD, _hold_time) if _holding else 0.0
	warmth *= _flame * (1.0 - 0.65 * pinch)
	_outer.modulate.a = 0.40 * warmth
	_inner.modulate.a = 0.62 * warmth
	_inner.scale = Vector2(0.6, 0.7) * (1.0 + (warmth - 1.0) * 0.12)

	# Flame frames: a lazy random flicker that quickens while the candle flares
	# or is being pinched.
	if not lit:
		return
	_frame_wait -= delta * (1.0 + pinch * 3.0)
	if _frame_wait <= 0.0:
		var current := FRAMES.find(_sprite.texture)
		var next := (current + 1 + _rng.randi_range(0, 1)) % FRAMES.size()
		_sprite.texture = FRAMES[next]
		_frame_wait = _rng.randf_range(0.10, 0.24) / (1.0 + _tap_light * 3.0)


func _puff_smoke() -> void:
	# A thin grey wisp curling up off the wick.
	var fx := CPUParticles2D.new()
	var img := Image.create(3, 3, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	fx.texture = ImageTexture.create_from_image(img)
	fx.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	fx.position = WICK + Vector2(0, -3)
	fx.one_shot = true
	fx.explosiveness = 0.1
	fx.amount = 8
	fx.lifetime = 1.8
	fx.direction = Vector2.UP
	fx.spread = 8.0
	fx.gravity = Vector2(4, -10)
	fx.initial_velocity_min = 9.0
	fx.initial_velocity_max = 16.0
	fx.damping_min = 2.0
	fx.damping_max = 4.0
	fx.color = Color("927e6a")
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0.85))
	ramp.set_color(1, Color(0.7, 0.6, 0.55, 0))
	fx.color_ramp = ramp
	add_child(fx)
	fx.emitting = true
	fx.finished.connect(fx.queue_free)


func _puff_embers(amount := 5) -> void:
	var fx := CPUParticles2D.new()
	var img := Image.create(3, 3, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	fx.texture = ImageTexture.create_from_image(img)
	fx.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	fx.position = FLAME
	fx.one_shot = true
	fx.explosiveness = 0.8
	fx.amount = amount
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


# ---- Light mites (lifted from alchemical_sort/scripts/LampGlow.gd) ------------
# Same flight model; only the hover range is tighter, since a candle is small.

func _shoo() -> void:
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


func _hide_bug(bug: Bug) -> void:
	bug.state = Flight.HIDDEN
	bug.visibility = 0.0
	bug.wants_return = false
	bug.node.position = bug.shelter
	bug.node.modulate.a = 0.0


func _choose_group() -> void:
	if _bugs.is_empty():
		return
	var candidates := _bugs.duplicate()
	for bug in _bugs:
		bug.wants_return = false
	for index in range(_rng.randi_range(1, _bugs.size())):
		var pick := _rng.randi_range(0, candidates.size() - 1)
		candidates[pick].wants_return = true
		candidates.remove_at(pick)


func _make_bug_texture() -> Texture2D:
	var image := Image.create(5, 3, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	image.set_pixel(0, 0, Color(1.0, 0.88, 0.49, 0.45))
	image.set_pixel(4, 0, Color(1.0, 0.88, 0.49, 0.45))
	image.set_pixel(1, 1, Color(1.0, 0.78, 0.29, 0.8))
	image.set_pixel(2, 1, Color(1.0, 0.97, 0.69))
	image.set_pixel(3, 1, Color(1.0, 0.78, 0.29, 0.8))
	return ImageTexture.create_from_image(image)


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
	flight.shelter = FLAME + (shelter_left if home.x < FLAME.x else shelter_right)
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
				bug.target = bug.home + Vector2(_rng.randf_range(-15.0, 15.0), _rng.randf_range(-11.0, 11.0))
				bug.course_wait = _rng.randf_range(0.7, 2.6)
			var drift := Vector2(_noise.get_noise_1d(_time * 1.7 + bug.phase), _noise.get_noise_1d(_time * 2.1 + bug.phase + 70.0))
			var desired := ((bug.target - bug.node.position) * 0.85 + drift * 9.0).limit_length(15.0)
			bug.velocity = bug.velocity.lerp(desired, 1.0 - exp(-2.8 * delta))
			bug.node.position += bug.velocity * delta
		Flight.FLEE:
			var progress := clampf(bug.age / bug.duration, 0.0, 1.0)
			var travel := 1.0 - pow(1.0 - progress, 2.0)
			bug.node.position = _curve(bug.start, bug.bend, bug.shelter, travel)
			bug.visibility = bug.start_visibility * (1.0 - smoothstep(0.2, 0.95, progress))
			if progress >= 1.0:
				bug.state = Flight.HIDDEN
		Flight.DANCE:
			# A ring round the flame, breathing in and out, drifting in from
			# wherever each mite was (or from its hiding place).
			var progress := clampf(bug.age / bug.duration, 0.0, 1.0)
			var angle := bug.orbit + bug.age * 2.8
			var radius := 30.0 + 6.0 * sin(bug.age * 3.1 + bug.orbit * 2.0)
			var ring := FLAME + Vector2(cos(angle), sin(angle) * 0.55) * radius
			bug.node.position = bug.start.lerp(ring, smoothstep(0.0, 0.35, progress))
			bug.visibility = minf(1.0, bug.start_visibility + bug.age * 2.5)
			if progress >= 1.0:
				bug.state = Flight.HOVER
				bug.velocity = Vector2.ZERO
				bug.course_wait = 0.0
		Flight.HIDDEN:
			if bug.wants_return and bug.quiet_left <= 0.0 and lit:
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
