#Menu.gd (zen_farm)
extends Control

const _Save = preload("res://games/zen_farm/scripts/SaveManager.gd")

@onready var _garden = $Garden
@onready var _continue: Button = %ContinueButton
var _changing_view := false
var _leaving := false

signal start_game(is_new: bool)
signal back_to_master


func _on_continue_pressed() -> void:
	if _leaving: return
	_leaving = true
	start_game.emit(false)

func _on_new_farm_pressed() -> void:
	if _leaving: return
	_leaving = true
	_Save.delete_save()
	start_game.emit(true)

func _on_back_pressed() -> void:
	if _leaving: return
	_leaving = true
	back_to_master.emit()


func _ready() -> void:
	var card: StyleBoxTexture = _garden._ui_style("card", 28).duplicate()
	card.texture_margin_left = 28
	card.texture_margin_right = 28
	card.texture_margin_top = 28
	card.texture_margin_bottom = 28
	card.content_margin_top = 28
	card.content_margin_bottom = 28
	card.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	card.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	%TitleCard.add_theme_stylebox_override("panel", card)
	%ActionsCard.add_theme_stylebox_override("panel", card)
	for button: Button in [%ContinueButton, %NewFarmButton, %BackButton, %AnotherGarden]:
		_garden._skin_button(button, "stake", "stake_down", 38, 20)
		button.focus_mode = Control.FOCUS_ALL
		button.add_theme_stylebox_override("focus", _garden._ui_style("plate_on", 20))
	%AnotherGarden.add_theme_font_size_override("font_size", 28)
	%ContinueButton.pressed.connect(_on_continue_pressed)
	%NewFarmButton.pressed.connect(_on_new_farm_pressed)
	%BackButton.pressed.connect(_on_back_pressed)
	%AnotherGarden.pressed.connect(_on_another_garden)
	visibility_changed.connect(_on_visibility_changed)
	refresh_state()


func refresh_state() -> void:
	_leaving = false
	_continue.visible = _Save.save_exists()


func _on_visibility_changed() -> void:
	# Pause node-bound wildlife tweens too while the real farm is open.
	_garden.process_mode = Node.PROCESS_MODE_INHERIT if is_visible_in_tree() else Node.PROCESS_MODE_DISABLED
	if is_visible_in_tree():
		_garden.regenerate()
		refresh_state()


func _on_another_garden() -> void:
	if _changing_view or _leaving:
		return
	_changing_view = true
	%AnotherGarden.disabled = true
	var tw := create_tween()
	tw.tween_property($Shade, "color:a", 1.0, 0.3)
	await tw.finished
	_garden.regenerate()
	tw = create_tween()
	tw.tween_property($Shade, "color:a", 0.48, 0.65)
	await tw.finished
	%AnotherGarden.disabled = false
	_changing_view = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if is_visible_in_tree():
			_on_back_pressed()
