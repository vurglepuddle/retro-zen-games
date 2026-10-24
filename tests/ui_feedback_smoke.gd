extends SceneTree

var checks := 0
var failures: Array[String] = []

class ReadyTooltip:
	extends Button
	func _ready() -> void:
		tooltip_text = "Assigned during ready"


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)


func mouse(button: Control, pressed: bool, emulated: bool = false) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = button.get_global_rect().get_center()
	event.pressed = pressed
	event.device = InputEvent.DEVICE_ID_EMULATION if emulated else 0
	root.push_input(event, true)


func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	root.push_input(event, true)
	event.pressed = false
	root.push_input(event, true)


func well_touch(game: Control) -> void:
	# Android can deliver both events for a single physical tap.
	for pressed in [true, false]:
		var touch := InputEventScreenTouch.new()
		touch.position = game._well_panel.get_global_rect().get_center()
		touch.pressed = pressed
		root.push_input(touch, true)
		mouse(game._well_panel, pressed, true)


func check_well_input(game: Control) -> void:
	game.prepare_farm(true)
	game.set_process(false)
	game._tip_panel.hide()
	game._active_tool = game.Tool.WATERING_CAN
	for level in range(3):
		game._can_level = level
		var capacity: int = game._can_max()
		var filled := "Can filled! (%d/%d)" % [capacity, capacity]
		for remaining in [0, capacity - 1]:
			game._can_water = remaining
			game._refresh_ui()
			well_touch(game)
			check(game._can_water == capacity and game._status_label.text == filled, "Well touch refills once from %d/%d and keeps confirmation" % [remaining, capacity])
		well_touch(game)
		check(game._status_label.text == "Can is already full.", "A later tap on a full level-%d can reports full" % level)
		game._can_water = 0
		game._refresh_ui()
		mouse(game._well_panel, true)
		mouse(game._well_panel, false)
		check(game._can_water == capacity and game._status_label.text == filled, "Physical mouse still refills level-%d can" % level)
	game._can_level = 0
	game._can_water = 0
	game._active_tool = game.Tool.HAND
	game._refresh_ui()
	well_touch(game)
	check(game._active_tool == game.Tool.WATERING_CAN and game._can_water == 0 and game._status_label.text == "Watering Can selected.", "First well tap selects the can once")
	var cell: FarmCell = game._cell_at_grid(0, 0)
	cell.reset_slots()
	cell.slot_states[0] = FarmCell.SlotState.CROP
	cell.slot_crop_ids[0] = 0
	game._can_water = 1
	game._try_water_cell(cell)
	check(game._can_water == 0 and game._can_btn.text == "0/5", "Last watering charge empties the can and updates its count")
	game._try_water_cell(cell)
	check(game._status_label.text == "Can is empty - fill at the Well.", "Empty can reports empty before refill")
	well_touch(game)
	check(game._can_water == 5 and game._status_label.text == "Can filled! (5/5)", "Empty-to-refilled can keeps the correct confirmation")


func capture(label: String) -> void:
	if not "--render-review" in OS.get_cmdline_user_args(): return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot/ui_feedback_review/%s.png" % label)


func _run() -> void:
	var isolated := ProjectSettings.globalize_path("res://.godot/puzzle_test_user/").replace("\\", "/")
	if not OS.get_user_data_dir().replace("\\", "/").begins_with(isolated):
		push_error("Use isolated puzzle_test_user APPDATA")
		quit(2)
		return
	root.size = Vector2i(540,1212)
	root.get_node("Pointer").enabled = false
	root.get_node("AudioManager")._audio_unlocked = true
	var policy = root.get_node("UIFeedback")
	var hub = load("res://scenes/MasterMenu.tscn").instantiate()
	root.add_child(hub)
	while hub._transitioning: await process_frame
	# Keep navigation in place while sending real GUI clicks to its buttons.
	hub._transitioning = true
	var hub_button: Button = hub.get_node("GemMatchTile")
	check(not hub_button.get_tooltip().is_empty(), "Desktop hub retains its tooltip")
	mouse(hub_button,true)
	mouse(hub_button,false)
	check(hub_button.has_focus(), "Pointer click keeps functional focus")
	check(hub_button.get_theme_stylebox("focus") is StyleBoxEmpty, "Hub pointer focus has no yellow corners")
	await capture("hub_mouse")
	key(KEY_TAB)
	check(root.gui_get_focus_owner() != hub_button, "Tab still navigates between hub buttons")
	check(root.gui_get_focus_owner().get_theme_stylebox("focus") is StyleBoxTexture, "Tab displays the authored focus frame")
	await capture("hub_keyboard")

	for path in ["res://games/gem_match/assets/ui/ui_pass/action_buttons.tres", "res://games/tile_chain/assets/ui/ui_pass/action_buttons.tres"]:
		var button := Button.new()
		button.theme = load(path)
		button.text = "TEST"
		button.position = Vector2(80,600)
		button.size = Vector2(360,100)
		button.tooltip_text = "Desktop help"
		root.add_child(button)
		await process_frame
		var original := button.get_theme_stylebox("focus")
		var hits := {"count":0}
		button.pressed.connect(func(): hits.count += 1)
		mouse(button,true)
		mouse(button,false)
		check(hits.count == 1, path + ": pointer activates once")
		check(button.get_theme_stylebox("focus") is StyleBoxEmpty, path + ": pointer has no focus frame")
		await capture(path.get_slice("/",3) + "_mouse")
		key(KEY_ENTER)
		check(hits.count == 2, path + ": keyboard activates once")
		check(button.get_theme_stylebox("focus") == original, path + ": keyboard restores authored focus")
		check(not button.has_theme_stylebox_override("focus"), path + ": original theme restored without an override")
		await capture(path.get_slice("/",3) + "_keyboard")
		mouse(button,true)
		mouse(button,false)
		check(button.get_theme_stylebox("focus") is StyleBoxEmpty, path + ": switching back to mouse hides focus again")
		button.queue_free()
		await process_frame

	var custom := Button.new()
	custom.position = Vector2(80,600)
	custom.size = Vector2(360,100)
	var original_override := StyleBoxFlat.new()
	custom.add_theme_stylebox_override("focus", original_override)
	root.add_child(custom)
	await process_frame
	mouse(custom,true)
	mouse(custom,false)
	check(custom.get_theme_stylebox("focus") is StyleBoxEmpty, "Custom focus override is hidden on click")
	key(KEY_RIGHT)
	check(custom.get_theme_stylebox("focus") == original_override, "Custom focus override is preserved for keyboard input")
	custom.queue_free()
	await process_frame

	# First touch must also handle desktop touchscreens and emulated mouse events.
	var touch := InputEventScreenTouch.new()
	touch.position = Vector2(30,30)
	touch.pressed = true
	root.push_input(touch,true)
	touch.pressed = false
	root.push_input(touch,true)
	for name in ["GemMatchTile","TileChainTile","AlchSortTile","Potion3Tile","ZenFarmTile"]:
		check(hub.get_node(name).get_tooltip().is_empty(), name + ": touch clears existing hover help")
	mouse(hub_button,true,true)
	mouse(hub_button,false,true)
	check(hub_button.get_theme_stylebox("focus") is StyleBoxEmpty, "Emulated mouse cannot restore touch focus corners")
	check(hub_button.get_tooltip().is_empty(), "Emulated mouse cannot restore a touch tooltip")
	check(policy.tooltip("Late error message").is_empty(), "Late tooltip assignments are suppressed on touch")
	if "--render-review" in OS.get_cmdline_user_args():
		var motion := InputEventMouseMotion.new()
		motion.device = InputEvent.DEVICE_ID_EMULATION
		motion.position = hub_button.get_global_rect().get_center()
		root.push_input(motion,true)
		await create_timer(0.8).timeout
		await capture("hub_touch_hover")

	var late := ReadyTooltip.new()
	root.add_child(late)
	await process_frame
	check(late.get_tooltip().is_empty(), "Tooltip assigned during runtime ready is suppressed on touch")
	late.queue_free()
	for kind in ["gem_match","tile_chain","alchemical_sort","potion_3","zen_farm"]:
		var game = load("res://games/%s/scenes/Game.tscn" % kind).instantiate()
		root.add_child(game)
		game.add_child(load("res://scripts/InGameAudio.gd").new())
		await process_frame
		for button in game.get_node("AudioControls").get_children():
			check(button.get_tooltip().is_empty(), kind + ": runtime audio has no touch tooltip")
		if kind == "zen_farm":
			check_well_input(game)
		game.queue_free()
		await process_frame
	# Freed focus owners must not leave dangling style overrides behind.
	key(KEY_TAB)
	check(root.gui_get_focus_owner().get_theme_stylebox("focus") is StyleBoxTexture, "Keyboard focus works after touch and scene disposal")
	hub.queue_free()
	await process_frame
	print("UI FEEDBACK: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
