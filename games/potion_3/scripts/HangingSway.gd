# HangingSway.gd (potion_3) — poke something hanging in the shop and it swings.
# Goes on a TextureRect: the herb bundles on their nails, the title sign on its
# chains, the UNDO sign's strings. A damped spring drives hang_sway.gdshader's
# `sway`: a tap knocks the thing away from the finger, dragging pulls it along,
# and on release it swings back past upright and settles. Offsets are in art px
# (1 art px = 3 game px).
extends TextureRect

const SHADER := preload("res://games/potion_3/assets/hang_sway.gdshader")
const ART_PX := 3.0
const CELEBRATE_GROUP := &"potion3_celebrate"
const LOOP_SILENT_DB := -42.0

## The nail (or the top of the chains), in texture px.
@export var pivot := Vector2(36, 6)
## Texture px below the pivot where the sway is measured: the bundle's length,
## or the chains' length for a sign.
@export var reach := 150.0
## Chains: everything deeper than `reach` moves as one rigid board.
@export var rigid := false
## Soft bundles bend more toward the tip.
@export_range(0.0, 1.0) var droop := 0.0
## Seconds for one full swing there and back.
@export var period := 1.3
@export_range(0.0, 1.0) var damping := 0.12
## Art px at `reach`: how far a tap knocks it, and the furthest it ever leans.
@export var tap_kick := 3.0
@export var max_sway := 5.0
## Art px of slow drift at `reach` while nobody touches it (0 = hangs still).
@export var idle_sway := 0.0
## Moves sideways with the swing, e.g. the sign's lettering or the UNDO board.
@export var follower: Control
## Swing together with this one (same texture size): they share its material.
@export var linked: Array[TextureRect] = []
## False: this rect ignores touches (it can still be kicked from code).
@export var pokeable := true
## Another control whose taps knock this one on release (the UNDO button).
@export var poke_from: Control
## Gives a little shake when a game is won.
@export var celebrates := false

@export_group("Sounds")
@export var tap_sound: AudioStream
@export var tap_volume_db := 0.0
## Loops while a finger drags it.
@export var drag_loop: AudioStream
@export var drag_volume_db := -8.0
## Plays when let go after a drag.
@export var release_sound: AudioStream
@export var release_volume_db := 0.0

var _sway := 0.0
var _velocity := 0.0
var _pressing := false
var _dragging := false
var _grab := Vector2.ZERO
var _grab_sway := 0.0
var _hold_target := 0.0
var _time := 0.0
var _shown_sway := INF
var _follower_x := 0.0
var _rng := RandomNumberGenerator.new()
var _noise := FastNoiseLite.new()
var _material: ShaderMaterial
var _tap_player: AudioStreamPlayer
var _loop_player: AudioStreamPlayer
var _loop_tween: Tween
var _release_player: AudioStreamPlayer
var _last_sound_ms := -100000


func _ready() -> void:
	_rng.randomize()
	_noise.seed = _rng.randi()
	_noise.frequency = 1.0
	_time = _rng.randf_range(0.0, 100.0)
	mouse_filter = Control.MOUSE_FILTER_STOP if pokeable else Control.MOUSE_FILTER_IGNORE
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter("pivot_y", pivot.y)
	_material.set_shader_parameter("reach", reach)
	_material.set_shader_parameter("rigid", rigid)
	_material.set_shader_parameter("droop", droop)
	_material.set_shader_parameter("art_px", ART_PX)
	_material.set_shader_parameter("pad", ceilf(max_sway * 1.3 + 2.0) * ART_PX)
	material = _material
	for other in linked:
		other.material = _material
	if follower:
		_follower_x = follower.position.x
	if poke_from:
		poke_from.gui_input.connect(_on_poke_from_input)
	if celebrates:
		add_to_group(CELEBRATE_GROUP)
	_tap_player = _make_player(tap_sound, tap_volume_db)
	_release_player = _make_player(release_sound, release_volume_db)
	_loop_player = _make_player(drag_loop, LOOP_SILENT_DB)
	if drag_loop is AudioStreamMP3:
		(drag_loop as AudioStreamMP3).loop = true
	_apply()


func _make_player(stream: AudioStream, volume_db: float) -> AudioStreamPlayer:
	if stream == null:
		return null
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume_db
	add_child(player)
	return player


# ---- Input ----------------------------------------------------------------------

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
			_on_drag(event.position)
	elif event is InputEventScreenDrag:
		if _pressing:
			_on_drag(event.position)
	else:
		return
	accept_event()


func _on_press(pressed: bool, pos: Vector2) -> void:
	if not pressed:
		if _dragging:
			_end_drag_loop()
			# Let go: the chains clink as it swings back.
			if absf(_sway) >= 0.8:
				_play(_release_player, clampf(absf(_sway) / max_sway, 0.4, 1.0))
		_pressing = false
		_dragging = false
		return
	_pressing = true
	_grab = pos
	# Knocked away from the finger; a poke dead on the axis picks a side.
	var side := pos.x - (pivot.x + roundf(_sway * _shape(pos.y)) * ART_PX)
	var dir := -signf(side) if absf(side) > 6.0 else _random_side()
	kick(dir)
	_play(_tap_player)
	Haptics.pulse(Haptics.TICK)


func _on_drag(pos: Vector2) -> void:
	if not _dragging:
		if absf(pos.x - _grab.x) < 8.0:
			return
		# The finger has really moved: from now on it carries the bundle.
		_dragging = true
		_grab = pos
		_grab_sway = _sway
		_start_drag_loop()
	# Grabbing high up moves it further than grabbing the tip.
	var depth := maxf(_grab.y - pivot.y, reach * 0.35)
	var pull := (pos.x - _grab.x) / ART_PX * reach / depth
	_hold_target = clampf(_grab_sway + pull, -max_sway, max_sway)


func _on_poke_from_input(event: InputEvent) -> void:
	# Swings once the button is let go, so it never slides out from under the
	# finger mid-press. The button still handles the event itself.
	var released := false
	if event is InputEventMouseButton:
		released = event.device != InputEvent.DEVICE_ID_EMULATION \
			and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed
	elif event is InputEventScreenTouch:
		released = not event.pressed
	if not released:
		return
	var centre := poke_from.size.x * 0.5
	var x: float = event.position.x
	kick(-signf(x - centre) if absf(x - centre) > 8.0 else _random_side())


## Knock it sideways: dir is -1 (left) or 1 (right).
func kick(dir: float, strength := 1.0) -> void:
	_velocity += dir * tap_kick * strength * TAU / period


func celebrate() -> void:
	if not is_visible_in_tree():
		return
	kick(_random_side(), 0.8)
	_play(_tap_player, 0.7)


func _random_side() -> float:
	return 1.0 if _rng.randf() < 0.5 else -1.0


# ---- Sound -------------------------------------------------------------------------

func _play(player: AudioStreamPlayer, loudness := 1.0) -> void:
	if player == null:
		return
	# Rapid taps would stack into a rattle; keep a little gap.
	var now := Time.get_ticks_msec()
	if now - _last_sound_ms < 120:
		return
	_last_sound_ms = now
	player.pitch_scale = _rng.randf_range(0.92, 1.08)
	player.volume_db = (tap_volume_db if player == _tap_player else release_volume_db) + linear_to_db(loudness)
	player.play()


func _start_drag_loop() -> void:
	if _loop_player == null:
		return
	if _loop_tween and _loop_tween.is_valid():
		_loop_tween.kill()
	if not _loop_player.playing:
		_loop_player.volume_db = LOOP_SILENT_DB
		_loop_player.play(_rng.randf() * _loop_player.stream.get_length())
	_loop_tween = create_tween()
	_loop_tween.tween_property(_loop_player, "volume_db", drag_volume_db, 0.22) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _end_drag_loop() -> void:
	if _loop_player == null or not _loop_player.playing:
		return
	if _loop_tween and _loop_tween.is_valid():
		_loop_tween.kill()
	_loop_tween = create_tween()
	_loop_tween.tween_property(_loop_player, "volume_db", LOOP_SILENT_DB, 0.65) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_loop_tween.tween_callback(_loop_player.stop)


# ---- Motion --------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	var remaining := minf(delta, 0.1)
	while remaining > 0.0:
		var step := minf(remaining, 1.0 / 120.0)
		_step(step)
		remaining -= step
	_apply()


func _step(dt: float) -> void:
	_time += dt
	var omega := TAU / period
	var target := idle_sway * _noise.get_noise_1d(_time * 0.22)
	var zeta := damping
	if _dragging:
		target = _hold_target
		zeta = 0.8   # follows the finger without wobbling
	var accel := -omega * omega * (_sway - target) - 2.0 * zeta * omega * _velocity
	_velocity += accel * dt
	_sway += _velocity * dt
	# Hard stop at the limit, like the string going taut.
	if absf(_sway) > max_sway:
		_sway = signf(_sway) * max_sway
		if signf(_velocity) == signf(_sway):
			_velocity *= -0.3


func _apply() -> void:
	if absf(_sway - _shown_sway) < 0.01:
		return
	_shown_sway = _sway
	_material.set_shader_parameter("sway", _sway)
	if follower:
		follower.position.x = _follower_x + roundf(_sway) * ART_PX


func _shape(local_y: float) -> float:
	# Mirrors hang_sway.gdshader: how much of `sway` a row at this height gets.
	var depth := maxf(local_y - pivot.y, 0.0) / reach
	if rigid:
		return minf(depth, 1.0)
	return depth * (1.0 + droop * (depth - 1.0))
