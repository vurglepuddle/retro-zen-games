#Menu.gd
extends Control

# mode: 0 = normal, 1 = countdown (90 s), 2 = level mode
signal start_game(mode: int)
signal back_to_master

@onready var sfx_click: AudioStreamPlayer = $SfxClick


func _on_StartButton_pressed() -> void:
	start_game.emit(0)


func _on_Start_pressed() -> void:
	if sfx_click:
		sfx_click.play()
	start_game.emit(0)


func _on_BackButton_pressed() -> void:
	back_to_master.emit()


func _on_Timed_pressed() -> void:
	if sfx_click and sfx_click.stream:
		sfx_click.play()
	start_game.emit(1)


func _on_Level_pressed() -> void:
	if sfx_click and sfx_click.stream:
		sfx_click.play()
	start_game.emit(2)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		back_to_master.emit()
