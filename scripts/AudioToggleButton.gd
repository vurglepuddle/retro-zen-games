# AudioToggleButton.gd
# A TextureButton that switches one audio channel (music or SFX) on and off.
# Each sheet is two frames side by side: normal | pressed.
extends TextureButton

enum Channel { MUSIC, SFX }

@export var channel := Channel.MUSIC
@export var sheet_on: Texture2D
@export var sheet_off: Texture2D

var _frames_on: Array[AtlasTexture] = []
var _frames_off: Array[AtlasTexture] = []


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_frames_on = _split(sheet_on)
	_frames_off = _split(sheet_off)
	pressed.connect(_on_pressed)
	if channel == Channel.MUSIC:
		AudioManager.music_toggled.connect(_show)
		_show(AudioManager.music_on)
	else:
		AudioManager.sfx_toggled.connect(_show)
		_show(AudioManager.sfx_on)


func _on_pressed() -> void:
	if channel == Channel.MUSIC:
		AudioManager.toggle_music()
	else:
		AudioManager.toggle_sfx()


func _show(on: bool) -> void:
	var frames := _frames_on if on else _frames_off
	if frames.size() < 2:
		return
	texture_normal = frames[0]
	texture_pressed = frames[1]
	texture_hover = frames[0]


func _split(sheet: Texture2D) -> Array[AtlasTexture]:
	var out: Array[AtlasTexture] = []
	if sheet == null:
		return out
	var w := sheet.get_width() * 0.5
	for i in 2:
		var frame := AtlasTexture.new()
		frame.atlas = sheet
		frame.region = Rect2(i * w, 0, w, sheet.get_height())
		out.append(frame)
	return out
