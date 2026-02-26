#Menu.gd (alchemical_sort)
extends Control

signal start_game(difficulty: int)  # 0=Easy 1=Medium 2=Hard 3=Zen 4=Mystery
signal back_to_master


func _on_easy_pressed()    -> void: start_game.emit(0)
func _on_medium_pressed()  -> void: start_game.emit(1)
func _on_hard_pressed()    -> void: start_game.emit(2)
func _on_zen_pressed()     -> void: start_game.emit(3)
func _on_mystery_pressed() -> void: start_game.emit(4)
func _on_quit_pressed()    -> void: back_to_master.emit()
