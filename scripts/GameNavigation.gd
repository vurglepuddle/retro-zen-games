extends Node

# Android broadcasts Back to every node. Only the scene controller owns it.
var _transitioning := false


func _enter_tree() -> void:
	get_tree().quit_on_go_back = false
	_install_game_controls.call_deferred()


func _install_game_controls() -> void:
	var game := get_node_or_null("Game")
	if game and not game.has_node("AudioControls"):
		game.add_child(preload("res://scripts/InGameAudio.gd").new())
	if game and not game.has_node("RoundSession"):
		var kind: String = game.scene_file_path.split("/")[3]
		if kind in preload("res://scripts/PuzzleSession.gd").KINDS:
			var session := preload("res://scripts/PuzzleSession.gd").new()
			session.name = "RoundSession"
			game.add_child(session)


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
