#Menu.gd
extends Control

signal start_game
signal back_to_master

@onready var sfx_click: AudioStreamPlayer = $SfxClick


func _on_StartButton_pressed() -> void:
	start_game.emit()


func _on_Start_pressed() -> void:
	if sfx_click:
		sfx_click.play()
	start_game.emit()


func _on_BackButton_pressed() -> void:
	back_to_master.emit()
