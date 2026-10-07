extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.get_node("AudioManager")._audio_unlocked = true
	var hub = load("res://scenes/MasterMenu.tscn").instantiate()
	root.add_child(hub)
	current_scene = hub
	await create_timer(0.6).timeout
	hub._on_gem_match_pressed()
	hub._on_potion_3_pressed()
	await create_timer(0.7).timeout
	if current_scene.scene_file_path != "res://games/gem_match/scenes/Main.tscn":
		push_error("Repeated hub taps selected more than one game.")
		quit(1)
		return
	root.propagate_notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await create_timer(0.7).timeout
	if current_scene.scene_file_path != "res://scenes/MasterMenu.tscn":
		push_error("Game menu Back did not return to hub.")
		quit(1)
		return
	print("HUB NAVIGATION: repeated taps and return passed")
	print("HUB BACK: dispatching Android Back; expected clean exit")
	root.propagate_notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await create_timer(0.5).timeout
	push_error("Hub Back did not close the app.")
	quit(1)
