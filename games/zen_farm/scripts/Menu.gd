#Menu.gd (zen_farm)
extends Control

const _Save = preload("res://games/zen_farm/scripts/SaveManager.gd")

@onready var _garden = $Garden
@onready var _continue: Button = %ContinueButton
var _changing_view := false
var _leaving := false
var _confirmation: ConfirmationDialog
var _restore_button: Button
var _restore_requested := false

signal start_game(is_new: bool)
signal back_to_master


func _on_continue_pressed() -> void:
	if _leaving: return
	_leaving = true
	start_game.emit(false)

func _on_new_farm_pressed() -> void:
	if _leaving: return
	if _Save.save_exists():
		_restore_requested = false
		_confirmation.title = "New farm"
		_confirmation.dialog_text = "Start a new farm?\nYour current farm will be kept\nso you can restore it later."
		_confirmation.get_ok_button().text = "NEW FARM"
		_confirmation.popup_centered(Vector2i(480, 240))
		return
	_leaving = true
	start_game.emit(true)

func _on_back_pressed() -> void:
	if _confirmation and _confirmation.visible:
		_confirmation.hide()
		return
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
	_restore_button = Button.new()
	_restore_button.text = "RESTORE PREVIOUS FARM"
	_restore_button.custom_minimum_size.y = 60
	_restore_button.add_theme_font_override("font", load("res://assets/font/vetka.ttf"))
	%BackButton.get_parent().add_child(_restore_button)
	%BackButton.get_parent().move_child(_restore_button, %BackButton.get_index())
	_garden._skin_button(_restore_button, "stake", "stake_down", 30, 20)
	_restore_button.focus_mode = Control.FOCUS_ALL
	_restore_button.add_theme_stylebox_override("focus", _garden._ui_style("plate_on", 20))
	_restore_button.pressed.connect(_on_restore_pressed)
	_confirmation = ConfirmationDialog.new()
	_confirmation.add_theme_font_override("font", load("res://assets/font/vetka.ttf"))
	_confirmation.add_theme_font_size_override("font_size", 26)
	_confirmation.add_theme_constant_override("buttons_min_width", 150)
	_confirmation.add_theme_constant_override("buttons_min_height", 56)
	_confirmation.add_theme_stylebox_override("panel", card)
	_confirmation.get_label().add_theme_font_override("font", load("res://assets/font/vetka.ttf"))
	_confirmation.get_label().add_theme_font_size_override("font_size", 28)
	_confirmation.get_label().add_theme_color_override("font_color", Color(0.247059, 0.156863, 0.196078, 1))
	add_child(_confirmation)
	_confirmation.get_cancel_button().text = "CANCEL"
	for button: Button in [_confirmation.get_ok_button(), _confirmation.get_cancel_button()]:
		button.add_theme_font_override("font", load("res://assets/font/vetka.ttf"))
		_garden._skin_button(button, "stake", "stake_down", 28, 20)
		button.focus_mode = Control.FOCUS_ALL
		button.add_theme_stylebox_override("focus", _garden._ui_style("plate_on", 20))
	_confirmation.confirmed.connect(_on_confirmation_confirmed)
	visibility_changed.connect(_on_visibility_changed)
	refresh_state()


func refresh_state() -> void:
	_leaving = false
	_continue.visible = _Save.save_exists()
	_restore_button.visible = _Save.previous_exists()


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


func request_back() -> void:
	_on_back_pressed()


func _on_restore_pressed() -> void:
	if _leaving: return
	_restore_requested = true
	_confirmation.title = "Restore farm"
	_confirmation.dialog_text = "Restore your previous farm?"
	_confirmation.get_ok_button().text = "RESTORE"
	_confirmation.popup_centered(Vector2i(480, 240))


func _on_confirmation_confirmed() -> void:
	if _leaving: return
	_confirmation.hide()
	if _restore_requested and not _Save.restore_previous_farm():
		show_save_error()
		return
	_leaving = true
	start_game.emit(not _restore_requested)


func show_save_error() -> void:
	_leaving = false
	var dialog := AcceptDialog.new()
	dialog.dialog_text = "Couldn't save the farm. Your previous farm has been kept.\nPlease try again."
	add_child(dialog)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(480, 220))
