#Main.gd (tile_chain orchestrator)
extends Node

# Mirrors gem_match/Main.gd: handles Menu <-> Game transitions and
# navigation back to the master app menu.

@onready var menu = $Menu
@onready var game = $Game

var _fade_rect: ColorRect = null


func _ready() -> void:
	AudioManager.play_music(preload("res://games/tile_chain/assets/music/999_2.mp3"))

	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0.0, 0.0, 0.0, 0.0)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_fade_rect)

	menu.connect("start_game", Callable(self, "_on_start_game"))
	menu.connect("back_to_master", Callable(self, "_on_back_to_master"))
	game.connect("back_to_menu", Callable(self, "_on_back_to_menu"))

	_fade_from_black()


func _fade_to_black() -> void:
	var tw := create_tween()
	tw.tween_property(_fade_rect, "color:a", 1.0, 0.22)
	await tw.finished


func _fade_from_black() -> void:
	var tw := create_tween()
	tw.tween_property(_fade_rect, "color:a", 0.0, 0.38) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await tw.finished


func _on_start_game() -> void:
	await _fade_to_black()
	menu.visible = false
	game.visible = true
	if game.has_method("prepare_board"):
		game.prepare_board()
	await _fade_from_black()
	if game.has_method("start_game"):
		game.start_game()


func _on_back_to_menu() -> void:
	await _fade_to_black()
	game.visible = false
	menu.visible = true
	await _fade_from_black()


func _on_back_to_master() -> void:
	await _fade_to_black()
	get_tree().change_scene_to_file("res://scenes/MasterMenu.tscn")
