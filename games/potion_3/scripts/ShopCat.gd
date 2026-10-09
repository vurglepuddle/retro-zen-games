# ShopCat.gd (potion_3) — the ginger cat asleep on the shop counter.
# Sheet: assets/ui/cat.png from art_src/potion_3/cat.aseprite — 7 frames side
# by side: sleep, breath, ear, peek, tail, purr_a, purr_b. The frame size is
# read from the sheet, and the node keeps its bottom edge (the counter) where
# the scene puts it, so the art can be re-exported at any size.
# It breathes, and now and then flicks an ear or its tail. A tap twitches an
# ear; a second tap and it peeks at you with one eye. Stroke it (drag along
# it) and it purrs: happy squint, quick purring breaths, little hearts, and on
# a phone a soft purr you can feel.
extends Control

const SHEET := preload("res://games/potion_3/assets/ui/cat.png")
const HEAD := Vector2(0.77, 0.07)   # where hearts rise from (above the ears), as a fraction of the frame
const ART_PX := 3
# Optional: drop these files in and they play.
const PURR_SOUND := "res://games/potion_3/assets/sfx/cat_purr.mp3"
const MRRP_SOUND := "res://games/potion_3/assets/sfx/cat_mrrp.mp3"
const LOOP_SILENT_DB := -40.0
const PURR_DB := -6.0

enum Pose { SLEEP, BREATH, EAR, PEEK, TAIL, PURR_A, PURR_B }

var _rng := RandomNumberGenerator.new()
var _frames: Array[AtlasTexture] = []
var _frame_size := Vector2.ZERO
var _sprite: TextureRect
var _heart: ImageTexture
var _inhaled := false
var _breath_wait := 0.0
var _accent_wait := 0.0
var _pose := Pose.SLEEP     # a short pose (ear, tail, peek) shown over the breathing
var _pose_left := 0.0
var _purr_left := 0.0       # seconds of purring still to go
var _purr_beat := 0.0
var _purr_high := false
var _heart_wait := 0.0
var _pressing := false
var _press_pos := Vector2.ZERO
var _last_pos := Vector2.ZERO
var _stroked := 0.0         # px the finger has travelled this press
var _poke_times: Array = []
var _purr_player: AudioStreamPlayer
var _purr_tween: Tween
var _mrrp_player: AudioStreamPlayer


func _ready() -> void:
	_rng.randomize()
	_frame_size = Vector2(SHEET.get_width() / float(Pose.size()), SHEET.get_height())
	# Stand on the same spot of the counter whatever size the art is.
	var bottom := position.y + size.y
	custom_minimum_size = _frame_size
	size = _frame_size
	position.y = bottom - _frame_size.y
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for i in Pose.size():
		var frame := AtlasTexture.new()
		frame.atlas = SHEET
		frame.region = Rect2(Vector2(i * _frame_size.x, 0), _frame_size)
		_frames.append(frame)
	_sprite = TextureRect.new()
	_sprite.texture = _frames[Pose.SLEEP]
	_sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_sprite)
	_heart = _make_heart()
	_breath_wait = _rng.randf_range(0.5, 2.0)
	_accent_wait = _rng.randf_range(4.0, 10.0)
	if ResourceLoader.exists(PURR_SOUND):
		var stream := load(PURR_SOUND) as AudioStream
		if stream is AudioStreamMP3:
			(stream as AudioStreamMP3).loop = true
		_purr_player = AudioStreamPlayer.new()
		_purr_player.stream = stream
		_purr_player.volume_db = LOOP_SILENT_DB
		add_child(_purr_player)
	if ResourceLoader.exists(MRRP_SOUND):
		_mrrp_player = AudioStreamPlayer.new()
		_mrrp_player.stream = load(MRRP_SOUND)
		add_child(_mrrp_player)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	delta = minf(delta, 0.1)
	if _purr_left > 0.0:
		_tick_purr(delta)
	else:
		_tick_sleep(delta)


func _tick_sleep(delta: float) -> void:
	# Slow breathing: a long rest breathed out, a shorter breath in.
	_breath_wait -= delta
	if _breath_wait <= 0.0:
		_inhaled = not _inhaled
		_breath_wait = _rng.randf_range(0.9, 1.2) if _inhaled else _rng.randf_range(1.5, 2.3)
	_accent_wait -= delta
	if _accent_wait <= 0.0 and _pose_left <= 0.0:
		_accent_wait = _rng.randf_range(5.0, 14.0)
		var roll := _rng.randf()
		if roll < 0.55:
			_strike(Pose.EAR, 0.18)
		elif roll < 0.93:
			_strike(Pose.TAIL, 0.45)
		else:
			_strike(Pose.PEEK, 1.1)   # rarely, it checks on the shop by itself
	if _pose_left > 0.0:
		_pose_left -= delta
		_show(_pose)
	else:
		_show(Pose.BREATH if _inhaled else Pose.SLEEP)


func _tick_purr(delta: float) -> void:
	# Purring: quick little breaths in the happy pose; keeps going a moment
	# after the stroking stops.
	if not _pressing:
		_purr_left -= delta
		if _purr_left <= 0.0:
			_end_purr()
			return
	_purr_beat -= delta
	if _purr_beat <= 0.0:
		_purr_high = not _purr_high
		_purr_beat = _rng.randf_range(0.13, 0.19)
		if _pressing and _purr_high:
			Haptics.pulse(Haptics.TICK, 240)   # you can feel it purr
	_show(Pose.PURR_B if _purr_high else Pose.PURR_A)
	_heart_wait -= delta
	if _pressing and _heart_wait <= 0.0:
		_heart_wait = _rng.randf_range(0.45, 0.7)
		_float_heart()


func _strike(pose: Pose, seconds: float) -> void:
	_pose = pose
	_pose_left = seconds


func _show(pose: Pose) -> void:
	_sprite.texture = _frames[pose]


# ---- Touch -------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	# Godot can synthesize a mouse event from a touch: handle the original once.
	if event is InputEventMouseButton:
		if event.device == InputEvent.DEVICE_ID_EMULATION or event.button_index != MOUSE_BUTTON_LEFT:
			return
		_on_press(event.pressed, event.position)
	elif event is InputEventScreenTouch:
		_on_press(event.pressed, event.position)
	elif event is InputEventMouseMotion:
		if event.device != InputEvent.DEVICE_ID_EMULATION and _pressing:
			_on_stroke(event.position)
	elif event is InputEventScreenDrag:
		if _pressing:
			_on_stroke(event.position)
	else:
		return
	accept_event()


func _on_press(pressed: bool, pos: Vector2) -> void:
	if pressed:
		_pressing = true
		_press_pos = pos
		_last_pos = pos
		_stroked = 0.0
		return
	_pressing = false
	if _stroked < 10.0:
		_on_poke()


func _on_stroke(pos: Vector2) -> void:
	_stroked += pos.distance_to(_last_pos)
	_last_pos = pos
	if _stroked < 10.0:
		return
	if _purr_left <= 0.0:
		_start_purr()
	_purr_left = 1.8


func _on_poke() -> void:
	if _purr_left > 0.0:
		_float_heart()   # still purring: a tap is just more love
		return
	var now := Time.get_ticks_msec() / 1000.0
	_poke_times.append(now)
	_poke_times = _poke_times.filter(func(t: float) -> bool: return now - t < 2.5)
	Haptics.pulse(Haptics.TICK)
	if _mrrp_player:
		_mrrp_player.pitch_scale = _rng.randf_range(0.95, 1.1)
		_mrrp_player.play()
	if _poke_times.size() >= 2:
		_poke_times.clear()
		_strike(Pose.PEEK, 1.4)   # one eye opens: "...yes?"
	else:
		_strike(Pose.EAR, 0.22)


func _start_purr() -> void:
	_pose_left = 0.0
	_purr_beat = 0.0
	_heart_wait = 0.15
	if _purr_player:
		if _purr_tween and _purr_tween.is_valid():
			_purr_tween.kill()
		if not _purr_player.playing:
			_purr_player.volume_db = LOOP_SILENT_DB
			_purr_player.play()
		_purr_tween = create_tween()
		_purr_tween.tween_property(_purr_player, "volume_db", PURR_DB, 0.4)


func _end_purr() -> void:
	_purr_left = 0.0
	_inhaled = false
	_breath_wait = _rng.randf_range(1.0, 2.0)
	if _purr_player and _purr_player.playing:
		if _purr_tween and _purr_tween.is_valid():
			_purr_tween.kill()
		_purr_tween = create_tween()
		_purr_tween.tween_property(_purr_player, "volume_db", LOOP_SILENT_DB, 0.8)
		_purr_tween.tween_callback(_purr_player.stop)


# ---- Hearts ------------------------------------------------------------------------

func _float_heart() -> void:
	var heart := TextureRect.new()
	heart.texture = _heart
	heart.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heart.size = _heart.get_size()
	var start := HEAD * _frame_size + Vector2(_rng.randf_range(-18.0, 9.0), -heart.size.y * 0.5)
	heart.position = start.snapped(Vector2(ART_PX, ART_PX))
	add_child(heart)
	var drift := _rng.randf_range(-12.0, 12.0)
	var tw := heart.create_tween().set_parallel()
	tw.tween_property(heart, "position:y", heart.position.y - 45.0, 1.2) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(heart, "position:x", heart.position.x + drift, 1.2)
	tw.tween_property(heart, "modulate:a", 0.0, 0.5).set_delay(0.7)
	tw.chain().tween_callback(heart.queue_free)


func _make_heart() -> ImageTexture:
	# 7x6 art px on the 3 px grid, from the potion_3 palette.
	var rows := [".XX.XX.", "XHXXXXX", "XXXXXXX", ".XXXXX.", "..XXX..", "...X..."]
	var red := Color8(239, 58, 12)
	var shine := Color8(239, 183, 117)
	var image := Image.create(7 * ART_PX, rows.size() * ART_PX, false, Image.FORMAT_RGBA8)
	for y in rows.size():
		for x in rows[y].length():
			var ch: String = rows[y][x]
			if ch == ".":
				continue
			image.fill_rect(Rect2i(x * ART_PX, y * ART_PX, ART_PX, ART_PX), shine if ch == "H" else red)
	return ImageTexture.create_from_image(image)
