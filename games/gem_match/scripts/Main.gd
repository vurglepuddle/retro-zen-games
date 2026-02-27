#Main.gd  (gem_match orchestrator)
extends Node

# Handles switching between the gem_match sub-menu and the game itself.
# Also handles navigation back to the master app menu.

@onready var menu = $Menu
@onready var game = $Game

var _fade_rect: ColorRect = null


func _ready() -> void:
	# Start the background music and keep it looping forever.
	AudioManager.play_music(preload("res://games/gem_match/assets/music/999.mp3"))

	# Full-screen black rect for scene transitions — sits above everything.
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0.0, 0.0, 0.0, 0.0)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_fade_rect)

	# Connect signals from the sub-menu.
	if menu.has_signal("start_game"):
		menu.connect("start_game", Callable(self, "_on_start_game"))
	if menu.has_signal("back_to_master"):
		menu.connect("back_to_master", Callable(self, "_on_back_to_master"))

	# Connect signal from the game when the player taps the in-game back button.
	if game.has_signal("back_to_menu"):
		game.connect("back_to_menu", Callable(self, "_on_back_to_menu"))


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
	# prepare_board() sets up the grid with gems hidden; the fade-in then
	# reveals the empty background before the entrance animation fires.
	if game.has_method("prepare_board"):
		game.prepare_board()
	await _fade_from_black()
	# start_game() animates gems falling in, then activates input.
	if game.has_method("start_game"):
		await game.start_game()


func _on_back_to_menu() -> void:
	await _fade_to_black()
	game.visible = false
	menu.visible = true
	await _fade_from_black()


func _on_back_to_master() -> void:
	await _fade_to_black()
	get_tree().change_scene_to_file("res://scenes/MasterMenu.tscn")
