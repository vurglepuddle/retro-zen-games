#Main.gd (zen_farm)
extends Node

@onready var _menu:           Control           = $Menu
@onready var _game:           Control           = $Game
@onready var _fade_rect:      ColorRect         = $FadeLayer/FadeRect
@onready var _ambient_player:  AudioStreamPlayer = $AmbientPlayer
@onready var _ambient2_player: AudioStreamPlayer = $Ambient2Player

const _AMBIENT_PATH  := "res://games/zen_farm/assets/music/ambient.mp3"
const _AMBIENT2_PATH := "res://games/zen_farm/assets/music/ambient2.mp3"
const _RAIN_PATH     := "res://games/zen_farm/assets/music/rain.mp3"
const _DAY_AMBIENT_DB := -5.0
const _NIGHT_AMBIENT_DB := -8.0
const _SILENT_DB := -80.0

var _rain_player: AudioStreamPlayer
var _night_mix: float = 0.0
var _rain_duck_db: float = 0.0
var _rain_tween: Tween = null
var _rain_duck_tween: Tween = null


func _ready() -> void:
	_game.visible = false
	_menu.start_game.connect(_on_start_game)
	_menu.back_to_master.connect(_on_back_to_master)
	_game.back_to_menu.connect(_on_back_to_menu)
	_game.rain_changed.connect(_on_rain_changed)
	_game.day_night_changed.connect(_on_day_night_changed)
	_rain_player = AudioStreamPlayer.new()
	add_child(_rain_player)
	AudioManager.play_music(load("res://games/zen_farm/assets/music/music.mp3"))
	_start_ambients()
	_fade_from_black()


func _start_ambients() -> void:
	if ResourceLoader.exists(_AMBIENT_PATH):
		var s := load(_AMBIENT_PATH) as AudioStreamMP3
		if s:
			s.loop = true
			_ambient_player.stream = s
			_ambient_player.play()
	if ResourceLoader.exists(_AMBIENT2_PATH):
		var s := load(_AMBIENT2_PATH) as AudioStreamMP3
		if s:
			s.loop = true
			_ambient2_player.stream = s
			_ambient2_player.play()
	_apply_ambient_mix()


func _stop_ambients() -> void:
	if _rain_tween and is_instance_valid(_rain_tween):
		_rain_tween.kill()
	if _rain_duck_tween and is_instance_valid(_rain_duck_tween):
		_rain_duck_tween.kill()
	_ambient_player.stop()
	_ambient2_player.stop()
	_rain_player.stop()


func _on_rain_changed(is_raining: bool) -> void:
	if _rain_tween and is_instance_valid(_rain_tween):
		_rain_tween.kill()
	if _rain_duck_tween and is_instance_valid(_rain_duck_tween):
		_rain_duck_tween.kill()
	if is_raining:
		if ResourceLoader.exists(_RAIN_PATH):
			var s := load(_RAIN_PATH) as AudioStreamMP3
			if s:
				s.loop = true
				_rain_player.stream = s
				if not _rain_player.playing:
					_rain_player.volume_db = _SILENT_DB
					_rain_player.play()
				_rain_tween = create_tween()
				_rain_tween.tween_property(_rain_player, "volume_db", 0.0, 2.0)
		_rain_duck_tween = create_tween()
		_rain_duck_tween.tween_method(_set_rain_duck, _rain_duck_db, -18.0, 2.0)
	else:
		_rain_tween = create_tween()
		_rain_tween.tween_property(_rain_player, "volume_db", _SILENT_DB, 2.0)
		_rain_tween.tween_callback(func():
			if _rain_player and _rain_player.volume_db <= _SILENT_DB + 0.1:
				_rain_player.stop()
		)
		_rain_duck_tween = create_tween()
		_rain_duck_tween.tween_method(_set_rain_duck, _rain_duck_db, 0.0, 2.0)


func _on_day_night_changed(night_amount: float) -> void:
	_night_mix = smoothstep(0.18, 0.72, night_amount)
	_apply_ambient_mix()


func _set_rain_duck(value: float) -> void:
	_rain_duck_db = value
	_apply_ambient_mix()


func _apply_ambient_mix() -> void:
	var day_mix := 1.0 - _night_mix
	if _ambient_player:
		_ambient_player.volume_db = _SILENT_DB if day_mix <= 0.01 else _DAY_AMBIENT_DB + linear_to_db(day_mix) + _rain_duck_db
	if _ambient2_player:
		_ambient2_player.volume_db = _SILENT_DB if _night_mix <= 0.01 else _NIGHT_AMBIENT_DB + linear_to_db(_night_mix) + _rain_duck_db


func _on_start_game(_is_new: bool) -> void:
	await _fade_to_black()
	_menu.visible = false
	_game.visible = true
	_game.prepare_farm()
	await _fade_from_black()
	_game.start_game()


func _on_back_to_menu() -> void:
	await _fade_to_black()
	_game.visible = false
	_menu.visible = true
	# Refresh continue button visibility
	_menu.refresh_state()
	await _fade_from_black()


func _on_back_to_master() -> void:
	await _fade_to_black()
	_stop_ambients()
	get_tree().change_scene_to_file("res://scenes/MasterMenu.tscn")


func _fade_to_black() -> void:
	var tw := create_tween()
	tw.tween_property(_fade_rect, "color:a", 1.0, 0.22)
	await tw.finished


func _fade_from_black() -> void:
	var tw := create_tween()
	tw.tween_property(_fade_rect, "color:a", 0.0, 0.38) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await tw.finished
