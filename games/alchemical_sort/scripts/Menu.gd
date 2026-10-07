#Menu.gd (alchemical_sort)
extends Control

signal start_game(difficulty: int)  # 0=Easy 1=Medium 2=Hard 3=Zen 4=Mystery
signal back_to_master

# The cabinet from the game, with one brew per difficulty on the middle shelf.
const BOTTLE_BUTTONS := ["EasyButton", "MediumButton", "HardButton", "ZenButton"]


func _ready() -> void:
	# A picked brew hops off the shelf while the scene fades out.
	for btn_name in BOTTLE_BUTTONS:
		var btn := get_node(btn_name) as Button
		btn.button_down.connect(_hop.bind(btn.get_node("Bottle") as Control))


func _hop(bottle: Control) -> void:
	var tw := bottle.create_tween()
	tw.tween_property(bottle, "position:y", -12.0, 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(bottle, "position:y", 0.0, 0.16).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


func _on_easy_pressed()    -> void: start_game.emit(0)
func _on_medium_pressed()  -> void: start_game.emit(1)
func _on_hard_pressed()    -> void: start_game.emit(2)
func _on_zen_pressed()     -> void: start_game.emit(3)
func _on_mystery_pressed() -> void: start_game.emit(4)
func _on_quit_pressed()    -> void: back_to_master.emit()




func request_back() -> void:
	back_to_master.emit()
