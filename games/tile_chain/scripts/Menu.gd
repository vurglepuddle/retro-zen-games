#Menu.gd (tile_chain)
extends Control

signal start_game
signal back_to_master


func _on_start_pressed() -> void:
	start_game.emit()


func _on_quit_pressed() -> void:
	back_to_master.emit()




func request_back() -> void:
	back_to_master.emit()
