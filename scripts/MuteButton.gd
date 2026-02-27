# MuteButton.gd
# Attach this script to a TextureButton in any scene.
# Set the 6 texture exports in the inspector, position the button wherever you
# like — the script handles everything else automatically.
#
# Texture slot mapping:
#   tex_on_normal / tex_on_pressed           — state 0: all audio on
#   tex_music_off_normal / tex_music_off_pressed — state 1: music muted
#   tex_all_off_normal / tex_all_off_pressed     — state 2: full mute

extends TextureButton

@export var tex_on_normal:        Texture2D
@export var tex_on_pressed:       Texture2D
@export var tex_music_off_normal:  Texture2D
@export var tex_music_off_pressed: Texture2D
@export var tex_all_off_normal:   Texture2D
@export var tex_all_off_pressed:  Texture2D


func _ready() -> void:
	pressed.connect(AudioManager.cycle)
	AudioManager.mute_state_changed.connect(_on_state_changed)
	_apply_textures(AudioManager.mute_state)


func _on_state_changed(state: int) -> void:
	_apply_textures(state)


func _apply_textures(state: int) -> void:
	match state:
		0:
			texture_normal  = tex_on_normal
			texture_pressed = tex_on_pressed
		1:
			texture_normal  = tex_music_off_normal
			texture_pressed = tex_music_off_pressed
		2:
			texture_normal  = tex_all_off_normal
			texture_pressed = tex_all_off_pressed
