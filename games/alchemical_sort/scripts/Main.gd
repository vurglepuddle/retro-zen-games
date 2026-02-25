#Main.gd (alchemical_sort)
extends Node

@onready var _menu: Control          = $Menu
@onready var _game: Control          = $Game
@onready var _fade_rect: ColorRect   = $FadeLayer/FadeRect

var _music: AudioStreamPlayer = null


func _ready() -> void:
	_game.visible = false

	# Ambient music.
	_music = AudioStreamPlayer.new()
	_music.stream = load("res://games/alchemical_sort/assets/music/menuet.mp3")
	_music.volume_db = linear_to_db(0.5)
	_music.finished.connect(func(): _music.play())
	add_child(_music)
	_music.play()

	_menu.start_game.connect(_on_start_game)
	_menu.back_to_master.connect(_on_back_to_master)
	_game.back_to_menu.connect(_on_back_to_menu)

	_fade_from_black()


func _on_start_game(difficulty: int) -> void:
	await _fade_to_black()
	_menu.visible = false
	_game.visible = true
	_game.set_difficulty(difficulty)
	_game.prepare_board()
	await _fade_from_black()
	_game.start_game()


func _on_back_to_menu() -> void:
	await _fade_to_black()
	_game.visible = false
	_menu.visible = true
	await _fade_from_black()


func _on_back_to_master() -> void:
	await _fade_to_black()
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
