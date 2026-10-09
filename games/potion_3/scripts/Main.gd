# Main.gd (potion_3)
extends "res://scripts/GameNavigation.gd"

@onready var _menu: Control        = $Menu
@onready var _game: Control        = $Game
@onready var _fade_rect: ColorRect = $FadeLayer/FadeRect

const _CandleGlow := preload("res://games/potion_3/scripts/CandleGlow.gd")
const _CRACKLE_PATH := "res://games/potion_3/assets/sfx/Candle_Crackle.mp3"
const _CRACKLE_DB := -10.0   # the recording is mostly quiet with sharp pops
const _SILENT_DB := -60.0

var _crackle: AudioStreamPlayer
var _crackle_tween: Tween


func _ready() -> void:
	_game.visible = false
	# Music — uncomment when a track is available:
	# AudioManager.play_music(load("res://games/potion_3/assets/music/track.mp3"))
	add_to_group(_CandleGlow.LISTENERS)
	_start_crackle()

	_menu.start_game.connect(_on_start_game)
	_menu.back_to_master.connect(_on_back_to_master)
	_game.back_to_menu.connect(_on_back_to_menu)

	_fade_from_black()


func _on_start_game(difficulty: int) -> void:
	if not _begin_transition(_fade_rect):
		return
	await _fade_to_black()
	_menu.visible = false
	_game.visible = true
	_game.set_difficulty(difficulty)
	_game.prepare_board()
	await _fade_from_black()
	_game.start_game()


func _on_back_to_menu() -> void:
	if not _begin_transition(_fade_rect):
		return
	_game.stop_game()
	await _fade_to_black()
	_game.visible = false
	_menu.visible = true
	await _fade_from_black()


func _on_back_to_master() -> void:
	if not _begin_transition(_fade_rect):
		return
	_fade_crackle(_SILENT_DB, 0.22)
	await _fade_to_black()
	get_tree().change_scene_to_file("res://scenes/MasterMenu.tscn")


func _start_crackle() -> void:
	# The candle's crackle sits under the music and switches off with it.
	var stream := load(_CRACKLE_PATH) as AudioStreamMP3
	if stream == null:
		return
	stream.loop = true
	_crackle = AudioStreamPlayer.new()
	_crackle.stream = stream
	_crackle.bus = AudioManager.MUSIC_BUS
	_crackle.volume_db = _SILENT_DB
	add_child(_crackle)
	_crackle.play(randf() * stream.get_length())
	if _CandleGlow.lit:
		_fade_crackle(_CRACKLE_DB, 1.2)


## CandleGlow: the shop candle was pinched out or relit.
func candle_lit_changed(lit: bool) -> void:
	_fade_crackle(_CRACKLE_DB if lit else _SILENT_DB, 0.8 if lit else 0.35)


func _fade_crackle(target_db: float, seconds: float) -> void:
	if _crackle == null:
		return
	if _crackle_tween and _crackle_tween.is_valid():
		_crackle_tween.kill()
	_crackle_tween = create_tween()
	_crackle_tween.tween_property(_crackle, "volume_db", target_db, seconds) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _fade_to_black() -> void:
	var tw := create_tween()
	tw.tween_property(_fade_rect, "color:a", 1.0, 0.22)
	await tw.finished


func _fade_from_black() -> void:
	_transitioning = true
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	var tw := create_tween()
	tw.tween_property(_fade_rect, "color:a", 0.0, 0.38) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await tw.finished
	_finish_transition(_fade_rect)
