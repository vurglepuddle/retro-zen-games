#MasterMenu.gd
extends Control

# Top-level app hub — shows all available games as tiles.
# Clicking a tile fades out then loads that game's scene.

var _fade_rect: ColorRect = null

@onready var _sfx_click: AudioStreamPlayer = $SfxClick
func _ready() -> void:
	# Ambient music.
	AudioManager.play_music(load("res://assets/music/999_turbo.ogg"))

	# Full-screen black rect for transitions — starts opaque then fades in.
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0.0, 0.0, 0.0, 1.0)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_fade_rect)

	if not AudioManager.is_audio_unlocked():
		await _show_splash()
	else:
		await _fade_from_black()


func _show_splash() -> void:
	# Layer 150: fully opaque splash — user replaces the bg ColorRect with their art.
	var splash_layer := CanvasLayer.new()
	splash_layer.layer = 150
	add_child(splash_layer)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	splash_layer.add_child(root)

	# --- Placeholder: swap this ColorRect for a TextureRect with your splash art ---
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.1, 0.14, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)
	# -------------------------------------------------------------------------------

	var lbl := Label.new()
	lbl.text = "TAP TO START"
	lbl.set_anchors_preset(Control.PRESET_CENTER)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.offset_left   = -160.0
	lbl.offset_top    = -30.0
	lbl.offset_right  =  160.0
	lbl.offset_bottom =  30.0
	var font := load("res://assets/font/vetka.ttf") as FontFile
	if font:
		lbl.add_theme_font_override("font", font)
		lbl.add_theme_font_size_override("font_size", 52)
	lbl.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.85))
	root.add_child(lbl)

	# Full-screen invisible tap catcher (on top of label).
	var btn := Button.new()
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	btn.flat = true
	btn.text = ""
	root.add_child(btn)

	# Layer 200: solid black cover — sits above the splash; fades away to reveal art.
	var cover_layer := CanvasLayer.new()
	cover_layer.layer = 200
	add_child(cover_layer)
	var cover := ColorRect.new()
	cover.color = Color(0.0, 0.0, 0.0, 1.0)
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cover.set_anchors_preset(Control.PRESET_FULL_RECT)
	cover_layer.add_child(cover)

	# Fade the cover away (splash is revealed). Instantly clear _fade_rect while
	# it is hidden behind the opaque splash — master menu is now fully ready.
	var tw_cover := create_tween()
	tw_cover.tween_property(cover, "color:a", 0.0, 0.40).set_ease(Tween.EASE_OUT)
	_fade_rect.color.a = 0.0

	await btn.pressed
	btn.disabled = true
	cover_layer.queue_free()

	# Splash fades out → master menu (already ready behind it) is revealed.
	var tw_out := create_tween()
	tw_out.tween_property(root, "modulate:a", 0.0, 0.50).set_ease(Tween.EASE_IN)
	await tw_out.finished
	splash_layer.queue_free()


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
	if _sfx_click.stream: _sfx_click.play()
	await _fade_to_black()
	get_tree().change_scene_to_file("res://games/gem_match/scenes/Main.tscn")


func _on_tile_chain_pressed() -> void:
	if _sfx_click.stream: _sfx_click.play()
	await _fade_to_black()
	get_tree().change_scene_to_file("res://games/tile_chain/scenes/Main.tscn")


func _on_alch_sort_pressed() -> void:
	if _sfx_click.stream: _sfx_click.play()
	await _fade_to_black()
	get_tree().change_scene_to_file("res://games/alchemical_sort/scenes/Main.tscn")
