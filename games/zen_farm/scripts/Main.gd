#Main.gd (zen_farm)
extends Node

@onready var _menu:           Control            = $Menu
@onready var _game:           Control            = $Game
@onready var _fade_rect:      ColorRect          = $FadeLayer/FadeRect
@onready var _music_player:   AudioStreamPlayer  = $MusicPlayer
@onready var _ambient_player: AudioStreamPlayer  = $AmbientPlayer

const _MUSIC_PATH   := "res://games/zen_farm/assets/music/music.mp3"
const _AMBIENT_PATH := "res://games/zen_farm/assets/music/ambient.mp3"


func _ready() -> void:
	_game.visible = false
	_menu.start_game.connect(_on_start_game)
	_menu.back_to_master.connect(_on_back_to_master)
	_game.back_to_menu.connect(_on_back_to_menu)
	_start_music()
	_fade_from_black()


func _start_music() -> void:
	if ResourceLoader.exists(_MUSIC_PATH):
		var s := load(_MUSIC_PATH) as AudioStreamMP3
		if s:
			s.loop = true
			_music_player.stream = s
			_music_player.play()
	if ResourceLoader.exists(_AMBIENT_PATH):
		var s := load(_AMBIENT_PATH) as AudioStreamMP3
		if s:
			s.loop = true
			_ambient_player.stream = s
			_ambient_player.play()


func _stop_music() -> void:
	_music_player.stop()
	_ambient_player.stop()


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
	_menu._ready()
	await _fade_from_black()


func _on_back_to_master() -> void:
	await _fade_to_black()
	_stop_music()
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
