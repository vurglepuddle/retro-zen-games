# AudioManager.gd
# Autoload singleton — music / SFX switches + music player, persists across scenes.
#
# Two independent switches, each with its own bus (default_bus_layout.tres):
#   "Music" — the shared music player, plus anything a game calls music-like
#             (zen_farm ambience + rain, potion_3 candle crackle). Games opt in
#             by setting `player.bus = AudioManager.MUSIC_BUS`.
#   "SFX"   — everything else. Any AudioStreamPlayer that enters the tree still
#             on "Master" is moved here automatically, so game scenes need no
#             per-node setup.
# Both buses send to Master. Music off fades the Music bus out, then mutes it;
# SFX off mutes the SFX bus straight away.
# Crossfade between tracks: 0.30s fade-out → switch stream → 0.40s fade-in.
#
# Web autoplay: play() is deferred until the first user gesture.

extends Node

const _SaveFile = preload("res://scripts/SafeConfig.gd")

signal music_toggled(on: bool)
signal sfx_toggled(on: bool)

const SAVE_PATH := "user://audio_settings.cfg"
const MUSIC_BUS := &"Music"
const SFX_BUS := &"SFX"

var music_on := true
var sfx_on := true

var _music: AudioStreamPlayer = null
var _music_volume_db: float = linear_to_db(0.5)
var _music_tween: Tween = null
var _music_bus_tween: Tween = null
var _audio_unlocked: bool = false


func _ready() -> void:
	set_process_input(true)
	_ensure_bus(MUSIC_BUS)
	_ensure_bus(SFX_BUS)
	get_tree().node_added.connect(_on_node_added)
	# At launch the first scene enters the tree alongside the autoloads, before
	# this _ready() runs, so its players were never seen by node_added.
	_route_existing(get_tree().root)

	_music = AudioStreamPlayer.new()
	_music.bus = MUSIC_BUS
	_music.volume_db = _music_volume_db
	_music.finished.connect(func():
		if _audio_unlocked:
			_music.play()
	)
	add_child(_music)
	_load_state()
	_apply_music(false)
	_apply_sfx()


# ---- Buses ------------------------------------------------------------------

func _ensure_bus(bus_name: StringName) -> void:
	# default_bus_layout.tres provides both buses from startup. Never add them
	# here: AudioServer.add_bus() at runtime corrupted the WebAudio driver
	# before (see TODO.md "Web audio fix"). A missing bus just plays on Master.
	if AudioServer.get_bus_index(bus_name) == -1:
		push_warning("AudioManager: bus '%s' missing from default_bus_layout.tres" % bus_name)


func _on_node_added(node: Node) -> void:
	# node_added fires before the node's own _ready(), so a game that sets
	# MUSIC_BUS in _ready() still wins.
	if node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D:
		if node.get("bus") == &"Master":
			node.set("bus", SFX_BUS)


func _route_existing(node: Node) -> void:
	_on_node_added(node)
	for child in node.get_children():
		_route_existing(child)


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
			_music_tween = create_tween()
			_music_tween.tween_property(_music, "volume_db", volume_db, 0.40) \
				.set_ease(Tween.EASE_OUT)
		)
	else:
		# Not yet playing: queue the stream; play (+ fade in) on unlock.
		_music.stream = stream
		_music.volume_db = -80.0
		if _audio_unlocked:
			_music.play()
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
			_music_tween = create_tween()
			_music_tween.tween_property(_music, "volume_db", _music_volume_db, 0.50) \
				.set_ease(Tween.EASE_OUT)


# ---- Switches -----------------------------------------------------------------

func toggle_music() -> void:
	set_music_on(not music_on)


func toggle_sfx() -> void:
	set_sfx_on(not sfx_on)


func set_music_on(on: bool) -> void:
	if on == music_on:
		return
	music_on = on
	_apply_music(true)
	_save_state()
	music_toggled.emit(music_on)


func set_sfx_on(on: bool) -> void:
	if on == sfx_on:
		return
	sfx_on = on
	_apply_sfx()
	_save_state()
	sfx_toggled.emit(sfx_on)


func _apply_music(fade: bool) -> void:
	var idx := AudioServer.get_bus_index(MUSIC_BUS)
	if _music_bus_tween != null and _music_bus_tween.is_valid():
		_music_bus_tween.kill()
	_music_bus_tween = null
	if idx == -1:
		return
	if not fade:
		AudioServer.set_bus_mute(idx, not music_on)
		AudioServer.set_bus_volume_db(idx, 0.0)
		return
	var set_volume := func(db: float) -> void:
		AudioServer.set_bus_volume_db(idx, db)
	_music_bus_tween = create_tween()
	if music_on:
		AudioServer.set_bus_volume_db(idx, -80.0)
		AudioServer.set_bus_mute(idx, false)
		_music_bus_tween.tween_method(set_volume, -80.0, 0.0, 0.40).set_ease(Tween.EASE_OUT)
	else:
		_music_bus_tween.tween_method(set_volume, AudioServer.get_bus_volume_db(idx), -80.0, 0.30) \
			.set_ease(Tween.EASE_IN)
		_music_bus_tween.tween_callback(func() -> void:
			AudioServer.set_bus_mute(idx, true)
			AudioServer.set_bus_volume_db(idx, 0.0)
		)


func _apply_sfx() -> void:
	var idx := AudioServer.get_bus_index(SFX_BUS)
	if idx != -1:
		AudioServer.set_bus_mute(idx, not sfx_on)


func _load_state() -> void:
	var cfg := ConfigFile.new()
	if _SaveFile.load_config(cfg, SAVE_PATH) != OK:
		return
	if cfg.has_section_key("audio", "music_on"):
		music_on = cfg.get_value("audio", "music_on", true)
		sfx_on = cfg.get_value("audio", "sfx_on", true)
	else:
		# Older saves kept one cycling state: 0 all on, 1 music off, 2 all off.
		var legacy: int = cfg.get_value("audio", "mute_state", 0)
		music_on = legacy == 0
		sfx_on = legacy != 2


func _save_state() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "music_on", music_on)
	cfg.set_value("audio", "sfx_on", sfx_on)
	_SaveFile.save_config(cfg, SAVE_PATH)


func is_audio_unlocked() -> bool:
	return _audio_unlocked


func _cancel_music_tween() -> void:
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	_music_tween = null
