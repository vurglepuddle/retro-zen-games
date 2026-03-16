#Menu.gd (tile_chain)
extends Control

signal start_game
signal back_to_master


func _on_start_pressed() -> void:
	start_game.emit()


func _on_quit_pressed() -> void:
	back_to_master.emit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		back_to_master.emit()
