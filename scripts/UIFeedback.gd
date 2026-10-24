extends Node

# Pointer clicks should show pressed artwork, without a keyboard focus frame.
# Touch can leave an emulated mouse hovering over the last button indefinitely.
var _touch_input := false
var _keyboard_input := false
var _suppressed: Button
var _previous_focus: StyleBox
var _had_override := false
var _empty_focus := StyleBoxEmpty.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_touch_input = OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()
	get_tree().node_added.connect(_node_added)
	get_viewport().gui_focus_changed.connect(_focus_changed)
	if _touch_input:
		_clear_tooltips(get_tree().root)


func tooltip(text: String) -> String:
	return "" if _touch_input else text


func _node_added(node: Node) -> void:
	if _touch_input and node is Control:
		# Scenes and runtime controls can assign their text during _ready().
		node.set_deferred("tooltip_text", "")


func _clear_tooltips(node: Node) -> void:
	if node is Control:
		node.tooltip_text = ""
	for child in node.get_children():
		_clear_tooltips(child)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		if not _touch_input:
			_touch_input = true
			_clear_tooltips(get_tree().root)
		_use_keyboard(false)
	elif event is InputEventMouseButton and event.pressed:
		_use_keyboard(false)
	elif event is InputEventKey and event.pressed:
		_use_keyboard(true)
	elif event is InputEventJoypadButton and event.pressed:
		_use_keyboard(true)
	elif event is InputEventJoypadMotion and absf(event.axis_value) > 0.5:
		_use_keyboard(true)


func _use_keyboard(value: bool) -> void:
	if _keyboard_input != value:
		_keyboard_input = value
		_update_focus()


func _focus_changed(_control: Control) -> void:
	_update_focus()


func _update_focus() -> void:
	_restore_focus()
	var owner := get_viewport().gui_get_focus_owner()
	if _keyboard_input or not owner is Button:
		return
	_suppressed = owner
	_had_override = owner.has_theme_stylebox_override("focus")
	_previous_focus = owner.get_theme_stylebox("focus")
	owner.add_theme_stylebox_override("focus", _empty_focus)


func _restore_focus() -> void:
	if is_instance_valid(_suppressed):
		if _had_override:
			_suppressed.add_theme_stylebox_override("focus", _previous_focus)
		else:
			_suppressed.remove_theme_stylebox_override("focus")
	_suppressed = null
	_previous_focus = null


func _exit_tree() -> void:
	_restore_focus()
