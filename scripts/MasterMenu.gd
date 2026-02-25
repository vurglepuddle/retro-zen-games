#MasterMenu.gd
extends Control

# Top-level app hub — shows all available games as tiles.
# Clicking a tile fades out then loads that game's scene.

var _fade_rect: ColorRect = null


func _ready() -> void:
	# Optional ambient music — plays only if the track exists in assets.
	var music_path := "res://assets/music/master_menu.mp3"
	if ResourceLoader.exists(music_path):
		var music := AudioStreamPlayer.new()
		music.stream = load(music_path)
		music.volume_db = linear_to_db(0.5)
		music.finished.connect(func(): music.play())
		add_child(music)
		music.play()

	# Full-screen black rect for transitions — starts opaque then fades in.
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0.0, 0.0, 0.0, 1.0)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_fade_rect)

	_fade_from_black()


func _fade_to_black() -> void:
	var tw := create_tween()
	tw.tween_property(_fade_rect, "color:a", 1.0, 0.22)
	await tw.finished


func _fade_from_black() -> void:
	var tw := create_tween()
	tw.tween_property(_fade_rect, "color:a", 0.0, 0.38) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await tw.finished


func _on_gem_match_pressed() -> void:
	await _fade_to_black()
	get_tree().change_scene_to_file("res://games/gem_match/scenes/Main.tscn")


func _on_tile_chain_pressed() -> void:
	await _fade_to_black()
	get_tree().change_scene_to_file("res://games/tile_chain/scenes/Main.tscn")


func _on_alch_sort_pressed() -> void:
	await _fade_to_black()
	get_tree().change_scene_to_file("res://games/alchemical_sort/scenes/Main.tscn")
