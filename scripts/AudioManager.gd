# AudioManager.gd
# Autoload singleton — global mute state + music player, persists across scenes.
#
# Cycle: 0 (all on) → 1 (music muted) → 2 (all muted) → 0
#
# No custom audio buses — uses Master bus only (web-safe).
# Music-only mute: volume_db set to -80 on the player.
# Full mute: Master bus muted by name.
# Crossfade: 0.30s fade-out → switch stream → 0.40s fade-in.
#
# Web autoplay: play() is deferred until the first user gesture.

extends Node

signal mute_state_changed(state: int)

# 0 = all on, 1 = music muted, 2 = all muted
var mute_state: int = 0

var _music: AudioStreamPlayer = null
var _music_volume_db: float = linear_to_db(0.5)
var _music_tween: Tween = null
var _audio_unlocked: bool = false


func _ready() -> void:
	set_process_input(true)

	_music = AudioStreamPlayer.new()
	_music.volume_db = _music_volume_db
	_music.finished.connect(func():
		if _audio_unlocked:
			_music.play()
	)
	add_child(_music)


# ---- Music ------------------------------------------------------------------

# Call from any scene's _ready() to set the background track.
# Crossfades if already playing; fades in on first play.
# On web, play() is deferred until first user gesture.
func play_music(stream: AudioStream, volume_db: float = linear_to_db(0.5)) -> void:
	if _music.stream == stream and _music.playing:
		return
	_music_volume_db = volume_db
	_cancel_music_tween()

	if _music.playing and _audio_unlocked:
		# Crossfade: fade out → switch → fade in.
		_music_tween = create_tween()
		_music_tween.tween_property(_music, "volume_db", -80.0, 0.30) \
			.set_ease(Tween.EASE_IN)
		_music_tween.tween_callback(func():
			_music.stream = stream
			_music.volume_db = -80.0
			_music.play()
			if mute_state == 0:
				_music_tween = create_tween()
				_music_tween.tween_property(_music, "volume_db", volume_db, 0.40) \
					.set_ease(Tween.EASE_OUT)
			else:
				_music.volume_db = -80.0
		)
	else:
		# Not yet playing: queue the stream; play (+ fade in) on unlock.
		_music.stream = stream
		_music.volume_db = -80.0
		if _audio_unlocked:
			_music.play()
			if mute_state == 0:
				_music_tween = create_tween()
				_music_tween.tween_property(_music, "volume_db", volume_db, 0.40) \
					.set_ease(Tween.EASE_OUT)


# ---- Audio unlock (first user gesture) -------------------------------------

func _input(event: InputEvent) -> void:
	if _audio_unlocked:
		return
	var pressed := false
	if event is InputEventMouseButton:
		pressed = (event as InputEventMouseButton).pressed
	elif event is InputEventScreenTouch:
		pressed = (event as InputEventScreenTouch).pressed
	if pressed:
		_audio_unlocked = true
		if _music.stream != null and not _music.playing:
			_music.volume_db = -80.0
			_music.play()
			if mute_state == 0:
				_music_tween = create_tween()
				_music_tween.tween_property(_music, "volume_db", _music_volume_db, 0.50) \
					.set_ease(Tween.EASE_OUT)


# ---- Mute state -------------------------------------------------------------

func cycle() -> void:
	mute_state = (mute_state + 1) % 3
	_apply_state()
	mute_state_changed.emit(mute_state)


func _apply_state() -> void:
	var master_idx := AudioServer.get_bus_index("Master")
	_cancel_music_tween()
	match mute_state:
		0: # all on
			AudioServer.set_bus_mute(master_idx, false)
			if _music != null:
				if _audio_unlocked and not _music.playing:
					_music.volume_db = -80.0
					_music.play()
				_music_tween = create_tween()
				_music_tween.tween_property(_music, "volume_db", _music_volume_db, 0.40) \
					.set_ease(Tween.EASE_OUT)
		1: # music off, SFX on
			AudioServer.set_bus_mute(master_idx, false)
			if _music != null:
				_music_tween = create_tween()
				_music_tween.tween_property(_music, "volume_db", -80.0, 0.30) \
					.set_ease(Tween.EASE_IN)
		2: # all off
			AudioServer.set_bus_mute(master_idx, true)


func is_audio_unlocked() -> bool:
	return _audio_unlocked


func _cancel_music_tween() -> void:
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	_music_tween = null
