# Menu.gd (potion_3) — the shop: a shelf of four potions, one per difficulty.
extends Control

signal start_game(difficulty: int)   # 0=Easy  1=Medium  2=Hard  3=Zen
signal back_to_master

const BOTTLE_BUTTONS := ["EasyButton", "MediumButton", "HardButton", "ZenButton"]


func _ready() -> void:
	# A picked bottle hops off the shelf while the scene fades out.
	for btn_name in BOTTLE_BUTTONS:
		var btn := get_node(btn_name) as Button
		btn.button_down.connect(_hop.bind(btn.get_node("Bottle") as Control))
	_layout_backdrop()
	get_viewport().size_changed.connect(_layout_backdrop)


func _layout_backdrop() -> void:
	## Same counter line as Game._layout_backdrop() (bottom of the dispenser
	## row: vp_h / 2 + 507 for the 3-row board), so the shop doesn't shift
	## between menu and game.
	($Backdrop/Counter as Control).position.y = roundf(get_viewport_rect().size.y / 2.0) + 507.0


func _hop(bottle: Control) -> void:
	var tw := bottle.create_tween()
	tw.tween_property(bottle, "position:y", -12.0, 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(bottle, "position:y", 0.0, 0.16).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


func _on_easy_pressed()   -> void: start_game.emit(0)
func _on_medium_pressed() -> void: start_game.emit(1)
func _on_hard_pressed()   -> void: start_game.emit(2)
func _on_zen_pressed()    -> void: start_game.emit(3)
func _on_quit_pressed()   -> void: back_to_master.emit()




func request_back() -> void:
	back_to_master.emit()
