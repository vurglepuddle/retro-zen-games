# Menu.gd (potion_3) — the shop: a shelf of four potions, one per difficulty.
extends Control

signal start_game(difficulty: int)   # 0=Easy  1=Medium  2=Hard  3=Zen
signal back_to_master

const BOTTLE_BUTTONS := ["EasyButton", "MediumButton", "HardButton", "ZenButton"]
# Two frames side by side: the Zen potion's sparkles drifting back and forth.
const ZEN_SHEET := preload("res://games/potion_3/assets/ui/bottle_zen-Sheet-export.png")

var _zen_bottle: TextureRect
var _zen_frames: Array[AtlasTexture] = []
var _zen_frame := 0
var _zen_wait := 0.0


func _ready() -> void:
	# A picked bottle hops off the shelf while the scene fades out.
	for btn_name in BOTTLE_BUTTONS:
		var btn := get_node(btn_name) as Button
		btn.button_down.connect(_hop.bind(btn.get_node("Bottle") as Control))
	# The sparkles swap the texture only, so they never fight the hop tween
	# (which moves the bottle's position).
	_zen_bottle = $ZenButton/Bottle
	var frame_w := ZEN_SHEET.get_width() * 0.5
	for i in 2:
		var frame := AtlasTexture.new()
		frame.atlas = ZEN_SHEET
		frame.region = Rect2(i * frame_w, 0, frame_w, ZEN_SHEET.get_height())
		_zen_frames.append(frame)
	_zen_bottle.texture = _zen_frames[0]
	_zen_wait = randf_range(0.4, 0.7)
	_layout_backdrop()
	get_viewport().size_changed.connect(_layout_backdrop)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_zen_wait -= delta
	if _zen_wait <= 0.0:
		_zen_frame = 1 - _zen_frame
		_zen_bottle.texture = _zen_frames[_zen_frame]
		_zen_wait = randf_range(0.45, 0.8)


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
