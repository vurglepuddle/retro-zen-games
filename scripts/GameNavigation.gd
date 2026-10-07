extends Node

# Android broadcasts Back to every node. Only the scene controller owns it.
var _transitioning := false


func _enter_tree() -> void:
	get_tree().quit_on_go_back = false


func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_GO_BACK_REQUEST or _transitioning:
		return
	var game := get_node_or_null("Game") as CanvasItem
	var menu := get_node_or_null("Menu") as Control
	if game and game.is_visible_in_tree():
		game.request_back()
	elif menu and menu.is_visible_in_tree():
		menu.request_back()


func _begin_transition(fade_rect: Control) -> bool:
	if _transitioning:
		return false
	_transitioning = true
	fade_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	return true


func _finish_transition(fade_rect: Control) -> void:
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_transitioning = false
