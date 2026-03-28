#Menu.gd (zen_farm)
extends Control

const _Save = preload("res://games/zen_farm/scripts/SaveManager.gd")

signal start_game(is_new: bool)
signal back_to_master


func _on_continue_pressed() -> void:
	start_game.emit(false)

func _on_new_farm_pressed() -> void:
	_Save.delete_save()
	start_game.emit(true)

func _on_back_pressed() -> void:
	back_to_master.emit()


func _ready() -> void:
	refresh_state()


func refresh_state() -> void:
	$ContinueButton.visible = _Save.save_exists()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		back_to_master.emit()
