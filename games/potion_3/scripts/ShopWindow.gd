# ShopWindow.gd (potion_3) — the night window in the shop menu.
# The art (art_src/potion_3/window.aseprite) is split by gen/split_window.py so
# that nothing in it moves in lockstep:
#   window_base.png     the frame, town and sky, with blinking bits taken out
#   window_moon_N.png   moon glow states; the glow breathes slowly
#   window_water_N.png  water states; the water drifts back and forth on random holds
#   code                four blinking stars, two "+" stars, town lights, shooting stars
#   owl.png             now and then an owl flaps past (art_src/potion_3/owl.aseprite)
# Tapping the glass knocks on it: the stars wink, someone in town may light a
# candle, and now and then a shooting star (or the owl) goes by.
# All coordinates are art pixels (1 art px = 3 game px) inside the 68×83 window.
extends Control

const ART_PX := 3
const BASE := preload("res://games/potion_3/assets/ui/window_base.png")
const MOON := [
	preload("res://games/potion_3/assets/ui/window_moon_1.png"),
	preload("res://games/potion_3/assets/ui/window_moon_2.png"),
]
const WATER := [
	preload("res://games/potion_3/assets/ui/window_water_1.png"),
	preload("res://games/potion_3/assets/ui/window_water_2.png"),
]
const KNOCK := preload("res://games/potion_3/assets/sfx/Window_Tapping.mp3")
const OWL := preload("res://games/potion_3/assets/ui/owl.png")   # 3 frames: up, mid, down
const OWL_SIZE := Vector2i(19, 10)
# [frame, seconds]: two wingbeats, then a glide on spread wings.
const OWL_BEATS := [[0, 0.09], [1, 0.06], [2, 0.09], [1, 0.06], [0, 0.09], [1, 0.06], [2, 0.09], [1, 0.42]]
# Colours that are outside (sky, moon, stars), as opposed to the window's wood.
const GLASS_COLOURS := ["080c3f", "24187c", "384cbc", "efd8a1", "efb775", "e4b87b", "efd29d"]
const TRANSOM_Y := 40   # the owl keeps to the upper panes

const CREAM := Color8(239, 216, 161)
const TAN := Color8(239, 183, 117)
const BLUE := Color8(56, 76, 188)
const VIOLET := Color8(36, 24, 124)
const NIGHT := Color8(8, 12, 63)
const LAMP := Color8(171, 92, 28)
const LAMP_LOW := Color8(114, 65, 19)

# Printed by split_window.py: position, sky colour behind it, its own colour.
const BLINK_STARS := [
	[Vector2i(39, 10), NIGHT, TAN],
	[Vector2i(27, 13), NIGHT, CREAM],
	[Vector2i(13, 24), VIOLET, CREAM],
	[Vector2i(28, 28), VIOLET, TAN],
]
const CROSS_STARS := [Vector2i(20, 20), Vector2i(52, 31)]
# One entry per lit window in town.
const CITY_LIGHTS := [
	[Vector2i(50, 50)],
	[Vector2i(23, 56)],
	[Vector2i(42, 56)],
	[Vector2i(52, 56)],
	[Vector2i(47, 57), Vector2i(48, 56), Vector2i(49, 57)],
	[Vector2i(23, 61)],
	[Vector2i(29, 62)],
	[Vector2i(11, 63)],
	[Vector2i(25, 63), Vector2i(26, 63)],
]
const GLASS := Rect2(6, 6, 56, 72)

enum Cross { CORE, TALL, WIDE, FULL }
enum Lamp { OFF, LOW, LIT }

var _rng := RandomNumberGenerator.new()
var _moon: TextureRect
var _water: TextureRect
var _moon_state := 0
var _moon_wait := 0.0
var _water_state := 0
var _water_dir := 1
var _water_wait := 0.0
var _stars: Array[Dictionary] = []
var _crosses: Array[Dictionary] = []
var _lamps: Array[Dictionary] = []
var _meteor_px: Array[ColorRect] = []
var _meteor_trail: Array[Vector2i] = []
var _meteor_pos := Vector2.ZERO
var _meteor_vel := Vector2.ZERO
var _meteor_life := 0.0
var _meteor_drain := 0.0
var _meteor_wait := 0.0
var _sky_mask: Image
var _knock: AudioStreamPlayer
var _knock_times: Array = []
var _clock := 0.0
var _glass := PackedByteArray()   # 1 where the upper panes show outside
var _owl_frames: Array[Image] = []
var _owl_canvas: Image
var _owl_texture: ImageTexture
var _owl_layer: TextureRect
var _owl_wait := 0.0
var _owl_flying := false
var _owl_pos := Vector2.ZERO        # art px, sprite top-left
var _owl_from_x := 0.0
var _owl_to_x := 0.0
var _owl_base_y := 0.0
var _owl_age := 0.0
var _owl_duration := 1.0
var _owl_beat := 0
var _owl_beat_left := 0.0
var _owl_drawn := Vector3i(-1000, -1000, -1)


func _ready() -> void:
	_rng.randomize()
	custom_minimum_size = Vector2(BASE.get_size())
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sky_mask = BASE.get_image()

	_add_layer(BASE)
	_moon = _add_layer(null)
	_water = _add_layer(null)
	_moon_wait = _rng.randf_range(1.0, 4.0)
	_water_wait = _rng.randf_range(0.3, 0.9)

	for star in BLINK_STARS:
		var faint: Color = BLUE if star[1] == VIOLET else VIOLET
		_stars.append({
			"rect": _add_pixel(star[0]),
			"ramp": [Color.TRANSPARENT, faint, star[2], CREAM],
			"level": 2, "target": 2, "wait": _rng.randf_range(0.2, 3.0),
		})
		_paint_star(_stars.back())
	for centre in CROSS_STARS:
		var arms: Array[ColorRect] = []
		for offset in [Vector2i.ZERO, Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			arms.append(_add_pixel(centre + offset))
		var cross := {"arms": arms, "shape": Cross.CORE, "wait": _rng.randf_range(0.5, 3.0)}
		_paint_cross(cross)
		_crosses.append(cross)
	for window in CITY_LIGHTS:
		var pixels: Array[ColorRect] = []
		for p in window:
			pixels.append(_add_pixel(p))
		var lamp := {"pixels": pixels, "state": Lamp.LIT, "wait": _rng.randf_range(2.0, 12.0), "flicker": 0.0}
		lamp.state = [Lamp.OFF, Lamp.LOW, Lamp.LIT, Lamp.LIT][_rng.randi_range(0, 3)]
		_paint_lamp(lamp)
		_lamps.append(lamp)
	_setup_owl()
	for i in 4:
		var rect := _add_pixel(Vector2i.ZERO)
		rect.visible = false
		_meteor_px.append(rect)
	_meteor_wait = _rng.randf_range(20.0, 45.0)

	_knock = AudioStreamPlayer.new()
	_knock.stream = KNOCK
	_knock.volume_db = -4.0
	add_child(_knock)


func _add_layer(texture: Texture2D) -> TextureRect:
	var layer := TextureRect.new()
	layer.texture = texture
	layer.size = size
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(layer)
	return layer


func _add_pixel(p: Vector2i) -> ColorRect:
	var rect := ColorRect.new()
	rect.position = Vector2(p * ART_PX)
	rect.size = Vector2(ART_PX, ART_PX)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rect)
	return rect


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	delta = minf(delta, 0.1)
	_clock += delta
	_tick_moon(delta)
	_tick_water(delta)
	for star in _stars:
		_tick_star(star, delta)
	for cross in _crosses:
		_tick_cross(cross, delta)
	for lamp in _lamps:
		_tick_lamp(lamp, delta)
	_tick_meteor(delta)
	_tick_owl(delta)


# ---- Moon & water: short random walks over the exported states -------------------

func _tick_moon(delta: float) -> void:
	_moon_wait -= delta
	if _moon_wait > 0.0:
		return
	# The glow breathes: rests dim or full, passes quickly through the middle.
	if _moon_state == 1:
		_moon_state = 0 if _rng.randf() < 0.5 else 2
	else:
		_moon_state = 1
	_moon.texture = null if _moon_state == 0 else MOON[_moon_state - 1]
	_moon_wait = _rng.randf_range(0.25, 0.6) if _moon_state == 1 else _rng.randf_range(1.6, 4.5)


func _tick_water(delta: float) -> void:
	_water_wait -= delta
	if _water_wait > 0.0:
		return
	# Back and forth, but it sometimes turns early and never keeps a beat.
	if _water_state + _water_dir < 0 or _water_state + _water_dir > WATER.size() or _rng.randf() < 0.25:
		_water_dir = -_water_dir
	_water_state = clampi(_water_state + _water_dir, 0, WATER.size())
	_water.texture = null if _water_state == 0 else WATER[_water_state - 1]
	_water_wait = _rng.randf_range(0.28, 0.85)


# ---- Stars ----------------------------------------------------------------------

func _tick_star(star: Dictionary, delta: float) -> void:
	star.wait -= delta
	if star.wait > 0.0:
		return
	if star.level != star.target:
		# Step through the ramp one colour at a time, like hand-drawn frames.
		star.level += signi(star.target - star.level)
		_paint_star(star)
		star.wait = _rng.randf_range(0.06, 0.12)
		return
	var roll := _rng.randf()
	match star.level:
		0: star.target = 2 if roll < 0.8 else 1
		1: star.target = 0 if roll < 0.4 else 2
		2: star.target = 3 if roll < 0.35 else (1 if roll < 0.7 else 0)
		3: star.target = 2
	star.wait = _rng.randf_range(1.5, 5.0) if star.level == 0 else _rng.randf_range(0.3, 2.6)


func _paint_star(star: Dictionary) -> void:
	var rect: ColorRect = star.rect
	rect.color = star.ramp[star.level]
	rect.visible = star.level > 0


func _tick_cross(cross: Dictionary, delta: float) -> void:
	cross.wait -= delta
	if cross.wait > 0.0:
		return
	var roll := _rng.randf()
	match cross.shape:
		Cross.CORE: cross.shape = Cross.TALL if roll < 0.5 else Cross.WIDE
		Cross.TALL, Cross.WIDE: cross.shape = Cross.FULL if roll < 0.55 else Cross.CORE
		Cross.FULL: cross.shape = [Cross.TALL, Cross.WIDE, Cross.CORE][_rng.randi_range(0, 2)]
	_paint_cross(cross)
	# Rests in its core shape; the sparkle itself is quick.
	cross.wait = _rng.randf_range(1.2, 4.0) if cross.shape == Cross.CORE else _rng.randf_range(0.12, 0.32)


func _paint_cross(cross: Dictionary) -> void:
	var arms: Array[ColorRect] = cross.arms   # centre, up, down, left, right
	var tall: bool = cross.shape == Cross.TALL or cross.shape == Cross.FULL
	var wide: bool = cross.shape == Cross.WIDE or cross.shape == Cross.FULL
	arms[0].color = TAN if cross.shape == Cross.FULL else CREAM
	arms[1].color = CREAM if tall else TAN
	arms[2].color = CREAM if tall else TAN
	arms[3].color = CREAM if wide else TAN
	arms[4].color = CREAM if wide else TAN


# ---- Town lights ----------------------------------------------------------------

func _tick_lamp(lamp: Dictionary, delta: float) -> void:
	if lamp.flicker > 0.0:
		lamp.flicker -= delta
		if lamp.flicker <= 0.0:
			_paint_lamp(lamp)
	lamp.wait -= delta
	if lamp.wait > 0.0:
		return
	var roll := _rng.randf()
	match lamp.state:
		Lamp.LIT:
			if roll < 0.3:
				# A draught catches the candle: a blink of the low colour.
				lamp.flicker = _rng.randf_range(0.08, 0.16)
				_paint_pixels(lamp, LAMP_LOW)
				lamp.wait = _rng.randf_range(2.0, 6.0)
				return
			lamp.state = Lamp.LOW if roll < 0.75 else Lamp.OFF
		Lamp.LOW:
			lamp.state = Lamp.LIT if roll < 0.65 else Lamp.OFF
		Lamp.OFF:
			lamp.state = Lamp.LIT if roll < 0.8 else Lamp.LOW
	_paint_lamp(lamp)
	lamp.wait = _rng.randf_range(4.0, 10.0) if lamp.state == Lamp.OFF else _rng.randf_range(3.0, 14.0)


func _paint_lamp(lamp: Dictionary) -> void:
	match lamp.state:
		Lamp.OFF: _paint_pixels(lamp, Color.TRANSPARENT)
		Lamp.LOW: _paint_pixels(lamp, LAMP_LOW)
		Lamp.LIT: _paint_pixels(lamp, LAMP)


func _paint_pixels(lamp: Dictionary, colour: Color) -> void:
	for rect: ColorRect in lamp.pixels:
		rect.color = colour
		rect.visible = colour.a > 0.0


# ---- Shooting stars --------------------------------------------------------------

func _tick_meteor(delta: float) -> void:
	_meteor_wait -= delta
	if _meteor_wait <= 0.0:
		_launch_meteor()
	if _meteor_life > 0.0:
		_meteor_life -= delta
		_meteor_pos += _meteor_vel * delta
		var cell := Vector2i(_meteor_pos.round())
		if _meteor_trail.is_empty() or cell != _meteor_trail[0]:
			_meteor_trail.push_front(cell)
			if _meteor_trail.size() > _meteor_px.size():
				_meteor_trail.pop_back()
	elif not _meteor_trail.is_empty():
		# Head burnt out: the tail catches up and fades behind it.
		_meteor_drain -= delta
		if _meteor_drain <= 0.0:
			_meteor_trail.pop_back()
			_meteor_drain = 0.035
	var colours := [CREAM, TAN, BLUE, VIOLET]
	for i in _meteor_px.size():
		var rect := _meteor_px[i]
		rect.visible = i < _meteor_trail.size() and _is_open_sky(_meteor_trail[i])
		if rect.visible:
			rect.position = Vector2(_meteor_trail[i] * ART_PX)
			rect.color = colours[i]


func _launch_meteor() -> void:
	_meteor_wait = _rng.randf_range(25.0, 60.0)
	if _meteor_life > 0.0 or not _meteor_trail.is_empty():
		return
	for attempt in 12:
		var start := Vector2i(_rng.randi_range(10, 57), _rng.randi_range(7, 13))
		if _is_open_sky(start):
			_meteor_pos = Vector2(start)
			var heading := Vector2(-2.0 if start.x > 33 or _rng.randf() < 0.5 else 2.0, 1.0)
			_meteor_vel = heading.normalized() * _rng.randf_range(42.0, 58.0)
			_meteor_life = _rng.randf_range(0.26, 0.40)
			_meteor_trail.clear()
			_meteor_drain = 0.0
			return


func _is_open_sky(p: Vector2i) -> bool:
	# Only the dark sky shows a meteor: it slips behind the frame, the
	# mullions, the moon and the horizon haze.
	if _sky_mask == null or p.x < 0 or p.y < 0 or p.x * ART_PX >= _sky_mask.get_width() or p.y * ART_PX >= _sky_mask.get_height():
		return false
	var c := _sky_mask.get_pixel(p.x * ART_PX + 1, p.y * ART_PX + 1)
	return c.is_equal_approx(NIGHT) or c.is_equal_approx(VIOLET)


# ---- Knocking on the glass ----------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	# Godot can synthesize a mouse event from a touch: handle the original once.
	var pos: Vector2
	if event is InputEventMouseButton:
		if event.device == InputEvent.DEVICE_ID_EMULATION or event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
			return
		pos = event.position
	elif event is InputEventScreenTouch:
		if not event.pressed:
			return
		pos = event.position
	else:
		return
	if not Rect2(GLASS.position * ART_PX, GLASS.size * ART_PX).has_point(pos):
		return
	accept_event()
	_knock.pitch_scale = _rng.randf_range(0.94, 1.08)
	_knock.play()
	Haptics.pulse(Haptics.TICK)

	# The stars wink back, one after another.
	for star in _stars:
		star.target = 3
		star.wait = _rng.randf_range(0.0, 0.3)
	for cross in _crosses:
		cross.wait = _rng.randf_range(0.0, 0.2)
	# Someone in town hears it and lights a candle.
	var dark := _lamps.filter(func(l: Dictionary) -> bool: return l.state != Lamp.LIT)
	if not dark.is_empty() and _rng.randf() < 0.5:
		var lamp: Dictionary = dark[_rng.randi_range(0, dark.size() - 1)]
		lamp.state = Lamp.LIT
		lamp.wait = _rng.randf_range(5.0, 12.0)
		_paint_lamp(lamp)
	# Every third knock in quick succession (or any knock, sometimes) wishes
	# a shooting star across.
	_knock_times.append(_clock)
	_knock_times = _knock_times.filter(func(t: float) -> bool: return _clock - t < 1.6)
	if _knock_times.size() >= 3 or _rng.randf() < 0.2:
		_knock_times.clear()
		_meteor_wait = 0.0
	elif _rng.randf() < 0.12:
		# Or the knock startles the owl off its perch.
		_owl_wait = 0.0


# ---- Owl ---------------------------------------------------------------------------
# Drawn at art resolution into a 68x83 image, only on glass pixels, so it slips
# behind the frame and mullions on every renderer (no clip_children needed).

func _setup_owl() -> void:
	var size_px := Vector2i(BASE.get_size()) / ART_PX
	_glass.resize(size_px.x * size_px.y)
	for y in mini(TRANSOM_Y, size_px.y):
		for x in size_px.x:
			var c := _sky_mask.get_pixel(x * ART_PX + 1, y * ART_PX + 1)
			if c.a > 0.5 and GLASS_COLOURS.has(c.to_html(false)):
				_glass[y * size_px.x + x] = 1
	var sheet := OWL.get_image()
	for i in 3:
		var frame := Image.create(OWL_SIZE.x, OWL_SIZE.y, false, Image.FORMAT_RGBA8)
		for y in OWL_SIZE.y:
			for x in OWL_SIZE.x:
				frame.set_pixel(x, y, sheet.get_pixel((i * OWL_SIZE.x + x) * ART_PX + 1, y * ART_PX + 1))
		_owl_frames.append(frame)
	_owl_canvas = Image.create(size_px.x, size_px.y, false, Image.FORMAT_RGBA8)
	_owl_texture = ImageTexture.create_from_image(_owl_canvas)
	_owl_layer = _add_layer(_owl_texture)
	_owl_layer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_owl_layer.size = size
	_owl_layer.visible = false
	_owl_wait = _rng.randf_range(15.0, 35.0)


func _tick_owl(delta: float) -> void:
	if not _owl_flying:
		_owl_wait -= delta
		if _owl_wait <= 0.0:
			_launch_owl()
		return
	_owl_age += delta
	var t := _owl_age / _owl_duration
	if t >= 1.0:
		_owl_flying = false
		_owl_layer.visible = false
		_owl_wait = _rng.randf_range(50.0, 120.0)
		return
	_owl_beat_left -= delta
	if _owl_beat_left <= 0.0:
		_owl_beat = (_owl_beat + 1) % OWL_BEATS.size()
		_owl_beat_left += OWL_BEATS[_owl_beat][1]
	var frame: int = OWL_BEATS[_owl_beat][0]
	# A shallow arc across the sky; each downstroke lifts it a pixel.
	_owl_pos.x = lerpf(_owl_from_x, _owl_to_x, t)
	_owl_pos.y = _owl_base_y - 3.0 * sin(t * PI) + (-1.0 if frame == 2 else 0.0)
	_draw_owl(Vector2i(_owl_pos.round()), frame)


func _launch_owl() -> void:
	_owl_wait = _rng.randf_range(50.0, 120.0)
	if _owl_flying:
		return
	var width := float(_owl_canvas.get_width())
	var rightward := _rng.randf() < 0.5
	_owl_from_x = -OWL_SIZE.x - 2.0 if rightward else width + 2.0
	_owl_to_x = width + 2.0 if rightward else -OWL_SIZE.x - 2.0
	_owl_base_y = _rng.randf_range(11.0, 19.0)
	_owl_duration = absf(_owl_to_x - _owl_from_x) / _rng.randf_range(48.0, 62.0)
	_owl_age = 0.0
	_owl_beat = 0
	_owl_beat_left = OWL_BEATS[0][1]
	_owl_flying = true
	_owl_drawn = Vector3i(-1000, -1000, -1)
	_owl_layer.visible = true


func _draw_owl(at: Vector2i, frame: int) -> void:
	var key := Vector3i(at.x, at.y, frame)
	if key == _owl_drawn:
		return
	_owl_drawn = key
	_owl_canvas.fill(Color.TRANSPARENT)
	var w := _owl_canvas.get_width()
	var h := _owl_canvas.get_height()
	var sprite := _owl_frames[frame]
	for y in OWL_SIZE.y:
		var cy := at.y + y
		if cy < 0 or cy >= h:
			continue
		for x in OWL_SIZE.x:
			var cx := at.x + x
			if cx < 0 or cx >= w or _glass[cy * w + cx] == 0:
				continue
			var c := sprite.get_pixel(x, y)
			if c.a > 0.5:
				_owl_canvas.set_pixel(cx, cy, c)
	_owl_texture.update(_owl_canvas)
